import { useCallback, useEffect, useState } from "react";
import { getPart, isInProgress, listParts, uploadPart, type Part } from "./api";

const POLL_MS = 1500;

export interface UploadState {
  fileName: string;
  progress: number; // 0..1
  error: string | null;
}

// All server state for connected mode: the parts list, the selected part, uploads, and
// polling of parts that are still being processed. Does nothing when `enabled` is false
// (React hooks can't be called conditionally, so demo mode passes false instead).
export function useParts(enabled: boolean) {
  const [parts, setParts] = useState<Part[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [upload, setUpload] = useState<UploadState | null>(null);

  const replacePart = (fresh: Part) => setParts((prev) => prev.map((p) => (p.id === fresh.id ? fresh : p)));

  // Fetch the list; state is set only when the request finishes. Returns a cancel function.
  const load = useCallback(() => {
    let cancelled = false;
    listParts()
      .then((list) => {
        if (cancelled) return;
        setParts(list);
        setLoadError(null);
        // Show something right away: the newest ready part.
        setSelectedId((current) => current ?? list.find((p) => p.status === "ready")?.id ?? null);
      })
      .catch((error: Error) => !cancelled && setLoadError(error.message))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, []);

  // Load the list once on start. useEffect runs after the first render; returning the cancel
  // function makes React ignore a late response if the component goes away.
  useEffect(() => (enabled ? load() : undefined), [enabled, load]);

  // "Retry" button (an event handler, so setting state first is fine).
  const refresh = useCallback(() => {
    setLoading(true);
    setLoadError(null);
    load();
  }, [load]);

  // Poll parts that are pending/processing until they are ready or failed. The effect
  // re-runs whenever the set of in-progress ids changes, and stops when it is empty.
  const inProgressIds = parts.filter(isInProgress).map((p) => p.id).join(",");
  useEffect(() => {
    if (!inProgressIds) return;
    let cancelled = false;
    const timer = setInterval(async () => {
      try {
        const fresh = await Promise.all(inProgressIds.split(",").map((id) => getPart(Number(id))));
        if (!cancelled) fresh.forEach(replacePart);
      } catch {
        // Temporary network error: keep polling.
      }
    }, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [inProgressIds]);

  const uploadFile = useCallback(async (file: File) => {
    setUpload({ fileName: file.name, progress: 0, error: null });
    try {
      const part = await uploadPart(file, (progress) =>
        setUpload((u) => (u ? { ...u, progress } : u)),
      );
      setParts((prev) => [part, ...prev]);
      setSelectedId(part.id);
      setUpload(null);
    } catch (error) {
      setUpload((u) => (u ? { ...u, error: (error as Error).message } : u));
    }
  }, []);

  const selected = parts.find((p) => p.id === selectedId) ?? null;

  return {
    parts,
    selected,
    select: setSelectedId,
    loading,
    loadError,
    refresh,
    upload,
    uploadFile,
    dismissUpload: () => setUpload(null),
  };
}
