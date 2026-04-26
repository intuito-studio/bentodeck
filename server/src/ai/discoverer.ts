// Tier-2 data-source discovery: given a platform's docs URL + an intent in
// English, Opus 4.7 reads the docs and emits a complete add_data_source
// payload (HTTP method, URL, headers, auth header). We then verify the
// generated spec by actually calling the endpoint once before persisting.
//
// This is what makes the README's "any public API is a first-class citizen"
// claim real — no hand-maintained connector catalog, no mapping tables.
// Linear today, Helius tomorrow, your bespoke API on Tuesday — all the
// same path.
import { z } from "zod";
import { getClient, OPUS_4_7 } from "./client.js";
import { capJsonSample, fetchFromSource } from "../sources/fetch.js";
import { createDataSource, saveLastSample } from "../db/repo.js";
import { log } from "../logger.js";
import type { DataSource } from "../types/schemas.js";

const DocsFetchSchema = z.object({
  ok: z.boolean(),
  bodyText: z.string(),
  status: z.number(),
});

const SourceSpec = z.object({
  url: z.string().url(),
  method: z.enum(["GET", "POST"]),
  headers: z.record(z.string(), z.string()).optional(),
  authHeaderKey: z.string().optional(),
  authHeaderValue: z.string().optional(),
  pollIntervalSec: z.number().int().positive().max(3600).default(60),
  reasoning: z.string().optional(),
});
export type SourceSpec = z.infer<typeof SourceSpec>;

const SYSTEM_PROMPT = `You are BentoDeck's data-source discoverer.

Given:
  • A platform's API documentation page (raw text content, with HTML
    stripped by us).
  • A user's intent in plain English ("count of open Linear issues",
    "Stripe MRR", "GitHub PRs awaiting review").
  • Optionally, an API key the user has supplied (treat as opaque).

Emit ONE concrete REST endpoint that BentoDeck can poll on a schedule
to satisfy the intent.

Hard rules:
  • The endpoint must be a GET (preferred) or POST that returns JSON.
  • No GraphQL. If the docs only describe GraphQL, pick the closest
    REST equivalent or the platform's REST fallback. If neither exists,
    fail loudly via reasoning rather than inventing one.
  • Authentication header keys come from the docs verbatim
    (e.g. "Authorization", "X-API-KEY"). When using a Bearer scheme,
    the value MUST be exactly "Bearer {{API_KEY}}" — do NOT inline the
    user's key. We substitute it in code.
  • Default poll interval: 60 seconds unless the docs explicitly state
    a stricter rate-limit, in which case pick the smallest multiple of
    60 that is safely under the limit.
  • If the docs contradict your training memory, trust the docs.

Always call emit_source_spec. Never respond in free text.`;

const TOOL = {
  name: "emit_source_spec",
  description:
    "Emit the discovered REST endpoint specification BentoDeck should poll.",
  input_schema: {
    type: "object" as const,
    properties: {
      url: { type: "string" },
      method: { type: "string", enum: ["GET", "POST"] },
      headers: {
        type: "object",
        additionalProperties: { type: "string" },
        description: "Extra non-auth HTTP headers as a flat key→value map.",
      },
      authHeaderKey: {
        type: "string",
        description:
          "Header name for auth (e.g. 'Authorization', 'X-API-KEY'). Omit if no auth required.",
      },
      authHeaderValue: {
        type: "string",
        description:
          "Header value template using the literal placeholder {{API_KEY}} where the user's key should be substituted (e.g. 'Bearer {{API_KEY}}'). Omit when no auth required.",
      },
      pollIntervalSec: { type: "integer", minimum: 1, maximum: 3600 },
      reasoning: {
        type: "string",
        description: "One-sentence why-this-endpoint explanation.",
      },
    },
    required: ["url", "method"],
  },
};

async function fetchDocsPlainText(url: string): Promise<{
  ok: boolean;
  text: string;
  status: number;
}> {
  try {
    const res = await fetch(url, {
      headers: {
        Accept: "text/html,application/xhtml+xml",
        "User-Agent": "BentoDeck/0.1 (+https://bentodeck.io)",
      },
    });
    const html = await res.text();
    // Strip HTML/script/style; collapse whitespace. Good enough — Opus is
    // robust to noisy text and the prompt-token budget here is generous.
    const stripped = html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/\s+/g, " ")
      .trim();
    // Cap at 60 KB of doc text — way more than any single endpoint section
    // would ever need, and keeps latency / cost sane.
    const text = stripped.slice(0, 60 * 1024);
    DocsFetchSchema.parse({ ok: res.ok, bodyText: text, status: res.status });
    return { ok: res.ok, text, status: res.status };
  } catch (err) {
    return {
      ok: false,
      text: err instanceof Error ? err.message : String(err),
      status: 0,
    };
  }
}

export type DiscoveryResult =
  | {
      ok: true;
      source: DataSource;
      spec: SourceSpec;
      sampleBodyPreview: string;
      // True when the source requires auth and the user didn't supply a
      // key. The source is persisted with needs_key=1; verification was
      // skipped. The iOS app must prompt for the key.
      needsKey?: boolean;
    }
  | {
      ok: false;
      reason: string;
      spec?: SourceSpec;
      bodyPreview?: string;
    };

export async function discoverDataSource(args: {
  docsUrl: string;
  intent: string;
  apiKey?: string;
  name?: string;
}): Promise<DiscoveryResult> {
  if (!process.env.ANTHROPIC_API_KEY) {
    return { ok: false, reason: "ANTHROPIC_API_KEY is not set" };
  }

  log.info(
    `[discover] docs=${args.docsUrl} intent="${args.intent}" key=${args.apiKey ? "present" : "absent"}`,
  );

  const docs = await fetchDocsPlainText(args.docsUrl);
  if (!docs.ok || docs.text.length < 80) {
    return {
      ok: false,
      reason: `couldn't fetch docs (HTTP ${docs.status}): ${docs.text.slice(0, 160)}`,
    };
  }

  const client = getClient();
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
            text: [
              `Intent: ${args.intent}`,
              args.apiKey
                ? `User has provided an API key (substitute as {{API_KEY}}).`
                : `No API key provided — only emit auth headers if the endpoint is fully public.`,
              ``,
              `Docs page: ${args.docsUrl}`,
              `Docs content (HTML stripped, possibly truncated):`,
              `\`\`\``,
              docs.text,
              `\`\`\``,
            ].join("\n"),
          },
        ],
      },
    ],
  });

  const toolUse = resp.content.find((b) => b.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") {
    return { ok: false, reason: "discoverer agent did not call emit_source_spec" };
  }
  let spec: SourceSpec;
  try {
    spec = SourceSpec.parse(toolUse.input);
  } catch (err) {
    return {
      ok: false,
      reason: `discoverer emitted an invalid spec: ${err instanceof Error ? err.message : err}`,
    };
  }
  log.info(
    `[discover] proposal: ${spec.method} ${spec.url} authKey=${spec.authHeaderKey ?? "—"} reason="${spec.reasoning ?? ""}"`,
  );

  // "Needs-key" path: the spec requires auth but the user didn't supply
  // a key. Persist the template verbatim (with {{API_KEY}}) and flip
  // needs_key=true. Skip verification — there's nothing to verify yet.
  // The iOS app will prompt for the key, then POST /data-sources/:id/key.
  const requiresAuth = !!spec.authHeaderKey;
  if (requiresAuth && !args.apiKey) {
    const source = createDataSource({
      name: args.name ?? new URL(spec.url).hostname,
      type: "rest",
      url: spec.url,
      method: spec.method,
      headers: spec.headers,
      authHeaderKey: spec.authHeaderKey,
      authHeaderValue: spec.authHeaderValue,
      pollIntervalSec: spec.pollIntervalSec,
      needsKey: true,
    });
    log.info(
      `[discover] persisted needs-key source=${source.id} (awaiting user key)`,
    );
    return {
      ok: true,
      source,
      spec,
      sampleBodyPreview:
        "(awaiting API key; sample will be captured on first successful poll)",
      needsKey: true,
    };
  }

  // Substitute the user's API key into the auth header value template.
  const authHeaderValue =
    spec.authHeaderKey && spec.authHeaderValue && args.apiKey
      ? spec.authHeaderValue.replace("{{API_KEY}}", args.apiKey)
      : spec.authHeaderValue && !spec.authHeaderValue.includes("{{API_KEY}}")
        ? spec.authHeaderValue
        : undefined;

  // Verification: actually try the endpoint once before persisting.
  // This protects us from hallucinated endpoints and bad auth.
  const trial = await fetchFromSource({
    id: "trial",
    name: args.name ?? "trial",
    type: "rest",
    url: spec.url,
    method: spec.method,
    headers: spec.headers,
    authHeaderKey: spec.authHeaderKey,
    authHeaderValue,
    pollIntervalSec: spec.pollIntervalSec,
    createdAt: "",
  });
  if (!trial.ok) {
    return {
      ok: false,
      reason: `verified call returned HTTP ${trial.status}`,
      spec,
      bodyPreview: trial.bodyText.slice(0, 400),
    };
  }

  const source = createDataSource({
    name: args.name ?? new URL(spec.url).hostname,
    type: "rest",
    url: spec.url,
    method: spec.method,
    headers: spec.headers,
    authHeaderKey: spec.authHeaderKey,
    authHeaderValue,
    pollIntervalSec: spec.pollIntervalSec,
  });
  saveLastSample(source.id, JSON.stringify(trial.body));

  return {
    ok: true,
    source,
    spec,
    sampleBodyPreview: capJsonSample(trial.body).slice(0, 800),
  };
}
