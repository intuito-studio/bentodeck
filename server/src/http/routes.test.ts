import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildHttpApp } from "./server.js";
import { withFreshDbAndThemes } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
} from "../db/repo.js";

let cleanup: () => void;

beforeEach(() => {
  const handle = withFreshDbAndThemes();
  cleanup = handle.cleanup;
});

afterEach(() => {
  cleanup();
});

const app = () => buildHttpApp();
const req = (method: string, path: string, body?: unknown) =>
  app().fetch(
    new Request(`http://test${path}`, {
      method,
      headers: body
        ? { "Content-Type": "application/json" }
        : {},
      body: body ? JSON.stringify(body) : undefined,
    }),
  );

describe("POST /dashboards", () => {
  it("creates a dashboard", async () => {
    const res = await req("POST", "/dashboards", { name: "SaaS Health" });
    expect(res.status).toBe(201);
    const body = (await res.json()) as { dashboard: { id: string; name: string; themeId: string } };
    expect(body.dashboard.name).toBe("SaaS Health");
    expect(body.dashboard.themeId).toBe("default");
    expect(body.dashboard.id).toBeTruthy();
  });

  it("applies a theme id if provided", async () => {
    const res = await req("POST", "/dashboards", {
      name: "X",
      themeId: "cyberpunk",
    });
    const body = (await res.json()) as { dashboard: { themeId: string } };
    expect(body.dashboard.themeId).toBe("cyberpunk");
  });

  it("rejects empty name", async () => {
    const res = await req("POST", "/dashboards", { name: "" });
    expect(res.status).toBe(400);
  });
});

describe("DELETE /dashboards/:id", () => {
  it("deletes an existing dashboard", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("DELETE", `/dashboards/${dash.id}`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("404s on missing", async () => {
    const res = await req("DELETE", "/dashboards/nope");
    expect(res.status).toBe(404);
  });
});

describe("PATCH /dashboards/:id/theme", () => {
  it("sets the theme", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("PATCH", `/dashboards/${dash.id}/theme`, {
      themeId: "terminal",
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; theme: { id: string } };
    expect(body.ok).toBe(true);
    expect(body.theme.id).toBe("terminal");
  });

  it("404s on unknown dashboard", async () => {
    const res = await req("PATCH", "/dashboards/nope/theme", {
      themeId: "terminal",
    });
    expect(res.status).toBe(404);
  });

  it("404s on unknown theme", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("PATCH", `/dashboards/${dash.id}/theme`, {
      themeId: "not-a-theme",
    });
    expect(res.status).toBe(404);
  });
});

describe("POST /dashboards/:id/apply-preset", () => {
  it("applies a valid preset", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("POST", `/dashboards/${dash.id}/apply-preset`, {
      preset: "cyberpunk",
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { applied: string };
    expect(body.applied).toBe("cyberpunk");
  });

  it("400s on invalid preset", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("POST", `/dashboards/${dash.id}/apply-preset`, {
      preset: "nope",
    });
    expect(res.status).toBe(400);
  });
});

describe("POST /data-sources", () => {
  it("creates a data source and redacts auth", async () => {
    const res = await req("POST", "/data-sources", {
      name: "Stripe",
      url: "https://api.stripe.com/x",
      authHeaderKey: "Authorization",
      authHeaderValue: "Bearer sk-test-secret",
      pollIntervalSec: 15,
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as {
      source: {
        id: string;
        name: string;
        authHeaderKey?: string;
        authHeaderValue?: string;
      };
    };
    expect(body.source.name).toBe("Stripe");
    expect(body.source.authHeaderKey).toBe("Authorization");
    expect(body.source.authHeaderValue).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain("sk-test-secret");
  });

  it("400s on invalid url", async () => {
    const res = await req("POST", "/data-sources", {
      name: "bad",
      url: "not-a-url",
    });
    expect(res.status).toBe(400);
  });
});

describe("GET /data-sources", () => {
  it("lists data sources with secrets redacted", async () => {
    createDataSource({
      name: "X",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      authHeaderKey: "Authorization",
      authHeaderValue: "sk-secret",
      pollIntervalSec: 60,
    });
    const res = await req("GET", "/data-sources");
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      sources: Array<{ authHeaderValue?: string }>;
    };
    expect(body.sources.length).toBe(1);
    expect(body.sources[0]?.authHeaderValue).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain("sk-secret");
  });
});

describe("POST + GET /dashboards/:id/widgets", () => {
  it("adds a widget and lists it", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const src = createDataSource({
      name: "API",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const addRes = await req("POST", `/dashboards/${dash.id}/widgets`, {
      sourceId: src.id,
      type: "number",
      title: "X",
      transformExpr: "value",
    });
    expect(addRes.status).toBe(201);

    const listRes = await req("GET", `/dashboards/${dash.id}/widgets`);
    expect(listRes.status).toBe(200);
    const body = (await listRes.json()) as { widgets: Array<{ title: string }> };
    expect(body.widgets).toHaveLength(1);
    expect(body.widgets[0]?.title).toBe("X");
  });

  it("404s when dashboard is missing", async () => {
    const res = await req("POST", "/dashboards/nope/widgets", {
      sourceId: "x",
      type: "number",
      title: "T",
      transformExpr: "value",
    });
    expect(res.status).toBe(404);
  });

  it("404s when source is missing", async () => {
    const dash = createDashboard({ name: "D", themeId: "default" });
    const res = await req("POST", `/dashboards/${dash.id}/widgets`, {
      sourceId: "nope",
      type: "number",
      title: "T",
      transformExpr: "value",
    });
    expect(res.status).toBe(404);
  });
});
