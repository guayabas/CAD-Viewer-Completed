// Messages between the main thread and the STEP worker.

export interface StepFace {
  id: number; // B-rep face index, 0..N-1 over the whole file (same shape as the server's face map)
  first: number; // first triangle
  count: number;
}

export interface StepMesh {
  name: string;
  color: [number, number, number] | null;
  positions: Float32Array; // meters, Z-up (OCCT axes); the viewer rotates to Y-up
  normals: Float32Array | null;
  indices: Uint32Array;
  faces: StepFace[];
}

export interface StepRequest {
  id: number;
  buffer: ArrayBuffer;
}

export type StepResponse =
  | { id: number; ok: true; meshes: StepMesh[]; ms: number }
  | { id: number; ok: false; error: string };
