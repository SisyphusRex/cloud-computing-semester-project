import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    // Locally the APIs run as two services (`make dev-up`); in production one
    // load balancer serves both paths. Proxying keeps the app's URLs identical.
    proxy: {
      "/ingest": "http://localhost:8081",
      "/search": "http://localhost:8082",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
  },
});
