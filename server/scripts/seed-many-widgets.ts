/**
 * Seeds an 8-widget dashboard so you can stress-test the bento grid:
 * auto-layout for many widgets, scroll behavior, edit-mode wiggle on
 * a packed grid, and drag-to-resize across a varied set of widget types.
 *
 * Reuses the same three demo data sources as seed-demo (Stripe / Supabase
 * / PostHog mock APIs) and slices different fields out of them with
 * JMESPath transforms to make 8 visually distinct widgets.
 *
 * Run:
 *   # With the server NOT running:
 *   tsx scripts/seed-many-widgets.ts
 *   # Then:
 *   npm start
 */
import "dotenv/config";
import { initDb } from "../src/db/schema.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  saveLastSample,
  seedPresetThemes,
  writeSnapshot,
} from "../src/db/repo.js";
import { log } from "../src/logger.js";

function makeSource(args: { name: string; url: string }): { id: string } {
  return createDataSource({
    name: args.name,
    type: "rest",
    url: args.url,
    method: "GET",
    pollIntervalSec: 5,
  });
}

async function main(): Promise<void> {
  initDb();
  seedPresetThemes();

  const dash = createDashboard({ name: "Big Demo (8 widgets)", themeId: "default" });
  log.info(`created dashboard id=${dash.id}`);

  const stripe = makeSource({
    name: "Stripe MRR",
    url: "http://localhost:3737/demo/stripe/mrr",
  });
  const signups = makeSource({
    name: "Supabase signups",
    url: "http://localhost:3737/demo/supabase/signups/today",
  });
  const errors = makeSource({
    name: "PostHog critical errors",
    url: "http://localhost:3737/demo/posthog/errors/critical",
  });

  // 8 widgets, varied types — gives the layout something to chew on.
  const specs: Array<{
    sourceId: string;
    type: "number" | "number_with_trend" | "sparkline" | "list" | "status" | "gauge";
    title: string;
    transformExpr: string;
    seedValue: number | string | unknown;
    sampleJson: unknown;
  }> = [
    {
      sourceId: stripe.id,
      type: "number_with_trend",
      title: "Stripe MRR",
      transformExpr: "mrr",
      seedValue: 4284,
      sampleJson: { mrr: 4284 },
    },
    {
      sourceId: stripe.id,
      type: "number",
      title: "Active subs",
      transformExpr: "active_subscriptions",
      seedValue: 147,
      sampleJson: { active_subscriptions: 147 },
    },
    {
      sourceId: signups.id,
      type: "sparkline",
      title: "Signups today",
      transformExpr: "count",
      seedValue: 31,
      sampleJson: { count: 31 },
    },
    {
      sourceId: errors.id,
      type: "number",
      title: "Critical errors (15m)",
      transformExpr: "result[0].count",
      seedValue: 0,
      sampleJson: { result: [{ count: 0 }] },
    },
    {
      sourceId: stripe.id,
      type: "sparkline",
      title: "MRR (cents)",
      transformExpr: "mrr_cents",
      seedValue: 428_400,
      sampleJson: { mrr_cents: 428_400 },
    },
    {
      sourceId: errors.id,
      type: "status",
      title: "API health",
      transformExpr: "result[0].count",
      seedValue: 0,
      sampleJson: { result: [{ count: 0 }] },
    },
    {
      sourceId: errors.id,
      type: "list",
      title: "Error buckets",
      transformExpr: "result",
      seedValue: [{ label: "critical", count: 0, window: "last_15m" }],
      sampleJson: {
        result: [{ label: "critical", count: 0, window: "last_15m" }],
      },
    },
    {
      sourceId: stripe.id,
      type: "number",
      title: "Currency",
      transformExpr: "currency",
      seedValue: "usd",
      sampleJson: { currency: "usd" },
    },
  ];

  const widgets = specs.map((spec, i) =>
    createWidget({
      dashboardId: dash.id,
      sourceId: spec.sourceId,
      type: spec.type,
      title: spec.title,
      transformExpr: spec.transformExpr,
      position: i,
    }),
  );

  // Seed initial values so the iOS app shows something before the poller
  // catches up. Every widget gets at least one snapshot.
  for (let i = 0; i < widgets.length; i++) {
    writeSnapshot({ widgetId: widgets[i]!.id, value: specs[i]!.seedValue });
  }
  saveLastSample(stripe.id, JSON.stringify({ mrr: 4284, mrr_cents: 428_400, active_subscriptions: 147, currency: "usd" }));
  saveLastSample(signups.id, JSON.stringify({ count: 31 }));
  saveLastSample(errors.id, JSON.stringify({ result: [{ label: "critical", count: 0, window: "last_15m" }] }));

  log.info("---");
  log.info(`dashboard:  ${dash.id}`);
  log.info(`widget count: ${widgets.length}`);
  log.info(`titles:     ${specs.map((s) => s.title).join(", ")}`);
  log.info("---");
  log.info("Next:");
  log.info(`  1. npm start`);
  log.info(`  2. Open the iOS app, tap into "Big Demo (8 widgets)"`);
  log.info(`  3. Long-press to enter edit mode, then drag the corner handles around.`);
}

main().catch((err) => {
  log.error("seed failed:", err);
  process.exit(1);
});
