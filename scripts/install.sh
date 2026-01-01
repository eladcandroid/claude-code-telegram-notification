#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration (can be overridden via environment variables)
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/eladcandroid/claude-code-telegram-notification/main}"
WORKER_URL="${WORKER_URL:-https://claude-code-telegram-bot.eladc-android.workers.dev}"
HOOK_URL="${HOOK_URL:-$REPO_RAW_URL/hooks/telegram-notify.sh}"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

main() {
    local install_key="$1"

    # Validate input
    if [ -z "$install_key" ]; then
        echo -e "${RED}Error: Install key is required${NC}"
        echo "Usage: curl -fsSL <url> | bash -s -- <INSTALL_KEY>"
        echo ""
        echo "Get your install key by messaging /start to the Telegram bot."
        exit 1
    fi

    # Check for required dependencies
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo ""
        echo "Install jq:"
        echo "  macOS: brew install jq"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  Other: https://stedolan.github.io/jq/download/"
        exit 1
    fi

    echo -e "${YELLOW}Installing Claude Code Telegram Notification Hook...${NC}"

    # Create hooks directory
    mkdir -p "$HOOKS_DIR"

    # Download and configure hook script
    echo "Downloading hook script..."
    curl -fsSL "$HOOK_URL" \
        | sed "s|__INSTALL_KEY__|$install_key|g; s|__WORKER_URL__|$WORKER_URL|g" \
        > "$HOOKS_DIR/telegram-notify.sh"

    chmod +x "$HOOKS_DIR/telegram-notify.sh"

    # Update settings.json with hook configuration
    echo "Configuring Claude Code settings..."
    configure_settings

    # Verify installation
    if [ -f "$HOOKS_DIR/telegram-notify.sh" ]; then
        echo -e "${GREEN}Hook installed successfully!${NC}"
        echo -e "   Location: $HOOKS_DIR/telegram-notify.sh"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "   1. Restart Claude Code if it's running"
        echo "   2. You'll receive Telegram notifications when sessions end"
        echo ""
        echo -e "${YELLOW}To uninstall:${NC}"
        echo "   rm $HOOKS_DIR/telegram-notify.sh"
        echo "   # Then remove the SessionEnd hook from $SETTINGS_FILE"

        # Send installation notification
        curl -sS -X POST "$WORKER_URL/notify" \
            -H "Content-Type: application/json" \
            -d "{\"key\": \"$install_key\", \"message\": \"Claude Code Telegram Notification Hook installed successfully!\"}" \
            > /dev/null 2>&1 || true
    else
        echo -e "${RED}Installation failed${NC}"
        exit 1
    fi
}

configure_settings() {
    local hook_command="$HOOKS_DIR/telegram-notify.sh"

    # Create settings file if it doesn't exist
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Check if SessionEnd hook already exists
    local existing_hooks
    existing_hooks=$(jq -r '.hooks.SessionEnd // empty' "$SETTINGS_FILE" 2>/dev/null || echo "")

    if [ -n "$existing_hooks" ]; then
        # Check if our hook is already configured
        local hook_exists
        hook_exists=$(echo "$existing_hooks" | jq -r --arg cmd "$hook_command" \
            'if type == "array" then [.[].hooks[]? | select(.command == $cmd)] | length else 0 end' 2>/dev/null || echo "0")

        if [ "$hook_exists" != "0" ]; then
            echo "Hook already configured in settings.json"
            return
        fi

        # Add our hook to existing SessionEnd hooks
        local new_hook='{"hooks": [{"type": "command", "command": "'"$hook_command"'", "timeout": 10}]}'
        jq --argjson hook "$new_hook" '.hooks.SessionEnd += [$hook]' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
        # Create new SessionEnd hook configuration
        jq --arg cmd "$hook_command" \
            '.hooks.SessionEnd = [{"hooks": [{"type": "command", "command": $cmd, "timeout": 10}]}]' \
            "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    fi

    echo "Updated $SETTINGS_FILE with SessionEnd hook"
}

main "$@"
