import type { Part } from "./api";
import type { UploadState } from "./useParts";

interface Props {
  parts: Part[];
  selectedId: number | null;
  onSelect: (id: number) => void;
  loading: boolean;
  loadError: string | null;
  onRetry: () => void;
  upload: UploadState | null;
  onUpload: (file: File) => void;
  onDismissUpload: () => void;
}

const STATUS_LABEL: Record<Part["status"], string> = {
  pending: "Queued",
  processing: "Meshing…",
  ready: "Ready",
  failed: "Failed",
};

// Left side panel in connected mode: upload button, upload progress, and the parts list.
export function PartsPanel(props: Props) {
  const { parts, selectedId, onSelect, loading, loadError, onRetry, upload, onUpload, onDismissUpload } = props;
  const uploading = upload !== null && upload.error === null;

  return (
    <aside className="panel">
      <header className="panel-header">
        <h1>Parts</h1>
        <label className={`button ${uploading ? "disabled" : ""}`}>
          Upload STEP
          <input
            type="file"
            accept=".step,.stp"
            hidden
            disabled={uploading}
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) onUpload(file);
              e.target.value = ""; // allow picking the same file again
            }}
          />
        </label>
      </header>

      {upload && (
        <div className={`upload ${upload.error ? "upload-error" : ""}`}>
          <div className="upload-name">{upload.fileName}</div>
          {upload.error ? (
            <>
              <div>{upload.error}</div>
              <button className="link" onClick={onDismissUpload}>Dismiss</button>
            </>
          ) : (
            <progress value={upload.progress} max={1} />
          )}
        </div>
      )}

      {loading && parts.length === 0 && (
        <p className="hint">Loading parts… A sleeping free server can take about a minute to wake up.</p>
      )}
      {loadError && (
        <div className="hint error">
          {loadError}. <button className="link" onClick={onRetry}>Retry</button>
        </div>
      )}
      {!loading && !loadError && parts.length === 0 && <p className="hint">No parts yet. Upload a STEP file.</p>}

      <ul className="parts">
        {parts.map((part) => (
          <li key={part.id}>
            <button
              className={`part ${part.id === selectedId ? "selected" : ""}`}
              onClick={() => onSelect(part.id)}
            >
              <span className="part-name">{part.name}</span>
              <span className={`status status-${part.status}`}>{STATUS_LABEL[part.status]}</span>
              {part.tessellation && (
                <span className="part-meta">
                  {part.tessellation.face_count} faces · {part.tessellation.triangle_count.toLocaleString()} triangles
                </span>
              )}
              {part.status === "failed" && part.error_message && (
                <span className="part-meta error">{part.error_message}</span>
              )}
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
