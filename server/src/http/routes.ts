import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { discoverDataSource } from "../ai/discoverer.js";
import { planWidget } from "../ai/setup.js";
import { generateTheme } from "../ai/theme.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  deleteDashboard,
  getDashboard,
  getDataSource,
  getInvestigation,
  getTheme,
  getWidget,
  latestSnapshot,
  listDashboards,
  listDataSources,
  listInvestigationsForWidget,
  listThemes,
  listWidgetsForDashboard,
  recentSnapshots,
  restoreNeedsKey,
  saveLastSample,
  saveTheme,
  setDashboardTheme,
  setDataSourceKey,
  writeSnapshot,
} from "../db/repo.js";
import { log } from "../logger.js";
import { fetchFromSource } from "../sources/fetch.js";
import type { DataSource } from "../types/schemas.js";

// Strip the auth-header secret before returning a data source over HTTP.
function redactSource(s: DataSource): Omit<DataSource, "authHeaderValue"> {
  const { authHeaderValue: _omit, ...safe } = s;
  return safe;
}

const PRESET_THEME_IDS = [
  "default",
  "cyberpunk",
  "terminal",
  "paper",
  "bento-orange",
  "pastel",
] as const;

// Zod schemas live here too so the MCP thin client can share them without
// pulling backend-only code. (Types already live in ../types/schemas.ts;
// these are just HTTP-input variants with defaults applied.)
const CreateDashboardBody = z.object({
  name: z.string().min(1),
  themeId: z.string().optional(),
});

const SetThemeBody = z.object({
  themeId: z.string(),
});

const ApplyPresetBody = z.object({
  preset: z.enum(PRESET_THEME_IDS),
});

const CreateDataSourceBody = z.object({
  name: z.string().min(1),
  url: z.string().url(),
  method: z.enum(["GET", "POST"]).default("GET"),
  headers: z.record(z.string(), z.string()).optional(),
  authHeaderKey: z.string().optional(),
  authHeaderValue: z.string().optional(),
  pollIntervalSec: z.number().int().positive().max(3600).default(60),
});

const CreateWidgetBody = z.object({
  sourceId: z.string(),
  type: z.enum([
    "number",
    "number_with_trend",
    "gauge",
    "sparkline",
    "list",
    "status",
  ]),
  title: z.string().min(1),
  transformExpr: z.string().min(1),
  position: z.number().int().nonnegative().default(0),
});

const CreateWidgetFromIntentBody = z.object({
  sourceId: z.string(),
  intent: z.string().min(3),
  position: z.number().int().nonnegative().default(0),
});

const GenerateThemeBody = z.object({
  prompt: z.string().min(2).max(200),
  dashboardId: z.string().optional(),
});

const DiscoverDataSourceBody = z.object({
  docsUrl: z.string().url(),
  intent: z.string().min(3).max(500),
  apiKey: z.string().optional(),
  name: z.string().optional(),
});

/**
 * The write-side of the BentoDeck HTTP API. Read-side routes (snapshots,
 * dashboard list, etc.) stay in server.ts so this module is the clear
 * home for operations that change state or call Opus 4.7.
 *
 * Split out of the MCP layer so the MCP process can be a thin stdio ↔ HTTP
 * proxy — see ../mcp/server.ts and ../mcp-entry.ts.
 */
export function buildRoutes(): Hono {
  const app = new Hono();

  // -------- dashboards --------

  app.post("/dashboards", zValidator("json", CreateDashboardBody), (c) => {
    const body = c.req.valid("json");
    const dash = createDashboard({
      name: body.name,
      themeId: body.themeId ?? "default",
    });
    return c.json({ dashboard: dash }, 201);
  });

  app.delete("/dashboards/:id", (c) => {
    const ok = deleteDashboard(c.req.param("id"));
    if (!ok) return c.json({ error: "not found" }, 404);
    return c.json({ ok: true });
  });

  app.patch(
    "/dashboards/:id/theme",
    zValidator("json", SetThemeBody),
    (c) => {
      const dashboardId = c.req.param("id");
      const { themeId } = c.req.valid("json");
      const dash = getDashboard(dashboardId);
      if (!dash) return c.json({ error: "dashboard not found" }, 404);
      const theme = getTheme(themeId);
      if (!theme) return c.json({ error: "theme not found" }, 404);
      setDashboardTheme(dashboardId, themeId);
      return c.json({ ok: true, theme });
    },
  );

  app.post(
    "/dashboards/:id/apply-preset",
    zValidator("json", ApplyPresetBody),
    (c) => {
      const dashboardId = c.req.param("id");
      const { preset } = c.req.valid("json");
      const dash = getDashboard(dashboardId);
      if (!dash) return c.json({ error: "dashboard not found" }, 404);
      const theme = getTheme(preset);
      if (!theme) return c.json({ error: "preset not found" }, 404);
      setDashboardTheme(dashboardId, preset);
      return c.json({ applied: preset, theme });
    },
  );

  // -------- data sources --------

  app.post(
    "/data-sources",
    zValidator("json", CreateDataSourceBody),
    (c) => {
      const body = c.req.valid("json");
      const src = createDataSource({
        name: body.name,
        type: "rest",
        url: body.url,
        method: body.method,
        headers: body.headers,
        authHeaderKey: body.authHeaderKey,
        authHeaderValue: body.authHeaderValue,
        pollIntervalSec: body.pollIntervalSec,
      });
      return c.json({ source: redactSource(src) }, 201);
    },
  );

  app.get("/data-sources", (c) => {
    return c.json({ sources: listDataSources().map(redactSource) });
  });

  // Set the API key for a data source that was registered via
  // `discover_data_source` without one. Substitutes the key into the stored
  // {{API_KEY}} template, makes a single verification call, and only flips
  // needs_key=false when that call returns 2xx.
  app.post(
    "/data-sources/:id/key",
    zValidator("json", z.object({ apiKey: z.string().min(1) })),
    async (c) => {
      const id = c.req.param("id");
      const existing = getDataSource(id);
      if (!existing) return c.json({ error: "not found" }, 404);
      const { apiKey } = c.req.valid("json");

      const updated = setDataSourceKey(id, apiKey);
      if (!updated) return c.json({ error: "not found" }, 404);

      // Verify by polling once. If auth still fails, restore the
      // {{API_KEY}} template + needs_key=true so the user can retry.
      const trial = await fetchFromSource(updated);
      if (!trial.ok) {
        log.warn(
          `[data-sources] verify failed source=${id} status=${trial.status}; rolling back`,
        );
        const restoreTemplate =
          existing.authHeaderValue ?? "Bearer {{API_KEY}}";
        restoreNeedsKey(id, restoreTemplate);
        return c.json(
          {
            ok: false,
            status: trial.status,
            bodyPreview: trial.bodyText.slice(0, 400),
          },
          200,
        );
      }
      saveLastSample(id, JSON.stringify(trial.body));
      return c.json({ ok: true, source: redactSource(updated) });
    },
  );

  // -------- widgets --------

  app.get("/dashboards/:id/widgets", (c) => {
    const dashboardId = c.req.param("id");
    const dash = getDashboard(dashboardId);
    if (!dash) return c.json({ error: "not found" }, 404);
    return c.json({ widgets: listWidgetsForDashboard(dashboardId) });
  });

  app.post(
    "/dashboards/:id/widgets",
    zValidator("json", CreateWidgetBody),
    (c) => {
      const dashboardId = c.req.param("id");
      const dash = getDashboard(dashboardId);
      if (!dash) return c.json({ error: "dashboard not found" }, 404);
      const body = c.req.valid("json");
      const src = getDataSource(body.sourceId);
      if (!src) return c.json({ error: "data source not found" }, 404);
      const widget = createWidget({
        dashboardId,
        sourceId: body.sourceId,
        type: body.type,
        title: body.title,
        transformExpr: body.transformExpr,
        position: body.position,
      });
      return c.json({ widget }, 201);
    },
  );

  // AI-assisted widget creation — the hero path.
  app.post(
    "/dashboards/:id/widgets/from-intent",
    zValidator("json", CreateWidgetFromIntentBody),
    async (c) => {
      const dashboardId = c.req.param("id");
      const body = c.req.valid("json");
      const dash = getDashboard(dashboardId);
      if (!dash) return c.json({ error: "dashboard not found" }, 404);
      const source = getDataSource(body.sourceId);
      if (!source) return c.json({ error: "data source not found" }, 404);

      log.info(
        `[intent] dashboard=${dashboardId} source=${body.sourceId} intent="${body.intent}"`,
      );

      // 1) Sample the source to get real JSON for Opus to plan against.
      const fetched = await fetchFromSource(source);
      if (!fetched.ok) {
        return c.json(
          {
            error: `data source returned HTTP ${fetched.status}`,
            bodyPreview: fetched.bodyText.slice(0, 400),
          },
          502,
        );
      }
      saveLastSample(body.sourceId, JSON.stringify(fetched.body));

      // 2) Ask Opus 4.7 for a JMESPath + widget type + title.
      const { plan, previewValue, previewError } = await planWidget({
        intent: body.intent,
        sampleJson: fetched.body,
        sourceName: source.name,
      });

      // 3) Persist the widget + seed a first snapshot so iOS has something
      //    to render immediately.
      const widget = createWidget({
        dashboardId,
        sourceId: body.sourceId,
        type: plan.widgetType,
        title: plan.title,
        transformExpr: plan.transformExpr,
        position: body.position,
      });
      if (!previewError && previewValue !== undefined) {
        writeSnapshot({ widgetId: widget.id, value: previewValue });
      }

      return c.json(
        {
          widget,
          plan,
          preview: { value: previewValue, error: previewError ?? null },
        },
        201,
      );
    },
  );

  // -------- read-side: widget state for Claude Desktop conversations --------

  app.get("/widgets/:id/state", (c) => {
    const widgetId = c.req.param("id");
    const widget = getWidget(widgetId);
    if (!widget) return c.json({ error: "widget not found" }, 404);
    const latest = latestSnapshot(widgetId);
    const recent = recentSnapshots(widgetId, 30).slice().reverse();
    const investigations = listInvestigationsForWidget(widgetId, 5);
    return c.json({
      widget,
      latest,
      history: recent.map((r) => ({
        value: r.value,
        anomaly: r.anomalyFlag,
        ts: r.ts,
      })),
      investigations,
    });
  });

  // -------- AI-discovered data sources (Tier-2) --------

  app.post(
    "/data-sources/discover",
    zValidator("json", DiscoverDataSourceBody),
    async (c) => {
      const body = c.req.valid("json");
      const result = await discoverDataSource({
        docsUrl: body.docsUrl,
        intent: body.intent,
        apiKey: body.apiKey,
        name: body.name,
      });
      if (!result.ok) {
        return c.json(
          {
            error: result.reason,
            spec: result.spec ?? null,
            bodyPreview: result.bodyPreview ?? null,
          },
          422,
        );
      }
      const { authHeaderValue: _omit, ...safe } = result.source;
      return c.json(
        {
          source: safe,
          spec: result.spec,
          sampleBodyPreview: result.sampleBodyPreview,
        },
        201,
      );
    },
  );

  // -------- investigations (Managed Agents reports) --------

  app.get("/widgets/:id/investigations", (c) => {
    const widgetId = c.req.param("id");
    const widget = getWidget(widgetId);
    if (!widget) return c.json({ error: "widget not found" }, 404);
    const investigations = listInvestigationsForWidget(widgetId);
    return c.json({ investigations });
  });

  app.get("/investigations/:id", (c) => {
    const inv = getInvestigation(c.req.param("id"));
    if (!inv) return c.json({ error: "not found" }, 404);
    return c.json({ investigation: inv });
  });

  // -------- themes --------

  app.post(
    "/themes/generate",
    zValidator("json", GenerateThemeBody),
    async (c) => {
      const { prompt, dashboardId } = c.req.valid("json");
      const theme = await generateTheme(prompt);
      saveTheme(theme, false);
      if (dashboardId) {
        const dash = getDashboard(dashboardId);
        if (!dash) {
          return c.json(
            {
              theme,
              appliedTo: null,
              warning: `dashboard ${dashboardId} not found — theme saved but not applied`,
            },
            201,
          );
        }
        setDashboardTheme(dashboardId, theme.id);
      }
      return c.json({ theme, appliedTo: dashboardId ?? null }, 201);
    },
  );

  return app;
}
