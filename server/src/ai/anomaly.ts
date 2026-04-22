import { getClient, OPUS_4_7 } from "./client.js";
import { log } from "../logger.js";
import type { Widget } from "../types/schemas.js";

export type AnomalyResult = {
  isAnomaly: boolean;
  explanation: string | null;
};

const MIN_HISTORY_POINTS = 3;

const SYSTEM_PROMPT = `You are BentoDeck's anomaly detector.

Given a widget's recent value history and the latest value, decide whether
the latest value is anomalous enough that the user should be notified on
their Lock Screen or Apple Watch.

An anomaly is:
  • A sudden drop or spike of ≥ 20% with no recent precedent.
  • A direction reversal in a previously-monotonic series.
  • A value of 0 or null appearing after a non-zero, non-null history.
  • A list or status widget's items or state changing materially.
  • Any value crossing an obviously meaningful threshold given the title
    (e.g., error count > 0 when title says "Critical errors").

It is NOT an anomaly when:
  • Small fluctuations in the same direction as the recent trend.
  • The series was already noisy and the new value fits the noise band.

If you flag an anomaly, explanation MUST be a single sentence ≤ 140 chars.
Start it with the direction and magnitude ("Down 96% …", "Spike of 47
errors in the last poll …"). Name the likely cause only if the data
itself implies one. No speculation, no hedging language.

Always call emit_anomaly_check. Never respond in free text.`;

const TOOL = {
  name: "emit_anomaly_check",
  description: "Emit the anomaly decision for this widget.",
  input_schema: {
    type: "object" as const,
    properties: {
      isAnomaly: { type: "boolean" },
      explanation: {
        type: "string",
        description: "One-sentence explanation if anomalous; empty string otherwise.",
      },
    },
    required: ["isAnomaly", "explanation"],
  },
};

export async function evaluateAnomaly(args: {
  widget: Pick<Widget, "id" | "title" | "type">;
  history: Array<{ value: unknown; ts: string }>;
  currentValue: unknown;
}): Promise<AnomalyResult> {
  if (!process.env.ANTHROPIC_API_KEY) {
    // AI not configured — treat as "no anomaly" so polling still works.
    return { isAnomaly: false, explanation: null };
  }
  if (args.history.length < MIN_HISTORY_POINTS) {
    return { isAnomaly: false, explanation: null };
  }

  const client = getClient();
  const historyText = args.history
    .map((h) => `  ${h.ts}: ${JSON.stringify(h.value)}`)
    .join("\n");

  const resp = await client.messages.create({
    model: OPUS_4_7,
    max_tokens: 256,
    system: [
      {
        type: "text",
        text: SYSTEM_PROMPT,
        cache_control: { type: "ephemeral" },
      },
    ],
    tools: [TOOL],
    tool_choice: { type: "tool", name: TOOL.name },
    messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: `Widget: "${args.widget.title}" (type: ${args.widget.type})\n\nRecent history (oldest → newest):\n${historyText}\n\nLatest value: ${JSON.stringify(args.currentValue)}`,
          },
        ],
      },
    ],
  });

  const toolUse = resp.content.find((b) => b.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") {
    log.warn(`[anomaly] widget=${args.widget.id} no tool_use in response`);
    return { isAnomaly: false, explanation: null };
  }
  const input = toolUse.input as { isAnomaly?: boolean; explanation?: string };
  const isAnomaly = Boolean(input.isAnomaly);
  const explanation = input.explanation?.trim() || null;
  return { isAnomaly, explanation: isAnomaly ? explanation : null };
}
