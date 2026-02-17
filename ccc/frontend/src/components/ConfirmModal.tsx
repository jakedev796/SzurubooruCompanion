/**
 * Reusable confirmation modal component
 */

import { X } from "lucide-react";

export interface ConfirmModalProps {
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  confirmClass?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmModal({
  title,
  message,
  confirmText = "Confirm",
  cancelText = "Cancel",
  confirmClass = "btn-danger",
  onConfirm,
  onCancel,
}: ConfirmModalProps) {
  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: "400px" }}>
        <div className="modal-header">
          <h3>{title}</h3>
          <button onClick={onCancel} className="modal-close"><X size={20} /></button>
        </div>
        <div className="modal-body">
          <p style={{ marginBottom: "1.5rem", color: "var(--text)" }}>{message}</p>
          <div style={{ display: "flex", gap: "0.5rem", justifyContent: "flex-end" }}>
            <button onClick={onCancel} className="btn">
              {cancelText}
            </button>
            <button onClick={onConfirm} className={`btn ${confirmClass}`}>
              {confirmText}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
