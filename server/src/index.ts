import "dotenv/config";
import { initDb } from "./db/schema.js";
import { startHttpServer } from "./http/server.js";
import { startMcpServer } from "./mcp/server.js";
import { startPoller } from "./scheduler/poller.js";
import { log } from "./logger.js";

async function main(): Promise<void> {
  initDb();
  await Promise.all([startHttpServer(), startMcpServer()]);
  startPoller();
  log.info("BentoDeck backend up");
}

main().catch((err: unknown) => {
  log.error("fatal:", err);
  process.exit(1);
});
