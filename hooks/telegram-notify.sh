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

# Calculate session duration and extract stats from transcript if available
DURATION_MS=""
SESSION_TITLE=""
INPUT_TOKENS=""
OUTPUT_TOKENS=""
COST_ESTIMATE=""
LAST_RESPONSE=""
FILES_MODIFIED=""
COMMANDS_RUN=""

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

  # Extract token usage - sum all input_tokens and output_tokens from usage fields
  INPUT_TOKENS=$(jq -sr '[.[] | .usage.input_tokens // 0] | add // 0' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
  OUTPUT_TOKENS=$(jq -sr '[.[] | .usage.output_tokens // 0] | add // 0' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

  echo "INPUT_TOKENS: $INPUT_TOKENS, OUTPUT_TOKENS: $OUTPUT_TOKENS" >> "$DEBUG_LOG"

  # Calculate cost estimate (Sonnet pricing: $3/MTok input, $15/MTok output)
  if [[ -n "$INPUT_TOKENS" && -n "$OUTPUT_TOKENS" && "$INPUT_TOKENS" != "0" ]]; then
    # Use awk for floating point math (more portable than bc)
    COST_ESTIMATE=$(awk "BEGIN {printf \"%.4f\", ($INPUT_TOKENS * 0.000003) + ($OUTPUT_TOKENS * 0.000015)}")
    echo "COST_ESTIMATE: $COST_ESTIMATE" >> "$DEBUG_LOG"
  fi

  # Extract last assistant response (truncated to 200 chars)
  LAST_RESPONSE=$(jq -sr '[.[] | select(.type == "assistant")] | last | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end // empty' "$TRANSCRIPT_PATH" 2>/dev/null | head -1 | cut -c1-200 || true)

  echo "LAST_RESPONSE: $LAST_RESPONSE" >> "$DEBUG_LOG"

  # Count files modified (unique file paths from Write and Edit tool calls)
  FILES_MODIFIED=$(jq -sr '[.[] | select(.type == "tool_use") | select(.name == "Write" or .name == "Edit") | .input.file_path // .input.path] | unique | length' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

  echo "FILES_MODIFIED: $FILES_MODIFIED" >> "$DEBUG_LOG"

  # Count bash commands run
  COMMANDS_RUN=$(jq -sr '[.[] | select(.type == "tool_use") | select(.name == "Bash")] | length' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

  echo "COMMANDS_RUN: $COMMANDS_RUN" >> "$DEBUG_LOG"
else
  echo "TRANSCRIPT EXISTS: no" >> "$DEBUG_LOG"
fi

# Build JSON payload with all available fields
PAYLOAD=$(jq -n \
  --arg key "$INSTALL_KEY" \
  --arg project "$PROJECT_NAME" \
  --arg sessionTitle "$SESSION_TITLE" \
  --argjson durationMs "${DURATION_MS:-null}" \
  --argjson inputTokens "${INPUT_TOKENS:-null}" \
  --argjson outputTokens "${OUTPUT_TOKENS:-null}" \
  --argjson costEstimate "${COST_ESTIMATE:-null}" \
  --arg lastResponse "$LAST_RESPONSE" \
  --argjson filesModified "${FILES_MODIFIED:-null}" \
  --argjson commandsRun "${COMMANDS_RUN:-null}" \
  '{key: $key, project: $project} +
   (if $sessionTitle != "" then {sessionTitle: $sessionTitle} else {} end) +
   (if $durationMs != null then {durationMs: $durationMs} else {} end) +
   (if $inputTokens != null and $inputTokens > 0 then {inputTokens: $inputTokens} else {} end) +
   (if $outputTokens != null and $outputTokens > 0 then {outputTokens: $outputTokens} else {} end) +
   (if $costEstimate != null and $costEstimate > 0 then {costEstimate: $costEstimate} else {} end) +
   (if $lastResponse != "" then {lastResponse: $lastResponse} else {} end) +
   (if $filesModified != null and $filesModified > 0 then {filesModified: $filesModified} else {} end) +
   (if $commandsRun != null and $commandsRun > 0 then {commandsRun: $commandsRun} else {} end)')

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
