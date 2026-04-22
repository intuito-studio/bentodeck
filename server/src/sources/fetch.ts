import type { DataSource } from "../types/schemas.js";

export type FetchResult = {
  ok: boolean;
  status: number;
  body: unknown;
  bodyText: string;
  headers: Record<string, string>;
};

export async function fetchFromSource(source: DataSource): Promise<FetchResult> {
  const headers: Record<string, string> = {
    Accept: "application/json",
    "User-Agent": "BentoDeck/0.1 (+https://bentodeck.io)",
    ...(source.headers ?? {}),
  };
  if (source.authHeaderKey && source.authHeaderValue) {
    headers[source.authHeaderKey] = source.authHeaderValue;
  }

  const res = await fetch(source.url, {
    method: source.method,
    headers,
  });

  const bodyText = await res.text();
  let body: unknown = bodyText;
  const contentType = res.headers.get("content-type") ?? "";
  if (contentType.includes("application/json") || contentType.includes("+json")) {
    try {
      body = JSON.parse(bodyText);
    } catch {
      // keep as text
    }
  } else if (bodyText.length > 0) {
    // Some APIs return JSON without a proper content-type header. Try parsing.
    try {
      body = JSON.parse(bodyText);
    } catch {
      /* keep as text */
    }
  }

  const outHeaders: Record<string, string> = {};
  res.headers.forEach((v, k) => {
    outHeaders[k] = v;
  });

  return {
    ok: res.ok,
    status: res.status,
    body,
    bodyText,
    headers: outHeaders,
  };
}

// JSON sample size cap sent to Opus 4.7 so we don't waste tokens on huge payloads.
// 16 KB is enough for almost every API's shape to be recognisable.
const MAX_SAMPLE_BYTES = 16 * 1024;

export function capJsonSample(value: unknown): string {
  const full = JSON.stringify(value, null, 2);
  if (full.length <= MAX_SAMPLE_BYTES) return full;
  return full.slice(0, MAX_SAMPLE_BYTES) + "\n…[truncated]";
}
