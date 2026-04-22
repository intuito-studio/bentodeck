import jmespath from "jmespath";
import { z } from "zod";
import { getClient, OPUS_4_7 } from "./client.js";
import { capJsonSample } from "../sources/fetch.js";
import { log } from "../logger.js";

export const WidgetPlan = z.object({
  transformExpr: z
    .string()
    .min(1)
    .describe("JMESPath expression applied to the source's JSON response."),
  widgetType: z.enum([
    "number",
    "number_with_trend",
    "gauge",
    "sparkline",
    "list",
    "status",
  ]),
  title: z.string().min(1).max(40),
  reasoning: z.string().optional(),
});
export type WidgetPlan = z.infer<typeof WidgetPlan>;

const SYSTEM_PROMPT = `You are the BentoDeck widget planner.

Given:
  • A user intent in plain English ("show my Stripe MRR", "number of failed checkouts today").
  • A sample JSON response from the user's API.

You decide:
  1. A JMESPath expression that extracts the single value or list the user wants from that response.
  2. The widget type that best fits that value.
  3. A short human-facing title (≤ 40 chars).

Rules:
  • You MUST use only JMESPath syntax (not JSONPath, not jq). Common patterns:
      data.mrr
      length(invoices[?status=='paid'])
      sum(orders[].total)
      [].{name: name, value: count} | [0:5]
  • Prefer the shortest expression that works.
  • Widget types:
      "number"              – a single scalar you can display big
      "number_with_trend"   – scalar that naturally has history (use when the user cares about "is it up or down?")
      "gauge"               – value between 0 and 100 (percentages, quota usage)
      "sparkline"           – a short numeric array (trend over time)
      "list"                – top-N items, where each has a label and a value
      "status"              – a discrete state: ok / warn / error
  • If the sample doesn't contain the data the intent asks for, still emit your best-effort expression and set reasoning to explain the uncertainty.
  • Keep the title concise and specific: "Stripe MRR", "Today's signups", "Critical errors (1h)".

Return your plan by calling the emit_widget_plan tool.`;

const TOOL = {
  name: "emit_widget_plan",
  description:
    "Emit the widget plan (JMESPath transform, widget type, title). Must be called exactly once.",
  input_schema: {
    type: "object" as const,
    properties: {
      transformExpr: {
        type: "string",
        description:
          "JMESPath expression applied to the source's JSON to produce the widget value.",
      },
      widgetType: {
        type: "string",
        enum: [
          "number",
          "number_with_trend",
          "gauge",
          "sparkline",
          "list",
          "status",
        ],
      },
      title: {
        type: "string",
        description: "Short human-facing widget title, ≤ 40 characters.",
      },
      reasoning: {
        type: "string",
        description: "Brief one-sentence reason for your choices.",
      },
    },
    required: ["transformExpr", "widgetType", "title"],
  },
};

export async function planWidget(args: {
  intent: string;
  sampleJson: unknown;
  sourceName: string;
}): Promise<{ plan: WidgetPlan; previewValue: unknown; previewError?: string }> {
  const client = getClient();
  const sample = capJsonSample(args.sampleJson);

  log.info(`[setup-agent] planning widget: intent="${args.intent}" source="${args.sourceName}"`);

  const resp = await client.messages.create({
    model: OPUS_4_7,
    max_tokens: 1024,
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
            text: `Intent: ${args.intent}\n\nData source: ${args.sourceName}\n\nSample response:\n\`\`\`json\n${sample}\n\`\`\``,
          },
        ],
      },
    ],
  });

  const toolUse = resp.content.find((b) => b.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") {
    throw new Error("setup agent did not call emit_widget_plan");
  }
  const plan = WidgetPlan.parse(toolUse.input);

  // Sanity-check the expression against the sample before returning.
  let previewValue: unknown = null;
  let previewError: string | undefined;
  try {
    previewValue = jmespath.search(args.sampleJson as object, plan.transformExpr);
  } catch (err) {
    previewError = err instanceof Error ? err.message : String(err);
  }

  log.info(
    `[setup-agent] plan: type=${plan.widgetType} expr="${plan.transformExpr}" title="${plan.title}"${
      previewError ? ` preview_error="${previewError}"` : ""
    }`,
  );

  return { plan, previewValue, previewError };
}
