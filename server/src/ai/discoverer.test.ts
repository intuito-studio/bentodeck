/**
 * Tests for the Tier-2 data-source discoverer.
 *
 * These exercise the parts of `discoverDataSource` that don't depend on
 * the real Anthropic API — by stubbing `getClient()` and the global
 * `fetch()` to return canned docs HTML and a canned API response.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { withFreshDbAndThemes } from "../test-utils.js";
import { discoverDataSource } from "./discoverer.js";
import { listDataSources } from "../db/repo.js";

// vi.mock must reference the same path the production module uses.
vi.mock("./client.js", () => {
  const create = vi.fn();
  return {
    getClient: () => ({ messages: { create } }),
    OPUS_4_7: "claude-opus-4-7",
    __mockCreate: create,
  };
});
const clientModule = await import("./client.js");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockCreate = (clientModule as any).__mockCreate as ReturnType<
  typeof vi.fn
>;

let cleanup: () => void = () => {};
let originalFetch: typeof globalThis.fetch;

beforeEach(() => {
  ({ cleanup } = withFreshDbAndThemes());
  process.env.ANTHROPIC_API_KEY = "test-key";
  mockCreate.mockReset();
  originalFetch = globalThis.fetch;
});

afterEach(() => {
  cleanup();
  globalThis.fetch = originalFetch;
});

const docsHtml = `<!DOCTYPE html>
<html><body>
  <h1>Linear API</h1>
  <p>Authenticate with Bearer tokens via the Authorization header.</p>
  <pre>GET https://api.linear.app/v1/issues?status=open</pre>
  <p>Returns JSON with a count field.</p>
</body></html>`;

function stubFetchSequence(responses: Array<{ ok: boolean; status: number; body: string; contentType?: string }>): void {
  let i = 0;
  globalThis.fetch = vi.fn(async () => {
    const r = responses[i++ % responses.length];
    return new Response(r.body, {
      status: r.status,
      headers: {
        "content-type": r.contentType ?? "application/json",
      },
    });
  }) as typeof globalThis.fetch;
}

function makeOpusToolUseResponse(input: Record<string, unknown>) {
  return {
    content: [
      { type: "tool_use", id: "tu_1", name: "emit_source_spec", input },
    ],
    stop_reason: "tool_use",
    usage: { input_tokens: 1, output_tokens: 1 },
  };
}

describe("discoverDataSource", () => {
  it("emits a working spec, verifies the call, and persists the source", async () => {
    stubFetchSequence([
      { ok: true, status: 200, body: docsHtml, contentType: "text/html" },
      { ok: true, status: 200, body: JSON.stringify({ count: 17 }) },
    ]);
    mockCreate.mockResolvedValue(
      makeOpusToolUseResponse({
        url: "https://api.linear.app/v1/issues?status=open",
        method: "GET",
        authHeaderKey: "Authorization",
        authHeaderValue: "Bearer {{API_KEY}}",
        pollIntervalSec: 60,
        reasoning: "issues count comes from /v1/issues",
      }),
    );

    const result = await discoverDataSource({
      docsUrl: "https://developers.linear.app/docs/issues",
      intent: "Open issues count",
      apiKey: "lin_secret_value",
      name: "Linear open issues",
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return; // narrow

    expect(result.source.name).toBe("Linear open issues");
    expect(result.source.method).toBe("GET");
    expect(result.source.authHeaderKey).toBe("Authorization");
    expect(result.spec.authHeaderValue).toBe("Bearer {{API_KEY}}"); // template only
    expect(result.sampleBodyPreview).toContain("count");

    // Persisted with the substituted real key, but the response payload's
    // sampleBodyPreview must NOT contain the secret because we only ever
    // showed the model the placeholder.
    expect(result.sampleBodyPreview).not.toContain("lin_secret_value");

    const stored = listDataSources();
    expect(stored).toHaveLength(1);
    expect(stored[0]?.authHeaderValue).toBe("Bearer lin_secret_value");
  });

  it("does not persist a source if verification call fails", async () => {
    stubFetchSequence([
      { ok: true, status: 200, body: docsHtml, contentType: "text/html" },
      { ok: false, status: 401, body: "{\"error\":\"unauthorized\"}" },
    ]);
    mockCreate.mockResolvedValue(
      makeOpusToolUseResponse({
        url: "https://api.linear.app/v1/issues",
        method: "GET",
        authHeaderKey: "Authorization",
        authHeaderValue: "Bearer {{API_KEY}}",
        pollIntervalSec: 60,
      }),
    );

    const result = await discoverDataSource({
      docsUrl: "https://docs.example.com",
      intent: "open issues",
      apiKey: "wrong-key",
    });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.reason).toMatch(/HTTP 401/);
    expect(result.spec).toBeDefined();
    expect(listDataSources()).toHaveLength(0);
  });

  it("fails loudly when the docs page can't be fetched", async () => {
    stubFetchSequence([
      { ok: false, status: 404, body: "<html>not found</html>", contentType: "text/html" },
    ]);

    const result = await discoverDataSource({
      docsUrl: "https://docs.example.com/missing",
      intent: "x",
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toMatch(/couldn't fetch docs/);
    }
    // No call to Anthropic should have been made.
    expect(mockCreate).not.toHaveBeenCalled();
    expect(listDataSources()).toHaveLength(0);
  });

  it("fails when the model emits an invalid spec", async () => {
    stubFetchSequence([
      { ok: true, status: 200, body: docsHtml, contentType: "text/html" },
    ]);
    mockCreate.mockResolvedValue(
      makeOpusToolUseResponse({
        url: "not-a-url",
        method: "PATCH" as unknown as "GET", // invalid
      }),
    );

    const result = await discoverDataSource({
      docsUrl: "https://docs.example.com",
      intent: "open issues",
    });

    expect(result.ok).toBe(false);
    expect(listDataSources()).toHaveLength(0);
  });

  it("no-ops cleanly when ANTHROPIC_API_KEY is unset", async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const result = await discoverDataSource({
      docsUrl: "https://docs.example.com",
      intent: "x",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toMatch(/ANTHROPIC_API_KEY/);
    }
    expect(mockCreate).not.toHaveBeenCalled();
    process.env.ANTHROPIC_API_KEY = "test-key"; // restore for other tests
  });
});
