// Helpers shared by test files that need a fresh SQLite DB.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { __resetDbForTests, initDb } from "./db/schema.js";
import { seedPresetThemes } from "./db/repo.js";

export function withFreshDb(): { dir: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "bentodeck-test-"));
  process.env.BENTODECK_DATA_DIR = dir;
  __resetDbForTests();
  initDb();
  return {
    dir,
    cleanup: () => {
      __resetDbForTests();
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

export function withFreshDbAndThemes(): { dir: string; cleanup: () => void } {
  const handle = withFreshDb();
  seedPresetThemes();
  return handle;
}
