// Web Worker: meshes STEP files with occt-import-js (OCCT in WebAssembly) off the main
// thread, so the page stays responsive. Started by stepLoader.ts on the first STEP file.
import occtimportjs, { type Occt, type OcctParams } from "occt-import-js";
// ?url: Vite copies the .wasm into the build and gives us its final URL.
import wasmUrl from "occt-import-js/dist/occt-import-js.wasm?url";
import type { StepMesh, StepRequest, StepResponse } from "./types";

// Close to the server's mesh density. occt-import-js measures the ratio against the average
// bounding-box side, the server against the diagonal: 0.02 here ≈ 0.01 there
// (NIST CTC 01: 9,724 vs 9,756 triangles).
const PARAMS: OcctParams = {
  linearUnit: "meter", // match the server's GLBs
  linearDeflectionType: "bounding_box_ratio",
  linearDeflection: 0.02,
  angularDeflection: 0.1,
};

// Load the 7.6 MB WASM once and reuse it for later files.
let occt: Promise<Occt> | null = null;
const getOcct = () =>
  (occt ??= occtimportjs({ locateFile: (path) => (path.endsWith(".wasm") ? wasmUrl : path) }));

self.onmessage = async (event: MessageEvent<StepRequest>) => {
  const { id, buffer } = event.data;
  try {
    const engine = await getOcct();
    const start = performance.now();
    const result = engine.ReadStepFile(new Uint8Array(buffer), PARAMS);
    if (!result.success) throw new Error("Could not read the STEP file");

    let nextFaceId = 0;
    const meshes: StepMesh[] = result.meshes.map((mesh) => ({
      name: mesh.name,
      color: mesh.color ?? null,
      positions: new Float32Array(mesh.attributes.position.array),
      normals: mesh.attributes.normal ? new Float32Array(mesh.attributes.normal.array) : null,
      indices: new Uint32Array(mesh.index.array),
      faces: mesh.brep_faces.map((face) => ({ id: nextFaceId++, first: face.first, count: face.last - face.first + 1 })),
    }));
    if (meshes.every((mesh) => mesh.indices.length === 0)) throw new Error("The STEP file has no surfaces to mesh");

    const response: StepResponse = { id, ok: true, meshes, ms: performance.now() - start };
    // Transfer the typed arrays' memory instead of copying it.
    const transfer = meshes.flatMap((m) => [m.positions.buffer, m.indices.buffer, ...(m.normals ? [m.normals.buffer] : [])]);
    self.postMessage(response, { transfer });
  } catch (error) {
    occt = null; // a WASM crash can leave the module unusable; reload it next time
    const message = error instanceof Error ? error.message : String(error);
    const response: StepResponse = { id, ok: false, error: message || "Could not mesh the STEP file" };
    self.postMessage(response);
  }
};
