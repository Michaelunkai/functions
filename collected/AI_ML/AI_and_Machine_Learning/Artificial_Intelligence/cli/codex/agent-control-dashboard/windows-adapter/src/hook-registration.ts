import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

// Lifecycle and tool activity are reconstructed from the local Codex
// transcript. Process hooks can outlive their launcher when stdin stays open.
const lifecycleEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd"] as const;

interface HookDocument {
  hooks?: Record<string, unknown>;
  [key: string]: unknown;
}

function isAgentControlEntry(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const entry = value as { hooks?: unknown };
  if (!Array.isArray(entry.hooks)) return false;
  return entry.hooks.some((hook) => {
    if (!hook || typeof hook !== "object") return false;
    const command = hook as Record<string, unknown>;
    return [command.commandWindows, command.command_windows, command.command]
      .some((candidate) => typeof candidate === "string" && candidate.includes("Invoke-AgentControlHook.ps1"));
  });
}

export function repairHookRegistration(hooksPath: string, _hookScriptPath: string): boolean {
  const raw = existsSync(hooksPath) ? readFileSync(hooksPath, "utf8") : "";
  const hadBom = raw.startsWith("\uFEFF");
  const document: HookDocument = raw
    ? JSON.parse(raw.replace(/^\uFEFF/, "")) as HookDocument
    : {};
  const hooks = document.hooks && typeof document.hooks === "object" && !Array.isArray(document.hooks)
    ? document.hooks
    : {};
  document.hooks = hooks;
  let changed = hadBom;

  for (const eventName of lifecycleEvents) {
    const current = Array.isArray(hooks[eventName]) ? hooks[eventName] as unknown[] : [];
    const replacement = current.filter((entry) => !isAgentControlEntry(entry));
    if (JSON.stringify(current) !== JSON.stringify(replacement)) {
      hooks[eventName] = replacement;
      changed = true;
    }
  }

  if (!changed && existsSync(hooksPath)) return false;
  mkdirSync(dirname(hooksPath), { recursive: true });
  const temporary = `${hooksPath}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(document, null, 2)}\n`, "utf8");
  renameSync(temporary, hooksPath);
  return true;
}
