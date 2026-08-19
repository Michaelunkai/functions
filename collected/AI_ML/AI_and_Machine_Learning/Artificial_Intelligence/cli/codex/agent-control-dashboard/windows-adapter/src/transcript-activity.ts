export interface TranscriptActivity {
  key: string;
  output: string;
}

export interface TerminalTranscript {
  turnId: string;
  lastAgentMessage?: string;
  result?: "DONE" | "WAITING" | "FAILED";
}

const terminalResultPattern =
  /(?:^|\r?\n)AGENT_CONTROL_RESULT:\s*(DONE|WAITING|FAILED)(?:\s+-\s+[^\r\n]+)?\s*$/i;

export interface TranscriptRecord {
  text: string;
  byteOffset: number;
}

export function findTerminalTranscript(
  lines: readonly string[],
  notBefore?: string
): TerminalTranscript | undefined {
  const lowerBound = notBefore ? Date.parse(notBefore) : undefined;
  let terminal: TerminalTranscript | undefined;
  for (const line of lines) {
    if (!line.includes('"task_complete"')) continue;
    try {
      const record = JSON.parse(line) as {
        timestamp?: string;
        type?: string;
        payload?: { type?: string; turn_id?: string; last_agent_message?: unknown };
      };
      const occurredAt = Date.parse(record.timestamp ?? "");
      if (record.type !== "event_msg" ||
        record.payload?.type !== "task_complete" ||
        !record.payload.turn_id ||
        (lowerBound !== undefined && (
          !Number.isFinite(lowerBound) ||
          !Number.isFinite(occurredAt) ||
          occurredAt < lowerBound
        ))) continue;
      const lastAgentMessage = typeof record.payload.last_agent_message === "string"
        ? record.payload.last_agent_message
        : undefined;
      const result = lastAgentMessage?.match(terminalResultPattern)?.[1]?.toUpperCase() as
        | "DONE" | "WAITING" | "FAILED" | undefined;
      terminal = {
        turnId: record.payload.turn_id,
        ...(lastAgentMessage !== undefined ? { lastAgentMessage } : {}),
        ...(result ? { result } : {})
      };
    } catch {
      // A transcript may be mid-write; retry it on the next poll.
    }
  }
  return terminal;
}

export function hasTerminalTranscript(lines: readonly string[], notBefore?: string): boolean {
  return Boolean(findTerminalTranscript(lines, notBefore));
}

export function hasCompletionTranscript(
  lines: readonly string[],
  notBefore?: string
): boolean {
  return findTerminalTranscript(lines, notBefore)?.result === "DONE";
}

function visibleText(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (Array.isArray(value)) {
    return value.map((block) => {
      if (!block || typeof block !== "object") return "";
      const text = (block as Record<string, unknown>).text;
      return typeof text === "string" ? text : "";
    }).join("").trim();
  }
  return value == null ? "" : JSON.stringify(value);
}

const genericToolSummary = "Tool completed; detailed output retained only in the native Codex session.";
const credentialName =
  String.raw`(?:owner[_-]?token|api[_-]?key|access[_-]?(?:token|key)|secret[_-]?access[_-]?key|private[_-]?key|database[_-]?url|connection[_-]?string|credentials?|token|password|passwd|secret)`;
const credentialFieldPattern = new RegExp(
  `^(?:authorization|(?:[a-z0-9]+[_-]?)*?(?:${credentialName}))$`,
  "i"
);
const toolOutputFieldPattern = /^(?:tool_output|tool_result|output|stdout|stderr)$/i;
const sensitivePatterns = [
  /\bAuthorization\s*:\s*Bearer\s+\S+/gi,
  /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi,
  /\bsk-(?:proj-)?[A-Za-z0-9_-]{12,}\b/g
];
const credentialAssignmentPattern = new RegExp(
  String.raw`(\b(?:[A-Za-z0-9]+[_-]?)*?(?:${credentialName})\b["']?\s*[:=]\s*)(?:(["'])([^\r\n]*?)\2|([^\s"',;}]+))`,
  "gi"
);
const safeToolStatusPatterns = [
  /\bBUILD (?:SUCCESSFUL|FAILED)\b/i,
  /\b\d+\s+(?:tests?|specs?|checks?)\s+(?:passed|failed|skipped)\b/i,
  /\b(?:tests?|specs?)\s*:\s*\d+\s+(?:passed|failed|skipped)\b/i,
  /\b(?:PARSER_OK|PowerShell(?: 5(?:\.1)?)? parse passed)\b/i,
  /\b(?:lint|typecheck|build|test)\s+(?:passed|failed|succeeded)\b/i,
  /\b(?:process )?exit(?:ed)?(?: with)? code\s*[:=]?\s*-?\d+\b/i
];

export function redactTranscriptText(
  text: string,
  sensitiveValues: readonly string[] = []
): string {
  let redacted = text;
  for (const value of sensitiveValues) {
    if (!value) continue;
    redacted = redacted.split(value).join("[REDACTED]");
  }
  for (const pattern of sensitivePatterns) {
    redacted = redacted.replace(pattern, (match) => {
      const separator = match.match(/^.*?(?:[:=]|Bearer)\s*/i)?.[0];
      return separator ? `${separator}[REDACTED]` : "[REDACTED]";
    });
  }
  redacted = redacted.replace(
    credentialAssignmentPattern,
    (_match, prefix: string, quote?: string) =>
      `${prefix}${quote ?? ""}[REDACTED]${quote ?? ""}`
  );
  return redacted.trim().slice(0, 1_000);
}

function redactHookText(
  text: string,
  sensitiveValues: readonly string[]
): string {
  let redacted = text;
  for (const value of sensitiveValues) {
    if (!value) continue;
    redacted = redacted.split(value).join("[REDACTED]");
  }
  for (const pattern of sensitivePatterns) {
    redacted = redacted.replace(pattern, (match) => {
      const separator = match.match(/^.*?(?:[:=]|Bearer)\s*/i)?.[0];
      return separator ? `${separator}[REDACTED]` : "[REDACTED]";
    });
  }
  redacted = redacted.replace(
    credentialAssignmentPattern,
    (_match, prefix: string, quote?: string) =>
      `${prefix}${quote ?? ""}[REDACTED]${quote ?? ""}`
  );
  return redacted.trim().slice(0, 20_000);
}

function pathLeaf(value: string): string {
  return value.trim().replace(/[\\/]+$/, "").split(/[\\/]/).filter(Boolean).at(-1) ?? "";
}

export function sanitizeHookPayload(
  payload: Record<string, unknown>,
  eventName = String(payload.hook_event_name ?? payload.event ?? ""),
  sensitiveValues: readonly string[] = []
): Record<string, unknown> {
  const sanitize = (value: unknown, key = ""): unknown => {
    if (credentialFieldPattern.test(key)) return "[REDACTED]";
    if (eventName === "PostToolUse" && toolOutputFieldPattern.test(key)) {
      return genericToolSummary;
    }
    if (typeof value === "string") {
      if (key.toLowerCase() === "cwd") return pathLeaf(value);
      return redactHookText(value, sensitiveValues);
    }
    if (Array.isArray(value)) return value.map((item) => sanitize(item));
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .map(([childKey, childValue]) => [childKey, sanitize(childValue, childKey)])
      );
    }
    return value;
  };
  return sanitize(payload) as Record<string, unknown>;
}

function summarizeToolOutput(
  text: string,
  sensitiveValues: readonly string[]
): string {
  const safeStatuses = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => safeToolStatusPatterns.some((pattern) => pattern.test(line)))
    .slice(0, 3)
    .map((line) => redactTranscriptText(line, sensitiveValues))
    .filter(Boolean);
  return safeStatuses.length > 0
    ? `Tool status: ${safeStatuses.join(" | ").slice(0, 400)}`
    : genericToolSummary;
}

function extractTranscriptRecords(
  records: readonly TranscriptRecord[],
  sensitiveValues: readonly string[] = []
): TranscriptActivity[] {
  const activity: TranscriptActivity[] = [];
  let lifecycleActive = true;
  let previousOutput: string | undefined;
  records.forEach((record) => {
    try {
      const parsed = JSON.parse(record.text) as {
        payload?: Record<string, unknown>;
      };
      const payload = parsed.payload ?? {};
      const type = String(payload.type ?? "");
      if (type === "task_started") {
        lifecycleActive = true;
        previousOutput = undefined;
        return;
      }
      if (type === "task_complete") {
        lifecycleActive = false;
        previousOutput = undefined;
        return;
      }
      if (!lifecycleActive) return;
      const visibleMessage = type === "agent_message" ? payload.message : undefined;
      const toolOutput = type === "function_call_output" || type === "custom_tool_call_output" ? payload.output : undefined;
      const value = visibleMessage ?? toolOutput;
      const text = visibleText(value);
      const output = visibleMessage !== undefined
        ? redactTranscriptText(text, sensitiveValues)
        : toolOutput !== undefined
          ? summarizeToolOutput(text, sensitiveValues)
          : "";
      if (output && output !== previousOutput) {
        activity.push({ key: `${record.byteOffset}:${type}`, output });
        previousOutput = output;
      }
    } catch {
      // A transcript may be mid-write; retry it on the next poll.
    }
  });
  return activity;
}

/** Extract only text that is visibly emitted by Codex, never private reasoning. */
export function extractTranscriptActivity(
  lines: readonly string[],
  sensitiveValues: readonly string[] = []
): TranscriptActivity[] {
  return extractTranscriptRecords(
    lines.map((text, byteOffset) => ({ text, byteOffset })),
    sensitiveValues
  );
}

export function extractTranscriptActivityRecords(
  records: readonly TranscriptRecord[],
  sensitiveValues: readonly string[] = []
): TranscriptActivity[] {
  return extractTranscriptRecords(records, sensitiveValues);
}
