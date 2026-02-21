"""
WD14 Tagger using wdtagger.
CPU: run in a subprocess (ProcessPoolExecutor) so PyTorch can use all cores without GIL.
Optional batch tagging runs multiple images in parallel (thread pool).
"""

import asyncio
import logging
import os
import re
import shutil
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Optional wdtagger import; WD14 is disabled at runtime if unavailable
try:
    import torch
    from wdtagger import Tagger
    WD14_AVAILABLE = True
except ImportError:
    WD14_AVAILABLE = False
    Tagger = None  # type: ignore[misc, assignment]
    torch = None  # type: ignore[assignment]


# Process-pool worker state (only in worker process)
_worker_tagger: Any = None


def _process_pool_init(model_name: str) -> None:
    """Run in worker process: set CPU threads and load model once."""
    global _worker_tagger
    os.environ.setdefault("OMP_NUM_THREADS", str(os.cpu_count() or 4))
    if torch is not None and torch.get_num_threads() == 1:
        n = int(os.environ.get("OMP_NUM_THREADS", "4"))
        try:
            torch.set_num_threads(n)
        except Exception:
            pass
    _worker_tagger = Tagger(model_repo=model_name)


def _process_pool_tag(path_str: str) -> Dict[str, Any]:
    """Run in worker process: tag one image, return serializable dict."""
    global _worker_tagger
    if _worker_tagger is None:
        return {}
    try:
        result = _worker_tagger.tag(path_str)
        if result is None:
            return {}
        return {
            "general_tag_data": getattr(result, "general_tag_data", None) or {},
            "character_tag_data": getattr(result, "character_tag_data", None) or {},
            "rating_data": getattr(result, "rating_data", None) or {},
        }
    except Exception:
        return {}


@dataclass
class TagResult:
    """Parsed tagging result for a single image."""
    general_tags: List[str] = field(default_factory=list)
    character_tags: List[str] = field(default_factory=list)
    safety: str = "unsafe"
    raw: Optional[Dict] = None


# In-process state (when not using process pool)
_tagger: Optional["Tagger"] = None
_tagger_lock = asyncio.Lock()
_thread_executor: Optional[ThreadPoolExecutor] = None
_process_executor: Optional[ProcessPoolExecutor] = None


def _get_thread_executor() -> ThreadPoolExecutor:
    global _thread_executor
    if _thread_executor is None:
        n = max(1, getattr(settings, "wd14_num_workers", 4))
        _thread_executor = ThreadPoolExecutor(max_workers=n, thread_name_prefix="wd14")
    return _thread_executor


def _get_process_executor() -> ProcessPoolExecutor:
    global _process_executor
    if _process_executor is None:
        model_name = getattr(settings, "wd14_model", "SmilingWolf/wd-swinv2-tagger-v3")
        if not os.environ.get("OMP_NUM_THREADS"):
            os.environ.setdefault("OMP_NUM_THREADS", str(os.cpu_count() or 4))
        _process_executor = ProcessPoolExecutor(
            max_workers=1,
            initializer=_process_pool_init,
            initargs=(model_name,),
        )
        logger.info("WD14 Tagger using process pool (CPU, no GIL)")
    return _process_executor


def _get_tagger():
    """Initialize and return the wdtagger Tagger (blocking). For thread-pool path only."""
    global _tagger
    if _tagger is not None:
        return _tagger
    if not WD14_AVAILABLE or Tagger is None:
        raise RuntimeError("WD14 Tagger not available. Install: pip install wdtagger torch torchvision")
    model_name = settings.wd14_model
    device = torch.device("cuda") if torch.cuda.is_available() else torch.device("cpu")
    if device.type == "cpu":
        n = os.environ.get("OMP_NUM_THREADS") or os.environ.get("TORCH_NUM_THREADS")
        if n is not None:
            try:
                torch.set_num_threads(int(n))
            except (ValueError, TypeError):
                pass
        if torch.get_num_threads() == 1:
            cpu_count = os.cpu_count()
            if cpu_count and cpu_count > 1:
                torch.set_num_threads(min(cpu_count, 8))
    try:
        nthreads = torch.get_num_threads()
    except Exception:
        nthreads = "?"
    logger.info("WD14 Tagger using device: %s (threads: %s)", device, nthreads)
    _tagger = Tagger(model_repo=model_name)
    return _tagger


async def _ensure_tagger():
    """Ensure in-process tagger is initialized (thread-pool path only)."""
    loop = asyncio.get_event_loop()
    async with _tagger_lock:
        if _tagger is None:
            executor = _get_thread_executor()
            await loop.run_in_executor(executor, _get_tagger)


def _clean_tag(tag: str) -> str:
    """Normalise a tag string."""
    tag = re.sub(r"\s*\([\d.]+\)$", "", str(tag))
    tag = tag.strip().replace(" ", "_")
    return tag if len(tag) > 1 else ""


def _result_to_namespace(d: Dict[str, Any]) -> Any:
    """Convert dict (from process pool) to object with .general_tag_data etc."""
    class NS:
        pass
    n = NS()
    n.general_tag_data = d.get("general_tag_data") or {}
    n.character_tag_data = d.get("character_tag_data") or {}
    n.rating_data = d.get("rating_data") or {}
    return n


def _process_wdtagger_result(result: Any) -> TagResult:
    """Convert wdtagger result (object or dict) to TagResult."""
    if isinstance(result, dict):
        result = _result_to_namespace(result)
    out = TagResult()
    threshold = settings.wd14_confidence_threshold
    max_tags = settings.wd14_max_tags

    if hasattr(result, "general_tag_data") and result.general_tag_data:
        items = sorted(result.general_tag_data.items(), key=lambda kv: kv[1], reverse=True)
        for tag, confidence in items:
            if confidence < threshold or len(out.general_tags) >= max_tags:
                if confidence < threshold:
                    break
                continue
            cleaned = _clean_tag(tag)
            if cleaned:
                out.general_tags.append(cleaned)

    if hasattr(result, "character_tag_data") and result.character_tag_data:
        for tag, confidence in result.character_tag_data.items():
            if confidence >= threshold:
                cleaned = _clean_tag(tag)
                if cleaned:
                    out.character_tags.append(cleaned)

    if hasattr(result, "rating_data") and result.rating_data:
        rating_data = result.rating_data
        best_rating = "general"
        best_conf = 0.0
        for rating, conf in rating_data.items():
            if conf > best_conf:
                best_conf = conf
                best_rating = rating
        if best_rating == "explicit":
            out.safety = "unsafe"
        elif best_rating in ("questionable", "sensitive"):
            out.safety = "sketchy"
        else:
            out.safety = "safe"

    return out


def _use_process_pool() -> bool:
    """Use process pool when CPU-only and enabled (avoids GIL for single-image)."""
    if not getattr(settings, "wd14_use_process_pool", True):
        return False
    if torch is not None and torch.cuda.is_available():
        return False
    return True


async def tag_image(image_path: Path) -> TagResult:
    """
    Tag an image using WD14.
    On CPU with process pool: runs in subprocess so PyTorch can use all cores.
    Otherwise: runs in dedicated thread pool.
    """
    if not settings.wd14_enabled:
        logger.debug("WD14 tagging disabled; skipping %s", image_path.name)
        return TagResult()

    if not WD14_AVAILABLE:
        logger.warning("WD14 Tagger not available; skipping %s", image_path.name)
        return TagResult()

    path_str = str(Path(image_path).resolve())
    try:
        if _use_process_pool():
            executor = _get_process_executor()
            loop = asyncio.get_event_loop()
            result_dict = await loop.run_in_executor(executor, _process_pool_tag, path_str)
            if not result_dict:
                return TagResult()
            return _process_wdtagger_result(result_dict)
        else:
            await _ensure_tagger()
            loop = asyncio.get_event_loop()
            thread_exec = _get_thread_executor()
            result = await loop.run_in_executor(thread_exec, lambda: _tagger.tag(path_str))
            if result is None:
                return TagResult()
            return _process_wdtagger_result(result)
    except Exception as exc:
        logger.warning("WD14 tagger failed for %s: %s", image_path.name, exc)
        return TagResult()


async def tag_images_batch(image_paths: List[Path]) -> List[TagResult]:
    """
    Tag multiple images in parallel (like reference project).
    When using thread pool, runs N tag() calls concurrently.
    When using process pool (1 worker), runs one at a time but each uses all cores.
    """
    if not image_paths or not settings.wd14_enabled or not WD14_AVAILABLE:
        return [TagResult() for _ in image_paths]
    tasks = [tag_image(p) for p in image_paths]
    raw = await asyncio.gather(*tasks, return_exceptions=True)
    out: List[TagResult] = []
    for r in raw:
        if isinstance(r, Exception):
            logger.warning("WD14 batch tag failed: %s", r)
            out.append(TagResult())
        else:
            out.append(r)
    return out


# ---------------------------------------------------------------------------
# Video frame tagging
# ---------------------------------------------------------------------------


async def _extract_video_frames(
    video_path: Path,
    output_dir: Path,
    scene_threshold: float = 0.3,
    max_frames: int = 10,
) -> List[Path]:
    """
    Extract key frames from a video using FFmpeg scene detection.
    Falls back to a single middle frame if scene detection yields nothing.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    output_pattern = str(output_dir / "frame_%04d.png")

    cmd = [
        "ffmpeg", "-i", str(video_path),
        "-vf", f"select='gt(scene,{scene_threshold})'",
        "-vsync", "vfr",
        "-frames:v", str(max_frames),
        output_pattern,
        "-y",
    ]
    logger.debug("Extracting video frames: %s", " ".join(cmd))

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)

    if proc.returncode != 0:
        logger.warning(
            "FFmpeg scene detection failed (rc=%d) for %s: %s",
            proc.returncode, video_path.name, stderr.decode(errors="replace")[:500],
        )

    frames = sorted(output_dir.glob("frame_*.png"))

    # Fallback: extract one frame from the middle of the video
    if not frames:
        logger.debug("Scene detection yielded 0 frames for %s, extracting middle frame", video_path.name)
        probe_cmd = [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(video_path),
        ]
        probe_proc = await asyncio.create_subprocess_exec(
            *probe_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        probe_stdout, _ = await asyncio.wait_for(probe_proc.communicate(), timeout=30)
        try:
            duration = float(probe_stdout.decode().strip())
        except (ValueError, AttributeError):
            duration = 0.0
        mid_time = max(duration / 2, 0.0)

        mid_frame_path = str(output_dir / "frame_0001.png")
        mid_cmd = [
            "ffmpeg", "-ss", str(mid_time),
            "-i", str(video_path),
            "-frames:v", "1",
            mid_frame_path,
            "-y",
        ]
        mid_proc = await asyncio.create_subprocess_exec(
            *mid_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await asyncio.wait_for(mid_proc.communicate(), timeout=30)
        frames = sorted(output_dir.glob("frame_*.png"))

    logger.info("Extracted %d frame(s) from %s", len(frames), video_path.name)
    return frames


def _aggregate_frame_tags(
    frame_results: List[TagResult],
    min_frame_ratio: float = 0.3,
    max_tags: int = 30,
) -> TagResult:
    """
    Aggregate tags from multiple video frames into a single TagResult.

    General tags: kept if they appear in >= min_frame_ratio of frames.
    Character tags: kept if they appear in any frame.
    Safety: most restrictive rating wins (unsafe > sketchy > safe).
    """
    if not frame_results:
        return TagResult()

    total_frames = len(frame_results)
    min_count = max(1, int(total_frames * min_frame_ratio))

    general_counts: Dict[str, int] = {}
    character_tags: set = set()

    SAFETY_RANK = {"safe": 0, "sketchy": 1, "unsafe": 2}
    SAFETY_NAME = {0: "safe", 1: "sketchy", 2: "unsafe"}
    worst_safety = 0

    for fr in frame_results:
        for tag in fr.general_tags:
            general_counts[tag] = general_counts.get(tag, 0) + 1

        for tag in fr.character_tags:
            character_tags.add(tag)

        rank = SAFETY_RANK.get(fr.safety, 2)
        if rank > worst_safety:
            worst_safety = rank

    qualified_general = [
        (tag, count)
        for tag, count in general_counts.items()
        if count >= min_count
    ]
    qualified_general.sort(key=lambda tc: (-tc[1], tc[0]))
    final_general = [tag for tag, _count in qualified_general[:max_tags]]

    return TagResult(
        general_tags=final_general,
        character_tags=list(character_tags),
        safety=SAFETY_NAME.get(worst_safety, "unsafe"),
    )


async def tag_video(
    video_path: Path,
    scene_threshold: float = 0.3,
    max_frames: int = 10,
    min_frame_ratio: float = 0.3,
) -> TagResult:
    """
    Tag a video by extracting key frames, running WD14 on each, and aggregating.
    Returns the same TagResult as tag_image() for seamless processor integration.
    """
    if not settings.wd14_enabled:
        logger.debug("WD14 tagging disabled; skipping video %s", video_path.name)
        return TagResult()

    if not WD14_AVAILABLE:
        logger.warning("WD14 Tagger not available; skipping video %s", video_path.name)
        return TagResult()

    frames_dir = video_path.parent / f"_frames_{video_path.stem}"
    try:
        frames = await _extract_video_frames(
            video_path, frames_dir,
            scene_threshold=scene_threshold,
            max_frames=max_frames,
        )
        if not frames:
            logger.warning("No frames extracted from %s", video_path.name)
            return TagResult()

        logger.info("Tagging %d frames from video %s", len(frames), video_path.name)
        frame_results = await tag_images_batch(frames)

        return _aggregate_frame_tags(
            frame_results,
            min_frame_ratio=min_frame_ratio,
            max_tags=settings.wd14_max_tags,
        )
    except Exception as exc:
        logger.warning("Video tagging failed for %s: %s", video_path.name, exc)
        return TagResult()
    finally:
        if frames_dir.exists():
            shutil.rmtree(frames_dir, ignore_errors=True)
