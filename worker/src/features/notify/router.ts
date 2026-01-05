import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { formatDuration } from "../../lib/format-duration";
import { sendTelegramMessage } from "../../lib/telegram";
import type { Env } from "../../lib/types";
import { getUserByKey } from "../users/service";
import { notifyRequestSchema } from "./schemas";

const notify = new Hono<{ Bindings: Env }>();

function formatTokens(tokens: number): string {
  if (tokens >= 1000000) {
    return `${(tokens / 1000000).toFixed(1)}M`;
  }
  if (tokens >= 1000) {
    return `${(tokens / 1000).toFixed(1)}K`;
  }
  return tokens.toString();
}

function formatCost(cost: number): string {
  if (cost < 0.01) {
    return `~$${cost.toFixed(4)}`;
  }
  return `~$${cost.toFixed(2)}`;
}

function escapeMarkdown(text: string): string {
  // Escape special Telegram markdown characters (only the essential ones)
  return text.replace(/[`*_[\]()~>#+|{}]/g, "\\$&");
}

interface NotificationData {
  projectName: string;
  sessionTitle?: string;
  durationMs?: number;
  inputTokens?: number;
  outputTokens?: number;
  costEstimate?: number;
  lastResponse?: string;
  filesModified?: number;
  commandsRun?: number;
}

function buildNotificationMessage(data: NotificationData): string {
  const lines: string[] = [];

  // Header section
  lines.push(`📁 \`${data.projectName}\``);

  if (data.sessionTitle) {
    lines.push(`📋 \`${data.sessionTitle}\``);
  }

  if (data.durationMs !== undefined) {
    lines.push(`⏱️${formatDuration(data.durationMs)}`);
  }

  // Response preview section
  if (data.lastResponse) {
    lines.push("");
    lines.push("💬 Response:");
    const truncated =
      data.lastResponse.length > 200 ? `${data.lastResponse.slice(0, 200)}...` : data.lastResponse;
    lines.push(`> ${escapeMarkdown(truncated)}`);
  }

  // Stats section
  const hasStats =
    data.costEstimate !== undefined ||
    data.filesModified !== undefined ||
    data.commandsRun !== undefined;

  if (hasStats) {
    lines.push("");
    lines.push("📊 Stats:");

    const statParts: string[] = [];

    if (data.costEstimate !== undefined && data.inputTokens && data.outputTokens) {
      statParts.push(
        `${formatCost(data.costEstimate)} (${formatTokens(data.inputTokens)} in / ${formatTokens(data.outputTokens)} out)`,
      );
    } else if (data.costEstimate !== undefined) {
      statParts.push(formatCost(data.costEstimate));
    }

    if (data.filesModified !== undefined && data.filesModified > 0) {
      statParts.push(`${data.filesModified} file${data.filesModified !== 1 ? "s" : ""}`);
    }

    if (data.commandsRun !== undefined && data.commandsRun > 0) {
      statParts.push(`${data.commandsRun} cmd${data.commandsRun !== 1 ? "s" : ""}`);
    }

    if (statParts.length > 0) {
      lines.push(`• ${statParts.join(" • ")}`);
    }
  }

  return lines.join("\n");
}

notify.post(
  "/notify",
  zValidator("json", notifyRequestSchema, (result, c) => {
    if (!result.success) {
      const firstError = result.error.issues[0];
      return c.json({ success: false, error: firstError?.message || "Invalid request" }, 400);
    }
  }),
  async (c) => {
    const body = c.req.valid("json");

    const userData = await getUserByKey(c.env.USERS, body.key);
    if (!userData) {
      return c.json({ success: false, error: "Invalid key" }, 401);
    }

    const projectName = body.project || "Unknown project";
    const message =
      body.message ||
      buildNotificationMessage({
        projectName,
        sessionTitle: body.sessionTitle,
        durationMs: body.durationMs,
        inputTokens: body.inputTokens,
        outputTokens: body.outputTokens,
        costEstimate: body.costEstimate,
        lastResponse: body.lastResponse,
        filesModified: body.filesModified,
        commandsRun: body.commandsRun,
      });

    const success = await sendTelegramMessage(c.env.BOT_TOKEN, userData.chatId, message);

    return c.json({ success });
  },
);

notify.get("/notify", (c) => {
  return c.text("Method not allowed", 405);
});

export { notify as notifyRouter };
