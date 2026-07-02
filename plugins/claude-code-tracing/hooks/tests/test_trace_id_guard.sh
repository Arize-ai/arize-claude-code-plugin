#!/bin/bash
# Regression test: span-emitting hooks must NOT emit a span when there is no
# active trace (empty current_trace_id). Sending a span with an empty traceId
# makes Arize reject it ("span trace ID cannot be empty") and drops the span.
#
# Dependency-free (no bats). Run: bash tests/test_trace_id_guard.sh
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# Hooks that build+send a span and therefore need the empty-trace guard.
SPAN_HOOKS=(post_tool_use notification permission_request subagent_stop stop)

# Run a hook in an isolated HOME with seeded session state, in dry-run mode.
# Echoes "SENT" if a span was emitted, "NONE" otherwise.
run_hook() {
  local hook="$1" seed_trace="$2"
  local home; home="$(mktemp -d)"
  mkdir -p "$home/.arize-claude-code"
  local sf="$home/.arize-claude-code/state_sess-1.json"
  if [[ "$seed_trace" == "yes" ]]; then
    printf '%s' '{"session_id":"sess-1","current_trace_id":"abc123def4567890abc123def4567890","current_trace_span_id":"1111222233334444","current_trace_start_time":"1000","trace_count":"1"}' > "$sf"
  else
    printf '%s' '{"session_id":"sess-1"}' > "$sf"
  fi
  local input='{"session_id":"sess-1","tool_name":"Bash","tool_use_id":"tu_1","tool_input":{"command":"ls"}}'
  local out
  out=$(HOME="$home" ARIZE_TRACE_ENABLED=true ARIZE_DRY_RUN=true \
        bash "$HOOKS_DIR/$hook.sh" <<<"$input" 2>&1)
  rm -rf "$home"
  if grep -q "DRY RUN:" <<<"$out"; then echo "SENT"; else echo "NONE"; fi
}

check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   - $desc"; PASS=$((PASS+1))
  else
    echo "FAIL - $desc (got '$got', want '$want')"; FAIL=$((FAIL+1))
  fi
}

echo "# empty-trace guard: no span emitted without an active trace"
for h in "${SPAN_HOOKS[@]}"; do
  [[ -f "$HOOKS_DIR/$h.sh" ]] || { echo "FAIL - $h.sh missing"; FAIL=$((FAIL+1)); continue; }
  check "$h: no active trace -> no span" "$(run_hook "$h" no)" "NONE"
done

echo "# post_tool_use still emits a span when a trace IS active (no regression)"
check "post_tool_use: active trace -> span sent" "$(run_hook post_tool_use yes)" "SENT"

echo
echo "# $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
