#!/bin/bash
set -e

# Configuration (replaced by install script)
INSTALL_KEY="__INSTALL_KEY__"
WORKER_URL="__WORKER_URL__"

# Read JSON input from stdin
INPUT=$(cat)

# Parse fields using jq
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')
NOTIFICATION_MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')

# Extract project name from working directory
PROJECT_NAME=$(basename "$CWD")

# Only handle permission_prompt (Stop hook handles idle notification)
if [[ "$NOTIFICATION_TYPE" != "permission_prompt" ]]; then
  exit 0
fi

EMOJI="🔐"
TITLE="Permission needed"

# Build the message
MESSAGE="${EMOJI} *${TITLE}*
📁 \`${PROJECT_NAME}\`"

if [[ -n "$NOTIFICATION_MESSAGE" ]]; then
  MESSAGE="${MESSAGE}
💬 ${NOTIFICATION_MESSAGE}"
fi

# Build JSON payload
PAYLOAD=$(jq -n \
  --arg key "$INSTALL_KEY" \
  --arg project "$PROJECT_NAME" \
  --arg message "$MESSAGE" \
  '{key: $key, project: $project, message: $message}')

# Send notification (fire and forget, don't block)
curl -sS -X POST "$WORKER_URL/notify" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 5 \
  > /dev/null 2>&1 &

exit 0
