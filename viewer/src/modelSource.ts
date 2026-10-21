import type * as THREE from "three";

// What the viewport shows: a GLB by URL (server part, bundled sample, local .glb), or an
// object already built in the browser (a local STEP file meshed by occt-import-js).
export type ModelSource =
  | { kind: "url"; url: string }
  | { kind: "object"; object: THREE.Object3D; key: string };

// Changes whenever a different model is shown (used as a React key to reset fit and errors).
export const sourceKey = (source: ModelSource) => (source.kind === "url" ? source.url : source.key);
