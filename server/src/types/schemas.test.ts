import { describe, expect, it } from "vitest";
import {
  DashboardInput,
  DataSourceInput,
  WidgetInput,
  WidgetType,
} from "./schemas.js";

describe("DataSourceInput", () => {
  it("accepts a minimal valid input and applies defaults", () => {
    const parsed = DataSourceInput.parse({
      name: "Stripe",
      url: "https://api.stripe.com/v1",
    });
    expect(parsed.type).toBe("rest");
    expect(parsed.method).toBe("GET");
    expect(parsed.pollIntervalSec).toBe(60);
  });

  it("accepts a fully-specified input", () => {
    const parsed = DataSourceInput.parse({
      name: "Stripe",
      type: "rest",
      url: "https://api.stripe.com/v1",
      method: "POST",
      headers: { X: "y" },
      authHeaderKey: "Authorization",
      authHeaderValue: "Bearer x",
      pollIntervalSec: 120,
    });
    expect(parsed.pollIntervalSec).toBe(120);
    expect(parsed.method).toBe("POST");
    expect(parsed.headers).toEqual({ X: "y" });
  });

  it("rejects empty name", () => {
    expect(() =>
      DataSourceInput.parse({ name: "", url: "https://x.com" }),
    ).toThrow();
  });

  it("rejects malformed URL", () => {
    expect(() =>
      DataSourceInput.parse({ name: "x", url: "not-a-url" }),
    ).toThrow();
  });

  it("rejects pollIntervalSec <= 0 and > 3600", () => {
    expect(() =>
      DataSourceInput.parse({
        name: "x",
        url: "https://x.com",
        pollIntervalSec: 0,
      }),
    ).toThrow();
    expect(() =>
      DataSourceInput.parse({
        name: "x",
        url: "https://x.com",
        pollIntervalSec: 3601,
      }),
    ).toThrow();
  });

  it("rejects non-integer pollIntervalSec", () => {
    expect(() =>
      DataSourceInput.parse({
        name: "x",
        url: "https://x.com",
        pollIntervalSec: 2.5,
      }),
    ).toThrow();
  });
});

describe("WidgetInput", () => {
  it("accepts a minimal valid widget and applies position default", () => {
    const parsed = WidgetInput.parse({
      dashboardId: "d1",
      sourceId: "s1",
      type: "number",
      title: "MRR",
      transformExpr: "data.mrr",
    });
    expect(parsed.position).toBe(0);
  });

  it("rejects empty title or transformExpr", () => {
    expect(() =>
      WidgetInput.parse({
        dashboardId: "d1",
        sourceId: "s1",
        type: "number",
        title: "",
        transformExpr: "x",
      }),
    ).toThrow();

    expect(() =>
      WidgetInput.parse({
        dashboardId: "d1",
        sourceId: "s1",
        type: "number",
        title: "ok",
        transformExpr: "",
      }),
    ).toThrow();
  });

  it("rejects negative position", () => {
    expect(() =>
      WidgetInput.parse({
        dashboardId: "d1",
        sourceId: "s1",
        type: "number",
        title: "ok",
        transformExpr: "x",
        position: -1,
      }),
    ).toThrow();
  });

  it("rejects unknown widget type", () => {
    expect(() =>
      WidgetInput.parse({
        dashboardId: "d1",
        sourceId: "s1",
        type: "unknown-type",
        title: "ok",
        transformExpr: "x",
      }),
    ).toThrow();
  });
});

describe("DashboardInput", () => {
  it("defaults themeId to 'default'", () => {
    const parsed = DashboardInput.parse({ name: "D" });
    expect(parsed.themeId).toBe("default");
  });

  it("rejects empty name", () => {
    expect(() => DashboardInput.parse({ name: "" })).toThrow();
  });
});

describe("WidgetType", () => {
  it("accepts all declared widget types", () => {
    for (const t of [
      "number",
      "number_with_trend",
      "gauge",
      "sparkline",
      "list",
      "status",
    ]) {
      expect(() => WidgetType.parse(t)).not.toThrow();
    }
  });
});
