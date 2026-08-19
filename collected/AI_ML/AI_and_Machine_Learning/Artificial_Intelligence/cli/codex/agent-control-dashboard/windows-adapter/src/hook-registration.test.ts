import { afterEach, describe, expect, it } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { repairHookRegistration } from "./hook-registration.js";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("hook registration self-repair", () => {
  it("removes process hooks while preserving unrelated entries and root settings", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hooks-"));
    roots.push(root);
    const hooksPath = join(root, "hooks.json");
    const hookScript = "C:\\AgentControl\\hooks\\Invoke-AgentControlHook.ps1";
    const unrelated = { hooks: [{ type: "command", command: "other-tool.exe" }] };
    writeFileSync(hooksPath, JSON.stringify({ version: 7, hooks: {
      Stop: [unrelated, { hooks: [{ type: "command", commandWindows: `powershell -File \"${hookScript}\"` }] }],
      Notification: [unrelated]
    } }), "utf8");

    expect(repairHookRegistration(hooksPath, hookScript)).toBe(true);
    const repaired = JSON.parse(readFileSync(hooksPath, "utf8")) as {
      version: number; hooks: Record<string, Array<{ hooks: Array<Record<string, unknown>> }>>;
    };
    expect(repaired.version).toBe(7);
    expect(repaired.hooks.Notification).toEqual([unrelated]);
    expect(repaired.hooks.Stop).toEqual([unrelated]);
    for (const event of ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd"]) {
      expect(JSON.stringify(repaired.hooks[event] ?? [])).not.toContain("Invoke-AgentControlHook.ps1");
    }
    expect(repairHookRegistration(hooksPath, hookScript)).toBe(false);
  });

  it("removes legacy registrations from every lifecycle event", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hooks-"));
    roots.push(root);
    const hooksPath = join(root, "hooks.json");
    const legacy = { hooks: [{ type: "command", command: "powershell -File Invoke-AgentControlHook.ps1" }] };
    writeFileSync(hooksPath, JSON.stringify({ hooks: {
      SessionStart: [legacy],
      UserPromptSubmit: [legacy],
      PostToolUse: [legacy],
      Stop: [legacy],
      SessionEnd: [legacy]
    } }), "utf8");
    expect(repairHookRegistration(hooksPath, "C:\\AgentControl\\Invoke-AgentControlHook.ps1")).toBe(true);
    const hooks = (JSON.parse(readFileSync(hooksPath, "utf8")) as { hooks: Record<string, unknown[]> }).hooks;
    for (const event of ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd"]) {
      expect(hooks[event]).toEqual([]);
    }
  });

  it("repairs a UTF-8 BOM-prefixed hooks document", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hooks-bom-"));
    roots.push(root);
    const hooksPath = join(root, "hooks.json");
    writeFileSync(hooksPath, `\uFEFF${JSON.stringify({ hooks: { Stop: [] } })}`, "utf8");

    expect(repairHookRegistration(hooksPath, "C:\\AgentControl\\Invoke-AgentControlHook.ps1")).toBe(true);
    const repaired = readFileSync(hooksPath, "utf8");
    expect(repaired.charCodeAt(0)).not.toBe(0xfeff);
    expect(JSON.parse(repaired).hooks.Stop).toHaveLength(0);
  });

  it("rewrites an otherwise canonical BOM-prefixed hooks document", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hooks-bom-canonical-"));
    roots.push(root);
    const hooksPath = join(root, "hooks.json");
    const hookScript = "C:\\AgentControl\\Invoke-AgentControlHook.ps1";
    repairHookRegistration(hooksPath, hookScript);
    writeFileSync(hooksPath, `\uFEFF${readFileSync(hooksPath, "utf8")}`, "utf8");

    expect(repairHookRegistration(hooksPath, hookScript)).toBe(true);
    expect(readFileSync(hooksPath, "utf8").charCodeAt(0)).not.toBe(0xfeff);
  });

  it("emits the SessionStart result contract as valid hook JSON in PowerShell 5", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-runtime-"));
    roots.push(root);
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({ hook_event_name: "SessionStart", session_id: "runtime-contract" }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });
    expect(result.status, result.stderr).toBe(0);
    const output = JSON.parse(result.stdout.trim()) as {
      continue: boolean;
      hookSpecificOutput: { hookEventName: string; additionalContext: string };
    };
    expect(output.continue).toBe(true);
    expect(output.hookSpecificOutput.hookEventName).toBe("SessionStart");
    expect(output.hookSpecificOutput.additionalContext).toContain("AGENT_CONTROL_RESULT: DONE");
    expect(output.hookSpecificOutput.additionalContext).toContain("AGENT_CONTROL_RESULT: WAITING");
    expect(output.hookSpecificOutput.additionalContext).toContain("AGENT_CONTROL_RESULT: FAILED");
  }, 15_000);

  it("writes only sanitized fallback hook JSON when the local receiver is unavailable", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-sanitized-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const ownerToken = "powershell-owner-token";
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "PostToolUse",
        session_id: "runtime-private",
        cwd: "C:\\Users\\operator\\private-repository",
        owner_token: ownerToken,
        note: '{"OPENAI_API_KEY":"openai-hook-value","client_secret":"client-hook-value","AWS_SECRET_ACCESS_KEY":"aws-hook-value","providerCredentials":"provider-hook-value"}',
        tool_output: `Private output ${ownerToken}`
      }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__OwnerToken: ownerToken,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    const fallback = readFileSync(fallbackPath, "utf8");
    expect(fallback).not.toContain(ownerToken);
    expect(fallback).not.toContain("C:\\\\Users\\\\operator");
    expect(fallback).not.toContain("Private output");
    expect(fallback).not.toContain("openai-hook-value");
    expect(fallback).not.toContain("client-hook-value");
    expect(fallback).not.toContain("aws-hook-value");
    expect(fallback).not.toContain("provider-hook-value");
    expect(fallback).toContain("detailed output retained only");
  }, 15_000);

  it("redacts the DPAPI owner token from arbitrary fallback payload text", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-dpapi-"));
    roots.push(root);
    const credentialRoot = join(root, "credentials");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const credentialScript = join(dirname(fileURLToPath(import.meta.url)), "..", "scripts", "AgentControlCredential.ps1");
    const ownerToken = "dpapi-owner-token";
    const writeToken = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
      `. '${credentialScript}'; Write-AgentControlOwnerToken -Root '${credentialRoot}' -Token '${ownerToken}'`
    ], {
      encoding: "utf8",
      timeout: 15_000
    });
    expect(writeToken.status, writeToken.stderr).toBe(0);

    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-CredentialRoot", credentialRoot
    ], {
      input: JSON.stringify({
        hook_event_name: "PostToolUse",
        session_id: "runtime-dpapi",
        note: `Unexpected output ${ownerToken}`
      }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__OwnerToken: "",
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    const fallback = readFileSync(fallbackPath, "utf8");
    expect(fallback).not.toContain(ownerToken);
    expect(fallback).toContain("[REDACTED]");
  }, 15_000);

  it("redacts complete quoted whitespace credential values before fallback persistence", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-quoted-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "SessionStart",
        session_id: "runtime-quoted",
        note: 'owner_token="quoted owner token with spaces" api_key=\'quoted api key with spaces\''
      }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__OwnerToken: "",
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    const fallback = readFileSync(fallbackPath, "utf8");
    expect(fallback).toContain('owner_token=\\"[REDACTED]\\"');
    expect(fallback).toContain("api_key=\\u0027[REDACTED]\\u0027");
    expect(fallback).not.toContain("quoted owner token with spaces");
    expect(fallback).not.toContain("quoted api key with spaces");
  }, 15_000);

  it("does not persist malformed hook input when the local receiver is unavailable", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-malformed-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: '{"owner_token":"raw-secret"',
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(existsSync(fallbackPath)).toBe(false);
  }, 15_000);

  it("rejects oversized hook input before it can reach fallback storage", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-oversize-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "PostToolUse",
        session_id: "runtime-oversize",
        note: "x".repeat(70_000)
      }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe('{"continue":true}');
    expect(existsSync(fallbackPath)).toBe(false);
  }, 15_000);

  it("rotates fallback storage instead of appending without a bound", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-rotate-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    mkdirSync(dirname(fallbackPath), { recursive: true });
    writeFileSync(fallbackPath, "x".repeat(4 * 1024 * 1024), "utf8");
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "SessionStart",
        session_id: "runtime-rotate"
      }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(readFileSync(fallbackPath, "utf8")).toContain("runtime-rotate");
    expect(readdirSync(dirname(fallbackPath)).some((name) =>
      /^fallback\.jsonl\.segment-\d{8}\.jsonl$/.test(name)
    )).toBe(true);
    expect(readFileSync(fallbackPath).byteLength).toBeLessThan(64 * 1024);
  }, 15_000);

  it("retains an ordered bounded segment spool across sustained outage rotations", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-segments-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    mkdirSync(dirname(fallbackPath), { recursive: true });

    for (let index = 0; index < 10; index += 1) {
      writeFileSync(join(dirname(fallbackPath), `fallback.jsonl.segment-${index.toString().padStart(8, "0")}.jsonl`), "x", "utf8");
    }
    writeFileSync(fallbackPath, "x".repeat(4 * 1024 * 1024), "utf8");
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "SessionEnd",
        session_id: "runtime-segmented",
        event_id: "segment-terminal"
      }),
      encoding: "utf8",
      timeout: 30_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
        AgentControl__HookFallbackPath: fallbackPath
      }
    });
    expect(result.status, result.stderr).toBe(0);

    const segmentFiles = readdirSync(dirname(fallbackPath))
      .filter((name) => name.startsWith("fallback.jsonl.segment-"))
      .sort();
    expect(segmentFiles.length).toBeGreaterThan(1);
    expect(segmentFiles.length).toBeLessThanOrEqual(8);
    expect(readFileSync(fallbackPath, "utf8")).toContain("segment-terminal");
    expect(segmentFiles[0]).toMatch(/segment-\d{8}\.jsonl$/);
  }, 120_000);

  it("coalesces low-value activity with a privacy-safe drop marker and preserves terminal events", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-coalesce-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const env = {
      ...process.env,
      AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
      AgentControl__HookFallbackPath: fallbackPath
    };
    for (let index = 0; index < 4; index += 1) {
      const result = spawnSync("powershell.exe", [
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
      ], {
        input: JSON.stringify({
          hook_event_name: "PostToolUse",
          session_id: "runtime-coalesce",
          event_id: `activity-${index}`,
          tool_name: "same-tool"
        }),
        encoding: "utf8",
        timeout: 15_000,
        env
      });
      expect(result.status, result.stderr).toBe(0);
    }
    const terminal = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({
        hook_event_name: "SessionEnd",
        session_id: "runtime-coalesce",
        event_id: "terminal-1"
      }),
      encoding: "utf8",
      timeout: 15_000,
      env
    });
    expect(terminal.status, terminal.stderr).toBe(0);
    const contents = readFileSync(fallbackPath, "utf8");
    expect(contents).toContain('"hook_event_name":"SessionEnd"');
    expect(contents).toContain("dropped_low_value_activity");
    expect(contents.length).toBeLessThan(256 * 1024);
  }, 120_000);

  it("serializes concurrent writers without losing terminal events or corrupting JSONL", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-concurrent-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const fallbackPath = join(process.env.LOCALAPPDATA!, "AgentControl", `test-${randomUUID()}`, "fallback.jsonl");
    roots.push(dirname(fallbackPath));
    const env = {
      ...process.env,
      AgentControl__HookEndpoint: "http://127.0.0.1:1/hooks",
      AgentControl__HookFallbackPath: fallbackPath
    };
    const children = Array.from({ length: 4 }, (_, index) => {
      const child = spawnSync("powershell.exe", [
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
      ], {
        input: JSON.stringify({
          hook_event_name: index === 3 ? "Stop" : "PostToolUse",
          session_id: "runtime-concurrent",
          event_id: `concurrent-${index}`
        }),
        encoding: "utf8",
        timeout: 30_000,
        env
      });
      return child;
    });
    expect(children.every((child) => child.status === 0)).toBe(true);
    const files = readdirSync(dirname(fallbackPath))
      .filter((name) => name.includes("fallback.jsonl"))
      .map((name) => join(dirname(fallbackPath), name));
    const lines = files.flatMap((file) => readFileSync(file, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean));
    expect(lines.length).toBeGreaterThanOrEqual(4);
    expect(lines.map((line) => JSON.parse(line)).some((payload) => payload.event_id === "concurrent-3")).toBe(true);
  }, 120_000);

  it("ignores off-host endpoint and out-of-root fallback overrides", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-override-"));
    roots.push(root);
    const script = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "Invoke-AgentControlHook.ps1");
    const forbiddenFallback = join(root, "forbidden.jsonl");
    const result = spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script
    ], {
      input: JSON.stringify({ hook_event_name: "SessionStart", session_id: "override-guard" }),
      encoding: "utf8",
      timeout: 15_000,
      env: {
        ...process.env,
        AgentControl__HookEndpoint: "https://example.invalid/hooks",
        AgentControl__HookFallbackPath: forbiddenFallback
      }
    });

    expect(result.status, result.stderr).toBe(0);
    expect(existsSync(forbiddenFallback)).toBe(false);
  }, 15_000);
});
