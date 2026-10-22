// Types for the VITE_* variables Vite inlines at build time (import.meta.env).
interface ImportMetaEnv {
  readonly VITE_API_URL?: string;
  // Demo mode only: link to the deployed full app (Rails + database), e.g. the Render URL.
  readonly VITE_FULL_APP_URL?: string;
}
