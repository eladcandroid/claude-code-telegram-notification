# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Telegram notification system for Claude Code. When a Claude Code session ends, users receive a Telegram message. The project consists of two parts:

- **hooks/** - Shell script hook that runs on SessionEnd and sends notifications to the worker
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

### Hook (hooks/)
- `telegram-notify.sh` - Shell script triggered by Claude Code's SessionEnd hook
- Reads JSON input from stdin (session_id, cwd, transcript_path, reason)
- Skips notifications if session was cleared or user logged out
- Extracts project name from working directory
- Optionally parses transcript for session title and duration
- Sends POST to worker `/notify` endpoint with install key

### Worker (worker/)
- Hono-based Cloudflare Worker with grammY for Telegram bot
- Routes: `/webhook` (Telegram bot), `/notify` (hook notifications)
- User data stored in Cloudflare KV (USERS namespace) keyed by install UUID
- Bot commands: /start (get install key), /revoke, /status, /help
- Uses Zod for request validation

### Install Flow
1. User sends /start to Telegram bot → bot generates UUID, stores chatId in KV
2. User runs curl install script with UUID
3. Script downloads hook to `~/.claude/hooks/telegram-notify.sh`
4. Script updates `~/.claude/settings.json` with SessionEnd hook config
5. Placeholders in hook are replaced with key/URL

## Key Files

- `hooks/telegram-notify.sh` - The hook script (placeholders replaced at install time)
- `scripts/install.sh` - User-facing installation script
- `worker/src/features/users/service.ts` - KV operations for user management
- `worker/src/features/notify/router.ts` - Notification endpoint that sends Telegram messages
- `worker/src/features/bot/bot.ts` - Telegram bot command handlers
