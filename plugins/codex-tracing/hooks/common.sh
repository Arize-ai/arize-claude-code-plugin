#!/bin/bash
# Common utilities for Arize Codex tracing hooks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="${HOME}/.arize-codex"
STATE_FILE=""

ARIZE_API_KEY="${ARIZE_API_KEY:-}"
ARIZE_SPACE_ID="${ARIZE_SPACE_ID:-}"
ARIZE_OTLP_ENDPOINT="${ARIZE_OTLP_ENDPOINT:-}"
PHOENIX_ENDPOINT="${PHOENIX_ENDPOINT:-}"
PHOENIX_API_KEY="${PHOENIX_API_KEY:-}"
ARIZE_PROJECT_NAME="${ARIZE_PROJECT_NAME:-}"
ARIZE_TRACE_ENABLED="${ARIZE_TRACE_ENABLED:-true}"
ARIZE_DRY_RUN="${ARIZE_DRY_RUN:-false}"
ARIZE_VERBOSE="${ARIZE_VERBOSE:-false}"
ARIZE_TRACE_DEBUG="${ARIZE_TRACE_DEBUG:-false}"
ARIZE_LOG_FILE="${ARIZE_LOG_FILE:-/tmp/arize-codex.log}"

_log_to_file() { [[ -n "$ARIZE_LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$ARIZE_LOG_FILE" || true; }
log() { [[ "$ARIZE_VERBOSE" == "true" ]] && { echo "[arize] $*" >&2; _log_to_file "$*"; } || true; }
error() { echo "[arize] ERROR: $*" >&2; _log_to_file "ERROR: $*"; }

debug_dump() {
  [[ "$ARIZE_TRACE_DEBUG" == "true" ]] || return 0
  local label="$1" data="$2"
  local safe_label
  safe_label=$(echo "$label" | tr -c '[:alnum:]_.-' '_')
  local ts
  ts=$(date +%s%3N 2>/dev/null || date +%s000)
  local dir="${STATE_DIR}/debug"
  mkdir -p "$dir"
  local file="${dir}/${safe_label}_${ts}.log"
  printf '%s\n' "$data" > "$file"
  _log_to_file "DEBUG wrote $safe_label to $file"
}

generate_uuid() {
  uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || \
    python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
    cat /proc/sys/kernel/random/uuid 2>/dev/null
}

get_timestamp_ms() {
  python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || \
    date +%s%3N 2>/dev/null || date +%s000
}

check_requirements() {
  [[ "$ARIZE_TRACE_ENABLED" == "true" ]] || exit 0
  command -v jq >/dev/null 2>&1 || { error "jq is required"; exit 1; }
  mkdir -p "$STATE_DIR"
}

resolve_session() {
  local thread_id="${1:-}"
  local key="${thread_id:-default}"
  key=$(echo "$key" | tr -c '[:alnum:]_.-' '_')
  STATE_FILE="${STATE_DIR}/state_${key}.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
  else
    jq empty "$STATE_FILE" >/dev/null 2>&1 || echo '{}' > "$STATE_FILE"
  fi
}

get_state() {
  jq -r ".[\"$1\"] // empty" "$STATE_FILE" 2>/dev/null || echo ""
}

set_state() {
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg k "$1" --arg v "$2" '. + {($k): $v}' "$STATE_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"
}

inc_state() {
  local current
  current=$(jq -r ".[\"$1\"] // 0" "$STATE_FILE" 2>/dev/null || echo "0")
  local next=$((current + 1))
  set_state "$1" "$next"
}

ensure_session_initialized() {
  local thread_id="$1" cwd="$2"
  [[ -n "$(get_state "session_id")" ]] || set_state "session_id" "${thread_id:-$(generate_uuid)}"
  [[ -n "$(get_state "project_name")" ]] || set_state "project_name" "${ARIZE_PROJECT_NAME:-$(basename "$cwd")}"
  [[ -n "$(get_state "cwd")" ]] || set_state "cwd" "$cwd"
  [[ -n "$(get_state "trace_count")" ]] || set_state "trace_count" "0"
}

gc_stale_state_files() {
  find "$STATE_DIR" -name 'state_*.json' -type f -mtime +7 -delete 2>/dev/null || true
}

get_target() {
  if [[ -n "$PHOENIX_ENDPOINT" ]]; then echo "phoenix"
  elif [[ -n "$ARIZE_API_KEY" && -n "$ARIZE_SPACE_ID" ]]; then echo "arize"
  else echo "none"
  fi
}

send_to_phoenix() {
  local span_json="$1"
  local project="${ARIZE_PROJECT_NAME:-codex}"
  local payload
  payload=$(echo "$span_json" | jq '{
    data: [.resourceSpans[].scopeSpans[].spans[] | {
      name: .name,
      context: { trace_id: .traceId, span_id: .spanId },
      parent_id: .parentSpanId,
      span_kind: "CHAIN",
      start_time: ((.startTimeUnixNano | tonumber) / 1e9 | strftime("%Y-%m-%dT%H:%M:%SZ")),
      end_time: ((.endTimeUnixNano | tonumber) / 1e9 | strftime("%Y-%m-%dT%H:%M:%SZ")),
      status_code: "OK",
      attributes: (reduce .attributes[] as $a ({}; . + {($a.key): ($a.value.stringValue // $a.value.doubleValue // $a.value.intValue // $a.value.boolValue // "")}))
    }]
  }')
  local curl_cmd=(curl -sf -X POST "${PHOENIX_ENDPOINT}/v1/projects/${project}/spans" -H "Content-Type: application/json")
  [[ -n "$PHOENIX_API_KEY" ]] && curl_cmd+=(-H "Authorization: Bearer ${PHOENIX_API_KEY}")
  curl_cmd+=(-d "$payload")
  "${curl_cmd[@]}" >/dev/null
}

send_to_arize() {
  local span_json="$1"
  local script="${PLUGIN_DIR}/scripts/send_span.py"
  local py=""
  for p in python3 /usr/bin/python3 /usr/local/bin/python3; do
    "$p" -c "import opentelemetry" >/dev/null 2>&1 && { py="$p"; break; }
  done
  [[ -n "$py" ]] || { error "Python with opentelemetry not found. Run: pip install opentelemetry-proto grpcio"; return 1; }
  echo "$span_json" | "$py" "$script"
}

send_span() {
  local span_json="$1"
  if [[ "$ARIZE_DRY_RUN" == "true" ]]; then
    log "DRY RUN"
    echo "$span_json" | jq -c . >&2
    return 0
  fi
  case "$(get_target)" in
    phoenix) send_to_phoenix "$span_json" ;;
    arize) send_to_arize "$span_json" ;;
    *) error "No target. Set PHOENIX_ENDPOINT or ARIZE_API_KEY + ARIZE_SPACE_ID"; return 1 ;;
  esac
}

build_span() {
  local name="$1" kind="$2" span_id="$3" trace_id="$4"
  local parent="${5:-}" start="$6" end="${7:-$start}" attrs
  attrs="${8:-"{}"}"

  local parent_json=""
  [[ -n "$parent" ]] && parent_json="\"parentSpanId\": \"$parent\","

  local kind_value="1"
  local kind_upper
  kind_upper=$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')
  case "$kind_upper" in
    ""|"LLM"|"CHAIN"|"TOOL"|"INTERNAL"|"SPAN_KIND_INTERNAL") kind_value="1" ;;
    "SERVER"|"SPAN_KIND_SERVER") kind_value="2" ;;
    "CLIENT"|"SPAN_KIND_CLIENT") kind_value="3" ;;
    "PRODUCER"|"SPAN_KIND_PRODUCER") kind_value="4" ;;
    "CONSUMER"|"SPAN_KIND_CONSUMER") kind_value="5" ;;
    "UNSPECIFIED"|"SPAN_KIND_UNSPECIFIED") kind_value="0" ;;
    *)
      [[ "$kind" =~ ^[0-9]+$ ]] && kind_value="$kind"
      ;;
  esac

  cat <<EOF
{"resourceSpans":[{"resource":{"attributes":[
  {"key":"service.name","value":{"stringValue":"codex"}}
]},"scopeSpans":[{"scope":{"name":"arize-codex-plugin"},"spans":[{
  "traceId":"$trace_id","spanId":"$span_id",$parent_json
  "name":"$name","kind":$kind_value,
  "startTimeUnixNano":"${start}000000","endTimeUnixNano":"${end}000000",
  "attributes":$(echo "$attrs" | jq -c '[to_entries[]|{"key":.key,"value":(if (.value|type)=="number" then (if ((.value|floor) == .value) then {"intValue":.value} else {"doubleValue":.value} end) elif (.value|type)=="boolean" then {"boolValue":.value} else {"stringValue":(.value|tostring)} end)}]'),
  "status":{"code":1}
}]}]}]}
EOF
}
