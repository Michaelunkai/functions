import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface, type Interface } from "node:readline";
import { fileURLToPath } from "node:url";
import type { ClaimedTask } from "./sync.js";
import { redactTranscriptText } from "./transcript-activity.js";

export interface DesktopLaunchResult {
  accepted: boolean;
  marker: string;
  sessionId: string;
  title: string;
  pinned: boolean;
  selectedModel: string;
  selectedEffort: string;
  expectedModel: string;
  expectedEffort: string;
  model: string;
  effort: string;
  processId: number;
  processStartedAt: string;
}

const supportedModels = new Set([
  "default",
  "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol",
  "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex-spark"
]);
const supportedEfforts = new Set(["default", "low", "medium", "high", "xhigh"]);

interface CodexInstall {
  executable: string;
  version: [number, number, number];
  prerelease: boolean;
}

function codexInstall(packageRoot: string, architecture: string): CodexInstall | undefined {
  const platformPackage = architecture === "arm64" ? "codex-win32-arm64" : "codex-win32-x64";
  const targetTriple = architecture === "arm64"
    ? "aarch64-pc-windows-msvc"
    : "x86_64-pc-windows-msvc";
  const executable = join(
    packageRoot, "node_modules", "@openai", platformPackage,
    "vendor", targetTriple, "bin", "codex.exe"
  );
  if (!existsSync(executable)) return undefined;
  try {
    const packageDocument = JSON.parse(
      readFileSync(join(packageRoot, "package.json"), "utf8")
    ) as { version?: string };
    const versionText = packageDocument.version?.trim() ?? "";
    const match = versionText.match(/^(\d+)\.(\d+)\.(\d+)(.*)$/);
    if (!match) return undefined;
    return {
      executable,
      version: [Number(match[1]), Number(match[2]), Number(match[3])],
      prerelease: match[4].startsWith("-")
    };
  } catch {
    return undefined;
  }
}

export function resolveCodexExecutable(
  parentEnv: NodeJS.ProcessEnv = process.env,
  architecture = process.arch
): string {
  const override = parentEnv.AgentControl__CodexExecutable?.trim();
  if (override && existsSync(override)) return resolve(override);

  const packageRoots: string[] = [];
  const localAppData = parentEnv.LOCALAPPDATA;
  if (localAppData) {
    packageRoots.push(join(localAppData, "npm-global", "node_modules", "@openai", "codex"));
    const versionsRoot = join(localAppData, "CodexVersions");
    try {
      for (const entry of readdirSync(versionsRoot, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        packageRoots.push(join(
          versionsRoot, entry.name, "npm-global", "node_modules", "@openai", "codex"
        ));
      }
    } catch {
      // A machine without versioned installs still has the normal npm candidate.
    }
  }
  if (parentEnv.APPDATA) {
    packageRoots.push(join(parentEnv.APPDATA, "npm", "node_modules", "@openai", "codex"));
  }

  const candidates = packageRoots
    .map((packageRoot) => codexInstall(packageRoot, architecture))
    .filter((candidate): candidate is CodexInstall => candidate !== undefined);
  const stableCandidates = candidates.filter((candidate) => !candidate.prerelease);
  const eligible = stableCandidates.length > 0 ? stableCandidates : candidates;
  eligible.sort((left, right) => {
    for (let index = 0; index < left.version.length; index += 1) {
      const difference = right.version[index] - left.version[index];
      if (difference !== 0) return difference;
    }
    return left.executable.localeCompare(right.executable);
  });
  return eligible[0]?.executable ?? "codex.exe";
}

export interface NativeCodexModel {
  model: string;
  supportedReasoningEfforts: Array<{ reasoningEffort: string }>;
  defaultReasoningEffort?: string;
  isDefault?: boolean;
}

export interface ResolvedNativeSelection {
  model: string;
  effort: string;
}

export interface NativeTurnState {
  completed: boolean;
  status?: string;
  error?: string;
  hasNativeActivity: boolean;
  hasAgentOutput: boolean;
}

export interface NativeTurnEvent {
  turnId: string;
  completed?: boolean;
  status?: string;
  error?: string;
  hasNativeActivity?: boolean;
  hasAgentOutput?: boolean;
}

export interface PersistedNativeProcess {
  processId: number;
  processStartedAt: string;
}

export interface PersistedNativeSession extends PersistedNativeProcess {
  sessionId: string;
}

export interface WindowsProcessDetails {
  processId: number;
  name: string;
  commandLine: string;
  creationDate: string;
}

export class DesktopLaunchError extends Error {
  constructor(message: string, readonly sessionId?: string) {
    super(message);
    this.name = "DesktopLaunchError";
  }
}

export class DesktopPreTurnLaunchError extends Error {
  constructor(message: string, readonly sessionId: string) {
    super(message);
    this.name = "DesktopPreTurnLaunchError";
  }
}

export interface NativeDesktopPinResult {
  sessionId: string;
  routeVerified: true;
  pinned: true;
}

export interface NativeDesktopPinCommand {
  executable: string;
  args: string[];
  env: NodeJS.ProcessEnv;
  windowsHide: true;
  timeoutMs: number;
}

export interface NativeDesktopPinExecution {
  code: number;
  stdout: string;
  stderr: string;
}

export interface NativeDesktopPinDependencies {
  parentEnv?: NodeJS.ProcessEnv;
  run?: (command: NativeDesktopPinCommand) => Promise<NativeDesktopPinExecution>;
}

function redactNativeError(value: unknown): string {
  return redactTranscriptText(String(value));
}

function normalized(value: string): string {
  return value.trim().toLowerCase();
}

export function nativeMissionEnvironment(
  taskId: string,
  parentEnv: NodeJS.ProcessEnv = process.env
): NodeJS.ProcessEnv {
  const env = sanitizedChildEnvironment(parentEnv);
  env.CODEX_ADAPTIVE_WORKER = "1";
  env.CODEX_ADAPTIVE_TASK_ID = taskId;
  return env;
}

function sanitizedChildEnvironment(
  parentEnv: NodeJS.ProcessEnv = process.env
): NodeJS.ProcessEnv {
  const allowedKeys = new Set([
    "APPDATA",
    "CODEX_HOME",
    "COLORTERM",
    "COMMONPROGRAMFILES",
    "COMMONPROGRAMFILES(X86)",
    "COMMONPROGRAMW6432",
    "COMSPEC",
    "HOMEDRIVE",
    "HOMEPATH",
    "HOME",
    "LANG",
    "LC_ALL",
    "LOCALAPPDATA",
    "LOGONSERVER",
    "NODE_EXTRA_CA_CERTS",
    "NO_PROXY",
    "NUMBER_OF_PROCESSORS",
    "OS",
    "PATH",
    "PATHEXT",
    "PROCESSOR_ARCHITECTURE",
    "PROCESSOR_IDENTIFIER",
    "PROCESSOR_LEVEL",
    "PROCESSOR_REVISION",
    "PROGRAMDATA",
    "PROGRAMFILES",
    "PROGRAMFILES(X86)",
    "PROGRAMW6432",
    "SESSIONNAME",
    "SSL_CERT_DIR",
    "SSL_CERT_FILE",
    "SYSTEMDRIVE",
    "SYSTEMROOT",
    "TEMP",
    "TERM",
    "TMP",
    "TMPDIR",
    "USERDNSDOMAIN",
    "USERDOMAIN",
    "USERNAME",
    "USERPROFILE",
    "WINDIR"
  ]);
  const proxyKeys = new Set(["ALL_PROXY", "HTTP_PROXY", "HTTPS_PROXY"]);
  const env: NodeJS.ProcessEnv = {};
  for (const [key, value] of Object.entries(parentEnv)) {
    const upperKey = key.toUpperCase();
    if (value === undefined) continue;
    if (allowedKeys.has(upperKey)) {
      env[key] = value;
      continue;
    }
    if (proxyKeys.has(upperKey)) {
      try {
        const proxy = new URL(value);
        if (!proxy.username && !proxy.password) env[key] = value;
      } catch {
        // An invalid proxy is safer to omit than to pass into the native worker.
      }
    }
  }
  return env;
}

export function nativeLaunchActivityTimeoutMs(
  value = process.env.AgentControl__NativeLaunchActivityTimeoutMs
): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 1_000 ? parsed : 30_000;
}

export function nativeTurnEvent(message: Record<string, any>): NativeTurnEvent | undefined {
  const turnId = String(
    message.params?.turn?.id ??
    message.params?.turnId ??
    ""
  ).trim();
  if (!turnId) return undefined;

  if (message.method === "turn/completed") {
    const error = String(
      message.params?.turn?.error?.message ??
      message.params?.error?.message ??
      message.params?.error ??
      ""
    ).trim();
    return {
      turnId,
      completed: true,
      status: String(message.params?.turn?.status ?? message.params?.status ?? "completed"),
      ...(error ? { error } : {})
    };
  }

  const delta = String(message.params?.delta ?? "");
  const hasAgentOutput = (
    message.method === "item/agentMessage/delta" &&
    delta.trim().length > 0
  ) || (
    message.method === "item/completed" &&
    message.params?.item?.type === "agentMessage" &&
    String(message.params?.item?.text ?? "").trim().length > 0
  );
  if (hasAgentOutput) {
    return { turnId, hasNativeActivity: true, hasAgentOutput: true };
  }

  const itemType = String(message.params?.item?.type ?? "");
  const substantiveItemTypes = new Set([
    "plan", "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall",
    "collabAgentToolCall", "subAgentActivity", "webSearch", "imageView", "sleep",
    "imageGeneration", "enteredReviewMode", "exitedReviewMode", "contextCompaction"
  ]);
  if (
    (message.method === "item/started" || message.method === "item/completed") &&
    substantiveItemTypes.has(itemType)
  ) {
    return { turnId, hasNativeActivity: true };
  }
  return { turnId };
}

export function nativeTurnFailure(state: NativeTurnState): string | undefined {
  if (!state.completed) return undefined;
  const status = normalized(state.status ?? "completed");
  if (status === "failed") {
    return `desktop_launch_turn_failed:${state.error?.trim() || "native_turn_failed"}`;
  }
  if (status === "interrupted") return "desktop_launch_turn_interrupted";
  if (status !== "completed") return `desktop_launch_turn_unaccepted_status:${status || "missing"}`;
  if (!state.hasAgentOutput) return "desktop_launch_turn_completed_without_agent_output";
  return undefined;
}

export function isTerminalNativeTurnStatus(status?: string): boolean {
  return new Set(["completed", "interrupted", "failed", "cancelled"]).has(normalized(status ?? ""));
}

export function nativeLaunchStatusFailure(status?: string): string | undefined {
  const value = normalized(status ?? "");
  if (value === "failed") return "desktop_launch_turn_failed:native_turn_failed";
  if (value === "interrupted" || value === "cancelled") {
    return `desktop_launch_turn_${value}`;
  }
  return undefined;
}

export function nativeTurnStatus(result: RpcResult, turnId: string): string | undefined {
  const turns = Array.isArray(result.thread?.turns) ? result.thread.turns : [];
  const turn = turns.find((candidate: any) => String(candidate?.id ?? "") === turnId);
  const status = String(turn?.status ?? "").trim();
  return status || undefined;
}

export function isManagedNativeProcess(
  actual: WindowsProcessDetails,
  expected: PersistedNativeProcess
): boolean {
  if (actual.processId !== expected.processId) return false;
  const processName = normalized(actual.name);
  if (processName !== "codex.exe" && !/^codex-[a-z0-9_-]+-windows-msvc\.exe$/.test(processName)) {
    return false;
  }
  if (!/(?:^|\s)app-server(?:\s|$)/i.test(actual.commandLine)) return false;
  if (!/(?:^|\s)--stdio(?:\s|$)/i.test(actual.commandLine)) return false;
  const actualStartedAt = Date.parse(actual.creationDate);
  const expectedStartedAt = Date.parse(expected.processStartedAt);
  if (!Number.isFinite(actualStartedAt) || !Number.isFinite(expectedStartedAt)) return false;
  return actualStartedAt >= expectedStartedAt - 5_000 &&
    actualStartedAt <= expectedStartedAt + 30_000;
}

export function nativeThreadDeepLink(sessionId: string): string {
  if (!sessionId.trim()) throw new Error("desktop_launch_session_id_missing");
  return `codex://threads/${encodeURIComponent(sessionId.trim())}`;
}

export function nativeThreadPinned(state: unknown, sessionId: string): boolean {
  if (!state || typeof state !== "object" || !sessionId.trim()) return false;
  const pinnedThreadIds = (state as Record<string, unknown>)["pinned-thread-ids"];
  return Array.isArray(pinnedThreadIds) &&
    pinnedThreadIds.some((candidate) => candidate === sessionId);
}

export function nativeDesktopPinCommand(
  sessionId: string,
  parentEnv: NodeJS.ProcessEnv = process.env
): NativeDesktopPinCommand {
  const normalizedSessionId = sessionId.trim();
  if (!normalizedSessionId) throw new Error("desktop_launch_session_id_missing");
  return {
    executable: "powershell.exe",
    args: [
      "-NoProfile",
      "-NonInteractive",
      "-STA",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      fileURLToPath(new URL("../scripts/Pin-CodexDesktopTask.ps1", import.meta.url)),
      "-SessionId",
      normalizedSessionId
    ],
    env: sanitizedChildEnvironment(parentEnv),
    windowsHide: true,
    timeoutMs: 180_000
  };
}

export function parseNativeDesktopPinResult(
  stdout: string,
  expectedSessionId: string
): NativeDesktopPinResult {
  const lines = stdout.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length !== 1) throw new Error("desktop_pin_helper_output_invalid");
  let parsed: unknown;
  try {
    parsed = JSON.parse(lines[0]);
  } catch {
    throw new Error("desktop_pin_helper_output_invalid");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("desktop_pin_helper_output_invalid");
  }
  const record = parsed as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (keys.join(",") !== "pinned,routeVerified,sessionId") {
    throw new Error("desktop_pin_helper_output_invalid");
  }
  if (record.sessionId !== expectedSessionId) {
    throw new Error(
      `desktop_pin_helper_session_mismatch:expected=${expectedSessionId}:actual=${
        typeof record.sessionId === "string" ? record.sessionId : "missing"
      }`
    );
  }
  if (record.routeVerified !== true) throw new Error("desktop_pin_helper_route_unverified");
  if (record.pinned !== true) throw new Error("desktop_pin_helper_pin_unverified");
  return {
    sessionId: expectedSessionId,
    routeVerified: true,
    pinned: true
  };
}

async function runNativeDesktopPinCommand(
  command: NativeDesktopPinCommand
): Promise<NativeDesktopPinExecution> {
  return await new Promise<NativeDesktopPinExecution>((resolve, reject) => {
    const child = spawn(command.executable, command.args, {
      env: command.env,
      windowsHide: command.windowsHide,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const complete = (result: NativeDesktopPinExecution) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(result);
    };
    const timeout = setTimeout(() => {
      child.kill();
      complete({
        code: -1,
        stdout,
        stderr: stderr.trim() || "desktop_pin_helper_timeout"
      });
    }, command.timeoutMs);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
      if (stdout.length > 65_536) child.kill();
    });
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
      if (stderr.length > 65_536) child.kill();
    });
    child.once("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.once("close", (code) => complete({
      code: code ?? -1,
      stdout,
      stderr
    }));
  });
}

export async function invokeNativeDesktopPinHelper(
  sessionId: string,
  dependencies: NativeDesktopPinDependencies = {}
): Promise<NativeDesktopPinResult> {
  const command = nativeDesktopPinCommand(sessionId, dependencies.parentEnv);
  const execution = await (dependencies.run ?? runNativeDesktopPinCommand)(command);
  if (execution.code !== 0) {
    throw new Error(
      `desktop_pin_helper_failed:${redactNativeError(execution.stderr.trim() || `exit_${execution.code}`)}`
    );
  }
  return parseNativeDesktopPinResult(execution.stdout, sessionId);
}

function nativeModel(models: NativeCodexModel[], model: string): NativeCodexModel {
  const resolved = models.find((candidate) => normalized(candidate.model) === model);
  if (!resolved) throw new Error(`desktop_launch_model_unavailable:${model}`);
  return resolved;
}

/**
 * Resolves Dashboard Default exactly as the PowerShell launcher does: against
 * the current top-level Codex settings before those settings are pinned.
 */
export function resolveNativeSelection(
  selectedModel: string,
  selectedEffort: string,
  models: NativeCodexModel[],
  configuredModel = "default",
  configuredEffort = "default"
): ResolvedNativeSelection {
  const selectedModelValue = normalized(selectedModel);
  const selectedEffortValue = normalized(selectedEffort);
  const configuredModelValue = normalized(configuredModel);
  const configuredEffortValue = normalized(configuredEffort);
  const defaultModel = models.find((candidate) => candidate.isDefault)?.model;
  const modelValue = selectedModelValue === "default"
    ? (configuredModelValue === "default" ? normalized(defaultModel ?? "") : configuredModelValue)
    : selectedModelValue;
  if (!modelValue) throw new Error("desktop_launch_default_model_unavailable");
  const model = nativeModel(models, modelValue);
  const effortValue = selectedEffortValue === "default"
    ? (configuredEffortValue === "default" ? normalized(model.defaultReasoningEffort ?? "") : configuredEffortValue)
    : selectedEffortValue;
  if (!effortValue) throw new Error(`desktop_launch_default_effort_unavailable:${modelValue}`);
  return { model: modelValue, effort: effortValue };
}

export function assertNativeSelectionAvailable(
  selectedModel: string,
  selectedEffort: string,
  models: NativeCodexModel[],
  configuredModel = "default",
  configuredEffort = "default"
): void {
  const resolved = resolveNativeSelection(
    selectedModel, selectedEffort, models, configuredModel, configuredEffort
  );
  const model = nativeModel(models, resolved.model);
  if (!model.supportedReasoningEfforts.some(
    (candidate) => normalized(candidate.reasoningEffort) === resolved.effort
  )) {
    throw new Error(`desktop_launch_effort_unavailable:${resolved.model}:${resolved.effort}`);
  }
}

function configuredCodexSetting(config: string, name: string): string | undefined {
  for (const line of config.split(/\r?\n/)) {
    if (/^\s*\[/.test(line)) break;
    const match = line.match(new RegExp(`^\\s*${name}\\s*=\\s*"([^"]+)"\\s*(?:#.*)?$`));
    if (match?.[1]) return normalized(match[1]);
  }
  return undefined;
}

function configuredCodexSelection(): ResolvedNativeSelection {
  let config: string;
  try {
    config = readFileSync(join(homedir(), ".codex", "config.toml"), "utf8");
  } catch {
    throw new Error("desktop_launch_default_config_unavailable");
  }
  const model = configuredCodexSetting(config, "model");
  const effort = configuredCodexSetting(config, "model_reasoning_effort");
  if (!model || !effort) throw new Error("desktop_launch_default_config_incomplete");
  return { model, effort };
}

async function nativeCodexModels(): Promise<NativeCodexModel[]> {
  return await new Promise((resolve, reject) => {
    const child = spawn(resolveCodexExecutable(), ["app-server", "--stdio"], {
      env: sanitizedChildEnvironment(),
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const settle = (callback: () => void): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      child.kill();
      callback();
    };
    const send = (message: object): void => {
      child.stdin.write(`${JSON.stringify(message)}\n`);
    };
    const timeout = setTimeout(
      () => settle(() => reject(new Error("desktop_launch_model_preflight_timeout"))),
      15_000
    );
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => { stderr = `${stderr}${chunk}`.slice(-4_000); });
    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
      for (;;) {
        const lineEnd = stdout.indexOf("\n");
        if (lineEnd < 0) break;
        const line = stdout.slice(0, lineEnd).trim();
        stdout = stdout.slice(lineEnd + 1);
        if (!line) continue;
        try {
          const message = JSON.parse(line) as {
            id?: number;
            error?: { message?: string };
            result?: { data?: NativeCodexModel[] };
          };
          if (message.id === 1) {
            if (message.error) {
              const errorMessage = redactNativeError(message.error.message ?? "initialize");
              settle(() => reject(new Error(`desktop_launch_model_preflight_failed:${errorMessage}`)));
              return;
            }
            send({ method: "initialized" });
            send({ method: "model/list", id: 2, params: { includeHidden: false, limit: 100 } });
          } else if (message.id === 2) {
            if (message.error || !Array.isArray(message.result?.data)) {
              settle(() => reject(new Error(
                `desktop_launch_model_preflight_failed:${redactNativeError(message.error?.message ?? "model_list")}`
              )));
              return;
            }
            settle(() => resolve(message.result!.data!));
            return;
          }
        } catch {
          // App-server logs may share stdout; only complete JSON protocol lines are authoritative.
        }
      }
    });
    child.once("error", (error) => settle(() => reject(error)));
    child.once("exit", (code) => {
      if (!settled) settle(() => reject(new Error(
        redactNativeError(stderr.trim() || `desktop_launch_model_preflight_exit:${code ?? -1}`)
      )));
    });
    send({
      method: "initialize",
      id: 1,
      params: {
        clientInfo: { name: "agent-control-preflight", title: "Agent Control Preflight", version: "0.1.0" },
        capabilities: null
      }
    });
  });
}

export async function preflightNativeSelection(selectedModel: string, selectedEffort: string): Promise<void> {
  const configured = configuredCodexSelection();
  assertNativeSelectionAvailable(
    selectedModel, selectedEffort, await nativeCodexModels(), configured.model, configured.effort
  );
}

function uniqueMissionSelection(
  description: string,
  label: string,
  supported: ReadonlySet<string>
): string | undefined {
  const pattern = new RegExp(`^${label}:\\s*([^\\r\\n]+)$`, "gim");
  const matches = [...description.matchAll(pattern)];
  if (matches.length === 0) return "default";
  if (matches.length !== 1) return undefined;
  const candidate = matches[0]?.[1]?.trim().toLowerCase();
  return candidate && supported.has(candidate) ? candidate : undefined;
}

/** Reads the user-selected model from the durable mission description. */
export function requestedModel(description: string): string | undefined {
  return uniqueMissionSelection(description, "Agent Control model", supportedModels);
}

/** Reads the user-selected reasoning effort from the durable mission description. */
export function requestedEffort(description: string): string | undefined {
  return uniqueMissionSelection(description, "Agent Control reasoning effort", supportedEfforts);
}

/**
 * A second fail-closed boundary: the PowerShell launcher records the native
 * Codex settings it observed, and the adapter will not accept a different pair.
 */
export function verifyRequestedSessionSettings(
  description: string,
  result: Pick<DesktopLaunchResult,
    "selectedModel" | "selectedEffort" | "expectedModel" | "expectedEffort" | "model" | "effort">
): void {
  const selectedModel = requestedModel(description);
  const selectedEffort = requestedEffort(description);
  if (!selectedModel || !selectedEffort) throw new Error("desktop_launch_selection_missing");

  const reportedSelectionModel = result.selectedModel?.trim().toLowerCase();
  const reportedSelectionEffort = result.selectedEffort?.trim().toLowerCase();
  const expectedModel = result.expectedModel?.trim().toLowerCase();
  const expectedEffort = result.expectedEffort?.trim().toLowerCase();
  const model = result.model?.trim().toLowerCase();
  const effort = result.effort?.trim().toLowerCase();
  if (reportedSelectionModel !== selectedModel || reportedSelectionEffort !== selectedEffort) {
    throw new Error("desktop_launch_selection_mismatch");
  }
  if (!expectedModel || !expectedEffort || !model || !effort) {
    throw new Error("desktop_launch_verified_settings_missing");
  }
  if (selectedModel !== "default" && expectedModel !== selectedModel) {
    throw new Error(`desktop_launch_resolved_model_mismatch:selected=${selectedModel}:resolved=${expectedModel}`);
  }
  if (selectedEffort !== "default" && expectedEffort !== selectedEffort) {
    throw new Error(`desktop_launch_resolved_effort_mismatch:selected=${selectedEffort}:resolved=${expectedEffort}`);
  }
  if (model !== expectedModel) {
    throw new Error(`desktop_launch_model_mismatch:expected=${expectedModel}:actual=${model}`);
  }
  if (effort !== expectedEffort) {
    throw new Error(`desktop_launch_effort_mismatch:expected=${expectedEffort}:actual=${effort || "missing"}`);
  }
}

export function desktopStopTimeoutMs(value = process.env.AgentControl__DesktopStopTimeoutMs): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 1_000 ? parsed : 3_000;
}

export function desktopMissionPrompt(task: ClaimedTask): string {
  const marker = `AC-${task.id.slice(0, 8)}`;
  return [
    `${task.title} [${marker}]`,
    "",
    "Agent Control mission:",
    task.description,
    "",
    "Persistent mission contract:",
    "EXECUTION CONTRACT: Agent Control owns this exact app-server thread and turn. Work only in this managed session and preserve its task identity.",
    "Before substantive work, call get_goal. If no active goal exists, call create_goal with this exact mission as the objective.",
    "Keep that goal active until every requested result is implemented and verified.",
    "Do not finish an ordinary turn while the mission remains incomplete. Continue working unless the owner manually stops the mission or an unavoidable external gate requires AGENT_CONTROL_RESULT: WAITING.",
    "Only emit AGENT_CONTROL_RESULT: DONE after complete verification.",
    "",
    missionResultContract()
  ].join("\n");
}

export function nativeAppServerMissionPrompt(task: ClaimedTask, sessionId: string): string {
  const verifiedSessionId = sessionId.trim();
  if (!verifiedSessionId) throw new Error("desktop_launch_session_id_missing");
  return [
    "APP-SERVER SESSION PROOF:",
    `Agent Control created or resumed this exact native app-server thread before this turn started: ${verifiedSessionId}`,
    "Desktop pinning is not a supported app-server capability and is not required for this managed mission.",
    "Do not call codex_app.set_thread_pinned. The adapter controls this exact thread and turn directly.",
    "",
    desktopMissionPrompt(task)
  ].join("\n");
}

export function nativeLaunchParams(
  workspace: string,
  model: string,
  effort: string,
  prompt: string
): {
  thread: Record<string, unknown>;
  turn: Record<string, unknown>;
} {
  return {
    thread: {
      model,
      allowProviderModelFallback: false,
      cwd: workspace,
      approvalPolicy: "never",
      sandbox: "danger-full-access",
      ephemeral: false,
      config: { model_reasoning_effort: effort }
    },
    turn: {
      input: [{ type: "text", text: prompt, text_elements: [] }],
      model,
      effort,
      cwd: workspace,
      approvalPolicy: "never",
      sandboxPolicy: { type: "dangerFullAccess" }
    }
  };
}

export function nativeThreadMaterializationParams(
  threadId: string
): { threadId: string; gitInfo: { branch: string } } {
  return {
    threadId,
    gitInfo: { branch: "agent-control-pre-turn" }
  };
}

export function nativeThreadNameParams(
  threadId: string,
  title: string
): { threadId: string; name: string } {
  const name = title.trim();
  if (!name) throw new Error("desktop_launch_title_missing");
  return { threadId, name };
}

export function nativeThreadGoalParams(
  threadId: string,
  objective: string
): { threadId: string; objective: string; status: "active" } {
  const normalizedObjective = objective.trim();
  if (!normalizedObjective) throw new Error("desktop_launch_objective_missing");
  return { threadId, objective: normalizedObjective, status: "active" };
}

export function verifiedNativeThreadStart(result: RpcResult): string {
  const thread = result.thread;
  const threadId = String(thread?.id ?? "").trim();
  if (!threadId) throw new Error("desktop_launch_session_id_missing");
  if (thread?.ephemeral === true) throw new Error("desktop_launch_ephemeral_thread_rejected");
  return threadId;
}

export function verifiedNativeTurnStart(result: RpcResult, expectedThreadId: string): string {
  const turn = result.turn;
  const turnId = String(turn?.id ?? "").trim();
  if (!turnId) throw new Error("desktop_launch_turn_id_missing");
  const actualThreadId = String(turn?.threadId ?? result.threadId ?? "").trim();
  if (actualThreadId && actualThreadId !== expectedThreadId) {
    throw new Error(
      `desktop_launch_turn_thread_mismatch:expected=${expectedThreadId}:actual=${actualThreadId}`
    );
  }
  if (isTerminalNativeTurnStatus(String(turn?.status ?? ""))) {
    throw new Error(`desktop_launch_turn_start_terminal:${String(turn.status).toLowerCase()}`);
  }
  return turnId;
}

export function nativeStopParams(threadId: string, turnId: string): {
  threadId: string;
  turnId: string;
} {
  return { threadId, turnId };
}

type RpcResult = Record<string, any>;

class NativeMissionSession {
  private readonly child: ChildProcessWithoutNullStreams;
  private readonly lines: Interface;
  private readonly pending = new Map<number, {
    resolve: (value: RpcResult) => void;
    reject: (error: Error) => void;
    timer: NodeJS.Timeout;
    method: string;
  }>();
  private nextId = 1;
  private stderr = "";
  private readonly turnStates = new Map<string, NativeTurnState>();
  threadId = "";
  turnId = "";
  readonly processStartedAt = new Date().toISOString();

  constructor(
    readonly taskId: string,
    private readonly onExit: (session: NativeMissionSession) => void
  ) {
    this.child = spawn(resolveCodexExecutable(), ["app-server", "--stdio"], {
      env: nativeMissionEnvironment(taskId),
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"]
    });
    this.lines = createInterface({ input: this.child.stdout, crlfDelay: Infinity });
    this.lines.on("line", (line) => this.handleLine(line));
    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk: string) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-8_000);
    });
    this.child.once("error", (error) => this.failAll(error));
    this.child.once("exit", (code) => {
      if (code !== 0) this.failAll(new Error(
        redactNativeError(this.stderr.trim() || `native_app_server_exit:${code ?? -1}`)
      ));
      this.onExit(this);
    });
  }

  private send(message: object): void {
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private handleLine(line: string): void {
    let message: any;
    try { message = JSON.parse(line); } catch { return; }
    if (message.id !== undefined && this.pending.has(Number(message.id))) {
      const waiter = this.pending.get(Number(message.id))!;
      this.pending.delete(Number(message.id));
      clearTimeout(waiter.timer);
      if (message.error) {
        waiter.reject(new Error(
          `${waiter.method}:${redactNativeError(message.error.message ?? JSON.stringify(message.error))}`
        ));
      }
      else waiter.resolve(message.result ?? {});
      return;
    }
    const event = nativeTurnEvent(message);
    if (event) {
      const current = this.turnStates.get(event.turnId) ?? {
        completed: false,
        hasNativeActivity: false,
        hasAgentOutput: false
      };
      this.turnStates.set(event.turnId, {
        completed: event.completed ?? current.completed,
        status: event.status ?? current.status,
        error: event.error ?? current.error,
        hasNativeActivity: event.hasNativeActivity ?? current.hasNativeActivity,
        hasAgentOutput: event.hasAgentOutput ?? current.hasAgentOutput
      });
    }
    if (message.id !== undefined && message.method) {
      this.send({
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32601, message: "Agent Control does not handle this server request" }
      });
    }
  }

  request(method: string, params: object, timeoutMs = 30_000): Promise<RpcResult> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`native_app_server_timeout:${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer, method });
      this.send({ jsonrpc: "2.0", id, method, params });
    });
  }

  notify(method: string, params: object): void {
    this.send({ jsonrpc: "2.0", method, params });
  }

  private turnState(): NativeTurnState {
    return this.turnStates.get(this.turnId) ?? {
      completed: false,
      hasNativeActivity: false,
      hasAgentOutput: false
    };
  }

  get completed(): boolean {
    return this.turnState().completed;
  }

  get processId(): number {
    const processId = this.child.pid;
    if (!processId) throw new Error("native_app_server_process_id_missing");
    return processId;
  }

  private async readTurnStatus(timeoutMs: number): Promise<string | undefined> {
    return this.readSpecificTurnStatus(this.threadId, this.turnId, timeoutMs);
  }

  async readSpecificTurnStatus(
    threadId: string,
    turnId: string,
    timeoutMs: number
  ): Promise<string | undefined> {
    const result = await this.request(
      "thread/read",
      { threadId, includeTurns: true },
      timeoutMs
    );
    return nativeTurnStatus(result, turnId);
  }

  async stop(timeoutMs = desktopStopTimeoutMs()): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    let interruptError: Error | undefined;
    if (this.completed) return;
    try {
      const before = await this.readTurnStatus(Math.max(1_000, deadline - Date.now()));
      if (isTerminalNativeTurnStatus(before)) return;
      await this.request(
        "turn/interrupt",
        nativeStopParams(this.threadId, this.turnId),
        Math.max(1_000, deadline - Date.now())
      );
    } catch (error) {
      interruptError = error instanceof Error ? error : new Error(String(error));
    }
    while (Date.now() < deadline) {
      if (this.completed) return;
      try {
        const status = await this.readTurnStatus(Math.max(1_000, deadline - Date.now()));
        if (isTerminalNativeTurnStatus(status)) return;
      } catch (error) {
        interruptError ??= error instanceof Error ? error : new Error(String(error));
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw interruptError ?? new Error("native_stop_terminal_proof_timeout");
  }

  async verifyLaunchViability(timeoutMs = nativeLaunchActivityTimeoutMs()): Promise<void> {
    const failure = nativeLaunchStatusFailure(await this.readTurnStatus(timeoutMs));
    if (failure) throw new Error(failure);
  }

  close(): void {
    this.lines.close();
    this.child.stdin.end();
    if (!this.child.killed) this.child.kill();
  }

  private failAll(error: Error): void {
    for (const waiter of this.pending.values()) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
    this.pending.clear();
  }
}

const nativeSessions = new Map<string, NativeMissionSession>();

function transcriptForSession(sessionId: string): string | undefined {
  const root = join(homedir(), ".codex", "sessions");
  if (!existsSync(root)) return undefined;
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop()!;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) pending.push(path);
      else if (entry.isFile() && entry.name.endsWith(`${sessionId}.jsonl`)) return path;
    }
  }
  return undefined;
}

async function waitForVerifiedTranscript(
  sessionId: string,
  workspace: string,
  model: string,
  effort: string
): Promise<void> {
  const deadline = Date.now() + 30_000;
  let lastError = "native_session_transcript_missing";
  while (Date.now() < deadline) {
    const transcript = transcriptForSession(sessionId);
    if (transcript) {
      try {
        const records = readFileSync(transcript, "utf8").split(/\r?\n/).filter(Boolean)
          .map((line) => JSON.parse(line) as { type?: string; payload?: Record<string, unknown> });
        const meta = records.find((record) => record.type === "session_meta")?.payload;
        const context = [...records].reverse().find((record) => record.type === "turn_context")?.payload;
        const actualWorkspace = String(meta?.cwd ?? "");
        const actualModel = normalized(String(context?.model ?? ""));
        const actualEffort = normalized(String(context?.effort ?? ""));
        if (!actualWorkspace || !context) throw new Error("native_session_proof_incomplete");
        if (resolve(actualWorkspace).toLowerCase() !== resolve(workspace).toLowerCase()) {
          throw new Error(`desktop_launch_workspace_mismatch:expected=${workspace}:actual=${actualWorkspace}`);
        }
        if (actualModel !== normalized(model)) {
          throw new Error(`desktop_launch_model_mismatch:expected=${model}:actual=${actualModel || "missing"}`);
        }
        if (actualEffort !== normalized(effort)) {
          throw new Error(`desktop_launch_effort_mismatch:expected=${effort}:actual=${actualEffort || "missing"}`);
        }
        return;
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
        if (lastError.includes("_mismatch:")) throw error;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(lastError);
}

export function missionResultContract(): string {
  return [
    "Finish your final response with exactly one standalone result marker and no words after it:",
    "AGENT_CONTROL_RESULT: DONE",
    "AGENT_CONTROL_RESULT: WAITING",
    "AGENT_CONTROL_RESULT: FAILED",
    "Use DONE only after the requested result is implemented and verified; use WAITING only for an unavoidable external gate; use FAILED only after supported recovery is exhausted."
  ].join("\n");
}

export async function launchPinnedDesktopTask(
  task: ClaimedTask,
  workspace: string,
  onNativeProcessStarted?: (process: PersistedNativeProcess) => void,
  onNativeSessionStarted?: (session: PersistedNativeSession) => void,
  _resumeSessionId?: string
): Promise<DesktopLaunchResult> {
  const selectedModel = requestedModel(task.description);
  const selectedEffort = requestedEffort(task.description);
  if (!selectedModel || !selectedEffort) throw new Error("desktop_launch_selection_missing");
  await preflightNativeSelection(selectedModel, selectedEffort);
  const configured = configuredCodexSelection();
  const models = await nativeCodexModels();
  const resolved = resolveNativeSelection(
    selectedModel, selectedEffort, models, configured.model, configured.effort
  );
  const session = new NativeMissionSession(task.id, (closed) => {
    if (nativeSessions.get(task.id) === closed) nativeSessions.delete(task.id);
  });
  nativeSessions.set(task.id, session);
  let sessionId = "";
  try {
    onNativeProcessStarted?.({
      processId: session.processId,
      processStartedAt: session.processStartedAt
    });
    await session.request("initialize", {
      clientInfo: { name: "agent-control", title: "Agent Control", version: "0.5.17" },
      capabilities: { experimentalApi: true, requestAttestation: false }
    });
    session.notify("initialized", {});
    const params = nativeLaunchParams(
      workspace, resolved.model, resolved.effort, desktopMissionPrompt(task)
    );
    // Every remotely dispatched READY claim gets a fresh native thread. A
    // persisted identity may be used for cleanup, never as a resume target.
    const startedThread = await session.request("thread/start", params.thread);
    sessionId = verifiedNativeThreadStart(startedThread);
    session.threadId = sessionId;
    await session.request(
      "thread/metadata/update",
      nativeThreadMaterializationParams(sessionId)
    );
    await session.request(
      "thread/name/set",
      nativeThreadNameParams(sessionId, task.title)
    );
    await session.request(
      "thread/goal/set",
      nativeThreadGoalParams(sessionId, task.description)
    );
    const turnPrompt = nativeAppServerMissionPrompt(task, sessionId);
    const startedTurn = await session.request("turn/start", {
      threadId: sessionId,
      ...params.turn,
      input: [{ type: "text", text: turnPrompt, text_elements: [] }]
    });
    session.turnId = verifiedNativeTurnStart(startedTurn, sessionId);
    onNativeSessionStarted?.({
      sessionId,
      processId: session.processId,
      processStartedAt: session.processStartedAt
    });
    await waitForVerifiedTranscript(sessionId, workspace, resolved.model, resolved.effort);
    await session.verifyLaunchViability();
    const result: DesktopLaunchResult = {
      accepted: true,
      marker: `AC-${task.id.slice(0, 8)}`,
      sessionId,
      title: task.title,
      // Persistent named app-server threads are the supported task surface.
      // Optional Desktop pin UI state must never invalidate a running mission.
      pinned: false,
      selectedModel,
      selectedEffort,
      expectedModel: resolved.model,
      expectedEffort: resolved.effort,
      model: resolved.model,
      effort: resolved.effort,
      processId: session.processId,
      processStartedAt: session.processStartedAt
    };
    verifyRequestedSessionSettings(task.description, result);
    return result;
  } catch (error) {
    if (!sessionId) {
      nativeSessions.delete(task.id);
      session.close();
      throw error;
    }
    if (!session.turnId) {
      nativeSessions.delete(task.id);
      session.close();
      throw new DesktopPreTurnLaunchError(
        error instanceof Error ? error.message : String(error),
        sessionId
      );
    }
    throw new DesktopLaunchError(
      error instanceof Error ? error.message : String(error),
      sessionId
    );
  }
}

function runWindowsCommand(command: string, args: string[], timeoutMs: number): Promise<{
  code: number;
  stdout: string;
  stderr: string;
}> {
  return new Promise((resolveCommand, reject) => {
    const child = spawn(command, args, { windowsHide: true });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => { stdout += chunk; });
    child.stderr.on("data", (chunk: string) => { stderr += chunk; });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`native_stop_command_timeout:${command}`));
    }, timeoutMs);
    child.once("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once("exit", (code) => {
      clearTimeout(timer);
      resolveCommand({ code: code ?? -1, stdout, stderr });
    });
  });
}

async function windowsProcess(processId: number): Promise<WindowsProcessDetails | undefined> {
  const script = [
    `$process = Get-CimInstance Win32_Process -Filter "ProcessId = ${processId}";`,
    "if ($null -eq $process) { exit 3 };",
    "$process | Select-Object @{n='processId';e={$_.ProcessId}},@{n='name';e={$_.Name}},",
    "@{n='commandLine';e={$_.CommandLine}},@{n='creationDate';e={$_.CreationDate.ToUniversalTime().ToString('o')}} |",
    "ConvertTo-Json -Compress"
  ].join(" ");
  const result = await runWindowsCommand(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", script],
    10_000
  );
  if (result.code === 3) return undefined;
  if (result.code !== 0) {
    throw new Error(
      `native_stop_process_inspection_failed:${redactNativeError(result.stderr.trim() || result.code)}`
    );
  }
  const parsed = JSON.parse(result.stdout.replace(/^\uFEFF/, "").trim()) as WindowsProcessDetails;
  return {
    processId: Number(parsed.processId),
    name: String(parsed.name ?? ""),
    commandLine: String(parsed.commandLine ?? ""),
    creationDate: String(parsed.creationDate ?? "")
  };
}

async function stopPersistedNativeProcess(expected: PersistedNativeProcess): Promise<boolean> {
  const actual = await windowsProcess(expected.processId);
  if (!actual) return true;
  if (!isManagedNativeProcess(actual, expected)) {
    throw new Error(`native_stop_process_identity_mismatch:${expected.processId}`);
  }
  const killed = await runWindowsCommand(
    "taskkill.exe",
    ["/PID", String(expected.processId), "/T", "/F"],
    15_000
  );
  if (killed.code !== 0 && await windowsProcess(expected.processId)) {
    throw new Error(
      `native_stop_process_tree_failed:${redactNativeError(killed.stderr.trim() || killed.code)}`
    );
  }
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    if (!await windowsProcess(expected.processId)) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`native_stop_process_tree_still_running:${expected.processId}`);
}

export type NativeStopCapability = "controllable" | "unavailable";

export function nativeStopCapability(
  threadId: string | undefined,
  turnId: string | undefined
): NativeStopCapability {
  return threadId?.trim() && turnId?.trim() ? "controllable" : "unavailable";
}

export async function stopPinnedDesktopTask(
  _workspace: string,
  taskId: string,
  persistedProcess?: PersistedNativeProcess,
  expectedSessionId?: string,
  terminalTranscriptProven = false
): Promise<boolean> {
  const session = nativeSessions.get(taskId);
  if (!session) {
    return persistedProcess ? await stopPersistedNativeProcess(persistedProcess) : false;
  }
  if (expectedSessionId && session.threadId !== expectedSessionId) {
    throw new Error(
      `native_stop_session_identity_mismatch:expected=${expectedSessionId}:actual=${session.threadId || "missing"}`
    );
  }
  if (terminalTranscriptProven) {
    nativeSessions.delete(taskId);
    session.close();
    return persistedProcess ? await stopPersistedNativeProcess(persistedProcess) : true;
  }
  if (nativeStopCapability(session.threadId, session.turnId) !== "controllable") return false;
  let gracefulStopError: unknown;
  try {
    await session.stop();
  } catch (error) {
    gracefulStopError = error;
  }
  nativeSessions.delete(taskId);
  session.close();
  if (persistedProcess) return await stopPersistedNativeProcess(persistedProcess);
  if (gracefulStopError) throw gracefulStopError;
  return true;
}
