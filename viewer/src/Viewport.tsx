import { Component, Suspense, useRef, type ReactNode } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Bounds, OrbitControls } from "@react-three/drei";
import * as THREE from "three";
import { GlbModel, ObjectModel } from "./Model";
import { sourceKey, type ModelSource } from "./modelSource";

interface Props {
  model: ModelSource | null;
  wireframe: boolean;
  onLoadError: (message: string) => void;
}

// The 3D view: lights, camera controls, and the model framed to fit.
export function Viewport({ model, wireframe, onLoadError }: Props) {
  return (
    // Start at a 3/4 view; Bounds keeps this direction and only moves the camera closer or farther.
    <Canvas camera={{ position: [1.0, 0.8, 1.2], near: 0.0001, far: 100 }}>
      <hemisphereLight args={["#ffffff", "#8a8a99", 1.2]} />
      <Headlight intensity={1.8} />
      {model && (
        // key: a new model gets a fresh error boundary and a fresh fit.
        <ModelErrorBoundary key={sourceKey(model)} onError={onLoadError}>
          <Suspense fallback={null}>
            {/* fit: frame the model once it loads. clip: set near/far from its size. observe: refit on resize. */}
            <Bounds fit clip observe margin={1.2}>
              {model.kind === "url" ? (
                <GlbModel url={model.url} wireframe={wireframe} />
              ) : (
                <ObjectModel object={model.object} wireframe={wireframe} />
              )}
            </Bounds>
          </Suspense>
        </ModelErrorBoundary>
      )}
      <OrbitControls makeDefault />
    </Canvas>
  );
}

// A directional light that follows the camera, as in most CAD viewers: whatever you look at
// is lit, and faces turned away from you get darker, which shows the shape.
function Headlight({ intensity }: { intensity: number }) {
  const light = useRef<THREE.DirectionalLight>(null);
  const camera = useThree((state) => state.camera);
  const controls = useThree((state) => state.controls) as unknown as { target?: THREE.Vector3 } | null;

  // useFrame runs before every rendered frame.
  useFrame(() => {
    if (!light.current) return;
    light.current.position.copy(camera.position);
    light.current.target.position.copy(controls?.target ?? new THREE.Vector3());
    light.current.target.updateMatrixWorld(); // the target isn't in the scene, so update it by hand
  });

  return <directionalLight ref={light} intensity={intensity} />;
}

// If the GLB fails to load (bad URL, CORS, corrupt file), report it instead of crashing the
// whole canvas. React only supports error boundaries as class components.
class ModelErrorBoundary extends Component<
  { children: ReactNode; onError: (message: string) => void },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(error: Error) {
    this.props.onError(error.message || "Could not load the model");
  }

  render() {
    return this.state.failed ? null : this.props.children;
  }
}
