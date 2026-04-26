// Claude Managed Agents integration: BentoDeck's incident investigator.
//
// When the poll loop's quick anomaly check fires, we ALSO kick off a
// long-running Managed Agents session whose job is to write a deeper
// incident report than a single Opus 4.7 call ever could. The agent has
// the full agent_toolset_20260401 (bash + file ops + web search), runs
// in a managed sandboxed container, and produces a multi-paragraph
// runbook-style report we surface in the iOS app via tap-on-banner.
//
// Why two paths:
//   • The wrist-buzz path (poll loop → checkAnomalyForWidget → one
//     Opus 4.7 call) needs to be fast and cheap. One sentence.
//   • The investigator path can take 30-60 seconds and burn more tokens.
//     It runs detached, streams events, persists incrementally to SQLite,
//     and is consumable when the user taps the alert. This is exactly
//     the "decoupling brain from hands" pattern Anthropic ships
//     Managed Agents for.
//
// The agent_id and environment_id are created once and cached in the
// kv table so we don't re-create them on every poll. The first
// investigation pays the ~one-time setup cost.
import { randomUUID } from "node:crypto";
import { getClient, OPUS_4_7 } from "./client.js";
import {
  createInvestigation,
  getWidget,
  kvGet,
  kvSet,
  latestSnapshotId,
  recentSnapshots,
  updateInvestigation,
} from "../db/repo.js";
import { log } from "../logger.js";
import type { Widget } from "../types/schemas.js";

const AGENT_ID_KEY = "managed_agents:investigator:agent_id";
const ENV_ID_KEY = "managed_agents:investigator:environment_id";

const SYSTEM_PROMPT = `You are BentoDeck's incident investigator.

You receive an anomalous metric from a live ops dashboard. Your job is to
write a concise but useful incident report for the dashboard owner: an
indie SaaS founder, a bot trader, or an AI-app builder who just got a
notification on their wrist or Lock Screen.

Your report MUST contain, in this order:

  1. A one-line headline (≤ 100 chars) restating what happened.
  2. A 2-4 sentence "what likely happened" hypothesis. Use any context
     about the metric type (MRR, error count, signups, etc.) to reason
     about probable causes. Be specific. No hedging filler.
  3. A "what to check first" bulleted runbook (3-6 items) — concrete
     things the owner can verify in their own systems in under 5 minutes.
  4. A "blast radius" sentence stating who or what might be affected
     downstream if the anomaly is real and persists.

You may use the agent toolset (web search especially) to look up known
causes for the kind of metric or service involved (e.g., recent Stripe
status incidents). Don't invent URLs; if you can't verify, say so.

Output the report as a single Markdown document. Do NOT wrap it in any
header / footer / preamble. Begin with the headline as a level-2 heading.`;

let setupPromise: Promise<{ agentId: string; environmentId: string }> | null =
  null;

async function ensureAgentAndEnvironment(): Promise<{
  agentId: string;
  environmentId: string;
}> {
  // Coalesce concurrent first-call attempts.
  if (setupPromise) return setupPromise;

  setupPromise = (async () => {
    const cached = {
      agentId: kvGet(AGENT_ID_KEY),
      environmentId: kvGet(ENV_ID_KEY),
    };
    if (cached.agentId && cached.environmentId) {
      log.info(
        `[investigator] reusing agent_id=${cached.agentId} env_id=${cached.environmentId}`,
      );
      return { agentId: cached.agentId, environmentId: cached.environmentId };
    }

    const client = getClient();
    log.info("[investigator] creating Managed Agent + Environment");

    const agent = await client.beta.agents.create({
      name: "BentoDeck Incident Investigator",
      model: OPUS_4_7,
      system: SYSTEM_PROMPT,
      tools: [{ type: "agent_toolset_20260401" }],
    });

    const environment = await client.beta.environments.create({
      name: "bentodeck-investigator",
      config: {
        type: "cloud",
        networking: { type: "unrestricted" },
      },
    });

    kvSet(AGENT_ID_KEY, agent.id);
    kvSet(ENV_ID_KEY, environment.id);

    log.info(
      `[investigator] created agent=${agent.id} env=${environment.id}`,
    );
    return { agentId: agent.id, environmentId: environment.id };
  })();

  // Don't memoise a failure — let the next attempt retry.
  setupPromise.catch(() => {
    setupPromise = null;
  });

  return setupPromise;
}

function summarizeHistory(
  history: Array<{ value: unknown; ts: string }>,
): string {
  if (history.length === 0) return "  (no prior history)";
  return history
    .slice(-12) // cap at 12 most-recent entries to keep prompt tight
    .map((h) => `  ${h.ts}: ${JSON.stringify(h.value)}`)
    .join("\n");
}

/**
 * Spawn an investigation in the background. Returns the new investigation id
 * immediately; the report is filled in over the following 30-60 seconds.
 *
 * Cost-bounded by the same `shouldInvokeAnomalyAI` gate that protects the
 * quick anomaly check, plus an internal one-investigation-per-anomaly rule.
 */
export function spawnInvestigation(args: {
  widget: Widget;
  anomalyExplanation: string;
  currentValue: unknown;
}): string | null {
  if (!process.env.ANTHROPIC_API_KEY) {
    return null; // AI not configured; investigations are best-effort.
  }

  const investigationId = randomUUID();
  const snapshotId = latestSnapshotId(args.widget.id);
  createInvestigation({
    id: investigationId,
    widgetId: args.widget.id,
    snapshotId,
  });

  // Fire and forget — never block the poll loop.
  void runInvestigation({
    investigationId,
    widget: args.widget,
    anomalyExplanation: args.anomalyExplanation,
    currentValue: args.currentValue,
  });

  return investigationId;
}

async function runInvestigation(args: {
  investigationId: string;
  widget: Widget;
  anomalyExplanation: string;
  currentValue: unknown;
}): Promise<void> {
  const { investigationId, widget } = args;
  try {
    updateInvestigation(investigationId, { status: "running" });
    const { agentId, environmentId } = await ensureAgentAndEnvironment();

    const client = getClient();
    const session = await client.beta.sessions.create({
      agent: agentId,
      environment_id: environmentId,
      title: `Investigate: ${widget.title}`,
    });
    updateInvestigation(investigationId, { sessionId: session.id });

    const history = recentSnapshots(widget.id, 30)
      .slice()
      .reverse()
      .map((h) => ({ value: h.value, ts: h.ts }));

    const userText = [
      `Widget: "${widget.title}" (type: ${widget.type})`,
      `Source widget id: ${widget.id}`,
      `Source dashboard id: ${widget.dashboardId}`,
      ``,
      `Just-fired anomaly explanation (the user has already seen this in a Local Notification):`,
      `> ${args.anomalyExplanation}`,
      ``,
      `Current value: ${JSON.stringify(args.currentValue)}`,
      ``,
      `Recent history (oldest → newest, up to 30 points):`,
      summarizeHistory(history),
      ``,
      `Investigate. Use web_search if helpful to check public status pages or known incidents for the relevant service. Write the report per the system-prompt format and emit it as your final agent.message before going idle.`,
    ].join("\n");

    log.info(
      `[investigator] session=${session.id} starting investigation widget=${widget.id}`,
    );

    // Open stream FIRST, then send the user event (events are buffered until
    // a stream attaches, per the Managed Agents docs).
    const stream = await client.beta.sessions.events.stream(session.id);
    await client.beta.sessions.events.send(session.id, {
      events: [
        {
          type: "user.message",
          content: [{ type: "text", text: userText }],
        },
      ],
    });

    let collected = "";
    let toolUseCount = 0;

    for await (const event of stream as AsyncIterable<{
      type: string;
      content?: Array<{ type: string; text?: string }>;
      name?: string;
    }>) {
      if (event.type === "agent.message" && Array.isArray(event.content)) {
        for (const block of event.content) {
          if (block.type === "text" && typeof block.text === "string") {
            collected += block.text;
          }
        }
        // Persist incrementally — the iOS app can poll for the report and
        // see partial progress on long investigations.
        updateInvestigation(investigationId, { report: collected });
      } else if (event.type === "agent.tool_use") {
        toolUseCount += 1;
      } else if (event.type === "session.status_idle") {
        break;
      }
    }

    // Pull the headline (first non-empty heading or first line).
    const headline =
      collected
        .split("\n")
        .map((l) => l.trim())
        .find((l) => l.length > 0)
        ?.replace(/^#+\s*/, "")
        .slice(0, 120) ?? null;

    updateInvestigation(investigationId, {
      status: "done",
      report: collected,
      title: headline,
    });
    log.info(
      `[investigator] session=${session.id} done widget=${widget.id} tools=${toolUseCount} chars=${collected.length}`,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    log.warn(
      `[investigator] failed widget=${widget.id} investigation=${investigationId}: ${message}`,
    );
    updateInvestigation(investigationId, {
      status: "failed",
      error: message,
    });
  }
}

// Test hook: clear the cached agent/environment so a fresh test run forces
// re-creation against a mocked SDK.
export function __resetInvestigatorForTests(): void {
  setupPromise = null;
}
