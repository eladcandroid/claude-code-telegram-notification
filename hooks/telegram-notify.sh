#!/bin/bash
set -e

# Configuration (replaced by install script)
INSTALL_KEY="__INSTALL_KEY__"
WORKER_URL="__WORKER_URL__"

# Debug log file
DEBUG_LOG="/tmp/telegram-notify-debug.log"

# Read JSON input from stdin
INPUT=$(cat)

# Debug: log input
echo "=== $(date) ===" >> "$DEBUG_LOG"
echo "INPUT: $INPUT" >> "$DEBUG_LOG"

# Parse fields using jq
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Skip if already in a stop hook cycle (prevents infinite loops)
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

# Extract project name from working directory
PROJECT_NAME=$(basename "$CWD")

# Debug: log transcript path
echo "TRANSCRIPT_PATH: $TRANSCRIPT_PATH" >> "$DEBUG_LOG"

# Calculate session duration from transcript if available
DURATION_MS=""
SESSION_TITLE=""
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  echo "TRANSCRIPT EXISTS: yes" >> "$DEBUG_LOG"
  echo "TRANSCRIPT LINE COUNT: $(wc -l < "$TRANSCRIPT_PATH")" >> "$DEBUG_LOG"
  echo "LAST 3 LINES:" >> "$DEBUG_LOG"
  tail -3 "$TRANSCRIPT_PATH" >> "$DEBUG_LOG" 2>&1 || true
  # Get first and last timestamps from transcript
  FIRST_TS=$(head -1 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null || true)
  LAST_TS=$(tail -1 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null || true)

  if [[ -n "$FIRST_TS" && -n "$LAST_TS" ]]; then
    # Convert ISO timestamps to epoch milliseconds and calculate duration
    FIRST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${FIRST_TS%%.*}" "+%s" 2>/dev/null || date -d "${FIRST_TS}" "+%s" 2>/dev/null || true)
    LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_TS%%.*}" "+%s" 2>/dev/null || date -d "${LAST_TS}" "+%s" 2>/dev/null || true)

    if [[ -n "$FIRST_EPOCH" && -n "$LAST_EPOCH" ]]; then
      DURATION_SEC=$((LAST_EPOCH - FIRST_EPOCH))
      DURATION_MS=$((DURATION_SEC * 1000))
    fi
  fi

  # Try to get session title from last user message (what Claude just responded to)
  # Content can be a string or array of content blocks like [{"type":"text","text":"..."}]

  # Debug: show all user messages found
  echo "ALL USER MESSAGES:" >> "$DEBUG_LOG"
  jq -sr '[.[] | select(.type == "user")] | .[] | .message.content' "$TRANSCRIPT_PATH" >> "$DEBUG_LOG" 2>&1 || true

  SESSION_TITLE=$(jq -sr '[.[] | select(.type == "user")] | last | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end // empty' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 | cut -c1-100 || true)

  echo "EXTRACTED SESSION_TITLE: $SESSION_TITLE" >> "$DEBUG_LOG"
else
  echo "TRANSCRIPT EXISTS: no" >> "$DEBUG_LOG"
fi

# Build JSON payload
PAYLOAD=$(jq -n \
  --arg key "$INSTALL_KEY" \
  --arg project "$PROJECT_NAME" \
  --arg sessionTitle "$SESSION_TITLE" \
  --argjson durationMs "${DURATION_MS:-null}" \
  '{key: $key, project: $project} + (if $sessionTitle != "" then {sessionTitle: $sessionTitle} else {} end) + (if $durationMs != null then {durationMs: $durationMs} else {} end)')

# Debug: log final payload
echo "FINAL PAYLOAD: $PAYLOAD" >> "$DEBUG_LOG"
echo "---" >> "$DEBUG_LOG"

# Send notification (fire and forget, don't block session exit)
curl -sS -X POST "$WORKER_URL/notify" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 5 \
  > /dev/null 2>&1 &

exit 0
