import { describe, expect, it } from "vitest";
import { createMockApi } from "./mock-api.js";

// Tests for the demo mock API. Note: importing this module starts a
// module-scope setInterval that drifts the mutable state every 3s (unref'd,
// so it won't keep the process alive). We avoid asserting exact values when
// drift could intervene — we reset right before asserting to keep windows
// tight. See the report notes on module-level mutable state.

describe("demo mock-api", () => {
  const app = createMockApi();

  async function get(path: string): Promise<Response> {
    return app.fetch(new Request(`http://x${path}`, { method: "GET" }));
  }
  async function post(path: string): Promise<Response> {
    return app.fetch(new Request(`http://x${path}`, { method: "POST" }));
  }

  it("/stripe/mrr returns the expected Stripe-like shape", async () => {
    await post("/control/reset");
    const res = await get("/stripe/mrr");
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.object).toBe("summary");
    expect(body.currency).toBe("usd");
    expect(typeof body.mrr).toBe("number");
    expect(typeof body.mrr_cents).toBe("number");
    expect(body.active_subscriptions).toBe(147);
    expect(typeof body.updated_at).toBe("string");
  });

  it("/supabase/signups/today returns the expected shape", async () => {
    await post("/control/reset");
    const res = await get("/supabase/signups/today");
    const body = (await res.json()) as { count: number; range: string };
    expect(typeof body.count).toBe("number");
    expect(body.range).toBe("today");
  });

  it("/posthog/errors/critical returns the expected PostHog-ish shape", async () => {
    await post("/control/reset");
    const res = await get("/posthog/errors/critical");
    const body = (await res.json()) as {
      result: Array<{ label: string; count: number; window: string }>;
    };
    expect(Array.isArray(body.result)).toBe(true);
    expect(body.result).toHaveLength(1);
    expect(body.result[0]!.label).toBe("critical");
    expect(typeof body.result[0]!.count).toBe("number");
    expect(body.result[0]!.window).toBe("last_15m");
  });

  it("spike raises errors count; reset clears it", async () => {
    await post("/control/reset");
    const beforeRes = await get("/posthog/errors/critical");
    const before = (await beforeRes.json()) as {
      result: Array<{ count: number }>;
    };
    expect(before.result[0]!.count).toBe(0);

    const spike = await post("/control/spike");
    const spikeBody = (await spike.json()) as {
      ok: boolean;
      spikeUntilMs: number;
    };
    expect(spikeBody.ok).toBe(true);
    expect(spikeBody.spikeUntilMs).toBeGreaterThan(Date.now());

    const duringRes = await get("/posthog/errors/critical");
    const during = (await duringRes.json()) as {
      result: Array<{ count: number }>;
    };
    expect(during.result[0]!.count).toBeGreaterThanOrEqual(42);

    await post("/control/reset");
    const afterRes = await get("/posthog/errors/critical");
    const after = (await afterRes.json()) as { result: Array<{ count: number }> };
    expect(after.result[0]!.count).toBe(0);
  });

  it("/control/state exposes the demo state + uptime", async () => {
    await post("/control/reset");
    const res = await get("/control/state");
    const body = (await res.json()) as Record<string, unknown>;
    expect(typeof body.mrrCents).toBe("number");
    expect(typeof body.signupsToday).toBe("number");
    expect(typeof body.errorsCritical).toBe("number");
    expect(typeof body.uptimeSec).toBe("number");
  });
});
