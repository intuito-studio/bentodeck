import { z } from "zod";

export const WidgetType = z.enum([
  "number",           // single big number
  "number_with_trend", // number + up/down arrow + delta
  "gauge",            // progress toward a target
  "sparkline",        // mini time-series line
  "list",             // top N items
  "status",           // ok / warn / error
]);
export type WidgetType = z.infer<typeof WidgetType>;

export const DataSourceType = z.enum(["rest"]);
export type DataSourceType = z.infer<typeof DataSourceType>;

export const HttpMethod = z.enum(["GET", "POST"]);
export type HttpMethod = z.infer<typeof HttpMethod>;

export const DataSourceInput = z.object({
  name: z.string().min(1),
  type: DataSourceType.default("rest"),
  url: z.string().url(),
  method: HttpMethod.default("GET"),
  headers: z.record(z.string(), z.string()).optional(),
  authHeaderKey: z.string().optional(),
  authHeaderValue: z.string().optional(),
  pollIntervalSec: z.number().int().positive().max(3600).default(60),
  // True when the source was discovered from docs but the user hasn't
  // supplied an API key yet. The poller skips these; the iOS app shows a
  // "Connect" warning card and lets the user paste the key into a
  // SecureField. Persisted to SQLite as data_sources.needs_key.
  needsKey: z.boolean().optional(),
});
export type DataSourceInput = z.infer<typeof DataSourceInput>;

export const DataSource = DataSourceInput.extend({
  id: z.string(),
  lastSampleJson: z.string().nullable().optional(),
  createdAt: z.string(),
});
export type DataSource = z.infer<typeof DataSource>;

export const WidgetInput = z.object({
  dashboardId: z.string(),
  sourceId: z.string(),
  type: WidgetType,
  title: z.string().min(1),
  transformExpr: z.string().min(1), // JMESPath expression
  position: z.number().int().nonnegative().default(0),
});
export type WidgetInput = z.infer<typeof WidgetInput>;

export const Widget = WidgetInput.extend({
  id: z.string(),
  createdAt: z.string(),
});
export type Widget = z.infer<typeof Widget>;

export const DashboardInput = z.object({
  name: z.string().min(1),
  themeId: z.string().default("default"),
});
export type DashboardInput = z.infer<typeof DashboardInput>;

export const Dashboard = DashboardInput.extend({
  id: z.string(),
  createdAt: z.string(),
});
export type Dashboard = z.infer<typeof Dashboard>;

export const Snapshot = z.object({
  id: z.number().int(),
  widgetId: z.string(),
  value: z.unknown(),
  anomalyFlag: z.boolean(),
  anomalyExplanation: z.string().nullable(),
  ts: z.string(),
});
export type Snapshot = z.infer<typeof Snapshot>;
