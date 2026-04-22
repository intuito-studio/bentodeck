/**
 * Seeds a dashboard + data source + widget against a public API,
 * runs the poller for a few ticks, prints the latest snapshot, exits.
 * Lets us verify the polling + JMESPath extraction pipeline end-to-end
 * without needing an Anthropic API key or Claude Desktop.
 *
 * Run: npx tsx scripts/smoke-poller.ts
 */
import "dotenv/config";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { initDb } from "../src/db/schema.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  latestSnapshot,
} from "../src/db/repo.js";
import { log } from "../src/logger.js";
import { startPoller, stopPoller } from "../src/scheduler/poller.js";

async function main(): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), "bentodeck-smoke-"));
  process.env.BENTODECK_DATA_DIR = dir;
  try {
    initDb();

    const dash = createDashboard({ name: "Smoke", themeId: "default" });
    const src = createDataSource({
      name: "GitHub public API",
      type: "rest",
      url: "https://api.github.com/repos/anthropics/anthropic-sdk-typescript",
      method: "GET",
      pollIntervalSec: 10,
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "Stars",
      transformExpr: "stargazers_count",
      position: 0,
    });

    log.info(`seeded dashboard=${dash.id} source=${src.id} widget=${widget.id}`);

    startPoller();

    // Allow the first tick (immediate) + a bit for the HTTP fetch to finish.
    await new Promise((r) => setTimeout(r, 8000));

    const snap = latestSnapshot(widget.id);
    if (!snap) {
      log.error("NO SNAPSHOT — poller did not produce a value");
      process.exit(2);
    }
    log.info(`ok. value=${JSON.stringify(snap.value)} ts=${snap.ts}`);
  } finally {
    stopPoller();
    rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((err) => {
  log.error("smoke failed:", err);
  process.exit(1);
});
