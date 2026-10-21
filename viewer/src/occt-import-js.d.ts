// Types for occt-import-js (OCCT compiled to WebAssembly). The package ships none; these cover
// only what the viewer uses. See node_modules/occt-import-js/README.md.
declare module "occt-import-js" {
  export interface OcctParams {
    linearUnit?: "millimeter" | "centimeter" | "meter" | "inch" | "foot";
    linearDeflectionType?: "bounding_box_ratio" | "absolute_value";
    linearDeflection?: number;
    angularDeflection?: number;
  }

  type Rgb = [number, number, number];

  export interface OcctMesh {
    name: string;
    color?: Rgb;
    // Triangles first..last (both included) come from one B-rep face.
    brep_faces: { first: number; last: number; color: Rgb | null }[];
    attributes: { position: { array: number[] }; normal?: { array: number[] } };
    index: { array: number[] };
  }

  export interface OcctResult {
    success: boolean;
    meshes: OcctMesh[];
  }

  export interface Occt {
    ReadStepFile(content: Uint8Array, params: OcctParams | null): OcctResult;
  }

  // Emscripten module factory. locateFile tells it where the .wasm file is served from.
  export default function occtimportjs(overrides?: { locateFile?: (path: string) => string }): Promise<Occt>;
}
