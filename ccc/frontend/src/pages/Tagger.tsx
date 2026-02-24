import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  Play,
  Pause,
  Square,
  Trash2,
  RefreshCcw,
  Clock,
  Download,
  Tag,
  Upload,
  CheckCircle2,
  GitMerge,
  XCircle,
  Ban,
  Info,
  AlertOctagon,
} from "lucide-react";
import {
  fetchJobs,
  fetchJob,
  fetchConfig,
  discoverTagJobs,
  abortAllTagJobs,
  searchTagJobsTags,
  type JobSummary,
  type JobsResponse,
  type TagSearchResult,
  startJob,
  pauseJob,
  stopJob,
  deleteJob,
  resumeJob,
  retryJob,
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";
import { formatRelativeDate, formatDurationSeconds } from "../utils/format";

const TAG_JOBS_PAGE_SIZE = 30;

const STATUS_ICONS: Record<string, React.ReactNode> = {
  pending: <Clock size={12} />,
  downloading: <Download size={12} />,
  tagging: <Tag size={12} />,
  uploading: <Upload size={12} />,
  paused: <Pause size={12} />,
  completed: <CheckCircle2 size={12} />,
  merged: <GitMerge size={12} />,
  stopped: <Ban size={12} />,
  failed: <XCircle size={12} />,
};

function StatusBadge({ status }: { status: string }) {
  const key = status.toLowerCase();
  const icon = STATUS_ICONS[key];
  return (
    <span className={`badge ${key}`}>
      {icon && <span className="badge-icon">{icon}</span>}
      {status}
    </span>
  );
}

type CriteriaMode = "tag" | "max_tag_count";

export default function Tagger() {
  const [data, setData] = useState<JobsResponse | null>(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [criteriaMode, setCriteriaMode] = useState<CriteriaMode>("tag");
  const [tagSearchInput, setTagSearchInput] = useState("");
  const [tagSearchResults, setTagSearchResults] = useState<TagSearchResult[]>([]);
  const [tagSearchLoading, setTagSearchLoading] = useState(false);
  const [selectedTags, setSelectedTags] = useState<TagSearchResult[]>([]);
  const [tagOperator, setTagOperator] = useState<"and" | "or">("and");
  const [showTagDropdown, setShowTagDropdown] = useState(false);
  const tagSearchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const tagDropdownRef = useRef<HTMLDivElement | null>(null);
  const [maxTagCount, setMaxTagCount] = useState<string>("5");
  const [replaceOriginalTags, setReplaceOriginalTags] = useState(false);
  const [limit, setLimit] = useState<string>("100");
  const [discoverLoading, setDiscoverLoading] = useState(false);
  const [abortLoading, setAbortLoading] = useState(false);
  const [loadingActions, setLoadingActions] = useState<Record<string, boolean>>({});
  const [message, setMessage] = useState<{ type: "ok" | "err"; text: string } | null>(null);

  useEffect(() => {
    fetchConfig()
      .then((c) => setBooruUrl(c.booru_url || ""))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setError(null);
    fetchJobs({
      job_type: "tag_existing",
      offset: 0,
      limit: TAG_JOBS_PAGE_SIZE,
      sort: "created_at_desc",
    })
      .then(setData)
      .catch((e: Error) => setError(e.message));
  }, []);

  const runTagSearch = useCallback((q: string) => {
    if (!q.trim()) {
      setTagSearchResults([]);
      setShowTagDropdown(false);
      return;
    }
    setTagSearchLoading(true);
    searchTagJobsTags(q, 20)
      .then((results) => {
        setTagSearchResults(results);
        setShowTagDropdown(true);
      })
      .catch(() => {
        setTagSearchResults([]);
        setShowTagDropdown(false);
      })
      .finally(() => setTagSearchLoading(false));
  }, []);

  useEffect(() => {
    if (tagSearchDebounceRef.current) clearTimeout(tagSearchDebounceRef.current);
    const q = tagSearchInput.trim();
    if (!q) {
      setTagSearchResults([]);
      setShowTagDropdown(false);
      return () => {};
    }
    tagSearchDebounceRef.current = setTimeout(() => runTagSearch(tagSearchInput), 300);
    return () => {
      if (tagSearchDebounceRef.current) clearTimeout(tagSearchDebounceRef.current);
    };
  }, [tagSearchInput, runTagSearch]);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (tagDropdownRef.current && !tagDropdownRef.current.contains(e.target as Node)) {
        setShowTagDropdown(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  function addSelectedTag(tag: TagSearchResult) {
    if (selectedTags.some((t) => t.name.toLowerCase() === tag.name.toLowerCase())) return;
    setSelectedTags((prev) => [...prev, tag]);
    setTagSearchInput("");
    setTagSearchResults([]);
    setShowTagDropdown(false);
  }

  function removeSelectedTag(name: string) {
    setSelectedTags((prev) => prev.filter((t) => t.name !== name));
  }

  useJobUpdates((payload: Record<string, unknown>) => {
    const id = String(payload.id ?? payload.job_id ?? "");
    if (!id) return;
    const updatedJob = { ...payload, id } as JobSummary;
    setData((prev) => {
      if (!prev?.results) return prev;
      const index = prev.results.findIndex((j) => j.id === id);
      if (index >= 0) {
        const newResults = [...prev.results];
        newResults[index] = { ...prev.results[index], ...updatedJob };
        return { ...prev, results: newResults };
      }
      fetchJob(id)
        .then((fullJob) => {
          setData((p) => {
            if (!p) return p;
            const idx = p.results.findIndex((j) => j.id === id);
            if (idx >= 0) return p;
            const results = [{ ...fullJob, ...updatedJob }, ...p.results].slice(0, TAG_JOBS_PAGE_SIZE);
            return { ...p, results, total: (p.total ?? 0) + 1 };
          });
        })
        .catch(() => {});
      return prev;
    });
  });

  async function handleDiscover() {
    const maxCount = maxTagCount.trim() ? parseInt(maxTagCount, 10) : null;
    const limitNum = limit.trim() ? Math.max(1, parseInt(limit, 10) || 100) : 100;
    if (criteriaMode === "tag") {
      if (selectedTags.length === 0) {
        setMessage({ type: "err", text: "Add at least one tag." });
        return;
      }
    }
    if (criteriaMode === "max_tag_count") {
      if (maxCount === null || isNaN(maxCount) || maxCount < 0 || maxCount > 1000) {
        setMessage({ type: "err", text: "Enter a number between 0 and 1000 for max tag count." });
        return;
      }
    }
    setMessage(null);
    setDiscoverLoading(true);
    try {
      const res = await discoverTagJobs({
        tags: criteriaMode === "tag" ? selectedTags.map((t) => t.name) : undefined,
        tag_operator: criteriaMode === "tag" ? tagOperator : undefined,
        max_tag_count: criteriaMode === "max_tag_count" ? (maxCount ?? undefined) : undefined,
        replace_original_tags: replaceOriginalTags,
        limit: limitNum,
      });
      setMessage({ type: "ok", text: `Created ${res.created} tag job(s).` });
      setData((prev) => {
        if (!prev) return prev;
        return { ...prev, total: (prev.total ?? 0) + res.created };
      });
      fetchJobs({
        job_type: "tag_existing",
        offset: 0,
        limit: TAG_JOBS_PAGE_SIZE,
        sort: "created_at_desc",
      }).then(setData);
    } catch (e) {
      setMessage({ type: "err", text: (e as Error).message });
    } finally {
      setDiscoverLoading(false);
    }
  }

  async function handleAbortAll() {
    setAbortLoading(true);
    setMessage(null);
    try {
      const res = await abortAllTagJobs();
      setMessage({ type: "ok", text: `Stopped ${res.aborted} pending tag job(s).` });
      fetchJobs({
        job_type: "tag_existing",
        offset: 0,
        limit: TAG_JOBS_PAGE_SIZE,
        sort: "created_at_desc",
      }).then(setData);
    } catch (e) {
      setMessage({ type: "err", text: (e as Error).message });
    } finally {
      setAbortLoading(false);
    }
  }

  async function handleJobAction(
    jobId: string,
    action: string,
    actionFn: (id: string) => Promise<JobSummary>
  ) {
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: true }));
    try {
      const updated = await actionFn(jobId);
      setData((prev) => {
        if (!prev) return prev;
        const index = prev.results.findIndex((j) => j.id === jobId);
        if (index >= 0) {
          const newResults = [...prev.results];
          newResults[index] = { ...newResults[index], status: updated.status };
          return { ...prev, results: newResults };
        }
        return prev;
      });
    } catch (e) {
      console.error((e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: false }));
    }
  }

  async function handleDeleteJob(jobId: string) {
    if (!confirm("Delete this tag job?")) return;
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: true }));
    try {
      await deleteJob(jobId);
      setData((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          results: prev.results.filter((j) => j.id !== jobId),
          total: Math.max(0, (prev.total ?? 0) - 1),
        };
      });
    } catch (e) {
      console.error((e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: false }));
    }
  }

  function getQuickActions(job: JobSummary) {
    const { id, status } = job;
    const isLoading = (action: string) => loadingActions[`${id}-${action}`];
    switch (status) {
      case "pending":
        return (
          <>
            <button
              className="btn btn-success btn-sm"
              onClick={() => handleJobAction(id, "start", startJob)}
              disabled={isLoading("start")}
              title="Start"
            >
              {isLoading("start") ? "..." : <Play size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "downloading":
      case "tagging":
      case "uploading":
        return (
          <>
            <button
              className="btn btn-warning btn-sm"
              onClick={() => handleJobAction(id, "pause", pauseJob)}
              disabled={isLoading("pause")}
              title="Pause"
            >
              {isLoading("pause") ? "..." : <Pause size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleJobAction(id, "stop", stopJob)}
              disabled={isLoading("stop")}
              title="Stop"
            >
              {isLoading("stop") ? "..." : <Square size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "paused":
      case "stopped":
        return (
          <>
            <button
              className="btn btn-success btn-sm"
              onClick={() => handleJobAction(id, "resume", resumeJob)}
              disabled={isLoading("resume")}
              title="Resume"
            >
              {isLoading("resume") ? "..." : <Play size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "completed":
      case "merged":
        return (
          <button
            className="btn btn-danger btn-sm"
            onClick={() => handleDeleteJob(id)}
            disabled={isLoading("delete")}
            title="Delete"
          >
            {isLoading("delete") ? "..." : <Trash2 size={14} />}
          </button>
        );
      case "failed":
        return (
          <>
            <button
              className="btn btn-warning btn-sm"
              onClick={() => handleJobAction(id, "retry", retryJob)}
              disabled={isLoading("retry")}
              title="Retry"
            >
              {isLoading("retry") ? "..." : <RefreshCcw size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      default:
        return null;
    }
  }

  const postId = (j: JobSummary) => j.szuru_post_id ?? j.target_szuru_post_id;

  return (
    <>
      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h2 style={{ marginTop: 0, marginBottom: "0.5rem" }}>Tagger</h2>
        <p style={{ color: "var(--text-muted)", fontSize: "0.9rem", marginBottom: "1rem" }}>
          Find posts on Szurubooru (uploaded by you) and run them through the AI tagger, then update tags on the board.
        </p>

        <div className="settings-form">
          <div className="form-group">
            <label>Criteria</label>
            <div style={{ display: "flex", gap: "1rem", alignItems: "center", flexWrap: "wrap" }}>
              <label style={{ display: "flex", alignItems: "center", gap: "0.35rem", cursor: "pointer" }}>
                <input
                  type="radio"
                  name="criteria"
                  checked={criteriaMode === "tag"}
                  onChange={() => setCriteriaMode("tag")}
                />
                Posts with tag
              </label>
              <label style={{ display: "flex", alignItems: "center", gap: "0.35rem", cursor: "pointer" }}>
                <input
                  type="radio"
                  name="criteria"
                  checked={criteriaMode === "max_tag_count"}
                  onChange={() => setCriteriaMode("max_tag_count")}
                />
                Posts with fewer than X tags
              </label>
            </div>
          </div>

          {criteriaMode === "tag" ? (
            <>
              <div className="form-group" ref={tagDropdownRef} style={{ position: "relative" }}>
                <label>Search tags</label>
                <input
                  type="text"
                  value={tagSearchInput}
                  onChange={(e) => setTagSearchInput(e.target.value)}
                  placeholder="Type to search your Szurubooru tags..."
                  autoComplete="off"
                />
                {showTagDropdown && (
                  <div
                    className="card"
                    style={{
                      position: "absolute",
                      top: "100%",
                      left: 0,
                      right: 0,
                      marginTop: 4,
                      maxHeight: 220,
                      overflowY: "auto",
                      zIndex: 10,
                      padding: "0.5rem 0",
                    }}
                  >
                    {tagSearchLoading ? (
                      <div style={{ padding: "0.5rem 0.75rem", color: "var(--text-muted)", fontSize: "0.9rem" }}>
                        Searching...
                      </div>
                    ) : tagSearchResults.length === 0 ? (
                      <div style={{ padding: "0.5rem 0.75rem", color: "var(--text-muted)", fontSize: "0.9rem" }}>
                        No tags found
                      </div>
                    ) : (
                      tagSearchResults.map((t) => (
                        <button
                          key={t.name}
                          type="button"
                          className="btn btn-sm"
                          style={{
                            display: "block",
                            width: "100%",
                            textAlign: "left",
                            padding: "0.4rem 0.75rem",
                            background: "transparent",
                            border: "none",
                            cursor: "pointer",
                          }}
                          onClick={() => addSelectedTag(t)}
                        >
                          {t.name} <span style={{ color: "var(--text-muted)" }}>({t.usages})</span>
                        </button>
                      ))
                    )}
                  </div>
                )}
              </div>
              {selectedTags.length > 0 && (
                <div className="form-group">
                  <label>Selected tags</label>
                  <div style={{ display: "flex", flexWrap: "wrap", gap: "0.5rem", alignItems: "center" }}>
                    {selectedTags.map((t) => (
                      <span
                        key={t.name}
                        className="tag"
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "0.35rem",
                          paddingRight: "0.25rem",
                        }}
                      >
                        {t.name} ({t.usages})
                        <button
                          type="button"
                          onClick={() => removeSelectedTag(t.name)}
                          title="Remove tag"
                          style={{
                            background: "none",
                            border: "none",
                            padding: 0,
                            cursor: "pointer",
                            color: "inherit",
                            opacity: 0.8,
                            lineHeight: 1,
                          }}
                        >
                          <XCircle size={14} />
                        </button>
                      </span>
                    ))}
                  </div>
                </div>
              )}
              {selectedTags.length >= 2 && (
                <div className="form-group">
                  <label>Match</label>
                  <div style={{ display: "flex", gap: "1rem", alignItems: "center", flexWrap: "wrap" }}>
                    <label style={{ display: "flex", alignItems: "center", gap: "0.35rem", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="tag_operator"
                        checked={tagOperator === "and"}
                        onChange={() => setTagOperator("and")}
                      />
                      Posts with ALL of these tags
                    </label>
                    <label style={{ display: "flex", alignItems: "center", gap: "0.35rem", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="tag_operator"
                        checked={tagOperator === "or"}
                        onChange={() => setTagOperator("or")}
                      />
                      Posts with ANY of these tags
                    </label>
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="form-group">
              <label>Max tag count (exclusive)</label>
              <input
                type="number"
                min={0}
                max={1000}
                value={maxTagCount}
                onChange={(e) => setMaxTagCount(e.target.value)}
                placeholder="e.g. 5"
              />
            </div>
          )}

          <div className="form-group">
            <label>Limit</label>
            <input
              type="number"
              min={1}
              value={limit}
              onChange={(e) => setLimit(e.target.value)}
            />
          </div>

          <div className="form-group">
            <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
              <input
                type="checkbox"
                checked={replaceOriginalTags}
                onChange={(e) => setReplaceOriginalTags(e.target.checked)}
              />
              Replace original tags
            </label>
          </div>

          <div className="form-actions">
            <button
              type="button"
              className="btn btn-primary"
              onClick={handleDiscover}
              disabled={discoverLoading}
            >
              {discoverLoading ? "Creating..." : "Create tag jobs"}
            </button>
            <button
              type="button"
              className="btn btn-danger"
              onClick={handleAbortAll}
              disabled={abortLoading}
              title="Stop all pending/paused tag jobs"
            >
              {abortLoading ? "..." : <><AlertOctagon size={16} style={{ verticalAlign: "middle" }} /> Abort all tag jobs</>}
            </button>
          </div>
        </div>

        {message && (
          <p
            style={{
              marginTop: "1rem",
              marginBottom: 0,
              color: message.type === "err" ? "var(--red)" : "var(--green)",
              fontSize: "0.9rem",
            }}
          >
            {message.text}
          </p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0, marginBottom: "0.75rem" }}>Tag job activity</h3>
        {error && <p style={{ color: "var(--red)" }}>{error}</p>}
        {data?.results?.length ? (
          <div className="table-wrap" style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th className="col-status">Status</th>
                  <th className="col-szuru">Post</th>
                  <th>Replace tags</th>
                  <th className="col-created">Created</th>
                  <th className="col-time">Time</th>
                  <th className="col-actions">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.results.map((j) => (
                  <tr key={j.id}>
                    <td>
                      <StatusBadge status={j.status} />
                    </td>
                    <td>
                      {postId(j) != null && booruUrl ? (
                        <a
                          href={`${booruUrl}/post/${postId(j)}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="post-link"
                        >
                          #{postId(j)}
                        </a>
                      ) : (
                        j.target_szuru_post_id != null ? `#${j.target_szuru_post_id}` : "-"
                      )}
                    </td>
                    <td>{j.replace_original_tags ? "Yes" : "No"}</td>
                    <td title={j.created_at ? new Date(j.created_at).toLocaleString() : ""}>
                      {formatRelativeDate(j.created_at)}
                    </td>
                    <td>{formatDurationSeconds(j.duration_seconds)}</td>
                    <td>
                      <div className="quick-actions">
                        {getQuickActions(j)}
                        <Link to={`/jobs/${j.id}`} className="btn btn-sm btn-info" title="Job details">
                          <Info size={14} />
                        </Link>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p style={{ color: "var(--text-muted)" }}>No tag jobs yet. Create some above.</p>
        )}
      </div>
    </>
  );
}
