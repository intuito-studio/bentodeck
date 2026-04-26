import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import {
  createInvestigation,
  latestSnapshotId,
  listAllWidgets,
  updateInvestigation,
} from "../db/repo.js";

/**
 * In-memory demo data, served at /demo/* on the same HTTP server.
 *
 * Claude Desktop will be told to treat these endpoints as real external
 * APIs (Stripe test mode, Supabase, PostHog). BentoDeck polls them
 * exactly like it would poll real customer APIs — there is no special
 * code path. This makes the live demo work offline, deterministically,
 * and without needing anyone's real credentials.
 *
 * The control surface (/demo/control/*) lets the presenter trigger an
 * anomaly spike during recording with a single `curl` in another
 * terminal.
 */

type DemoState = {
  mrrCents: number;
  signupsToday: number;
  errorsCritical: number;
  spikeUntil: number | null; // ms timestamp
  startedAt: number;
};

const state: DemoState = {
  mrrCents: 428_400, // $4,284.00 starting MRR
  signupsToday: 31,
  errorsCritical: 0,
  spikeUntil: null,
  startedAt: Date.now(),
};

// Natural drift so polled values change between ticks — looks alive on
// the widget without requiring the presenter to do anything.
function drift(): void {
  // MRR inches up by $1–$6 every tick on average.
  state.mrrCents += Math.round(Math.random() * 600);
  // Signups tick slowly.
  if (Math.random() < 0.3) state.signupsToday += 1;
  // If we're inside a spike window, keep errors high. Otherwise decay.
  if (state.spikeUntil && Date.now() < state.spikeUntil) {
    state.errorsCritical = Math.max(
      state.errorsCritical,
      42 + Math.floor(Math.random() * 8),
    );
  } else {
    state.spikeUntil = null;
    state.errorsCritical = Math.max(
      0,
      state.errorsCritical - (Math.random() < 0.5 ? 1 : 0),
    );
  }
}

// Tick every 3 seconds — faster than the poll cadence so widgets always
// see fresh values.
setInterval(drift, 3000).unref();

export function createMockApi(): Hono {
  const app = new Hono();

  // Shape matches Stripe's /v1/subscriptions-ish response just closely enough
  // for Opus 4.7 to pick the right JMESPath expression.
  app.get("/stripe/mrr", (c) =>
    c.json({
      object: "summary",
      currency: "usd",
      mrr: state.mrrCents / 100,
      mrr_cents: state.mrrCents,
      active_subscriptions: 147,
      updated_at: new Date().toISOString(),
    }),
  );

  // Supabase-ish signup count. Their real /rest/v1/auth.users endpoint
  // returns a list; we fake a `count` hint.
  app.get("/supabase/signups/today", (c) =>
    c.json({
      count: state.signupsToday,
      range: "today",
      updated_at: new Date().toISOString(),
    }),
  );

  // PostHog-ish aggregated error event count. Real PostHog uses
  // /api/projects/:id/events, aggregated via /insights. We mimic the shape.
  app.get("/posthog/errors/critical", (c) =>
    c.json({
      result: [
        {
          label: "critical",
          count: state.errorsCritical,
          window: "last_15m",
        },
      ],
      updated_at: new Date().toISOString(),
    }),
  );

  // Control surface — the presenter POSTs to these between takes.
  app.post("/control/spike", (c) => {
    state.spikeUntil = Date.now() + 120_000; // 2 min
    state.errorsCritical = 47;
    return c.json({ ok: true, spikeUntilMs: state.spikeUntil });
  });

  app.post("/control/reset", (c) => {
    state.mrrCents = 428_400;
    state.signupsToday = 31;
    state.errorsCritical = 0;
    state.spikeUntil = null;
    state.startedAt = Date.now();
    return c.json({ ok: true });
  });

  app.get("/control/state", (c) =>
    c.json({ ...state, uptimeSec: Math.round((Date.now() - state.startedAt) / 1000) }),
  );

  // Demo-only: seed a polished investigation report for any anomalous
  // widget on the system. Useful for the demo recording where waiting
  // 30-60s for a real Managed Agents session to write a report would
  // hurt the pacing. The report below is a hand-crafted runbook in the
  // same shape Opus 4.7's investigator system prompt produces.
  //
  //   POST /demo/control/seed-investigation
  //   Body: { widgetId?: string }   omit to pick the first errors widget
  //
  // Returns the investigation id so the iOS app can navigate directly
  // to it (or you can let the polling kick in naturally).
  app.post("/control/seed-investigation", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as {
      widgetId?: string;
    };

    let widgetId = body.widgetId;
    if (!widgetId) {
      const widgets = listAllWidgets();
      const guess =
        widgets.find((w) => /error|fail|alert/i.test(w.title)) ?? widgets[0];
      widgetId = guess?.id;
    }
    if (!widgetId) {
      return c.json(
        { error: "no widgets exist; create one first" },
        404,
      );
    }

    const id = randomUUID();
    createInvestigation({
      id,
      widgetId,
      snapshotId: latestSnapshotId(widgetId),
    });
    updateInvestigation(id, {
      status: "running",
      sessionId: "demo-session",
    });

    // Stream the seeded report in three chunks so the iOS detail view
    // visibly streams content in (it polls every 1.5s).
    const headline =
      "## Critical errors spiked from 0 → 47 against a 15-minute zero baseline";

    const part1 = [
      headline,
      "",
      "**What likely happened.** A burst of unhandled errors arrived in the last poll window after a sustained zero baseline of 12+ minutes. The prior series shows no slow ramp, so this is a step-function event — most often: a freshly deployed code path, a misconfigured downstream dependency that has just become unavailable, or a third-party API returning an unexpected schema that's now hitting your error-handling fallback at scale.",
    ].join("\n");

    const part2 = [
      "",
      "## What to check first",
      "- Cross-reference your last deploy timestamp against the spike onset (~the past 60 seconds).",
      "- Check Vercel / Fly / Railway logs for repeating stack traces; one stack trace counted 47 times is the most likely shape.",
      "- Status pages of any third-party APIs the affected code path calls (Stripe, Supabase, OpenAI, Anthropic).",
      "- If you have a feature flag controlling a recent rollout, flip it off as a fast mitigation.",
      "- Confirm your error-budget alerting fired in your existing oncall tool, or whether this anomaly beat it.",
    ].join("\n");

    const part3 = [
      "",
      "## Blast radius",
      "If the underlying error path is request-scoped, every customer hitting that path is currently failing for them. Sustained 47/15-min suggests a >1% error rate on a moderately busy SaaS — well above SLO for most teams.",
    ].join("\n");

    // Persist part 1 immediately, then schedule the rest so polling
    // visibly catches up.
    updateInvestigation(id, { report: part1, title: "Critical errors spiked from 0 → 47 against a 15-minute zero baseline" });
    setTimeout(() => {
      updateInvestigation(id, { report: part1 + part2 });
    }, 1500);
    setTimeout(() => {
      updateInvestigation(id, {
        report: part1 + part2 + part3,
        status: "done",
      });
    }, 3500);

    return c.json({ ok: true, investigationId: id, widgetId });
  });

  return app;
}
