// Client for the Rails JSON API (web/). Connected mode is on when VITE_API_URL is set at build
// time: `VITE_API_URL=http://localhost:3000 npm run dev` in development, or `VITE_API_URL=/`
// when Rails serves the viewer itself (same origin, the Docker image). Without it the viewer
// is a static demo that only opens local files.

const RAW_API_URL = import.meta.env.VITE_API_URL ?? "";
export const isConnected = RAW_API_URL !== "";
// "/" becomes "", so requests go to "/parts" on the page's own origin.
export const API_URL = RAW_API_URL.replace(/\/+$/, "");

export type PartStatus = "pending" | "processing" | "ready" | "failed";

// Triangles [first, first + count) of a primitive belong to B-rep face `id`.
export interface FaceRange {
  id: number;
  first: number;
  count: number;
}

export interface FaceMap {
  primitives: { indices_accessor: number; triangle_count: number; faces: FaceRange[] }[];
}

export interface Tessellation {
  id: number;
  rel_deflection: number;
  linear_deflection: number;
  angular_deflection: number;
  triangle_count: number;
  face_count: number;
  bbox: { min: [number, number, number]; max: [number, number, number] };
  timings: Record<string, number>;
  occt_version: string | null;
  created_at: string;
  glb_url: string | null;
  face_map?: FaceMap; // only in GET /parts/:id
}

export interface Part {
  id: number;
  name: string;
  file_format: string;
  status: PartStatus;
  error_message: string | null;
  created_at: string;
  updated_at: string;
  tessellation: Tessellation | null;
}

export const isInProgress = (part: Part) => part.status === "pending" || part.status === "processing";

// Rails sends {"errors": [...]} for validation errors and {"error": "..."} otherwise.
function errorFrom(status: number, body: unknown): Error {
  const data = (body ?? {}) as { errors?: string[]; error?: string };
  return new Error(data.errors?.join(", ") || data.error || `Server error (HTTP ${status})`);
}

const unreachable = () => new Error(`Could not reach the server at ${API_URL || window.location.origin}`);

async function getJson<T>(path: string): Promise<T> {
  let response: Response;
  try {
    response = await fetch(API_URL + path, { headers: { Accept: "application/json" } });
  } catch {
    throw unreachable();
  }
  const body = await response.json().catch(() => null);
  if (!response.ok) throw errorFrom(response.status, body);
  return body as T;
}

export const listParts = () => getJson<{ parts: Part[] }>("/parts").then((body) => body.parts);

export const getPart = (id: number) => getJson<Part>(`/parts/${id}`);

// POST /parts with the file. Uses XMLHttpRequest because fetch() can't report upload progress.
export function uploadPart(file: File, onProgress: (fraction: number) => void): Promise<Part> {
  return new Promise((resolve, reject) => {
    const form = new FormData();
    form.append("file", file);

    const xhr = new XMLHttpRequest();
    xhr.open("POST", `${API_URL}/parts`);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) onProgress(event.loaded / event.total);
    };
    xhr.onload = () => {
      let body: unknown = null;
      try {
        body = JSON.parse(xhr.responseText);
      } catch {
        // not JSON (e.g. a proxy error page); handled below
      }
      if (xhr.status === 201) resolve(body as Part);
      else reject(errorFrom(xhr.status, body));
    };
    xhr.onerror = () => reject(unreachable());
    xhr.send(form);
  });
}
