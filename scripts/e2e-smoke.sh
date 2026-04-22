#!/usr/bin/env bash
# BentoDeck end-to-end smoke test.
#
# Fresh SQLite -> seed demo dashboard -> start server -> assert snapshot ->
# spike errors -> assert spike propagated -> reset -> tear down.
#
# Exit 0 on all-pass, non-zero on any failure. Always prints log file path.
# Run before the hackathon demo to confirm the backend pipeline works.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"
PORT=3737
BASE_URL="http://localhost:$PORT"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/bentodeck-e2e-$TS.log"
SEED_LOG="/tmp/bentodeck-e2e-seed-$TS.log"

SERVER_PID=""
START_EPOCH=$(date +%s)

# ---------------------------------------------------------------------------
# Output helpers (with plain-ASCII fallback when not a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_BOLD=""
  C_RESET=""
fi

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

section() {
  printf "\n%s==> %s%s\n" "$C_BOLD$C_BLUE" "$1" "$C_RESET"
}

info() {
  printf "   %s\n" "$1"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  RESULTS+=("${C_GREEN}PASS${C_RESET}  $1")
  printf "   %sPASS%s %s\n" "$C_GREEN" "$C_RESET" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  RESULTS+=("${C_RED}FAIL${C_RESET}  $1")
  printf "   %sFAIL%s %s\n" "$C_RED" "$C_RESET" "$1"
}

die() {
  fail "$1"
  exit 1
}

# ---------------------------------------------------------------------------
# Cleanup (always runs — kills backend, prints summary)
# ---------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  set +e

  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
    # Give it a moment to flush, then hard-kill if still alive.
    for _ in 1 2 3 4 5; do
      kill -0 "$SERVER_PID" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  # Belt and suspenders: kill anything still clinging to the port (e.g. the
  # `tsx watch` child process survives its parent in some shells).
  lsof -ti:"$PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true

  local runtime=$(( $(date +%s) - START_EPOCH ))
  print_summary "$exit_code" "$runtime"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

print_summary() {
  local exit_code=$1
  local runtime=$2

  printf "\n%s==================== SUMMARY ====================%s\n" "$C_BOLD" "$C_RESET"
  local r
  for r in "${RESULTS[@]:-}"; do
    [ -z "$r" ] && continue
    printf "  %s\n" "$r"
  done
  printf "%s=================================================%s\n" "$C_BOLD" "$C_RESET"
  printf "  Passed:   %s%d%s\n" "$C_GREEN" "$PASS_COUNT" "$C_RESET"
  printf "  Failed:   %s%d%s\n" "$C_RED" "$FAIL_COUNT" "$C_RESET"
  printf "  Runtime:  %ds\n" "$runtime"
  printf "  Log file: %s\n" "$LOG_FILE"
  printf "  Seed log: %s\n" "$SEED_LOG"

  if [ "$exit_code" -eq 0 ] && [ "$FAIL_COUNT" -eq 0 ]; then
    printf "\n%s%sALL GREEN. Demo pipeline is ready.%s\n\n" "$C_BOLD" "$C_GREEN" "$C_RESET"
  else
    printf "\n%s%sSMOKE TEST FAILED. See log: %s%s\n\n" "$C_BOLD" "$C_RED" "$LOG_FILE" "$C_RESET"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Free the port
# ---------------------------------------------------------------------------
section "Step 1/10: Killing any previous bentodeck process on port $PORT"
EXISTING_PIDS="$(lsof -ti:"$PORT" 2>/dev/null || true)"
if [ -n "$EXISTING_PIDS" ]; then
  info "Found existing PIDs: $EXISTING_PIDS — killing"
  echo "$EXISTING_PIDS" | xargs kill -9 2>/dev/null || true
  sleep 1
else
  info "Port $PORT is free"
fi

# ---------------------------------------------------------------------------
# Step 2: Wipe SQLite data
# ---------------------------------------------------------------------------
section "Step 2/10: Cleaning server/data/ for a fresh SQLite file"
if [ -d "$SERVER_DIR/data" ]; then
  # Remove sqlite files but leave the directory itself (server expects it).
  find "$SERVER_DIR/data" -maxdepth 1 -type f \
    \( -name "bentodeck.sqlite" -o -name "bentodeck.sqlite-wal" -o -name "bentodeck.sqlite-shm" \) \
    -print -delete | sed 's#^#   removed: #' || true
else
  mkdir -p "$SERVER_DIR/data"
fi
info "Data dir clean: $SERVER_DIR/data"

# ---------------------------------------------------------------------------
# Step 3: Seed demo dashboard (capture dashboard id)
# ---------------------------------------------------------------------------
section "Step 3/10: Seeding demo dashboard"
# seed-demo writes its log output to stderr (see server/src/logger.ts), so
# we redirect 2>&1 into the seed log file and grep out the UUID.
(
  cd "$SERVER_DIR"
  npm run --silent seed-demo
) > "$SEED_LOG" 2>&1 || {
  cat "$SEED_LOG" || true
  die "npm run seed-demo failed — see $SEED_LOG"
}

# Look for a line like: "dashboard:  <uuid>"
DASHBOARD_ID="$(grep -Eo 'dashboard:[[:space:]]+[0-9a-fA-F-]{36}' "$SEED_LOG" \
  | head -1 \
  | awk '{print $2}')"

if [ -z "${DASHBOARD_ID:-}" ]; then
  info "Seed log contents:"
  sed 's/^/     /' "$SEED_LOG"
  die "could not extract dashboard UUID from seed output"
fi
pass "Seed produced dashboard id: $DASHBOARD_ID"

# ---------------------------------------------------------------------------
# Step 4: Start the backend in the background
# ---------------------------------------------------------------------------
# NOTE: We use `npm start` (tsx, no watch) rather than `npm run dev`
# (tsx watch). The HTTP routes, poll scheduler, MCP server, and mock API
# are all identical — the only difference is `dev` enables the file
# watcher, which races with our mid-test DB writes on macOS/APFS and
# silently restarts the process, breaking idempotency. The smoke test
# explicitly wants a single clean run, so `start` is the right binary.
section "Step 4/10: Starting backend (npm start) in background"
(
  cd "$SERVER_DIR"
  # Detach stdin so the child doesn't fight this script's terminal; pipe
  # stdout+stderr into the log file for post-mortem on failure.
  npm start --silent < /dev/null > "$LOG_FILE" 2>&1 &
  echo $! > /tmp/bentodeck-e2e-pid-$TS
) || die "failed to spawn backend"

SERVER_PID="$(cat /tmp/bentodeck-e2e-pid-$TS)"
rm -f /tmp/bentodeck-e2e-pid-$TS
info "Backend PID: $SERVER_PID"
info "Log file:    $LOG_FILE"

# ---------------------------------------------------------------------------
# Step 5: Wait for /health (up to 15s)
# ---------------------------------------------------------------------------
section "Step 5/10: Waiting for /health"
HEALTH_OK=0
for i in $(seq 1 30); do
  # Check the server process is actually still alive first — otherwise we'd
  # wait the full 15s for a process that already crashed.
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    die "backend PID $SERVER_PID exited before /health responded (see $LOG_FILE)"
  fi
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/health" || true)"
  if [ "$HTTP_CODE" = "200" ]; then
    HEALTH_OK=1
    info "Health responded after ~$((i * 500)) ms"
    break
  fi
  sleep 0.5
done
if [ "$HEALTH_OK" -ne 1 ]; then
  die "/health never returned 200 (timeout 15s)"
fi
pass "/health returned 200"

# ---------------------------------------------------------------------------
# Step 6: Assert /dashboards has our one dashboard
# ---------------------------------------------------------------------------
section "Step 6/10: GET /dashboards"
DASH_JSON="$(curl -sS "$BASE_URL/dashboards")"
DASH_COUNT="$(echo "$DASH_JSON" | jq '.dashboards | length')"
FIRST_ID="$(echo "$DASH_JSON" | jq -r '.dashboards[0].id // ""')"

if [ "$DASH_COUNT" = "1" ]; then
  pass "/dashboards returned exactly 1 dashboard"
else
  info "Response: $DASH_JSON"
  die "/dashboards returned $DASH_COUNT entries, expected 1"
fi

if [ "$FIRST_ID" = "$DASHBOARD_ID" ]; then
  pass "/dashboards[0].id matches seeded id"
else
  die "/dashboards[0].id=$FIRST_ID did not match seeded $DASHBOARD_ID"
fi

# ---------------------------------------------------------------------------
# Step 7: Assert /dashboards/:id/snapshot has the 3 expected widgets
# ---------------------------------------------------------------------------
section "Step 7/10: GET /dashboards/$DASHBOARD_ID/snapshot (initial)"
SNAP_JSON="$(curl -sS "$BASE_URL/dashboards/$DASHBOARD_ID/snapshot")"

WIDGET_COUNT="$(echo "$SNAP_JSON" | jq '.widgets | length')"
if [ "$WIDGET_COUNT" = "3" ]; then
  pass "snapshot has exactly 3 widgets"
else
  info "Snapshot: $SNAP_JSON"
  die "snapshot returned $WIDGET_COUNT widgets, expected 3"
fi

assert_widget() {
  local title=$1
  local expected_value=$2
  local actual_value
  actual_value="$(echo "$SNAP_JSON" | jq -r --arg t "$title" '.widgets[] | select(.title==$t) | .value // "null"')"
  if [ -z "$actual_value" ] || [ "$actual_value" = "null" ]; then
    fail "widget \"$title\" missing or null (got: $actual_value)"
    return 1
  fi
  if [ "$actual_value" = "$expected_value" ]; then
    pass "widget \"$title\" = $actual_value"
  else
    fail "widget \"$title\" = $actual_value, expected $expected_value"
    return 1
  fi
}

assert_widget "Stripe MRR" "4284" || die "widget assertion failed"
assert_widget "Signups today" "31" || die "widget assertion failed"
assert_widget "Critical errors (15m)" "0" || die "widget assertion failed"

# ---------------------------------------------------------------------------
# Step 8: POST /demo/control/spike
# ---------------------------------------------------------------------------
section "Step 8/10: POST /demo/control/spike"
SPIKE_JSON="$(curl -sS -X POST "$BASE_URL/demo/control/spike")"
SPIKE_OK="$(echo "$SPIKE_JSON" | jq -r '.ok // false')"
if [ "$SPIKE_OK" = "true" ]; then
  pass "spike endpoint returned ok:true ($SPIKE_JSON)"
else
  info "Response: $SPIKE_JSON"
  die "spike endpoint did not return ok:true"
fi

# ---------------------------------------------------------------------------
# Step 9: Wait one full poll cycle + margin
# ---------------------------------------------------------------------------
section "Step 9/10: Sleeping 8s for the poll loop to propagate the spike"
sleep 8

# ---------------------------------------------------------------------------
# Step 10: Re-fetch snapshot, assert errors widget >= 40
# ---------------------------------------------------------------------------
section "Step 10/10: GET snapshot (post-spike)"
SNAP2_JSON="$(curl -sS "$BASE_URL/dashboards/$DASHBOARD_ID/snapshot")"
ERR_VALUE="$(echo "$SNAP2_JSON" | jq -r '.widgets[] | select(.title=="Critical errors (15m)") | .value')"
info "Critical errors post-spike value: $ERR_VALUE"
if [ -z "$ERR_VALUE" ] || [ "$ERR_VALUE" = "null" ]; then
  info "Snapshot: $SNAP2_JSON"
  die "errors widget value missing after spike"
fi
# Integer comparison — the mock sets errorsCritical to 47 (plus up to +7 jitter).
if [ "$ERR_VALUE" -ge 40 ] 2>/dev/null; then
  pass "errors propagated through poll loop (value=$ERR_VALUE, >= 40)"
else
  die "errors widget value $ERR_VALUE did not reach expected threshold (>= 40)"
fi

# ---------------------------------------------------------------------------
# Cleanup demo state: POST /demo/control/reset
# ---------------------------------------------------------------------------
section "Cleanup: POST /demo/control/reset"
RESET_JSON="$(curl -sS -X POST "$BASE_URL/demo/control/reset" || echo '{}')"
RESET_OK="$(echo "$RESET_JSON" | jq -r '.ok // false')"
if [ "$RESET_OK" = "true" ]; then
  pass "reset endpoint returned ok:true"
else
  fail "reset endpoint did not return ok:true ($RESET_JSON)"
fi

# Backend is killed by the EXIT trap. exit 0 => all assertions passed.
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
