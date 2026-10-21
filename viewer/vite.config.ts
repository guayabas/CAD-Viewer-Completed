import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // URL prefix the site is served from. "/" locally; GitHub Pages serves a project site from
  // "/<repo>/", so the Pages workflow sets VITE_BASE to that.
  base: process.env.VITE_BASE ?? '/',
})
