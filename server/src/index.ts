import "dotenv/config";
import { initDb } from "./db/schema.js";
import { startHttpServer } from "./http/server.js";
import { startMcpServer } from "./mcp/server.js";
import { log } from "./logger.js";

async function main(): Promise<void> {
  initDb();
  await Promise.all([startHttpServer(), startMcpServer()]);
  log.info("BentoDeck backend up");
}

main().catch((err: unknown) => {
  log.error("fatal:", err);
  process.exit(1);
});
