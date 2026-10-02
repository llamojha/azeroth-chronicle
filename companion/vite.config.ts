import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Tauri serves the dev frontend on a fixed port and expects the build output in
// ./dist (see src-tauri/tauri.conf.json `frontendDist`).
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  build: {
    outDir: "dist",
    target: "es2021",
    sourcemap: true,
  },
});
