import { Hono } from "hono";

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

  return app;
}
