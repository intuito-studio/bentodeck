import Anthropic from "@anthropic-ai/sdk";

let client: Anthropic | null = null;

export function getClient(): Anthropic {
  if (client) return client;
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error(
      "ANTHROPIC_API_KEY is not set. Copy server/.env.example to server/.env and fill it in.",
    );
  }
  client = new Anthropic({ apiKey });
  return client;
}

// Model pin. Opus 4.7 is the hackathon theme model; do not change without
// updating CLAUDE.md and the submission writeup.
export const OPUS_4_7 = "claude-opus-4-7";
