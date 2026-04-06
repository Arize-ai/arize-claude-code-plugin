#!/bin/bash
# Common utilities for Arize Claude Code tracing hooks

set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="${HOME}/.arize-claude-code"

# Derive Claude Code's PID (grandparent) for per-session state isolation
_CLAUDE_PID=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ') || true
STATE_FILE="${STATE_DIR}/state_${_CLAUDE_PID:-$$}.json"

ARIZE_API_KEY="${ARIZE_API_KEY:-}"
ARIZE_SPACE_ID="${ARIZE_SPACE_ID:-}"
PHOENIX_ENDPOINT="${PHOENIX_ENDPOINT:-}"
PHOENIX_API_KEY="${PHOENIX_API_KEY:-}"
ARIZE_PROJECT_NAME="${ARIZE_PROJECT_NAME:-}"
ARIZE_USER_ID="${ARIZE_USER_ID:-}"
ARIZE_TRACE_ENABLED="${ARIZE_TRACE_ENABLED:-true}"
ARIZE_DRY_RUN="${ARIZE_DRY_RUN:-false}"
ARIZE_VERBOSE="${ARIZE_VERBOSE:-false}"
ARIZE_LOG_FILE="${ARIZE_LOG_FILE:-/tmp/arize-claude-code.log}"

# --- Logging ---
_log_to_file() { [[ -n "$ARIZE_LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$ARIZE_LOG_FILE" || true; }
log() { [[ "$ARIZE_VERBOSE" == "true" ]] && { echo "[arize] $*" >&2; _log_to_file "$*"; } || true; }
log_always() { echo "[arize] $*" >&2; _log_to_file "$*"; }
error() { echo "[arize] ERROR: $*" >&2; }

# --- Utilities ---
generate_uuid() {
  uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || \
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    od -x /dev/urandom | head -1 | awk '{print $2$3"-"$4"-4"substr($5,2)"-a"substr($6,2)"-"$7$8$9}'
}

generate_trace_id() { generate_uuid | tr -d '-'; }
generate_span_id() { generate_uuid | tr -d '-' | cut -c1-16; }

get_timestamp_ms() {
  # GNU date (Linux) supports %N; macOS outputs literal "3N" so verify digits-only
  local _ts; _ts=$(date +%s%3N 2>/dev/null)
  if [[ "$_ts" =~ ^[0-9]{13,}$ ]]; then echo "$_ts"; return; fi
  # macOS/BSD: perl is ~5x lighter than python3 for this
  perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time()*1000' 2>/dev/null || \
    python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || \
    echo "$(date +%s)000"
}

get_file_birth_ms() {
  local _fb_path="$1"
  [[ -z "$_fb_path" || ! -f "$_fb_path" ]] && return 0
  if stat -f %B "$_fb_path" &>/dev/null; then
    echo $(( $(stat -f %B "$_fb_path") * 1000 ))
  elif stat -c %W "$_fb_path" &>/dev/null; then
    local _fb_val; _fb_val=$(stat -c %W "$_fb_path")
    [[ "$_fb_val" =~ ^[0-9]+$ && "$_fb_val" -gt 0 ]] && echo $(( _fb_val * 1000 ))
  fi
}

# --- State (per-session JSON file with mkdir-based locking) ---
_STATE_INITIALIZED=""

init_state() {
  [[ -n "$_STATE_INITIALIZED" ]] && return 0
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
  else
    jq empty "$STATE_FILE" 2>/dev/null || echo '{}' > "$STATE_FILE"
  fi
  _STATE_INITIALIZED=1
}

_LOCK_DIR="${STATE_DIR}/.lock_${_CLAUDE_PID:-$$}"

_lock_state() {
  local attempts=0
  while ! mkdir "$_LOCK_DIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -gt 30 ]]; then
      # Stale lock recovery after ~3s
      rm -rf "$_LOCK_DIR"
      mkdir "$_LOCK_DIR" 2>/dev/null || true
      return 0
    fi
    sleep 0.1
  done
}

_unlock_state() {
  rmdir "$_LOCK_DIR" 2>/dev/null || true
}

get_state() {
  jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || echo ""
}

set_state() {
  _lock_state
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg k "$1" --arg v "$2" '. + {($k): $v}' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  _unlock_state
}

del_state() {
  _lock_state
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg k "$1" 'del(.[$k])' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  _unlock_state
}

del_states() {
  [[ $# -eq 0 ]] && return 0
  _lock_state
  local tmp="${STATE_FILE}.tmp.$$"
  jq '[($ARGS.positional[])] as $keys | with_entries(select(.key as $k | $keys | index($k) | not))' \
    --args "$@" < "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  _unlock_state
}

get_or_set_state() {
  _lock_state
  local val
  val=$(jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || echo "")
  if [[ -z "$val" ]]; then
    val="$2"
    local tmp="${STATE_FILE}.tmp.$$"
    jq --arg k "$1" --arg v "$val" '. + {($k): $v}' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  fi
  _unlock_state
  echo "$val"
}

# Returns 1 (skip) if this event is a duplicate in a team scenario.
# Convention: returns 0 = proceed, 1 = skip. Callers: `check_team_dedup ... || exit 0`
# The teammate's first event sets a marker and proceeds. Repeat teammate events
# for the same item_id are skipped. The lead's event finds the marker and skips.
# In single-agent mode (no agent_id, no markers), always returns 0.
check_team_dedup() {
  local item_id="$1" prefix="$2" agent_id="$3"
  [[ -z "$item_id" ]] && return 0
  if [[ -n "$agent_id" ]]; then
    [[ -n "$(get_state "${prefix}_${item_id}")" ]] && return 1
    set_state "${prefix}_${item_id}" "1"; return 0
  elif [[ -n "$(get_state "${prefix}_${item_id}")" ]]; then
    del_state "${prefix}_${item_id}"; return 1
  fi
  return 0
}

# Remove per-team ephemeral keys (teammate_, active_agent_, seen_tool_, tc_seen_).
# agent_* keys are intentionally kept: SubagentStop needs agent_*_span_id /
# agent_*_start_time to emit grouping spans, and agent_*_shutdown_complete is
# the sentinel that tells SubagentStop to skip span creation when post_tool_use
# already emitted the grouping span via the shutdown_response path.
clean_team_state() {
  _lock_state
  local tmp="${STATE_FILE}.tmp.$$"
  jq 'with_entries(select(.key | test("^(teammate_|active_agent_|seen_tool_|tc_seen_)") | not))' \
    "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  _unlock_state
}

# Send Turn span with full transcript data, then clean up.
# Called by UserPromptSubmit (new prompt) and SessionEnd (session closes).
# $1 = transcript path (optional)
close_active_turn() {
  local _cat_transcript="${1:-}"
  local _cat_tid _cat_sid
  _cat_tid=$(get_state "current_trace_id"); _cat_sid=$(get_state "current_trace_span_id")
  [[ -z "$_cat_tid" || -z "$_cat_sid" ]] && return 0

  local _cat_start _cat_prompt _cat_count _cat_proj _cat_uid _cat_sess _cat_tn _cat_sline
  _cat_start=$(get_state "current_trace_start_time")
  _cat_prompt=$(get_state "current_trace_prompt")
  _cat_count=$(get_state "trace_count")
  _cat_proj=$(get_state "project_name")
  _cat_uid=$(get_state "user_id")
  _cat_sess=$(get_state "session_id")
  _cat_tn=$(get_state "turn_team_name")
  [[ -z "$_cat_tn" ]] && _cat_tn=$(get_state "team_name")
  _cat_sline=$(get_state "trace_start_line")

  local _cat_output="" _cat_model="" _cat_in=0 _cat_out=0
  local _cat_end
  _cat_end=$(get_state "deferred_turn_end_time")
  [[ -z "$_cat_end" ]] && _cat_end=$(get_timestamp_ms)
  [[ -z "$_cat_transcript" ]] && _cat_transcript=$(get_state "deferred_transcript")
  if [[ -n "$_cat_transcript" && -f "$_cat_transcript" ]]; then
    parse_transcript "$_cat_transcript" "${_cat_sline:-0}"
    _cat_output=$(printf '%s' "$_pt_all_text" | head -c "10000")
    _cat_model="$_pt_model"; _cat_in=$_pt_in_tokens; _cat_out=$_pt_out_tokens
  fi
  [[ -z "$_cat_output" ]] && _cat_output="(No response)"
  local _cat_tot=$((_cat_in + _cat_out))

  local _cat_msgs; _cat_msgs=$(jq -nc --arg o "$_cat_output" \
    '[{"message.role":"assistant","message.content":$o}]')
  local _cat_attrs; _cat_attrs=$(jq -nc \
    --arg sid "$_cat_sess" --arg num "$_cat_count" --arg proj "$_cat_proj" \
    --arg in "$_cat_prompt" --arg out "$_cat_output" --arg model "$_cat_model" \
    --argjson in_tok "$_cat_in" --argjson out_tok "$_cat_out" --argjson total "$_cat_tot" \
    --argjson msgs "$_cat_msgs" --arg tn "$_cat_tn" --arg uid "$_cat_uid" \
    '{"session.id":$sid,"trace.number":$num,"project.name":$proj,
      "openinference.span.kind":"AGENT","llm.model_name":$model,
      "llm.token_count.prompt":$in_tok,"llm.token_count.completion":$out_tok,
      "llm.token_count.total":$total,"input.value":$in,"output.value":$out,
      "llm.output_messages":$msgs}
     + (if $tn != "" then {"team.name":$tn} else {} end)
     + (if $uid != "" then {"user.id":$uid} else {} end)')

  send_span "$(build_span "Turn $_cat_count" "AGENT" "$_cat_sid" "$_cat_tid" "" \
    "$_cat_start" "$_cat_end" "$_cat_attrs")" || true
  set_state "last_trace_id" "$_cat_tid"
  set_state "last_trace_span_id" "$_cat_sid"
  del_states current_trace_id current_trace_span_id current_trace_start_time \
    current_trace_prompt turn_team_name \
    deferred_transcript deferred_turn_end_time
  log "Turn $_cat_count closed"
}

inc_state() {
  _lock_state
  local val
  val=$(jq -r --arg k "$1" '.[$k] // "0"' "$STATE_FILE" 2>/dev/null)
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg k "$1" --arg v "$((${val:-0} + 1))" '. + {($k): $v}' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
  _unlock_state
}

# --- Target Detection ---
get_target() {
  if [[ -n "$PHOENIX_ENDPOINT" ]]; then echo "phoenix"
  elif [[ -n "$ARIZE_API_KEY" && -n "$ARIZE_SPACE_ID" ]]; then echo "arize"
  else echo "none"
  fi
}

# --- Send to Phoenix (REST API) ---
send_to_phoenix() {
  local span_json="$1"
  local project="${ARIZE_PROJECT_NAME:-claude-code}"

  local payload
  payload=$(echo "$span_json" | jq '{
    data: [.resourceSpans[].scopeSpans[].spans[] | {
      name: .name,
      context: { trace_id: .traceId, span_id: .spanId },
      parent_id: .parentSpanId,
      span_kind: ((.attributes[] | select(.key == "openinference.span.kind") | .value.stringValue) // "CHAIN"),
      start_time: ((.startTimeUnixNano | tonumber) / 1e9 | strftime("%Y-%m-%dT%H:%M:%SZ")),
      end_time: ((.endTimeUnixNano | tonumber) / 1e9 | strftime("%Y-%m-%dT%H:%M:%SZ")),
      status_code: "OK",
      attributes: (reduce .attributes[] as $a ({}; . + {($a.key): ($a.value.stringValue // $a.value.intValue // $a.value.doubleValue // "")}))
    }]
  }')

  # Build curl command with optional Authorization header
  local curl_cmd=(curl -sf -X POST "${PHOENIX_ENDPOINT}/v1/projects/${project}/spans" -H "Content-Type: application/json")
  [[ -n "$PHOENIX_API_KEY" ]] && curl_cmd+=(-H "Authorization: Bearer ${PHOENIX_API_KEY}")
  curl_cmd+=(-d "$payload")

  "${curl_cmd[@]}" >/dev/null
}

# --- Send to Arize AX (requires Python) ---
send_to_arize() {
  local span_json="$1"
  local script="${PLUGIN_DIR}/scripts/send_span.py"

  # Find python with opentelemetry (cached per session to avoid slow conda/pipx lookups)
  local py=""
  local cached_py
  cached_py=$(get_state "python_path")
  if [[ -n "$cached_py" ]] && "$cached_py" -c "import opentelemetry" 2>/dev/null; then
    py="$cached_py"
  else
    # Build candidate list: common paths + conda + pipx venvs
    local candidates=(python3 /usr/bin/python3 /usr/local/bin/python3 "$HOME/.local/bin/python3")
    local conda_base
    conda_base=$(conda info --base 2>/dev/null) && [[ -n "$conda_base" ]] && candidates+=("${conda_base}/bin/python3")
    local pipx_dir="${HOME}/.local/pipx/venvs"
    [[ -d "$pipx_dir" ]] || pipx_dir="${HOME}/.local/share/pipx/venvs"
    if [[ -d "$pipx_dir" ]]; then
      for venv in "$pipx_dir"/*/bin/python3; do
        [[ -x "$venv" ]] && candidates+=("$venv")
      done
    fi
    for p in "${candidates[@]}"; do
      "$p" -c "import opentelemetry" 2>/dev/null && { py="$p"; break; }
    done
    [[ -n "$py" ]] && set_state "python_path" "$py"
  fi

  [[ -z "$py" ]] && { error "Python with opentelemetry not found. Run: pip install opentelemetry-proto grpcio"; return 1; }
  [[ ! -f "$script" ]] && { error "send_span.py not found"; return 1; }

  local stderr_tmp
  stderr_tmp=$(mktemp)
  if echo "$span_json" | "$py" "$script" 2>"$stderr_tmp"; then
    _log_to_file "DEBUG send_to_arize succeeded"
    rm -f "$stderr_tmp"
  else
    _log_to_file "DEBUG send_to_arize FAILED (exit=$?)"
    [[ -s "$stderr_tmp" ]] && { _log_to_file "DEBUG stderr:"; cat "$stderr_tmp" >> "$ARIZE_LOG_FILE"; }
    rm -f "$stderr_tmp"
    return 1
  fi
}

# --- Main send function ---
send_span() {
  local span_json="$1"
  local span_name="${2:-}"
  local target
  target=$(get_target)

  if [[ "$ARIZE_DRY_RUN" == "true" ]]; then
    log_always "DRY RUN:"
    echo "$span_json" | jq -c '.resourceSpans[].scopeSpans[].spans[].name' >&2
    return 0
  fi

  [[ "$ARIZE_VERBOSE" == "true" ]] && echo "$span_json" | jq -c . >&2

  case "$target" in
    phoenix) send_to_phoenix "$span_json" ;;
    arize) send_to_arize "$span_json" ;;
    *) error "No target. Set PHOENIX_ENDPOINT or ARIZE_API_KEY + ARIZE_SPACE_ID"; return 1 ;;
  esac

  [[ -z "$span_name" ]] && span_name=$(echo "$span_json" | jq -r '.resourceSpans[0].scopeSpans[0].spans[0].name // "unknown"' 2>/dev/null)
  log "Sent span: $span_name ($target)"
}

# --- Build OTLP span ---
build_span() {
  # $_kind is intentionally unused in the OTLP output below. OTLP SpanKind (SERVER/CLIENT/etc.)
  # is for RPC roles; OpenInference types (LLM/TOOL/CHAIN) are carried via the
  # openinference.span.kind attribute instead. kind=1 (INTERNAL) is correct for all spans.
  local name="$1" _kind="$2" span_id="$3" trace_id="$4"
  local parent="${5:-}" start="$6"
  local end="${7:-$start}" attrs
  attrs="${8:-"{}"}"

  local name_json
  name_json="\"$(printf '%s' "$name" | sed 's/\\/\\\\/g;s/"/\\"/g;s/	/\\t/g')\""

  local parent_json=""
  [[ -n "$parent" ]] && parent_json="\"parentSpanId\": \"$parent\","

  cat <<EOF
{"resourceSpans":[{"resource":{"attributes":[
  {"key":"service.name","value":{"stringValue":"claude-code"}}
]},"scopeSpans":[{"scope":{"name":"arize-claude-plugin"},"spans":[{
  "traceId":"$trace_id","spanId":"$span_id",$parent_json
  "name":$name_json,"kind":1,
  "startTimeUnixNano":"${start}000000","endTimeUnixNano":"${end}000000",
  "attributes":$(echo "$attrs" | jq -c '[to_entries[]|{"key":.key,"value":(if (.value|type)=="number" then (if ((.value|floor) == .value) then {"intValue":.value} else {"doubleValue":.value} end) else {"stringValue":(.value|tostring)} end)}]'),
  "status":{"code":1}
}]}]}]}
EOF
}

# --- Session Resolution (for Agent SDK compatibility) ---

# Resolve session state file using session_id from hook input JSON.
# Call after reading stdin in each hook. Falls back to PID-based key if no session_id.
resolve_session() {
  local input="${1:-'{}'}"
  local sid="${2:-}"
  [[ -z "$sid" ]] && sid=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")

  if [[ -n "$sid" ]]; then
    _SESSION_KEY="$sid"
  elif [[ -n "${CLAUDE_SESSION_KEY:-}" ]]; then
    _SESSION_KEY="$CLAUDE_SESSION_KEY"
  else
    # Fall back to current PID-based derivation (already set at source time)
    return 0
  fi

  STATE_FILE="${STATE_DIR}/state_${_SESSION_KEY}.json"
  _LOCK_DIR="${STATE_DIR}/.lock_${_SESSION_KEY}"
  _STATE_INITIALIZED=""  # new state file needs validation
  init_state
}

# Idempotent session initialization. If session_id is already in state, returns immediately.
# Used by SessionStart directly and as lazy init fallback in UserPromptSubmit
# (for environments like the Python Agent SDK where SessionStart doesn't fire).
ensure_session_initialized() {
  local input="${1:-'{}'}"

  # Skip if session already initialized
  local existing_sid
  existing_sid=$(get_state "session_id")
  if [[ -n "$existing_sid" ]]; then
    return 0
  fi

  local session_id
  session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  [[ -z "$session_id" ]] && session_id=$(generate_uuid)

  local project_name="${ARIZE_PROJECT_NAME:-}"
  if [[ -z "$project_name" ]]; then
    local cwd
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
    project_name=$(basename "${cwd:-$(pwd)}")
  fi

  set_state "session_id" "$session_id"
  set_state "session_start_time" "$(get_timestamp_ms)"
  set_state "project_name" "$project_name"
  set_state "trace_count" "0"
  set_state "tool_count" "0"

  # Store user ID if provided via env var or hook input
  local user_id="${ARIZE_USER_ID:-}"
  if [[ -z "$user_id" ]]; then
    user_id=$(echo "$input" | jq -r '.user_id // empty' 2>/dev/null || echo "")
  fi
  [[ -n "$user_id" ]] && set_state "user_id" "$user_id"

  log "Session initialized: $session_id"
}

# Garbage-collect orphaned state files for PIDs no longer running.
# Only cleans numeric (PID-based) keys; session_id-based files are cleaned by SessionEnd.
gc_stale_state_files() {
  for f in "${STATE_DIR}"/state_*.json; do
    [[ -f "$f" ]] || continue
    local file_key
    file_key=$(basename "$f" | sed 's/state_//;s/\.json//')
    # Only GC numeric (PID-based) keys; skip non-numeric session keys
    if [[ "$file_key" =~ ^[0-9]+$ ]] && ! kill -0 "$file_key" 2>/dev/null; then
      rm -f "$f"
      rm -rf "${STATE_DIR}/.lock_${file_key}"
    fi
  done
}

# --- Transcript Parsing ---
# Sets caller-scope variables: _pt_model, _pt_in_tokens, _pt_out_tokens, _pt_all_text
parse_transcript() {
  local _pt_file="$1" _pt_skip="${2:-0}"
  _pt_model="" _pt_in_tokens=0 _pt_out_tokens=0 _pt_all_text=""

  [[ ! -f "$_pt_file" ]] && return 0

  # Token dedup: streaming chunks share a requestId. Only the final entry per
  # requestId carries cumulative counts, so the reduce commits on rid change.
  # Branches: no requestId -> sum directly; new requestId -> finalize prev group; same -> replace (last is cumulative)
  local _pt_raw
  _pt_raw=$(tail -n +"$((_pt_skip + 1))" "$_pt_file" | jq -rsc '
    [.[] | select(.type == "assistant")] |
    {
      model: (map(.message.model // empty) | map(select(. != "")) | last // ""),
      text: [.[] | .message.content |
             if type == "array" then [.[] | select(.type == "text") | .text] | join("\n")
             else (. // "")
             end | select(. != "" and . != "null")
            ] | join("\n") | gsub("^\\n+|\\n+$"; ""),
      in_tokens: (reduce .[] as $e (
        {last_rid: null, sum: 0, current: 0};
        if ($e.requestId == null or $e.requestId == "")
        then {last_rid: null, sum: (.sum + .current + (($e.message.usage.input_tokens // 0) + ($e.message.usage.cache_read_input_tokens // 0) + ($e.message.usage.cache_creation_input_tokens // 0))), current: 0}
        elif ($e.requestId != .last_rid)
        then {last_rid: $e.requestId, sum: (.sum + .current), current: (($e.message.usage.input_tokens // 0) + ($e.message.usage.cache_read_input_tokens // 0) + ($e.message.usage.cache_creation_input_tokens // 0))}
        else {last_rid: .last_rid, sum: .sum, current: (($e.message.usage.input_tokens // 0) + ($e.message.usage.cache_read_input_tokens // 0) + ($e.message.usage.cache_creation_input_tokens // 0))}
        end) | (.sum + .current)),
      out_tokens: (reduce .[] as $e (
        {last_rid: null, sum: 0, current: 0};
        if ($e.requestId == null or $e.requestId == "")
        then {last_rid: null, sum: (.sum + .current + ($e.message.usage.output_tokens // 0)), current: 0}
        elif ($e.requestId != .last_rid)
        then {last_rid: $e.requestId, sum: (.sum + .current), current: ($e.message.usage.output_tokens // 0)}
        else {last_rid: .last_rid, sum: .sum, current: ($e.message.usage.output_tokens // 0)}
        end) | (.sum + .current))
    } | (([.model // "", (.in_tokens // 0 | tostring), (.out_tokens // 0 | tostring)] | join("\u001f")), (.text // ""))
  ' 2>/dev/null) || return 0

  # Metadata on first line (unit-separator-delimited), text on remaining lines
  { IFS=$'\x1f' read -r _pt_model _pt_in_tokens _pt_out_tokens; _pt_all_text=$(cat); } <<< "$_pt_raw"
}

# --- Trace Context Resolution ---
# Resolve current trace ID, falling back to last completed turn's trace
resolve_trace_id() {
  local tid
  tid=$(get_state "current_trace_id")
  [[ -z "$tid" ]] && tid=$(get_state "last_trace_id")
  echo "$tid"
}

# Resolve parent span ID with agent grouping override
# Args: $1 = agent_id (optional), $2 = agent_type (optional, fallback)
resolve_parent_span_id() {
  local agent_id="${1:-}"
  local agent_type="${2:-}"
  local parent_span_id
  parent_span_id=$(get_state "current_trace_span_id")
  [[ -z "$parent_span_id" ]] && parent_span_id=$(get_state "last_trace_span_id")
  # Direct lookup by agent_id
  if [[ -n "$agent_id" ]]; then
    local agent_pid
    agent_pid=$(get_state "agent_${agent_id}_span_id")
    [[ -n "$agent_pid" ]] && parent_span_id="$agent_pid"
  elif [[ -n "$agent_type" ]]; then
    # Fallback: reverse-map agent_type → agent_id → span_id
    local mapped_id
    mapped_id=$(get_state "active_agent_${agent_type}")
    if [[ -n "$mapped_id" ]]; then
      local agent_pid
      agent_pid=$(get_state "agent_${mapped_id}_span_id")
      [[ -n "$agent_pid" ]] && parent_span_id="$agent_pid"
    fi
  fi
  echo "$parent_span_id"
}

# --- Role Resolution ---
# Sets caller-scope: _role ("lead", "teammate", "subagent", or "")
# Args: $1 = agent_id, $2 = team_name
determine_role() {
  _role=""
  if [[ -n "$1" ]]; then
    _role="subagent"
    [[ -n "$2" ]] && _role="teammate"
  elif [[ -n "$2" ]]; then
    _role="lead"
  fi
  return 0
}

# --- Init ---
check_requirements() {
  [[ "$ARIZE_TRACE_ENABLED" != "true" ]] && exit 0
  command -v jq &>/dev/null || { error "jq required. See: https://jqlang.github.io/jq/download/"; exit 1; }
  init_state
}
