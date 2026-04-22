import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Scrub env vars that might trigger outbound network calls.
    setupFiles: ["./src/test-setup.ts"],
    // Default pool (forks) + isolation means each test file gets its own
    // module cache — the DB singleton leak only matters within a file.
    testTimeout: 10_000,
    hookTimeout: 10_000,
    // NodeNext `.js` specifiers just work with vitest's default resolver.
  },
});
