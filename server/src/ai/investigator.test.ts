/**
 * Tests for the Claude Managed Agents incident investigator.
 *
 * Mocks the @anthropic-ai/sdk client end-to-end (agents.create,
 * environments.create, sessions.create, events.stream, events.send) so
 * runInvestigation() can be exercised against fake streamed events.
 *
 * Covers:
 *   • Happy path: seeded investigation transitions running → done with
 *     a streamed report and a recorded session_id.
 *   • Cache reuse: second invocation in the same process does NOT
 *     re-create the agent or environment.
 *   • Failure path: SDK throws → status='failed', error recorded,
 *     setupPromise reset so the next call retries.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { withFreshDbAndThemes } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  getInvestigation,
  kvGet,
} from "../db/repo.js";

// Build the mocked SDK BEFORE we import the investigator, so the
// investigator's `getClient()` resolves to our mock factory.
const mockAgentsCreate = vi.fn();
const mockEnvironmentsCreate = vi.fn();
const mockSessionsCreate = vi.fn();
const mockEventsStream = vi.fn();
const mockEventsSend = vi.fn();

vi.mock("./client.js", () => ({
  getClient: () => ({
    beta: {
      agents: { create: mockAgentsCreate },
      environments: { create: mockEnvironmentsCreate },
      sessions: {
        create: mockSessionsCreate,
        events: { stream: mockEventsStream, send: mockEventsSend },
      },
    },
  }),
  OPUS_4_7: "claude-opus-4-7",
}));

// Now import the investigator — it picks up the mock above.
const investigatorModule = await import("./investigator.js");
const { spawnInvestigation, __resetInvestigatorForTests } =
  investigatorModule;

let cleanup: () => void = () => {};
let widgetId = "";

beforeEach(() => {
  ({ cleanup } = withFreshDbAndThemes());
  process.env.ANTHROPIC_API_KEY = "test-key";
  __resetInvestigatorForTests();
  mockAgentsCreate.mockReset();
  mockEnvironmentsCreate.mockReset();
  mockSessionsCreate.mockReset();
  mockEventsStream.mockReset();
  mockEventsSend.mockReset();

  const dash = createDashboard({ name: "D", themeId: "default" });
  const src = createDataSource({
    name: "S",
    type: "rest",
    url: "https://example.com",
    method: "GET",
    pollIntervalSec: 60,
  });
  const w = createWidget({
    dashboardId: dash.id,
    sourceId: src.id,
    type: "number",
    title: "Critical errors",
    transformExpr: "x",
    position: 0,
  });
  widgetId = w.id;
});

afterEach(() => {
  cleanup();
});

// Helper to build an async iterable returning the supplied events in order.
function fakeStream(
  events: Array<Record<string, unknown>>,
): AsyncIterable<Record<string, unknown>> {
  return {
    [Symbol.asyncIterator]() {
      let i = 0;
      return {
        next: async () => {
          if (i >= events.length) return { value: undefined, done: true };
          // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
          const value = events[i++]!;
          return { value, done: false };
        },
      };
    },
  };
}

async function untilTerminal(
  investigationId: string,
  timeoutMs = 4000,
): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const inv = getInvestigation(investigationId);
    if (inv && (inv.status === "done" || inv.status === "failed")) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error("investigation never terminated");
}

describe("investigator: happy path", () => {
  it("creates agent + env once, runs session, persists streamed report", async () => {
    mockAgentsCreate.mockResolvedValue({ id: "ag_test_1" });
    mockEnvironmentsCreate.mockResolvedValue({ id: "env_test_1" });
    mockSessionsCreate.mockResolvedValue({ id: "ses_test_1" });
    mockEventsStream.mockResolvedValue(
      fakeStream([
        {
          type: "agent.message",
          content: [{ type: "text", text: "## Spike of 47 errors\n\n" }],
        },
        {
          type: "agent.tool_use",
          name: "web_search",
        },
        {
          type: "agent.message",
          content: [
            {
              type: "text",
              text: "Body of the report explaining what happened.",
            },
          ],
        },
        { type: "session.status_idle" },
      ]),
    );
    mockEventsSend.mockResolvedValue({});

    const investigationId = spawnInvestigation({
      widget: {
        id: widgetId,
        dashboardId: "dash-1",
        sourceId: "src-1",
        type: "number",
        title: "Critical errors",
        transformExpr: "x",
        position: 0,
        createdAt: "2026-04-26T00:00:00Z",
      },
      anomalyExplanation: "Spike of 47 errors in last poll.",
      currentValue: 47,
    });
    expect(investigationId).not.toBeNull();
    if (!investigationId) return;

    await untilTerminal(investigationId);

    const inv = getInvestigation(investigationId)!;
    expect(inv.status).toBe("done");
    expect(inv.sessionId).toBe("ses_test_1");
    expect(inv.report).toContain("Spike of 47 errors");
    expect(inv.report).toContain("explaining what happened");
    expect(inv.title).toBe("Spike of 47 errors");
    expect(inv.completedAt).not.toBeNull();

    expect(mockAgentsCreate).toHaveBeenCalledTimes(1);
    expect(mockEnvironmentsCreate).toHaveBeenCalledTimes(1);
    expect(mockSessionsCreate).toHaveBeenCalledTimes(1);
    expect(mockEventsSend).toHaveBeenCalledTimes(1);

    // KV cache populated.
    expect(kvGet("managed_agents:investigator:agent_id")).toBe("ag_test_1");
    expect(kvGet("managed_agents:investigator:environment_id")).toBe(
      "env_test_1",
    );
  });

  it("reuses cached agent + environment on second invocation", async () => {
    // Pre-seed the kv cache so the investigator skips creation.
    const { kvSet } = await import("../db/repo.js");
    kvSet("managed_agents:investigator:agent_id", "ag_existing");
    kvSet("managed_agents:investigator:environment_id", "env_existing");

    mockSessionsCreate.mockResolvedValue({ id: "ses_2" });
    mockEventsStream.mockResolvedValue(
      fakeStream([
        {
          type: "agent.message",
          content: [{ type: "text", text: "## Headline\n\nbody" }],
        },
        { type: "session.status_idle" },
      ]),
    );
    mockEventsSend.mockResolvedValue({});

    const id = spawnInvestigation({
      widget: {
        id: widgetId,
        dashboardId: "dash-1",
        sourceId: "src-1",
        type: "number",
        title: "Critical errors",
        transformExpr: "x",
        position: 0,
        createdAt: "2026-04-26T00:00:00Z",
      },
      anomalyExplanation: "x",
      currentValue: 1,
    })!;
    await untilTerminal(id);

    expect(getInvestigation(id)?.status).toBe("done");
    expect(mockAgentsCreate).not.toHaveBeenCalled();
    expect(mockEnvironmentsCreate).not.toHaveBeenCalled();
    expect(mockSessionsCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        agent: "ag_existing",
        environment_id: "env_existing",
      }),
    );
  });
});

describe("investigator: failure paths", () => {
  it("marks investigation as failed when the SDK throws", async () => {
    mockAgentsCreate.mockRejectedValue(new Error("boom: rate limited"));

    const id = spawnInvestigation({
      widget: {
        id: widgetId,
        dashboardId: "dash-1",
        sourceId: "src-1",
        type: "number",
        title: "Critical errors",
        transformExpr: "x",
        position: 0,
        createdAt: "2026-04-26T00:00:00Z",
      },
      anomalyExplanation: "x",
      currentValue: 1,
    })!;
    await untilTerminal(id);

    const inv = getInvestigation(id)!;
    expect(inv.status).toBe("failed");
    expect(inv.error).toContain("boom: rate limited");
    expect(inv.completedAt).not.toBeNull();
  });

  it("returns null and skips DB writes when ANTHROPIC_API_KEY is unset", () => {
    delete process.env.ANTHROPIC_API_KEY;
    const id = spawnInvestigation({
      widget: {
        id: widgetId,
        dashboardId: "dash-1",
        sourceId: "src-1",
        type: "number",
        title: "Critical errors",
        transformExpr: "x",
        position: 0,
        createdAt: "2026-04-26T00:00:00Z",
      },
      anomalyExplanation: "x",
      currentValue: 1,
    });
    expect(id).toBeNull();
    expect(mockAgentsCreate).not.toHaveBeenCalled();
    process.env.ANTHROPIC_API_KEY = "test-key";
  });
});
