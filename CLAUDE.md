# CAD-Viewer

A web app that ingests CAD files, tessellates them with Open CASCADE (OCCT), stores parts in Postgres and shows them in the browser with React + React Three Fiber (R3F). The goal is a small, clean, end-to-end product (schema → API → UI → deploy), with the graphics and geometry done properly.

## Architecture (target)

```
upload STEP ──► Rails (Postgres, Active Storage) ──► background job (Solid Queue)
                                                        │
                                                        ▼
                                         tessellator (C++ CLI, OCCT)
                                         STEP in → GLB + JSON metadata out
                                                        │
                                                        ▼
                         React + R3F viewer loads the GLB from Rails
```

All three pieces are connected: the viewer uploads to Rails, Rails runs the tessellator in a job, and the viewer polls and loads the GLB.

- **tessellator/**: C++17 CLI built with CMake against OCCT 7.6.3 (Ubuntu apt packages). `tessellator <in.step> <out.glb> [--rel-deflection 0.01] [--angular 0.1] [--meta out.json]`. Exit codes: 0 ok, 1 read/transfer error, 2 usage error, 3 mesh/export error; errors on stderr.
- **viewer/**: Vite + React + TypeScript + R3F (`three`, `@react-three/fiber`, `@react-three/drei`). One codebase, two modes, picked at build time by `VITE_API_URL`:
  - **Demo** (unset): for viewing. Opens the bundled NIST GLB, local `.glb` files, and local STEP files meshed in the browser. Static, published to GitHub Pages.
  - **Connected** (`VITE_API_URL=http://localhost:3000 npm run dev`, or copy `.env.example` to `.env.development.local`): for saving. Everything goes through the server: parts panel, upload with progress (button or drag and drop), polling every 1.5 s while pending/processing, loads `glb_url`. No local file opening in this mode (user decision: demo = view, connected = save to the database).
  - Local files (demo mode, "Open file" or drag and drop): `.glb` loads directly; `.step`/`.stp` is meshed by **occt-import-js** (OCCT 7.x in WASM, LGPL-2.1, 7.6 MB `.wasm`) in a Web Worker (`src/step/stepWorker.ts`, created lazily by `stepLoader.ts`), so the WASM downloads only when a STEP file is opened and the page doesn't freeze. Params: `linearUnit: meter`, `bounding_box_ratio` 0.02 (its ratio is against the average bbox side, not the diagonal; ≈ server's 0.01), angular 0.1. Output is Z-up, so the built group is rotated -90° about X. Each mesh keeps `userData.faces` = `{id, first, count}[]`, the same shape as the server's face map.
  - Testing the worker without a browser: run the built `dist/assets/stepWorker-*.js` in Node with a harness that defines `self`/`postMessage`, serves `fetch` from `dist/`, and hides `process` (otherwise Emscripten takes its Node path and fails on `__dirname`).
  - Files: `api.ts` (types + fetch/XHR client; XHR because fetch has no upload progress), `useParts.ts` (hook with all server state and polling), `PartsPanel.tsx`, `Viewport.tsx` (Canvas, headlight + hemisphere light, Bounds, error boundary for failed GLB loads), `modelSource.ts` (`ModelSource` = GLB URL or prebuilt object), `Model.tsx` (`GlbModel`, `ObjectModel`), `App.tsx` (mode switch, local files, status messages).
  - oxlint `only-export-components`: `.tsx` files export only components (keeps React fast refresh working); put shared types and helpers in `.ts` files.
  - Lint with `npm run lint` (oxlint). Its `set-state-in-effect` rule: set state from event handlers or async callbacks, not synchronously in `useEffect`.
- **web/**: Rails 8.1 app (`-d postgresql -j esbuild`) used as a JSON API: Postgres, Solid Queue, Active Storage (local disk in dev, R2 later), rack-cors. Databases `cad_viewer_autogen_development` / `cad_viewer_autogen_test` (renamed so this copy doesn't share the original `CAD-Viewer` app's `web_development`).
  - API (`PartsController < ApiController < ActionController::API`, JSON from `app/views/parts/*.json.jbuilder`): `POST /parts` (multipart `file`, optional `name`) → 201 + pending part; `GET /parts` (latest 100, no face maps); `GET /parts/:id` (with `tessellation.face_map` and `glb_url`, a Rails redirect URL to the blob).
  - Upload limits: `.step`/`.stp` only, 50 MB (`Part::MAX_FILE_SIZE`, also checked from Content-Length before parsing), `rate_limit` 10 uploads/min per IP on create, tessellator timeout.
  - `TessellatePartJob`: pending → processing → ready / failed. Downloads the source to a temp dir, runs `Tessellator#run` (`app/models/tessellator.rb`, wraps the CLI with `Open3.capture3` and coreutils `timeout`), creates a `Tessellation` with the GLB attached. Failures store a readable message (the CLI's stderr, with the temp path replaced by the uploaded file name) in `error_message`; no retries.
  - Config (`config/initializers/tessellator.rb`, env vars): `TESSELLATOR_BIN` (default `../tessellator/build/tessellator`), `TESSELLATOR_TIMEOUT` (120 s), `TESSELLATOR_REL_DEFLECTION` (0.01), `TESSELLATOR_ANGULAR_DEFLECTION` (0.1). CORS: `CORS_ORIGINS` (comma-separated, default `http://localhost:5173`).
  - Seed (`db/seeds.rb`): creates the "NIST CTC 01" part from `samples/` and meshes it with `perform_now` (the command exits before an async job would run). Idempotent.
  - Tests: `bin/rails test` (models, the CLI wrapper with fake shell-script binaries for errors/timeouts, the job with the real binary and the committed sample, the API). The real-binary tests skip if the tessellator isn't built. Also `bin/rubocop` and `bin/brakeman`.
- **samples/**: test CAD files (e.g. NIST CTC 01 `nist_ctc_01_asme1_ap242-e1.stp`). Git-ignored.

## Data model (will be defended in the README)

- **parts** (exists): `name`, `file_format` (`step`/`iges`/`brep`), `status` enum (pending 0 → processing 1 → ready 2 / failed 3, indexed), `error_message`, `has_one_attached :source_file`.
- **tessellations** (exists): belongs_to part (indexed, foreign key); `has_one_attached :glb`, `rel_deflection`, `linear_deflection` (m), `angular_deflection` (rad), `triangle_count`, `face_count`, `bbox` (jsonb), `face_map` (jsonb), `timings` (jsonb), `occt_version`. All `null: false` except `occt_version`. `Part#latest_tessellation` is the newest one.
- Tessellations are a separate table because one part can have several quality levels.
- **Keep the B-rep face IDs** in the output (triangle range per face) so the viewer can pick and highlight CAD faces. This is the base for marking inspection regions or defects on a part.
- Possible later: **inspection_regions** (part_id, face_ids, label), to save picked faces.

## Milestones

1. [x] Tessellator: procedural shape → BRepMesh → XCAF → GLB. Verified in Blender.
2. [x] Tessellator reads real STEP files (`STEPCAFControl_Reader`, with colors and names) and meshes each free shape. Deflection is relative: linear = 1% of the bbox diagonal, angular = 0.1 rad.
3. [x] Tessellator CLI: arguments, exit codes, JSON metadata (OCCT version, settings, bbox in meters/Y-up, triangle and face counts, timings, face map). Faces are merged into one glTF primitive per part (`SetMergeFaces`).
4. [x] Rails app: `Part` and `Tessellation` models, `TessellatePartJob`, JSON API, upload limits, CORS, tests. **Later:** Solid Queue queue-database choice for production (milestone G).
5. [~] Viewer: open a GLB, orbit controls, zoom-to-fit, wireframe/shaded toggle, headlight, connected mode (parts list, upload, polling, load from Rails). **Next:** B-rep edges as lines, face picking with the face map.
6. [x] Open a local STEP file in the browser without the server (occt-import-js in a Web Worker), plus drag and drop.
7. [~] GitHub Pages: `.github/workflows/pages.yml` builds `viewer/` in demo mode with `VITE_BASE=/<repo>/` (`vite.config.ts` reads it) and deploys with `actions/deploy-pages`. Repo: `git@github.com:guayabas/CAD-Viewer-Completed.git`, site https://guayabas.github.io/CAD-Viewer-Completed/. Not pushed yet (the user commits). Needs Settings → Pages → Source: GitHub Actions.
8. [ ] Docker (multi-stage: build the tessellator, ship the OCCT runtime libs with Rails), deploy, README with architecture and data-model decisions.

Tessellator next steps: export B-rep edge polylines (for drawing edges as lines).

## How the tessellator works

1. `STEPCAFControl_Reader` reads the STEP file into an XCAF document (shapes, names, colors, assembly).
2. `BRepMesh_IncrementalMesh` does the meshing. Its constructor stores a `Poly_Triangulation` on every face. It is the only step that creates triangles.
3. Exploring the faces with `BRep_Tool::Triangulation` only reads that mesh back (for counts and normals). It does not mesh.
4. XCAF (`XCAFDoc_ShapeTool`) holds the B-rep and its structure, not triangles.
5. `RWGltf_CafWriter` writes the existing triangulations. Without step 2 it writes an empty GLB. With `SetMergeFaces(true)` each part is one primitive.
6. **Face map:** `FaceMapWriter` (`face_map_writer.h/.cpp`) subclasses the writer and overrides `saveIndices`, which runs once per face, in output order, while that face's triangles are appended to the primitive. It records `{primitive, face id, first triangle, count}`, so the map matches the GLB by construction. In the JSON, each primitive is identified by `indices_accessor` (= `meshes[m].primitives[p].indices` in the GLB); in three.js, `gltf.parser.associations.get(mesh)` gives `{meshes, primitives}` to look it up. Face ids are 0..N-1 in writer order.
7. Units: OCCT is mm and Z-up, glTF is meters and Y-up. Set on the writer: `SetInputLengthUnit(0.001)` and `SetInputCoordinateSystem(RWMesh_CoordinateSystem_Zup)`.

## Environment and gotchas found so far

- Windows 11 + WSL **Ubuntu 24.04**. The project lives in the Linux filesystem (`~/Projects/CAD-Viewer`), not `/mnt/c` (too slow).
- VS Code must be opened **through WSL** (`code .` from Ubuntu; the bottom-left corner says "WSL: Ubuntu-24.04"), with the C/C++ extension installed in WSL. Opening `\\wsl.localhost\...` from Windows makes IntelliSense use MSVC and Windows paths.
- `.vscode/c_cpp_properties.json`: g++, `linux-gcc-x64`, `compileCommands` → `build/compile_commands.json`, include `/usr/include/opencascade`. CMake has `CMAKE_EXPORT_COMPILE_COMMANDS ON`.
- Use LF line endings (`"files.eol": "\n"`).
- Ubuntu's OCCT is built with TBB: install `libtbb-dev`, otherwise the build fails with `No rule to make target .../libtbb.so`. For any other missing `.so`, use `apt-file search` and install the `-dev` package.
- OCCT headers are included as **SYSTEM** (`target_include_directories(... SYSTEM ...)`) to hide OCCT's `std::iterator` deprecation warnings; `-Wall -Wextra` stay on for our code.
- Link only the toolkits used directly; OCCT's CMake config adds their dependencies. Current set: TKXDESTEP TKSTEP TKMesh TKTopAlgo TKXCAF TKLCAF TKRWMesh.
- Normals: OCCT 7.6 `BRepMesh` stores no normals, and that is fine: `RWGltf_CafWriter` (via `RWMesh_FaceIterator`) computes them from the exact surface and flips them for reversed faces. **Do not** precompute them with `BRepLib::EnsureNormalConsistency(..., true)`: it stores raw surface normals and the writer exports them unflipped, so reversed faces get inverted normals (3 of 6 faces on a box). `BRepLib_ToolTriangulatedShape` does not exist in 7.6.3 (`StdPrs_ToolTriangulatedShape` does, but it is in the visualization toolkit). Checked by comparing normals with triangle winding: only degenerate slivers (~1e-6 mm²) disagree.
- **Black model in the viewer:** two causes. (1) No lights: `MeshStandardMaterial` is lit, so a scene without lights renders black. Only `ambientLight` looks flat (no shading); the viewer uses a headlight (directional light that follows the camera) plus a hemisphere light. (2) A GLB with no material gets glTF's default material (metalness = 1), which looks dark with no environment to reflect. The viewer sets `metalness = 0`, `roughness = 0.6`. Long-term fix: write a color or material from the tessellator.
- The canvas needs a parent with height (`html, body, #root { height: 100% }` and `.app { height: 100% }`), or it stays small.
- Dev ports: Rails 3000, Vite 5173. CORS only allows origins in `CORS_ORIGINS` (default `http://localhost:5173`); a Vite on another port needs to be added there.
- Camera `near: 0.0001`, because parts arrive in meters (a 10 mm part is 0.01 m).
- drei `<Bounds>` does nothing on load unless you pass `fit` (use `fit clip observe`). It keeps the camera's starting direction, so start the camera at a 3/4 view, not straight down an axis.
- Node from nvm (LTS). Ubuntu's apt Node 18 is too old for current Vite.

## Conventions

- Boring, well-known tools: Rails, React, Postgres; save new ideas for the graphics and geometry.
- Name things and design the schema before writing code; record the reasons in the README.
- C++17, CMake, OCCT. TypeScript for the viewer.
- The viewer's default model `viewer/public/nist_ctc_01_asme1_ap242-e1.glb` and its `.json` metadata are generated from `samples/`; regenerate both after tessellator changes.
- Commit `package.json`, `package-lock.json`, `tsconfig*.json`, `vite.config.ts`, `index.html`, and the sample `viewer/public/nist_ctc_01_asme1_ap242-e1.glb` + `.json` (allowed through the `viewer/public/*.glb` ignore rule). Ignored: `tessellator/build/`, `tessellator/*.glb`, `viewer/public/*.glb`, `samples/` (except the NIST STEP and its README), `node_modules`, `dist`, `CLAUDE.local.md`, `HANDOFF.md`, and `*:Zone.Identifier`.
