import { useRef, useState } from "react";
import { isConnected } from "./api";
import type { ModelSource } from "./modelSource";
import { PartsPanel } from "./PartsPanel";
import { meshStepFile } from "./step/stepLoader";
import { useParts } from "./useParts";
import { Viewport } from "./Viewport";

// Bundled sample for demo mode. BASE_URL keeps the path right when the site is served from a
// sub-folder (GitHub Pages serves it from /<repo>/).
const DEMO_MODEL: ModelSource = { kind: "url", url: `${import.meta.env.BASE_URL}nist_ctc_01_asme1_ap242-e1.glb` };
const DEMO_INFO = "NIST CTC 01 sample · 117 faces · 9,756 triangles · open or drop your own STEP or GLB file";

// Demo mode is for viewing: files open on this computer (STEP is meshed in the browser).
// Connected mode is for saving: files go to the server, which meshes and stores them.

// A file opened on this computer (demo mode only). STEP files are meshed in the browser.
interface LocalModel {
  source: ModelSource;
  info: string;
}

const extensionOf = (name: string) => name.toLowerCase().split(".").pop() ?? "";

export default function App() {
  const api = useParts(isConnected);
  const [local, setLocal] = useState<LocalModel | null>(isConnected ? null : { source: DEMO_MODEL, info: DEMO_INFO });
  const [meshing, setMeshing] = useState<string | null>(null); // name of the STEP file being meshed
  const [localError, setLocalError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [wireframe, setWireframe] = useState(false);
  const [dragging, setDragging] = useState(false);
  // Ignore a slow STEP result if another file was opened in the meantime.
  const latestOpen = useRef(0);

  const openLocalFile = async (file: File | undefined) => {
    if (!file) return;
    const openId = ++latestOpen.current;
    setLocalError(null);
    setLoadError(null);
    const extension = extensionOf(file.name);

    if (extension === "glb") {
      if (local?.source.kind === "url" && local.source.url.startsWith("blob:")) URL.revokeObjectURL(local.source.url);
      setMeshing(null);
      setLocal({ source: { kind: "url", url: URL.createObjectURL(file) }, info: `${file.name} · local GLB` });
    } else if (extension === "step" || extension === "stp") {
      setMeshing(file.name);
      try {
        const result = await meshStepFile(file);
        if (openId !== latestOpen.current) return;
        setLocal({
          source: { kind: "object", object: result.object, key: `step-${openId}` },
          info: `${file.name} · ${result.faceCount} faces · ${result.triangleCount.toLocaleString()} triangles · meshed in your browser in ${Math.round(result.ms)} ms`,
        });
      } catch (error) {
        if (openId === latestOpen.current) setLocalError(`Could not open ${file.name}: ${(error as Error).message}`);
      } finally {
        if (openId === latestOpen.current) setMeshing(null);
      }
    } else {
      setLocalError(`${file.name}: open a .step, .stp or .glb file`);
    }
  };

  const selectPart = (id: number) => {
    latestOpen.current++; // drop any STEP file still meshing
    api.select(id);
    setLocal(null);
    setMeshing(null);
    setLocalError(null);
    setLoadError(null);
  };

  // What to show: a local file wins; otherwise the selected server part once it is ready.
  const part = local ? null : api.selected;
  const partUrl = part?.status === "ready" ? (part.tessellation?.glb_url ?? null) : null;
  const model: ModelSource | null = local?.source ?? (partUrl ? { kind: "url", url: partUrl } : null);

  let message: string | null = null;
  if (meshing) message = `Meshing ${meshing} in your browser… The first file also downloads the 7.6 MB OCCT engine.`;
  else if (localError) message = localError;
  else if (loadError) message = `Could not load the model: ${loadError}`;
  else if (part?.status === "failed") message = `Processing failed: ${part.error_message ?? "unknown error"}`;
  else if (part && !partUrl) message = part.status === "ready" ? "This part has no mesh." : "Meshing on the server…";
  else if (!model) message = isConnected ? "Select a part, or upload or drop a STEP file." : "Drop a STEP or GLB file here.";

  let info: string | null = null;
  if (local) info = local.info;
  else if (part?.tessellation && partUrl) {
    const t = part.tessellation;
    info = `${part.name} · ${t.face_count} faces · ${t.triangle_count.toLocaleString()} triangles · meshed on the server in ${Math.round(t.timings.total ?? 0)} ms`;
  }

  return (
    <div className="app">
      {isConnected && (
        <PartsPanel
          parts={api.parts}
          selectedId={local ? null : (api.selected?.id ?? null)}
          onSelect={selectPart}
          loading={api.loading}
          loadError={api.loadError}
          onRetry={api.refresh}
          upload={api.upload}
          onUpload={api.uploadFile}
          onDismissUpload={api.dismissUpload}
        />
      )}

      <main
        className={`stage ${dragging ? "dragging" : ""}`}
        data-drop-label={isConnected ? "Drop to upload" : "Drop to open"}
        onDragOver={(e) => {
          e.preventDefault(); // required, or the browser won't allow a drop here
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault(); // stop the browser from opening the file itself
          setDragging(false);
          const file = e.dataTransfer.files[0];
          if (!file) return;
          if (isConnected) void api.uploadFile(file); // same as "Upload STEP"
          else void openLocalFile(file);
        }}
      >
        <div className="toolbar">
          {!isConnected && (
            <label className="button" title="Opens on this computer; nothing is uploaded">
              Open file
              <input
                type="file"
                accept=".step,.stp,.glb"
                hidden
                onChange={(e) => {
                  void openLocalFile(e.target.files?.[0]);
                  e.target.value = ""; // allow opening the same file again
                }}
              />
            </label>
          )}
          <button className="button" onClick={() => setWireframe((w) => !w)}>
            {wireframe ? "Shaded" : "Wireframe"}
          </button>
        </div>

        <Viewport model={model} wireframe={wireframe} onLoadError={setLoadError} />

        {message && <div className={`message ${meshing ? "busy" : ""}`}>{message}</div>}
        {info && !meshing && <div className="info">{info}</div>}
      </main>
    </div>
  );
}
