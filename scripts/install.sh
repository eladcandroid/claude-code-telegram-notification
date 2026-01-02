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
SESSION_HOOK_URL="${SESSION_HOOK_URL:-$REPO_RAW_URL/hooks/telegram-notify.sh}"
NOTIFICATION_HOOK_URL="${NOTIFICATION_HOOK_URL:-$REPO_RAW_URL/hooks/telegram-notification.sh}"
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

    # Download and configure stop hook script
    echo "Downloading stop hook script..."
    curl -fsSL "$SESSION_HOOK_URL" \
        | sed "s|__INSTALL_KEY__|$install_key|g; s|__WORKER_URL__|$WORKER_URL|g" \
        > "$HOOKS_DIR/telegram-notify.sh"
    chmod +x "$HOOKS_DIR/telegram-notify.sh"

    # Download and configure notification hook script
    echo "Downloading notification hook script..."
    curl -fsSL "$NOTIFICATION_HOOK_URL" \
        | sed "s|__INSTALL_KEY__|$install_key|g; s|__WORKER_URL__|$WORKER_URL|g" \
        > "$HOOKS_DIR/telegram-notification.sh"
    chmod +x "$HOOKS_DIR/telegram-notification.sh"

    # Update settings.json with hook configuration
    echo "Configuring Claude Code settings..."
    configure_settings

    # Verify installation
    if [ -f "$HOOKS_DIR/telegram-notify.sh" ] && [ -f "$HOOKS_DIR/telegram-notification.sh" ]; then
        echo -e "${GREEN}Hooks installed successfully!${NC}"
        echo -e "   Stop hook: $HOOKS_DIR/telegram-notify.sh"
        echo -e "   Notification hook: $HOOKS_DIR/telegram-notification.sh"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "   1. Restart Claude Code if it's running"
        echo "   2. You'll receive Telegram notifications when:"
        echo "      - Claude finishes responding (waiting for input)"
        echo "      - Claude needs your permission"
        echo ""
        echo -e "${YELLOW}To uninstall:${NC}"
        echo "   rm $HOOKS_DIR/telegram-notify.sh $HOOKS_DIR/telegram-notification.sh"
        echo "   # Then remove the hooks from $SETTINGS_FILE"

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
    local session_hook="$HOOKS_DIR/telegram-notify.sh"
    local notification_hook="$HOOKS_DIR/telegram-notification.sh"

    # Create settings file if it doesn't exist
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Configure Stop hook (triggers when Claude finishes responding)
    configure_hook "Stop" "$session_hook" ""

    # Configure Notification hook for permission_prompt
    configure_hook "Notification" "$notification_hook" "permission_prompt"

    echo "Updated $SETTINGS_FILE with hooks"
}

configure_hook() {
    local hook_type="$1"
    local hook_command="$2"
    local matcher="$3"

    # Check if hook already exists
    local existing_hooks
    existing_hooks=$(jq -r ".hooks.${hook_type} // empty" "$SETTINGS_FILE" 2>/dev/null || echo "")

    if [ -n "$existing_hooks" ]; then
        # Check if our specific hook is already configured
        local hook_exists
        if [ -n "$matcher" ]; then
            hook_exists=$(echo "$existing_hooks" | jq -r --arg cmd "$hook_command" --arg m "$matcher" \
                'if type == "array" then [.[] | select(.matcher == $m) | .hooks[]? | select(.command == $cmd)] | length else 0 end' 2>/dev/null || echo "0")
        else
            hook_exists=$(echo "$existing_hooks" | jq -r --arg cmd "$hook_command" \
                'if type == "array" then [.[].hooks[]? | select(.command == $cmd)] | length else 0 end' 2>/dev/null || echo "0")
        fi

        if [ "$hook_exists" != "0" ]; then
            return
        fi

        # Add our hook to existing hooks
        if [ -n "$matcher" ]; then
            local new_hook='{"matcher": "'"$matcher"'", "hooks": [{"type": "command", "command": "'"$hook_command"'", "timeout": 10}]}'
        else
            local new_hook='{"hooks": [{"type": "command", "command": "'"$hook_command"'", "timeout": 10}]}'
        fi
        jq --argjson hook "$new_hook" ".hooks.${hook_type} += [\$hook]" "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
        # Create new hook configuration
        if [ -n "$matcher" ]; then
            jq --arg cmd "$hook_command" --arg m "$matcher" \
                ".hooks.${hook_type} = [{\"matcher\": \$m, \"hooks\": [{\"type\": \"command\", \"command\": \$cmd, \"timeout\": 10}]}]" \
                "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
                && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        else
            jq --arg cmd "$hook_command" \
                ".hooks.${hook_type} = [{\"hooks\": [{\"type\": \"command\", \"command\": \$cmd, \"timeout\": 10}]}]" \
                "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
                && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        fi
    fi
}

main "$@"
