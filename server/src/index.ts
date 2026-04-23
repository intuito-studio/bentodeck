// Backend entry point. Boots the HTTP API, SQLite, and the poll scheduler.
//
// The MCP stdio server is NO LONGER launched from here — it lives in
// src/mcp-entry.ts and is spawned independently by Claude Desktop (or any
// MCP client). That split lets one backend process serve many short-lived
// MCP client processes, which is the production-correct shape.
import "dotenv/config";
import { seedPresetThemes } from "./db/repo.js";
import { initDb } from "./db/schema.js";
import { startHttpServer } from "./http/server.js";
import { startPoller } from "./scheduler/poller.js";
import { log } from "./logger.js";

async function main(): Promise<void> {
  initDb();
  seedPresetThemes();
  await startHttpServer();
  startPoller();
  log.info("BentoDeck backend up (MCP runs separately via src/mcp-entry.ts)");
}

main().catch((err: unknown) => {
  log.error("fatal:", err);
  process.exit(1);
});
