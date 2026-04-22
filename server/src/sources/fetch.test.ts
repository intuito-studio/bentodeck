import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { capJsonSample, fetchFromSource } from "./fetch.js";
import type { DataSource } from "../types/schemas.js";

// A local ephemeral HTTP server keeps everything offline and deterministic.
let server: Server;
let baseUrl = "";

beforeAll(async () => {
  server = createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname === "/json") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ hello: "world", n: 7 }));
      return;
    }
    if (url.pathname === "/text") {
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end("plain body");
      return;
    }
    if (url.pathname === "/ambiguous-json") {
      // JSON body but no content-type hint → fetch.ts tries to parse anyway.
      res.writeHead(200, { "Content-Type": "application/octet-stream" });
      res.end('{"x":42}');
      return;
    }
    if (url.pathname === "/echo-headers") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ headers: req.headers }));
      return;
    }
    if (url.pathname === "/boom") {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "nope" }));
      return;
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const addr = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${addr.port}`;
});

afterAll(async () => {
  await new Promise<void>((resolve, reject) =>
    server.close((err) => (err ? reject(err) : resolve())),
  );
});

function makeSource(path: string, extras: Partial<DataSource> = {}): DataSource {
  return {
    id: "test-src",
    name: "test",
    type: "rest",
    url: `${baseUrl}${path}`,
    method: "GET",
    pollIntervalSec: 60,
    createdAt: new Date().toISOString(),
    ...extras,
  };
}

describe("capJsonSample", () => {
  it("returns the full JSON when it is under the cap", () => {
    const v = { a: 1, b: "two" };
    const out = capJsonSample(v);
    expect(out).toBe(JSON.stringify(v, null, 2));
  });

  it("truncates and appends a marker when over the cap", () => {
    // Build a payload that definitely exceeds 16 KB after pretty-printing.
    const big = { items: Array.from({ length: 5000 }, (_, i) => `s${i}`) };
    const out = capJsonSample(big);
    expect(out.endsWith("…[truncated]")).toBe(true);
    // Total length is the cap + marker (15 chars "…[truncated]\n" prefix, etc).
    expect(out.length).toBeGreaterThan(16 * 1024);
    expect(out.length).toBeLessThan(16 * 1024 + 50);
  });
});

describe("fetchFromSource", () => {
  it("parses JSON responses with application/json content-type", async () => {
    const src = makeSource("/json");
    const r = await fetchFromSource(src);
    expect(r.ok).toBe(true);
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ hello: "world", n: 7 });
    expect(r.bodyText).toContain("hello");
  });

  it("returns text body as-is for text/plain", async () => {
    const src = makeSource("/text");
    const r = await fetchFromSource(src);
    expect(r.ok).toBe(true);
    expect(r.body).toBe("plain body");
    expect(r.bodyText).toBe("plain body");
  });

  it("best-effort parses JSON even when content-type is not JSON", async () => {
    const src = makeSource("/ambiguous-json");
    const r = await fetchFromSource(src);
    expect(r.body).toEqual({ x: 42 });
  });

  it("sends auth header when provided", async () => {
    const src = makeSource("/echo-headers", {
      authHeaderKey: "X-API-Key",
      authHeaderValue: "secret-123",
    });
    const r = await fetchFromSource(src);
    expect(r.ok).toBe(true);
    const body = r.body as { headers: Record<string, string> };
    expect(body.headers["x-api-key"]).toBe("secret-123");
  });

  it("merges extra headers", async () => {
    const src = makeSource("/echo-headers", {
      headers: { "X-Extra": "hi" },
    });
    const r = await fetchFromSource(src);
    const body = r.body as { headers: Record<string, string> };
    expect(body.headers["x-extra"]).toBe("hi");
    expect(body.headers["accept"]).toContain("application/json");
  });

  it("marks non-2xx responses ok=false", async () => {
    const src = makeSource("/boom");
    const r = await fetchFromSource(src);
    expect(r.ok).toBe(false);
    expect(r.status).toBe(500);
    expect(r.body).toEqual({ error: "nope" });
  });
});
