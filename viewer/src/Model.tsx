import { useEffect } from "react";
import { useGLTF } from "@react-three/drei";
import * as THREE from "three";
import { disposeObject } from "./step/stepLoader";

// Same look for both kinds. A GLB without a material gets glTF's default (metalness 1),
// which renders almost black without an environment map, so force a matte plastic look.
function applyDisplay(root: THREE.Object3D, wireframe: boolean) {
  root.traverse((child) => {
    if (!(child instanceof THREE.Mesh)) return;
    const materials = Array.isArray(child.material) ? child.material : [child.material];
    for (const material of materials) {
      material.wireframe = wireframe;
      if (material instanceof THREE.MeshStandardMaterial) {
        material.metalness = 0;
        material.roughness = 0.6;
      }
    }
  });
}

export function GlbModel({ url, wireframe }: { url: string; wireframe: boolean }) {
  // useGLTF suspends (shows the Suspense fallback) until the file has loaded, and caches it by URL.
  const { scene } = useGLTF(url);
  useEffect(() => applyDisplay(scene, wireframe), [scene, wireframe]);
  return <primitive object={scene} />;
}

export function ObjectModel({ object, wireframe }: { object: THREE.Object3D; wireframe: boolean }) {
  useEffect(() => applyDisplay(object, wireframe), [object, wireframe]);
  // When this object is replaced or removed, free its GPU buffers.
  useEffect(() => () => disposeObject(object), [object]);
  return <primitive object={object} />;
}
