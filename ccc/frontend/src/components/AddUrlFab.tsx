import { useState } from "react";
import { Plus, X } from "lucide-react";
import { createJobUrl } from "../api";
import { useToast } from "../contexts/ToastContext";

const JOB_CREATED_EVENT = "ccc-job-created";

export default function AddUrlFab() {
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const { showToast } = useToast();

  async function handleSubmit() {
    const url = value.trim();
    if (!url) {
      showToast("Enter a URL", "error");
      return;
    }
    setSubmitting(true);
    try {
      await createJobUrl(url);
      setValue("");
      setOpen(false);
      showToast("Job created", "success");
      window.dispatchEvent(new CustomEvent(JOB_CREATED_EVENT));
    } catch (e) {
      showToast((e as Error).message || "Failed to create job", "error");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <button
        type="button"
        className="fab"
        onClick={() => setOpen(true)}
        title="Add media URL"
        aria-label="Add media URL"
      >
        <Plus size={24} />
      </button>

      {open && (
        <div className="modal-overlay" onClick={() => setOpen(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: "420px" }}>
            <div className="modal-header">
              <h3>Add media URL</h3>
              <button onClick={() => setOpen(false)} className="modal-close" aria-label="Close">
                <X size={20} />
              </button>
            </div>
            <div className="modal-body">
              <p style={{ fontSize: "0.9rem", color: "var(--text-muted)", marginBottom: "1rem" }}>
                Paste a URL from a supported site to create a download job.
              </p>
              <div className="form-group">
                <label htmlFor="add-url-input">URL</label>
                <input
                  id="add-url-input"
                  type="url"
                  value={value}
                  onChange={(e) => setValue(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && handleSubmit()}
                  placeholder="https://..."
                  autoFocus
                  style={{ fontFamily: "monospace", fontSize: "0.9rem" }}
                />
              </div>
              <div style={{ display: "flex", gap: "0.5rem", justifyContent: "flex-end", marginTop: "1rem" }}>
                <button onClick={() => setOpen(false)} className="btn">
                  Cancel
                </button>
                <button onClick={handleSubmit} className="btn btn-primary" disabled={submitting}>
                  {submitting ? "Creating..." : "Create job"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

export { JOB_CREATED_EVENT };
