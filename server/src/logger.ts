// MCP stdio uses stdout for its JSON-RPC stream.
// Every log line MUST go to stderr or it corrupts the protocol.

type Level = "info" | "warn" | "error" | "debug";

function emit(level: Level, args: unknown[]): void {
  const prefix = `[${new Date().toISOString()}] [${level}]`;
  // eslint-disable-next-line no-console
  console.error(prefix, ...args);
}

export const log = {
  info: (...args: unknown[]) => emit("info", args),
  warn: (...args: unknown[]) => emit("warn", args),
  error: (...args: unknown[]) => emit("error", args),
  debug: (...args: unknown[]) => emit("debug", args),
};
