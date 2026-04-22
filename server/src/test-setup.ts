// Global test setup — runs once per test file before any tests execute.
// Ensures no test accidentally hits the Anthropic API if a developer has
// ANTHROPIC_API_KEY set in their environment. `evaluateAnomaly()` in
// src/ai/anomaly.ts early-returns when this var is missing, so the poll
// loop tests that fire-and-forget anomaly checks stay fully offline.
delete process.env.ANTHROPIC_API_KEY;
