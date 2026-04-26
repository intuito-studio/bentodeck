import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { log } from "../logger.js";

/**
 * THIN MCP CLIENT.
 *
 * Every tool here is a stdio-shaped wrapper around an HTTP call to the
 * BentoDeck backend. No direct DB access, no Anthropic SDK, no poller.
 * This lets Claude Desktop spawn a tiny per-conversation process while
 * the backend stays a long-lived, centralized service with the scheduler
 * and SQLite — the architecture a production SaaS would have.
 *
 * The backend URL is read from BENTODECK_BASE_URL (defaults to localhost
 * on the demo port). Error bodies from the backend are surfaced verbatim
 * to Claude, so it can explain failures back to the user without us
 * re-humanizing them here.
 */

function text(t: string) {
  return { content: [{ type: "text" as const, text: t }] };
}

function json(v: unknown) {
  return text(JSON.stringify(v, null, 2));
}

const PRESET_IDS = [
  "default",
  "cyberpunk",
  "terminal",
  "paper",
  "bento-orange",
  "pastel",
] as const;

function resolveBaseUrl(): string {
  const raw = process.env.BENTODECK_BASE_URL ?? "http://localhost:3737";
  return raw.replace(/\/+$/, "");
}

async function http<T = unknown>(
  method: "GET" | "POST" | "DELETE" | "PATCH",
  path: string,
  body?: unknown,
  baseUrl: string = resolveBaseUrl(),
): Promise<{ ok: boolean; status: number; data: T | string }> {
  const url = `${baseUrl}${path}`;
  const init: RequestInit = {
    method,
    headers: body
      ? { "Content-Type": "application/json", Accept: "application/json" }
      : { Accept: "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  };
  try {
    const res = await fetch(url, init);
    const raw = await res.text();
    const contentType = res.headers.get("content-type") ?? "";
    let parsed: T | string = raw;
    if (contentType.includes("application/json")) {
      try {
        parsed = JSON.parse(raw) as T;
      } catch {
        /* keep raw */
      }
    }
    return { ok: res.ok, status: res.status, data: parsed };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      data: err instanceof Error ? err.message : String(err),
    };
  }
}

export function buildMcpServer(baseUrl: string = resolveBaseUrl()): McpServer {
  const mcp = new McpServer({
    name: "bentodeck",
    version: "0.1.0",
  });

  const call = <T>(
    method: "GET" | "POST" | "DELETE" | "PATCH",
    path: string,
    body?: unknown,
  ) => http<T>(method, path, body, baseUrl);

  const formatError = (
    action: string,
    r: Awaited<ReturnType<typeof call>>,
  ) => {
    if (r.status === 0) {
      return text(
        `couldn't reach BentoDeck backend at ${baseUrl} (${r.data}). Is \`npm start\` running?`,
      );
    }
    const detail =
      typeof r.data === "string" ? r.data : JSON.stringify(r.data);
    return text(`${action} failed: HTTP ${r.status} ${detail}`);
  };

  // -------- sanity --------

  mcp.tool(
    "ping",
    "Health check. Returns pong when the BentoDeck MCP and its backend are reachable.",
    {},
    async () => {
      const r = await call<{ ok: boolean }>("GET", "/health");
      if (!r.ok) return formatError("ping", r);
      return text("pong — bentodeck backend reachable");
    },
  );

  // -------- dashboards --------

  mcp.tool(
    "create_dashboard",
    "Create an empty dashboard. Returns the new dashboard id. Add widgets with create_widget_from_intent afterwards.",
    {
      name: z.string().min(1).describe("User-facing name, e.g. 'SaaS Health'"),
      themeId: z
        .string()
        .optional()
        .describe(
          `Preset theme id (${PRESET_IDS.join(", ")}). Omit for default.`,
        ),
    },
    async ({ name, themeId }) => {
      const r = await call("POST", "/dashboards", { name, themeId });
      if (!r.ok) return formatError("create_dashboard", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "list_dashboards",
    "List all dashboards on this BentoDeck instance with their ids, names, and themes.",
    {},
    async () => {
      const r = await call("GET", "/dashboards");
      if (!r.ok) return formatError("list_dashboards", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "delete_dashboard",
    "Delete a dashboard by id. Cascades to its widgets and their snapshots. Does not delete shared data sources.",
    {
      id: z.string().describe("Dashboard id returned from create_dashboard."),
    },
    async ({ id }) => {
      const r = await call("DELETE", `/dashboards/${encodeURIComponent(id)}`);
      if (!r.ok) return formatError("delete_dashboard", r);
      return text(`deleted ${id}`);
    },
  );

  mcp.tool(
    "set_dashboard_theme",
    "Change the theme of an existing dashboard. Use apply_theme_preset for presets or generate_theme for AI-generated themes.",
    {
      dashboardId: z.string(),
      themeId: z
        .string()
        .describe("Either a preset id or a previously-saved theme id."),
    },
    async ({ dashboardId, themeId }) => {
      const r = await call(
        "PATCH",
        `/dashboards/${encodeURIComponent(dashboardId)}/theme`,
        { themeId },
      );
      if (!r.ok) return formatError("set_dashboard_theme", r);
      return json(r.data);
    },
  );

  // -------- data sources --------

  mcp.tool(
    "add_data_source",
    "Register a REST API data source. BentoDeck will poll this URL on a schedule and feed the result to widgets. For auth, use authHeaderKey='Authorization' and authHeaderValue='Bearer sk-…' or similar.",
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
      const r = await call("POST", "/data-sources", input);
      if (!r.ok) return formatError("add_data_source", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "list_data_sources",
    "List registered data sources (without secrets). Useful when you want to attach a new widget to an existing source.",
    {},
    async () => {
      const r = await call("GET", "/data-sources");
      if (!r.ok) return formatError("list_data_sources", r);
      return json(r.data);
    },
  );

  // -------- widgets --------

  mcp.tool(
    "add_widget",
    "Add a widget to a dashboard with a manually-specified JMESPath. For AI-assisted creation (recommended), use create_widget_from_intent instead.",
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
          "JMESPath expression applied to the source's latest JSON response.",
        ),
      position: z.number().int().nonnegative().default(0),
    },
    async ({ dashboardId, ...body }) => {
      const r = await call(
        "POST",
        `/dashboards/${encodeURIComponent(dashboardId)}/widgets`,
        body,
      );
      if (!r.ok) return formatError("add_widget", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "list_widgets",
    "List widgets attached to a dashboard.",
    { dashboardId: z.string() },
    async ({ dashboardId }) => {
      const r = await call(
        "GET",
        `/dashboards/${encodeURIComponent(dashboardId)}/widgets`,
      );
      if (!r.ok) return formatError("list_widgets", r);
      return json(r.data);
    },
  );

  // -------- read-side: bring data back to the conversation --------

  mcp.tool(
    "get_widget_state",
    "Read the current state of a single widget — its definition, latest value, recent history (up to 30 points, oldest→newest), and any recent investigations. Use this when the user asks 'what's happening with X?' and you need to ground your answer in real polled data, not invent it. Investigations include any Claude Managed Agents reports that have been written for this widget.",
    { widgetId: z.string() },
    async ({ widgetId }) => {
      const r = await call(
        "GET",
        `/widgets/${encodeURIComponent(widgetId)}/state`,
      );
      if (!r.ok) return formatError("get_widget_state", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "list_investigations",
    "List recent Claude Managed Agents incident investigations for a widget. Returns the most recent first; default limit 10. Use this to check whether an investigation report is ready before fetching it.",
    {
      widgetId: z.string(),
    },
    async ({ widgetId }) => {
      const r = await call(
        "GET",
        `/widgets/${encodeURIComponent(widgetId)}/investigations`,
      );
      if (!r.ok) return formatError("list_investigations", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "get_investigation",
    "Read a single Claude Managed Agents investigation report by id. The report is Markdown and contains: a headline, a 'what likely happened' hypothesis, a 'what to check first' runbook, and a 'blast radius' summary. Use this to discuss the report with the user in chat.",
    { id: z.string() },
    async ({ id }) => {
      const r = await call(
        "GET",
        `/investigations/${encodeURIComponent(id)}`,
      );
      if (!r.ok) return formatError("get_investigation", r);
      return json(r.data);
    },
  );

  // -------- hero AI tool --------

  mcp.tool(
    "create_widget_from_intent",
    "Add a widget by describing what you want to see in plain English. BentoDeck samples the data source, uses Opus 4.7 to pick a JMESPath transform and widget type, writes an initial snapshot, and returns the widget plus a preview. This is the primary way to add widgets — prefer it over add_widget.",
    {
      dashboardId: z.string(),
      sourceId: z.string(),
      intent: z
        .string()
        .min(3)
        .describe(
          "What the user wants to see. Examples: 'Stripe MRR', 'count of failed checkouts today', 'top 5 customers by revenue'.",
        ),
      position: z.number().int().nonnegative().default(0),
    },
    async ({ dashboardId, sourceId, intent, position }) => {
      const r = await call(
        "POST",
        `/dashboards/${encodeURIComponent(dashboardId)}/widgets/from-intent`,
        { sourceId, intent, position },
      );
      if (!r.ok) return formatError("create_widget_from_intent", r);
      return json(r.data);
    },
  );

  // -------- themes --------

  mcp.tool(
    "list_themes",
    `List available themes. Presets ship with BentoDeck: ${PRESET_IDS.join(", ")}. AI-generated themes also appear here.`,
    {},
    async () => {
      const r = await call("GET", "/themes");
      if (!r.ok) return formatError("list_themes", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "apply_theme_preset",
    `Apply one of the built-in preset themes to a dashboard. Presets: ${PRESET_IDS.join(", ")}.`,
    {
      dashboardId: z.string(),
      preset: z.enum(PRESET_IDS),
    },
    async ({ dashboardId, preset }) => {
      const r = await call(
        "POST",
        `/dashboards/${encodeURIComponent(dashboardId)}/apply-preset`,
        { preset },
      );
      if (!r.ok) return formatError("apply_theme_preset", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "discover_data_source",
    "Read a platform's API documentation and emit a working REST endpoint to poll, all in one call. Use this when the user references a platform by name (Linear, Helius, GitHub, your own bespoke API) and you don't already know the exact endpoint. BentoDeck fetches the docs, asks Opus 4.7 to pick the right endpoint + headers + auth scheme, and verifies the call before persisting. The user's API key (if any) is substituted in safely — never log it.",
    {
      docsUrl: z
        .string()
        .url()
        .describe(
          "URL of the platform's API documentation page or the relevant section.",
        ),
      intent: z
        .string()
        .min(3)
        .max(500)
        .describe("What the user wants to monitor in plain English."),
      apiKey: z
        .string()
        .optional()
        .describe(
          "User's API key, if the API requires auth. BentoDeck stores it server-side and substitutes it into the generated header.",
        ),
      name: z
        .string()
        .optional()
        .describe("Friendly name for the data source. Defaults to the URL host."),
    },
    async (input) => {
      const r = await call("POST", "/data-sources/discover", input);
      if (!r.ok) return formatError("discover_data_source", r);
      return json(r.data);
    },
  );

  mcp.tool(
    "generate_theme",
    "Generate a new theme from a vibe prompt ('cyberpunk terminal', 'calm pastel notebook', 'minimal nordic', 'retro trading floor') using Opus 4.7. The theme is saved and, if dashboardId is provided, applied immediately.",
    {
      prompt: z.string().min(2).max(200),
      dashboardId: z.string().optional(),
    },
    async ({ prompt, dashboardId }) => {
      const r = await call("POST", "/themes/generate", {
        prompt,
        dashboardId,
      });
      if (!r.ok) return formatError("generate_theme", r);
      return json(r.data);
    },
  );

  return mcp;
}

export async function startMcpServer(): Promise<void> {
  const mcp = buildMcpServer();
  const transport = new StdioServerTransport();
  await mcp.connect(transport);
  log.info(`MCP stdio server connected → ${resolveBaseUrl()}`);
}
