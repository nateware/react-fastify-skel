import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    include: ["test/**/*.test.ts"],
    // Use forks pool with tsx so Node.js resolves .js → .ts imports.
    // Needed because @fastify/autoload uses dynamic import() which
    // bypasses Vite's module resolution pipeline.
    pool: "forks",
    poolOptions: {
      forks: {
        execArgv: ["--import", "tsx"],
      },
    },
  },
});
