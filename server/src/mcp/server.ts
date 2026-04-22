import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { log } from "../logger.js";

export async function startMcpServer(): Promise<void> {
  const mcp = new McpServer({
    name: "bentodeck",
    version: "0.1.0",
  });

  // Sanity-check tool. Real tools (create_dashboard_from_intent, add_widget,
  // generate_theme, etc.) land in the next milestone.
  mcp.tool(
    "ping",
    "Health check. Returns a pong message so Claude Desktop can verify the BentoDeck MCP server is connected.",
    {},
    async () => ({
      content: [
        {
          type: "text",
          text: "pong — bentodeck mcp server connected",
        },
      ],
    }),
  );

  const transport = new StdioServerTransport();
  await mcp.connect(transport);
  log.info("MCP stdio server connected");
}
