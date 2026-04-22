import { getClient, OPUS_4_7 } from "./client.js";
import type { Theme } from "../themes/presets.js";
import { log } from "../logger.js";

const SYSTEM_PROMPT = `You are BentoDeck's theme designer.

Given a short natural-language vibe prompt (e.g. "cyberpunk terminal",
"calm pastel notebook", "minimal nordic"), you emit a complete theme
JSON for a dashboard of live-data widgets rendered on an iPhone Home
Screen, Lock Screen, and (later) Apple Watch.

Hard rules:
  • All color values must be hex strings ("#RRGGBB" or "#RRGGBBAA"),
    uppercase, no shorthand.
  • Colors must achieve WCAG AA contrast between primary text and
    background (at least 4.5:1). The user is going to glance at these
    on a phone in sunlight.
  • accent, positive, and negative must be visually distinguishable
    from both primary and background.
  • chart.fillStart must be the same hue as chart.stroke at ~30-40%
    alpha; chart.fillEnd must be the same hue at 0% alpha.
  • Don't drift into whimsy that sacrifices readability. "Playful" is
    fine. "Unreadable" is not.

Font family choices: "rounded" (friendly), "serif" (editorial),
"monospaced" (technical / retro / terminal), "default" (neutral).
Weight: "regular", "medium", "semibold", "bold", "heavy".

Always call emit_theme. Never respond in free text.`;

const TOOL = {
  name: "emit_theme",
  description: "Emit the generated theme JSON.",
  input_schema: {
    type: "object" as const,
    properties: {
      name: { type: "string", description: "A short title for the theme, ≤ 24 chars." },
      colors: {
        type: "object",
        properties: {
          background: { type: "string" },
          surface: { type: "string" },
          primary: { type: "string" },
          secondary: { type: "string" },
          accent: { type: "string" },
          positive: { type: "string" },
          negative: { type: "string" },
          border: { type: "string" },
        },
        required: [
          "background",
          "surface",
          "primary",
          "secondary",
          "accent",
          "positive",
          "negative",
          "border",
        ],
      },
      font: {
        type: "object",
        properties: {
          family: {
            type: "string",
            enum: ["rounded", "serif", "monospaced", "default"],
          },
          weightPrimary: {
            type: "string",
            enum: ["regular", "medium", "semibold", "bold", "heavy"],
          },
        },
        required: ["family", "weightPrimary"],
      },
      chart: {
        type: "object",
        properties: {
          stroke: { type: "string" },
          fillStart: { type: "string" },
          fillEnd: { type: "string" },
        },
        required: ["stroke", "fillStart", "fillEnd"],
      },
    },
    required: ["name", "colors", "font", "chart"],
  },
};

export async function generateTheme(prompt: string): Promise<Theme> {
  const client = getClient();
  log.info(`[theme-agent] generating: "${prompt}"`);

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
        content: [{ type: "text", text: `Vibe: ${prompt}` }],
      },
    ],
  });

  const toolUse = resp.content.find((b) => b.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") {
    throw new Error("theme agent did not call emit_theme");
  }
  const input = toolUse.input as Omit<Theme, "id">;
  // Derive a slug-style id from the prompt + a short timestamp so multiple
  // generations of the same vibe don't collide.
  const slug =
    prompt
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 32) || "ai";
  const id = `ai-${slug}-${Date.now().toString(36)}`;

  const theme: Theme = { id, ...input };
  log.info(`[theme-agent] emitted id=${id} name="${theme.name}"`);
  return theme;
}
