// Main-thread side of in-browser STEP meshing: sends the file to the worker and turns the
// result into three.js objects. The file never leaves the visitor's computer.
import * as THREE from "three";
import type { StepFace, StepMesh, StepRequest, StepResponse } from "./types";

export interface StepModel {
  object: THREE.Group;
  faceCount: number;
  triangleCount: number;
  ms: number;
}

let worker: Worker | null = null;
let nextId = 1;
const waiting = new Map<number, { resolve: (r: StepResponse) => void; reject: (e: Error) => void }>();

// Created on first use, so the worker and the WASM are only downloaded when needed.
function getWorker(): Worker {
  if (worker) return worker;
  worker = new Worker(new URL("./stepWorker.ts", import.meta.url), { type: "module" });
  worker.onmessage = (event: MessageEvent<StepResponse>) => {
    waiting.get(event.data.id)?.resolve(event.data);
    waiting.delete(event.data.id);
  };
  worker.onerror = (event) => {
    // The worker itself failed (e.g. the WASM could not be downloaded): fail everything waiting.
    const error = new Error(event.message || "The STEP engine failed to load");
    waiting.forEach(({ reject }) => reject(error));
    waiting.clear();
    worker?.terminate();
    worker = null;
  };
  return worker;
}

export async function meshStepFile(file: File): Promise<StepModel> {
  const buffer = await file.arrayBuffer();
  const id = nextId++;
  const response = await new Promise<StepResponse>((resolve, reject) => {
    waiting.set(id, { resolve, reject });
    const request: StepRequest = { id, buffer };
    getWorker().postMessage(request, [buffer]);
  });
  if (!response.ok) throw new Error(response.error);

  return {
    object: buildObject(response.meshes),
    faceCount: response.meshes.reduce((n, m) => n + m.faces.length, 0),
    triangleCount: response.meshes.reduce((n, m) => n + m.indices.length / 3, 0),
    ms: response.ms,
  };
}

const DEFAULT_COLOR = new THREE.Color(0.7, 0.7, 0.75);

function buildObject(meshes: StepMesh[]): THREE.Group {
  const group = new THREE.Group();
  // OCCT is Z-up, glTF and the server's GLBs are Y-up: rotate -90° about X.
  group.rotation.x = -Math.PI / 2;

  for (const mesh of meshes) {
    if (mesh.indices.length === 0) continue;
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(mesh.positions, 3));
    if (mesh.normals) geometry.setAttribute("normal", new THREE.BufferAttribute(mesh.normals, 3));
    else geometry.computeVertexNormals();
    geometry.setIndex(new THREE.BufferAttribute(mesh.indices, 1));

    const material = new THREE.MeshStandardMaterial({
      color: mesh.color ? new THREE.Color(...mesh.color) : DEFAULT_COLOR,
      metalness: 0,
      roughness: 0.6,
    });
    const object = new THREE.Mesh(geometry, material);
    object.name = mesh.name;
    // Face ranges for picking: triangles [first, first + count) belong to B-rep face `id`.
    object.userData.faces = mesh.faces satisfies StepFace[];
    group.add(object);
  }
  return group;
}

// Free GPU memory of an object built above when it is replaced.
export function disposeObject(root: THREE.Object3D) {
  root.traverse((child) => {
    if (child instanceof THREE.Mesh) {
      child.geometry.dispose();
      (Array.isArray(child.material) ? child.material : [child.material]).forEach((m) => m.dispose());
    }
  });
}
