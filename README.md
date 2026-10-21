# CAD Viewer

**Live demo: https://guayabas.github.io/CAD-Viewer-Completed/** (open or drop a STEP file; it's meshed in your browser and never uploaded)

<!-- Screenshot: save one as docs/screenshot.png, then uncomment the next line. -->
<!-- ![CAD Viewer showing the NIST CTC 01 part](docs/screenshot.png) -->

Upload a CAD file (STEP), mesh it with Open CASCADE, store it in Postgres, and view it in the browser with React Three Fiber. The meshes keep their B-rep face IDs, the base for picking CAD faces to mark inspection regions or defects.

```
upload STEP ──► Rails API (Postgres, Active Storage) ──► TessellatePartJob (Solid Queue)
                                                              │
                                                              ▼
                                        tessellator (C++17, OCCT 7.6): STEP → GLB + JSON face map
                                                              │
                                                              ▼
                          React + R3F viewer polls the part and loads the GLB
```

| Folder | What it is |
|---|---|
| `tessellator/` | C++ CLI: STEP in, GLB + JSON metadata (bbox, counts, timings, face map) out |
| `web/` | Rails 8 JSON API: parts, tessellations, upload limits, background job |
| `viewer/` | Vite + React + TypeScript + R3F. Demo mode (static, meshes STEP in the browser with occt-import-js) or connected mode (`VITE_API_URL`, talks to Rails) |
| `samples/` | NIST CTC 01 STEP test file (public domain) |

More (architecture, data-model decisions, running locally, deploy) is coming in this README.
