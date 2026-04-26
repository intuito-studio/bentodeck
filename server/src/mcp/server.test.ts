import { describe, expect, it } from "vitest";
import { buildMcpServer } from "./server.js";

// Minimal MCP surface test. We don't roundtrip stdio (complex, low value);
// we just assert every tool listed in server.ts got registered.

describe("MCP server registration", () => {
  it("registers all expected tools", () => {
    const mcp = buildMcpServer();
    // McpServer keeps tools in _registeredTools (see mcp.js internals).
    const registered = (
      mcp as unknown as { _registeredTools: Record<string, unknown> }
    )._registeredTools;
    const names = Object.keys(registered).sort();

    expect(names).toEqual(
      [
        "ping",
        "create_dashboard",
        "list_dashboards",
        "delete_dashboard",
        "set_dashboard_theme",
        "add_data_source",
        "discover_data_source",
        "list_data_sources",
        "add_widget",
        "list_widgets",
        "create_widget_from_intent",
        "get_widget_state",
        "list_investigations",
        "get_investigation",
        "list_themes",
        "apply_theme_preset",
        "generate_theme",
      ].sort(),
    );
    expect(names).toHaveLength(17);
  });
});
