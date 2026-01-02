# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Telegram notification system for Claude Code. Users receive Telegram messages when:
- Claude finishes responding (waiting for input)
- Claude needs permission to run a tool

The project consists of two parts:

- **hooks/** - Shell script hooks that run on various Claude Code events and send notifications to the worker
- **worker/** - Cloudflare Worker that handles Telegram bot commands and delivers notifications

## Commands

```bash
# Install dependencies (from root)
pnpm install

# Development (runs worker locally with wrangler)
pnpm dev

# Linting
pnpm lint          # Check for issues
pnpm lint:fix      # Auto-fix issues

# Type checking
pnpm typecheck     # Runs worker typecheck only

# Testing
pnpm test          # Run worker tests with vitest

# Worker deployment (from worker/)
cd worker
pnpm exec wrangler deploy
```

## Architecture

### Hooks (hooks/)
- `telegram-notify.sh` - Triggered on Stop (Claude finishes responding)
  - Reads JSON input from stdin (session_id, cwd, transcript_path, stop_hook_active)
  - Skips if stop_hook_active is true (prevents infinite loops)
  - Extracts project name from working directory
  - Optionally parses transcript for session title and duration
  - Sends POST to worker `/notify` endpoint with install key

- `telegram-notification.sh` - Triggered on Notification events
  - Handles `permission_prompt` (Claude needs permission to run a tool)
  - Reads JSON input with notification_type and message
  - Sends formatted notification to Telegram

### Worker (worker/)
- Hono-based Cloudflare Worker with grammY for Telegram bot
- Routes: `/webhook` (Telegram bot), `/notify` (hook notifications)
- User data stored in Cloudflare KV (USERS namespace) keyed by install UUID
- Bot commands: /start (get install key), /revoke, /status, /help
- Uses Zod for request validation

### Install Flow
1. User sends /start to Telegram bot → bot generates UUID, stores chatId in KV
2. User runs curl install script with UUID
3. Script downloads hooks to `~/.claude/hooks/`:
   - `telegram-notify.sh` (Stop)
   - `telegram-notification.sh` (Notification)
4. Script updates `~/.claude/settings.json` with hook configs (Stop, Notification with permission_prompt matcher)
5. Placeholders in hooks are replaced with key/URL

## Key Files

- `hooks/telegram-notify.sh` - Stop hook script (placeholders replaced at install time)
- `hooks/telegram-notification.sh` - Notification hook script for permission prompts
- `scripts/install.sh` - User-facing installation script
- `worker/src/features/users/service.ts` - KV operations for user management
- `worker/src/features/notify/router.ts` - Notification endpoint that sends Telegram messages
- `worker/src/features/bot/bot.ts` - Telegram bot command handlers
