// Standalone entry for the MCP thin-client process.
//
// This is what Claude Desktop (or any MCP client) spawns as a subprocess
// over stdio. It does NOT boot the HTTP server, poller, SQLite, or AI
// SDKs — it only translates MCP tool calls into HTTP requests against
// the backend at BENTODECK_BASE_URL.
//
// Run directly:      npx tsx server/src/mcp-entry.ts
// Claude Desktop:    see README.md Phase 3 for the config snippet.
import "dotenv/config";
import { startMcpServer } from "./mcp/server.js";
import { log } from "./logger.js";

startMcpServer().catch((err: unknown) => {
  log.error("mcp-entry fatal:", err);
  process.exit(1);
});
