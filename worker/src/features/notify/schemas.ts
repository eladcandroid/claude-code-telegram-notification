import { z } from "zod";

export const notifyRequestSchema = z.object({
  key: z.string().min(1, "Missing key"),
  project: z.string().optional(),
  sessionTitle: z.string().optional(),
  durationMs: z.number().optional(),
  message: z.string().optional(),
  // Enhanced notification fields
  inputTokens: z.number().optional(),
  outputTokens: z.number().optional(),
  costEstimate: z.number().optional(),
  lastResponse: z.string().optional(),
  filesModified: z.number().optional(),
  commandsRun: z.number().optional(),
});
