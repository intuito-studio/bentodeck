import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  createDashboard,
  createDataSource,
  createWidget,
  deleteDashboard,
  getDashboard,
  getDataSource,
  listDashboards,
  listDataSources,
  listWidgetsForDashboard,
  setDashboardTheme,
} from "../db/repo.js";
import { log } from "../logger.js";

function text(t: string) {
  return { content: [{ type: "text" as const, text: t }] };
}

function json(v: unknown) {
  return text(JSON.stringify(v, null, 2));
}

export async function startMcpServer(): Promise<void> {
  const mcp = new McpServer({
    name: "bentodeck",
    version: "0.1.0",
  });

  // -------- sanity --------

  mcp.tool(
    "ping",
    "Health check — returns pong so Claude can verify the BentoDeck MCP server is connected.",
    {},
    async () => text("pong — bentodeck mcp server connected"),
  );

  // -------- dashboards --------

  mcp.tool(
    "create_dashboard",
    "Create an empty dashboard. Returns the new dashboard id. Add widgets to it with add_widget afterwards.",
    {
      name: z.string().min(1).describe("User-facing name, e.g. 'SaaS Health'"),
      themeId: z
        .string()
        .optional()
        .describe("Preset theme id (default, cyberpunk, terminal, paper, bento-orange, pastel). Omit for default."),
    },
    async ({ name, themeId }) => {
      const dash = createDashboard({ name, themeId: themeId ?? "default" });
      return json({ dashboard: dash });
    },
  );

  mcp.tool(
    "list_dashboards",
    "List all dashboards on this BentoDeck instance with their ids, names, and themes.",
    {},
    async () => json({ dashboards: listDashboards() }),
  );

  mcp.tool(
    "delete_dashboard",
    "Delete a dashboard by id. Cascades to its widgets and their snapshots. Does not delete shared data sources.",
    {
      id: z.string().describe("Dashboard id returned from create_dashboard."),
    },
    async ({ id }) => {
      const ok = deleteDashboard(id);
      return text(ok ? `deleted ${id}` : `no dashboard with id ${id}`);
    },
  );

  mcp.tool(
    "set_dashboard_theme",
    "Change the theme of an existing dashboard. Use apply_theme_preset for presets or generate_theme for AI-generated themes.",
    {
      dashboardId: z.string(),
      themeId: z.string().describe("Either a preset id or a previously-saved theme id."),
    },
    async ({ dashboardId, themeId }) => {
      const ok = setDashboardTheme(dashboardId, themeId);
      return text(ok ? `theme set to ${themeId}` : `no dashboard with id ${dashboardId}`);
    },
  );

  // -------- data sources --------

  mcp.tool(
    "add_data_source",
    "Register a REST API data source. You provide the URL, method, headers, and optional auth. BentoDeck will poll this URL on a schedule and feed the result to widgets. For auth, use authHeaderKey='Authorization' and authHeaderValue='Bearer sk-…' or similar.",
    {
      name: z.string().min(1).describe("Short label, e.g. 'Stripe MRR'."),
      url: z.string().url(),
      method: z.enum(["GET", "POST"]).default("GET"),
      headers: z
        .record(z.string(), z.string())
        .optional()
        .describe("Extra headers as a flat key→value map."),
      authHeaderKey: z.string().optional().describe("e.g. 'Authorization'"),
      authHeaderValue: z.string().optional().describe("e.g. 'Bearer sk-…'"),
      pollIntervalSec: z
        .number()
        .int()
        .positive()
        .max(3600)
        .default(60)
        .describe("How often to poll, in seconds. Min 1, max 3600."),
    },
    async (input) => {
      const src = createDataSource({
        name: input.name,
        type: "rest",
        url: input.url,
        method: input.method,
        headers: input.headers,
        authHeaderKey: input.authHeaderKey,
        authHeaderValue: input.authHeaderValue,
        pollIntervalSec: input.pollIntervalSec,
      });
      // Don't leak the auth header in the returned record.
      const { authHeaderValue: _omit, ...safe } = src;
      return json({ source: safe });
    },
  );

  mcp.tool(
    "list_data_sources",
    "List registered data sources (without secrets). Useful when you want to attach a new widget to an existing source.",
    {},
    async () => {
      const sources = listDataSources().map((s) => {
        const { authHeaderValue: _omit, ...safe } = s;
        return safe;
      });
      return json({ sources });
    },
  );

  // -------- widgets --------

  mcp.tool(
    "add_widget",
    "Add a widget to a dashboard. You must provide the JMESPath expression that extracts the value from the source's JSON response. For AI-assisted creation (recommended), use create_widget_from_intent once that tool ships.",
    {
      dashboardId: z.string(),
      sourceId: z.string(),
      type: z.enum([
        "number",
        "number_with_trend",
        "gauge",
        "sparkline",
        "list",
        "status",
      ]),
      title: z.string().min(1).describe("Short label shown on the widget."),
      transformExpr: z
        .string()
        .min(1)
        .describe(
          "JMESPath expression applied to the source's latest JSON response. E.g. 'data.mrr' or 'length(errors[?level==\\'critical\\'])'.",
        ),
      position: z.number().int().nonnegative().default(0),
    },
    async (input) => {
      const dash = getDashboard(input.dashboardId);
      if (!dash) return text(`no dashboard with id ${input.dashboardId}`);
      const src = getDataSource(input.sourceId);
      if (!src) return text(`no data source with id ${input.sourceId}`);
      const widget = createWidget(input);
      return json({ widget });
    },
  );

  mcp.tool(
    "list_widgets",
    "List widgets attached to a dashboard.",
    {
      dashboardId: z.string(),
    },
    async ({ dashboardId }) => {
      const widgets = listWidgetsForDashboard(dashboardId);
      return json({ widgets });
    },
  );

  const transport = new StdioServerTransport();
  await mcp.connect(transport);
  log.info("MCP stdio server connected");
}
