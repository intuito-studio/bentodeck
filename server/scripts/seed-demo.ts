/**
 * Seeds the BentoDeck database with a complete demo dashboard using the
 * built-in mock API (/demo/*). Useful as a fallback if Claude Desktop
 * flakes during the demo recording, or for rehearsing the iOS-side
 * experience without going through the full MCP flow.
 *
 * Run:
 *   # With the server NOT running elsewhere:
 *   npm run seed-demo
 *
 *   # Then start the server normally:
 *   npm run dev
 *
 * Prints the dashboard id so you can pin it in the iOS app.
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

function makeSource(args: {
  name: string;
  url: string;
}): { id: string } {
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

  const dash = createDashboard({ name: "SaaS Health", themeId: "default" });
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

  const widgets = [
    createWidget({
      dashboardId: dash.id,
      sourceId: stripe.id,
      type: "number",
      title: "Stripe MRR",
      transformExpr: "mrr",
      position: 0,
    }),
    createWidget({
      dashboardId: dash.id,
      sourceId: signups.id,
      type: "number",
      title: "Signups today",
      transformExpr: "count",
      position: 1,
    }),
    createWidget({
      dashboardId: dash.id,
      sourceId: errors.id,
      type: "number",
      title: "Critical errors (15m)",
      transformExpr: "result[0].count",
      position: 2,
    }),
  ];

  // Seed initial snapshots so iOS has something to render before the
  // first real poll fires.
  writeSnapshot({ widgetId: widgets[0]!.id, value: 4284 });
  writeSnapshot({ widgetId: widgets[1]!.id, value: 31 });
  writeSnapshot({ widgetId: widgets[2]!.id, value: 0 });
  saveLastSample(stripe.id, JSON.stringify({ mrr: 4284 }));
  saveLastSample(signups.id, JSON.stringify({ count: 31 }));
  saveLastSample(errors.id, JSON.stringify({ result: [{ count: 0 }] }));

  log.info("---");
  log.info(`dashboard:  ${dash.id}`);
  log.info(`widgets:    ${widgets.map((w) => w.id).join(", ")}`);
  log.info("---");
  log.info("Next:");
  log.info(`  1. npm run dev     (starts backend + mock API + poller)`);
  log.info(`  2. Open the iOS app, the dashboard will appear as "SaaS Health"`);
  log.info(`  3. curl -XPOST http://localhost:3737/demo/control/spike   (fires anomaly)`);
  log.info(`  4. curl -XPOST http://localhost:3737/demo/control/reset   (resets)`);
}

main().catch((err) => {
  log.error("seed failed:", err);
  process.exit(1);
});
