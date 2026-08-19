import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  assertNativeSelectionAvailable, desktopMissionPrompt, nativeAppServerMissionPrompt,
  desktopStopTimeoutMs,
  isManagedNativeProcess, isTerminalNativeTurnStatus, nativeLaunchActivityTimeoutMs,
  nativeLaunchStatusFailure,
  missionResultContract, nativeLaunchParams, nativeThreadMaterializationParams,
  nativeMissionEnvironment, nativeStopParams, nativeThreadDeepLink, nativeThreadGoalParams,
  nativeThreadNameParams, nativeThreadPinned,
  nativeStopCapability, nativeTurnEvent, nativeTurnFailure, nativeTurnStatus, requestedEffort, requestedModel,
  resolveCodexExecutable, resolveNativeSelection,
  verifyRequestedSessionSettings, verifiedNativeThreadStart, verifiedNativeTurnStart
} from "./desktop-launcher.js";

describe("desktopMissionPrompt", () => {
  function runVerificationScript(script: string, userProfile: string) {
    return spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "-"], {
      input: `$ErrorActionPreference = 'Stop'; ${script}`,
      encoding: "utf8",
      env: { ...process.env, USERPROFILE: userProfile }
    });
  }

  it("keeps an understandable title, a trace marker, and the full mission", () => {
    const prompt = desktopMissionPrompt({
      id: "12345678-abcd", title: "Repair synchronization", description: "Fix offline retry behavior",
      status: "IN_PROGRESS", version: 3
    });
    expect(prompt).toContain("Repair synchronization [AC-12345678]");
    expect(prompt).toContain("Agent Control mission:\nFix offline retry behavior");
  });

  it("opens and verifies the requested workspace before creating a task", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(join(root, "..", "scripts", "Start-CodexDesktopTask.ps1"), "utf8");
    const verification = readFileSync(join(root, "..", "scripts", "CodexSessionVerification.ps1"), "utf8");
    expect(script).toContain("AGENT_CONTROL_TASK_MODEL");
    expect(script).toContain("AGENT_CONTROL_TASK_EFFORT");
    expect(script).toContain("$launchArguments += @('-c'");
    expect(script).toContain("model_reasoning_effort");
    expect(script).toContain("CodexSessionVerification.ps1");
    expect(verification).toContain("function Confirm-RequestedSessionSettings");
    expect(verification).toContain("function Resolve-RequestedSessionSetting");
    expect(verification).toContain("Agent Control selection 'default' could not resolve");
    expect(verification).toContain("Codex session settings did not match the requested model/effort");
    expect(verification).toContain("model mismatch");
    expect(verification).toContain("reasoning effort mismatch");
    expect(script).toContain(
      "Wait-Until { Get-CodexWindowForWorkspace -ExpectedWorkspace $workspacePath }"
    );
    expect(script).toContain("Codex Desktop did not open the required workspace");
    expect(script).toContain("function Confirm-SessionWorkspace");
    expect(script).toContain("Codex session workspace did not match the requested task workspace");
    expect(script).toContain("function ConvertTo-NormalizedWorkspacePath");
    expect(script).toContain("[System.IO.Path]::GetFullPath($Path)");
    const launcherSource = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    expect(launcherSource).toContain('session.request("thread/start", params.thread)');
    expect(launcherSource).not.toContain('session.request("thread/resume"');
  });

  it("creates a fresh visible native session for every claimed mission", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcherSource = readFileSync(join(root, "desktop-launcher.ts"), "utf8");

    expect(launcherSource).toContain("const session = new NativeMissionSession(task.id");
    expect(launcherSource).toContain('const startedThread = await session.request("thread/start", params.thread)');
    expect(launcherSource).toContain("Every remotely dispatched READY claim gets a fresh native thread");
    expect(launcherSource).toContain('input: [{ type: "text", text: turnPrompt, text_elements: [] }]');
    expect(launcherSource).not.toContain('session.request("thread/resume"');
    expect(launcherSource).not.toContain("nativeThreadMaterializationParams(_resumeSessionId)");
  });

  it("starts and stops an exact task-owned native turn without Desktop window matching", () => {
    expect(nativeLaunchParams(
      "C:\\AgentControl\\tasks\\task-1",
      "gpt-5.6-terra",
      "high",
      "Do the mission"
    )).toEqual({
      thread: {
        model: "gpt-5.6-terra",
        allowProviderModelFallback: false,
        cwd: "C:\\AgentControl\\tasks\\task-1",
        approvalPolicy: "never",
        sandbox: "danger-full-access",
        ephemeral: false,
        config: { model_reasoning_effort: "high" }
      },
      turn: {
        input: [{ type: "text", text: "Do the mission", text_elements: [] }],
        model: "gpt-5.6-terra",
        effort: "high",
        cwd: "C:\\AgentControl\\tasks\\task-1",
        approvalPolicy: "never",
        sandboxPolicy: { type: "dangerFullAccess" }
      }
    });
    expect(nativeStopParams("thread-1", "turn-1")).toEqual({
      threadId: "thread-1",
      turnId: "turn-1"
    });
  });

  it("materializes a new native thread without creating a bootstrap turn", () => {
    const mission = "Write the exact mission marker once";
    const params = nativeThreadMaterializationParams("thread-1");

    expect(JSON.stringify(params)).not.toContain(mission);
    expect(params).toEqual({
      threadId: "thread-1",
      gitInfo: { branch: "agent-control-pre-turn" }
    });
  });

  it("names the task and activates its durable goal before work starts", () => {
    expect(nativeThreadNameParams("thread-1", "  Repair dashboard lifecycle  ")).toEqual({
      threadId: "thread-1",
      name: "Repair dashboard lifecycle"
    });
    expect(nativeThreadGoalParams("thread-1", "  Finish and verify the mission  ")).toEqual({
      threadId: "thread-1",
      objective: "Finish and verify the mission",
      status: "active"
    });
    expect(() => nativeThreadNameParams("thread-1", "   "))
      .toThrow("desktop_launch_title_missing");
    expect(() => nativeThreadGoalParams("thread-1", "   "))
      .toThrow("desktop_launch_objective_missing");
  });

  it("accepts only a durable non-ephemeral thread/start result", () => {
    expect(verifiedNativeThreadStart({
      thread: { id: "thread-1", ephemeral: false }
    })).toBe("thread-1");
    expect(verifiedNativeThreadStart({ thread: { id: "thread-1" } })).toBe("thread-1");
    expect(() => verifiedNativeThreadStart({ thread: { id: "thread-1", ephemeral: true } }))
      .toThrow("desktop_launch_ephemeral_thread_rejected");
    expect(() => verifiedNativeThreadStart({ thread: {} }))
      .toThrow("desktop_launch_session_id_missing");
  });

  it("accepts only a real turn/start result owned by the fresh thread", () => {
    expect(verifiedNativeTurnStart({
      turn: { id: "turn-1", threadId: "thread-1", status: "inProgress" }
    }, "thread-1")).toBe("turn-1");
    expect(verifiedNativeTurnStart({
      turn: { id: "turn-1" }
    }, "thread-1")).toBe("turn-1");
    expect(() => verifiedNativeTurnStart({
      turn: { id: "turn-1", threadId: "thread-2", status: "inProgress" }
    }, "thread-1")).toThrow("desktop_launch_turn_thread_mismatch");
    expect(() => verifiedNativeTurnStart({
      turn: { id: "turn-1", status: "completed" }
    }, "thread-1")).toThrow("desktop_launch_turn_start_terminal:completed");
    expect(() => verifiedNativeTurnStart({ turn: {} }, "thread-1"))
      .toThrow("desktop_launch_turn_id_missing");
  });

  it("keeps materialization free of user input so the exact mission appears once", () => {
    const mission = "MISSION_TEXT_MUST_APPEAR_ONCE";
    const task = {
      id: "task-prompt-once",
      title: "Prompt once",
      description: mission,
      status: "IN_PROGRESS",
      version: 1
    } as const;
    const combined = [
      JSON.stringify(nativeThreadMaterializationParams("019f610d-dae2-7171-9b28-08e27fdafe11")),
      nativeAppServerMissionPrompt(task, "019f610d-dae2-7171-9b28-08e27fdafe11")
    ].join("\n");

    expect(combined.split(mission)).toHaveLength(2);
  });

  it("runs an exact pinned mission as an adaptive worker so routing hooks cannot swallow it", () => {
    expect(nativeMissionEnvironment("task-1", {
      PATH: "C:\\Windows",
      OPENAI_API_KEY: "must-not-leak",
      CODEX_API_KEY: "must-not-leak",
      AgentControl__OwnerToken: "must-not-leak",
      OWNER_TOKEN: "must-not-leak",
      SERVICE_ACCESS_TOKEN: "must-not-leak",
      SERVICE_PASSWORD: "must-not-leak",
      DATABASE_URL: "postgres://user:password@database.example/private",
      PGURL: "postgres://user:password@database.example/private",
      ARBITRARY_CUSTOM_SETTING: "must-not-be-inherited",
      USERPROFILE: "C:\\Users\\operator",
      CODEX_HOME: "C:\\Users\\operator\\.codex",
      NO_PROXY: "127.0.0.1,localhost",
      HTTPS_PROXY: "https://proxy.example",
      HTTP_PROXY: "https://proxy-user:proxy-pass@proxy.example"
    })).toEqual({
      PATH: "C:\\Windows",
      USERPROFILE: "C:\\Users\\operator",
      CODEX_HOME: "C:\\Users\\operator\\.codex",
      NO_PROXY: "127.0.0.1,localhost",
      HTTPS_PROXY: "https://proxy.example",
      CODEX_ADAPTIVE_WORKER: "1",
      CODEX_ADAPTIVE_TASK_ID: "task-1"
    });
  });

  it("selects the newest installed native Codex binary instead of a stale PATH link", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-codex-"));
    const localAppData = join(root, "local");
    const appData = join(root, "roaming");
    const executableTail = join(
      "node_modules", "@openai", "codex-win32-x64", "vendor",
      "x86_64-pc-windows-msvc", "bin", "codex.exe"
    );
    const installs = [
      {
        packageRoot: join(localAppData, "CodexVersions", "0.143.0", "npm-global", "node_modules", "@openai", "codex"),
        version: "0.143.0"
      },
      {
        packageRoot: join(localAppData, "npm-global", "node_modules", "@openai", "codex"),
        version: "0.144.4"
      }
    ];
    try {
      for (const install of installs) {
        mkdirSync(join(install.packageRoot, dirname(executableTail)), { recursive: true });
        writeFileSync(join(install.packageRoot, "package.json"), JSON.stringify({
          name: "@openai/codex",
          version: install.version
        }));
        writeFileSync(join(install.packageRoot, executableTail), "");
      }

      expect(resolveCodexExecutable({
        LOCALAPPDATA: localAppData,
        APPDATA: appData
      })).toBe(join(installs[1].packageRoot, executableTail));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("fails closed when a native turn ends without real agent output", () => {
    expect(nativeTurnFailure({
      completed: false,
      status: undefined,
      error: undefined,
      hasNativeActivity: false,
      hasAgentOutput: false
    })).toBeUndefined();
    expect(nativeTurnFailure({
      completed: true,
      status: "completed",
      error: undefined,
      hasNativeActivity: true,
      hasAgentOutput: true
    })).toBeUndefined();
    expect(nativeTurnFailure({
      completed: true,
      status: "completed",
      error: undefined,
      hasNativeActivity: false,
      hasAgentOutput: false
    })).toBe("desktop_launch_turn_completed_without_agent_output");
    expect(nativeTurnFailure({
      completed: true,
      status: "interrupted",
      error: undefined,
      hasNativeActivity: false,
      hasAgentOutput: false
    })).toBe("desktop_launch_turn_interrupted");
    expect(nativeTurnFailure({
      completed: true,
      status: "failed",
      error: "model is unavailable",
      hasNativeActivity: false,
      hasAgentOutput: false
    })).toBe("desktop_launch_turn_failed:model is unavailable");
    expect(nativeTurnFailure({
      completed: true,
      status: "cancelled",
      error: undefined,
      hasNativeActivity: true,
      hasAgentOutput: true
    })).toBe("desktop_launch_turn_unaccepted_status:cancelled");
  });

  it("records only substantive activity and preserves events received before turn/start resolves", () => {
    expect(nativeTurnEvent({
      method: "item/started",
      params: { turnId: "turn-1", item: { type: "userMessage" } }
    })).toEqual({ turnId: "turn-1" });
    expect(nativeTurnEvent({
      method: "item/agentMessage/delta",
      params: { turnId: "turn-1", delta: "" }
    })).toEqual({ turnId: "turn-1" });
    expect(nativeTurnEvent({
      method: "item/started",
      params: { turnId: "turn-1", item: { type: "commandExecution" } }
    })).toEqual({ turnId: "turn-1", hasNativeActivity: true });
    expect(nativeTurnEvent({
      method: "item/agentMessage/delta",
      params: { turnId: "turn-1", delta: "Working" }
    })).toEqual({ turnId: "turn-1", hasNativeActivity: true, hasAgentOutput: true });
    expect(nativeTurnEvent({
      method: "turn/completed",
      params: { turn: { id: "turn-1", status: "failed", error: { message: "unsupported model" } } }
    })).toEqual({
      turnId: "turn-1",
      completed: true,
      status: "failed",
      error: "unsupported model"
    });
  });

  it("uses a bounded condition-based launch activity gate", () => {
    expect(nativeLaunchActivityTimeoutMs("15000")).toBe(15_000);
    expect(nativeLaunchActivityTimeoutMs("999")).toBe(30_000);
    expect(nativeLaunchActivityTimeoutMs("invalid")).toBe(30_000);
  });

  it("opens the exact verified native Codex task by its supported deep link", () => {
    expect(nativeThreadDeepLink("019f5e54-dbad-7960-8957-692ac27bc3e8"))
      .toBe("codex://threads/019f5e54-dbad-7960-8957-692ac27bc3e8");
    expect(() => nativeThreadDeepLink("")).toThrow("desktop_launch_session_id_missing");
  });

  it("installs hook configuration as BOM-free JSON so the adapter can always repair it", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const installer = readFileSync(join(root, "..", "Install-AgentControlAdapter.ps1"), "utf8");
    expect(installer).toContain("System.Text.UTF8Encoding($false)");
    expect(installer).not.toContain("Set-Content -LiteralPath $temporary -Encoding UTF8");
  });

  it("activates a rebuilt adapter by safely replacing only its exact idle node process", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const installer = readFileSync(join(root, "..", "Install-AgentControlAdapter.ps1"), "utf8");
    expect(installer).toContain('$PSVersionTable.PSEdition -eq "Core"');
    expect(installer).toContain("System32\\WindowsPowerShell\\v1.0\\powershell.exe");
    expect(installer).toContain("-File $PSCommandPath -ApiUrl $ApiUrl");
    expect(installer).toContain("managedTaskId");
    expect(installer).toContain("legacy idle adapter");
    expect(installer).toContain("Refusing to restart Agent Control while a managed task is active");
    expect(installer).toContain("Refusing to restart Agent Control because authenticated /health/details inspection failed");
    expect(installer).toContain("Invoke-RestMethod -Uri \"http://127.0.0.1:17867/health\"");
    expect(installer).toContain("Get-CimInstance Win32_Process");
    expect(installer).toContain("[System.StringComparison]::OrdinalIgnoreCase");
    expect(installer).toContain("Stop-Process -Id $process.ProcessId -Force");
    expect(installer).toContain("Agent Control adapter health did not recover after installation");
  });

  it("uses Default for legacy missions without a model selection", () => {
    expect(requestedModel("Build it\n\nAgent Control model: gpt-5.6-terra")).toBe("gpt-5.6-terra");
    expect(requestedModel("Agent Control model: default")).toBe("default");
    expect(requestedModel("Agent Control model: gpt-5.6-terra\nAgent Control model: gpt-5.6-sol")).toBeUndefined();
    expect(requestedModel("Agent Control model: made-up-model")).toBeUndefined();
    expect(requestedModel("Build it")).toBe("default");
  });

  it("uses Default for legacy missions without a reasoning effort selection", () => {
    expect(requestedEffort("Agent Control reasoning effort: xhigh")).toBe("xhigh");
    expect(requestedEffort("Agent Control reasoning effort: default")).toBe("default");
    expect(requestedEffort("Agent Control reasoning effort: high\nAgent Control reasoning effort: low")).toBeUndefined();
    expect(requestedEffort("Agent Control reasoning effort: maximum")).toBeUndefined();
    expect(requestedEffort("Build it")).toBe("default");
  });

  it("requires a persistent goal so an ordinary app-server turn boundary cannot end the mission", () => {
    const prompt = desktopMissionPrompt({
      id: "task-persistent",
      title: "Persistent mission",
      description: "Keep working",
      status: "IN_PROGRESS",
      version: 1
    });

    expect(prompt).toContain("call get_goal");
    expect(prompt).toContain("call create_goal");
    expect(prompt).toContain("exact app-server thread and turn");
    expect(prompt).not.toContain("pinned this exact Codex task");
    expect(prompt).toContain("Do not finish an ordinary turn while the mission remains incomplete");
    const launcher = readFileSync(
      join(dirname(fileURLToPath(import.meta.url)), "desktop-launcher.ts"),
      "utf8"
    );
    const goalSet = launcher.indexOf('"thread/goal/set"');
    const turnStart = launcher.indexOf('session.request("turn/start"', goalSet);
    expect(goalSet).toBeGreaterThan(0);
    expect(turnStart).toBeGreaterThan(goalSet);
  });

  it("gives the worker exact app-server session proof without claiming Desktop pin support", () => {
    const prompt = nativeAppServerMissionPrompt({
      id: "task-pinned",
      title: "Pinned mission",
      description: "Verify one marker",
      status: "IN_PROGRESS",
      version: 1
    }, "019f610d-dae2-7171-9b28-08e27fdafe11");

    expect(prompt).toContain("019f610d-dae2-7171-9b28-08e27fdafe11");
    expect(prompt).toContain("APP-SERVER SESSION PROOF");
    expect(prompt).toContain("created or resumed this exact native app-server thread");
    expect(prompt).toContain("Do not call codex_app.set_thread_pinned");
    expect(prompt).toContain("Desktop pinning is not a supported app-server capability");
    expect(prompt).toContain("Agent Control mission:\nVerify one marker");
  });

  it("keeps terminal completion instructions exact and standalone", () => {
    const contract = missionResultContract();
    expect(contract).toContain(
      "Finish your final response with exactly one standalone result marker and no words after it:"
    );
    expect(contract.match(/^AGENT_CONTROL_RESULT: (DONE|WAITING|FAILED)$/gm)).toEqual([
      "AGENT_CONTROL_RESULT: DONE",
      "AGENT_CONTROL_RESULT: WAITING",
      "AGENT_CONTROL_RESULT: FAILED"
    ]);
    expect(contract).toContain("Use DONE only after the requested result is implemented and verified");
  });

  it("treats Desktop state as read-only secondary evidence for the exact native task", () => {
    expect(nativeThreadPinned({
      "pinned-thread-ids": ["thread-a", "thread-b"]
    }, "thread-b")).toBe(true);
    expect(nativeThreadPinned({
      "pinned-thread-ids": ["thread-a", "thread-b"]
    }, "thread-c")).toBe(false);
    expect(nativeThreadPinned({ "pinned-thread-ids": "thread-b" }, "thread-b")).toBe(false);
    expect(nativeThreadPinned(undefined, "thread-b")).toBe(false);
  });

  it("rejects a launched session unless selection, resolved pair, and actual pair all match", () => {
    const description = "Agent Control model: gpt-5.6-terra\nAgent Control reasoning effort: high";
    expect(() => verifyRequestedSessionSettings(description, {
      selectedModel: "gpt-5.6-terra", selectedEffort: "high",
      expectedModel: "gpt-5.6-terra", expectedEffort: "high",
      model: "gpt-5.6-terra", effort: "high"
    })).not.toThrow();
    expect(() => verifyRequestedSessionSettings(description, {
      selectedModel: "gpt-5.6-terra", selectedEffort: "high",
      expectedModel: "gpt-5.6-terra", expectedEffort: "high",
      model: "gpt-5.6-luna", effort: "high"
    })).toThrow("desktop_launch_model_mismatch");
    expect(() => verifyRequestedSessionSettings(description, {
      selectedModel: "gpt-5.6-terra", selectedEffort: "high",
      expectedModel: "gpt-5.6-terra", expectedEffort: "high",
      model: "gpt-5.6-terra", effort: "medium"
    })).toThrow("desktop_launch_effort_mismatch");
  });

  it("accepts Default only when the launcher proves its resolved native settings", () => {
    const description = "Agent Control model: default\nAgent Control reasoning effort: default";
    expect(() => verifyRequestedSessionSettings(description, {
      selectedModel: "default", selectedEffort: "default",
      expectedModel: "gpt-5.6-sol", expectedEffort: "medium",
      model: "gpt-5.6-sol", effort: "medium"
    })).not.toThrow();
    expect(() => verifyRequestedSessionSettings(description, {
      selectedModel: "default", selectedEffort: "default",
      expectedModel: "gpt-5.6-sol", expectedEffort: "medium",
      model: "gpt-5.6-luna", effort: "medium"
    })).toThrow("desktop_launch_model_mismatch");
  });

  it("executes the PowerShell default resolver and native session verifier", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const library = join(root, "..", "scripts", "CodexSessionVerification.ps1");
    const profile = mkdtempSync(join(tmpdir(), "agent-control-pwsh-"));
    const configDirectory = join(profile, ".codex");
    const sessionPath = join(profile, "session.jsonl");
    mkdirSync(configDirectory, { recursive: true });
    writeFileSync(join(configDirectory, "config.toml"), [
      'model = "gpt-5.6-sol"',
      'model_reasoning_effort = "medium"',
      "",
      "[features]",
      "example = true"
    ].join("\n"));
    writeFileSync(sessionPath, [
      JSON.stringify({ type: "session_meta", payload: { cwd: "C:\\work" } }),
      JSON.stringify({ type: "turn_context", payload: { model: "gpt-5.6-sol", effort: "medium" } })
    ].join("\n"));

    try {
      const result = runVerificationScript([
        `. '${library.replaceAll("'", "''")}'`,
        `$configPath = '${join(configDirectory, "config.toml").replaceAll("'", "''")}'`,
        `Set-CodexTopLevelSetting -ConfigPath $configPath -Name model -Value gpt-5.6-terra`,
        `$temporarilyPinnedModel = Resolve-RequestedSessionSetting -Selection default -ConfigName model`,
        `Set-CodexTopLevelSetting -ConfigPath $configPath -Name model -Value gpt-5.6-sol`,
        `$model = Resolve-RequestedSessionSetting -Selection default -ConfigName model`,
        `$effort = Resolve-RequestedSessionSetting -Selection default -ConfigName model_reasoning_effort`,
        `$actual = Confirm-RequestedSessionSettings -SessionPath '${sessionPath.replaceAll("'", "''")}' -ExpectedModel $model -ExpectedEffort $effort`,
        `$mismatch = try { Confirm-RequestedSessionSettings -SessionPath '${sessionPath.replaceAll("'", "''")}' -ExpectedModel gpt-5.6-terra -ExpectedEffort medium; $null } catch { $_.Exception.Message }`,
        `[pscustomobject]@{ pinnedModel = $temporarilyPinnedModel; model = $actual.model; effort = $actual.effort; mismatch = $mismatch } | ConvertTo-Json -Compress`
      ].join("; "), profile);
      expect(result.status, result.stderr).toBe(0);
      expect(JSON.parse(result.stdout.trim())).toEqual({
        pinnedModel: "gpt-5.6-terra",
        model: "gpt-5.6-sol",
        effort: "medium",
        mismatch: expect.stringContaining("model mismatch")
      });
    } finally {
      rmSync(profile, { recursive: true, force: true });
    }
  }, 15_000);

  it("uses only the newest relevant turn_context for native session settings", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const library = join(root, "..", "scripts", "CodexSessionVerification.ps1");
    const profile = mkdtempSync(join(tmpdir(), "agent-control-pwsh-"));
    const sessionPath = join(profile, "session.jsonl");
    writeFileSync(sessionPath, [
      JSON.stringify({ type: "session_meta", payload: { cwd: "C:\\work" } }),
      JSON.stringify({ type: "turn_context", payload: { model: "gpt-5.6-sol", effort: "medium" } }),
      JSON.stringify({ type: "turn_context", payload: { model: "gpt-5.6-terra", effort: "high" } })
    ].join("\n"));

    try {
      const result = runVerificationScript([
        `. '${library.replaceAll("'", "''")}'`,
        `$staleExpectationError = try { Confirm-RequestedSessionSettings -SessionPath '${sessionPath.replaceAll("'", "''")}' -ExpectedModel gpt-5.6-sol -ExpectedEffort medium | Out-Null; $null } catch { $_.Exception.Message }`,
        `$actual = Confirm-RequestedSessionSettings -SessionPath '${sessionPath.replaceAll("'", "''")}' -ExpectedModel gpt-5.6-terra -ExpectedEffort high`,
        `[pscustomobject]@{ model = $actual.model; effort = $actual.effort; staleExpectationError = $staleExpectationError } | ConvertTo-Json -Compress`
      ].join("; "), profile);
      expect(result.status, result.stderr).toBe(0);
      expect(JSON.parse(result.stdout.trim())).toEqual({
        model: "gpt-5.6-terra",
        effort: "high",
        staleExpectationError: expect.stringContaining("model mismatch")
      });
    } finally {
      rmSync(profile, { recursive: true, force: true });
    }
  }, 15_000);

  it("fails closed when the launcher does not report the resolved Default selection", () => {
    expect(() => verifyRequestedSessionSettings("Build it", {
      selectedModel: "", selectedEffort: "",
      expectedModel: "gpt-5.6-sol", expectedEffort: "medium",
      model: "gpt-5.6-sol", effort: "medium"
    })).toThrow("desktop_launch_selection_mismatch");
  });

  it("rejects an exact model or effort that the signed-in native runtime does not advertise", () => {
    const models = [{
      model: "gpt-5.6-terra",
      supportedReasoningEfforts: [{ reasoningEffort: "low" }, { reasoningEffort: "medium" }]
    }];
    expect(() => assertNativeSelectionAvailable("gpt-5.6-terra", "low", models)).not.toThrow();
    expect(() => assertNativeSelectionAvailable("gpt-5.6-sol", "low", models))
      .toThrow("desktop_launch_model_unavailable:gpt-5.6-sol");
    expect(() => assertNativeSelectionAvailable("gpt-5.6-terra", "xhigh", models))
      .toThrow("desktop_launch_effort_unavailable:gpt-5.6-terra:xhigh");
  });

  it("preflights mixed Default selections against their exact configured native pair", () => {
    const models = [{
      model: "gpt-5.6-terra",
      defaultReasoningEffort: "medium",
      supportedReasoningEfforts: [{ reasoningEffort: "low" }, { reasoningEffort: "medium" }]
    }];
    expect(resolveNativeSelection("default", "high", models, "gpt-5.6-terra", "medium"))
      .toEqual({ model: "gpt-5.6-terra", effort: "high" });
    expect(() => assertNativeSelectionAvailable(
      "default", "high", models, "gpt-5.6-terra", "medium"
    )).toThrow("desktop_launch_effort_unavailable:gpt-5.6-terra:high");
    expect(() => assertNativeSelectionAvailable(
      "gpt-5.6-terra", "default", models, "gpt-5.6-terra", "xhigh"
    )).toThrow("desktop_launch_effort_unavailable:gpt-5.6-terra:xhigh");
  });

  it("resolves Dashboard Default from the native catalog without provider fallback", () => {
    const models = [
      {
        model: "gpt-5.6-sol",
        isDefault: true,
        defaultReasoningEffort: "medium",
        supportedReasoningEfforts: [
          { reasoningEffort: "low" },
          { reasoningEffort: "medium" }
        ]
      },
      {
        model: "gpt-5.6-terra",
        defaultReasoningEffort: "high",
        supportedReasoningEfforts: [
          { reasoningEffort: "medium" },
          { reasoningEffort: "high" }
        ]
      }
    ];

    expect(resolveNativeSelection("default", "default", models, "default", "default"))
      .toEqual({ model: "gpt-5.6-sol", effort: "medium" });
    expect(() => assertNativeSelectionAvailable(
      "default", "default", models, "default", "default"
    )).not.toThrow();
    expect(nativeLaunchParams(
      "C:\\AgentControl\\tasks\\task-default",
      "gpt-5.6-sol",
      "medium",
      "Use the exact native catalog default"
    ).thread.allowProviderModelFallback).toBe(false);
  });

  it("reports a confirmed opened-session identifier when a late native proof fails", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(join(root, "..", "scripts", "Start-CodexDesktopTask.ps1"), "utf8");
    expect(script).toContain("sessionOpened = $true");
    expect(script).toContain("error = $_.Exception.Message");
    expect(script).toContain("$newSessionId = $null");
  });

  it("restores every available clipboard format after submitting the mission prompt", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(join(root, "..", "scripts", "Start-CodexDesktopTask.ps1"), "utf8");
    expect(script).toContain("Clipboard]::GetDataObject()");
    expect(script).toContain("GetFormats($true)");
    expect(script).toContain(
      "Clipboard]::SetDataObject($Snapshot.DataObject, $true)"
    );
    expect(script).toContain("Assert-ClipboardSnapshotRestored -Snapshot $Snapshot");
  });

  it("keeps the legacy workspace-label stop helper disabled", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(join(root, "..", "scripts", "Stop-CodexDesktopTask.ps1"), "utf8");
    expect(script).toContain("legacy_desktop_stop_disabled");
    expect(script).not.toContain("Test-WorkspaceLabel");
    expect(script).not.toContain("Find-CodexStopButton");
  });

  it("bounds a stale Desktop stop so reconciliation can continue claiming Ready work", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    expect(launcher).toContain('"turn/interrupt"');
    expect(launcher).toContain("nativeStopParams(this.threadId, this.turnId)");
    expect(launcher).toContain('"thread/read"');
    expect(launcher).toContain("AgentControl__DesktopStopTimeoutMs");
    expect(desktopStopTimeoutMs()).toBe(3_000);
  });

  it("accepts exact-session completion events when thread/read omits the managed turn", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const stopStart = launcher.indexOf("async stop(timeoutMs = desktopStopTimeoutMs())");
    const stopEnd = launcher.indexOf("async verifyLaunchViability", stopStart);
    const stopBody = launcher.slice(stopStart, stopEnd);
    expect(stopBody).toContain('"turn/interrupt"');
    expect(stopBody).toContain("this.readTurnStatus(Math.max(1_000, deadline - Date.now()))");
    expect(stopBody.match(/if \(this\.completed\) return;/g)).toHaveLength(2);
  });

  it("closes a transcript-proven terminal app-server without interrupting its completed turn", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const stopStart = launcher.indexOf("export async function stopPinnedDesktopTask(");
    const stopBody = launcher.slice(stopStart);
    const terminalBranch = stopBody.indexOf("if (terminalTranscriptProven)");
    const interrupt = stopBody.indexOf("await session.stop()");

    expect(terminalBranch).toBeGreaterThan(0);
    expect(terminalBranch).toBeLessThan(interrupt);
    expect(stopBody).toContain("session.close()");
    expect(stopBody).toContain("await stopPersistedNativeProcess(persistedProcess)");
  });

  it("force-closes the exact persisted app-server after the short graceful stop window", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const stopStart = launcher.indexOf("export async function stopPinnedDesktopTask(");
    const stopBody = launcher.slice(stopStart);

    expect(stopBody).toContain("let gracefulStopError: unknown");
    expect(stopBody).toContain("await session.stop()");
    expect(stopBody).toContain("if (persistedProcess) return await stopPersistedNativeProcess(persistedProcess)");
    expect(stopBody.indexOf("await session.stop()"))
      .toBeLessThan(stopBody.lastIndexOf("await stopPersistedNativeProcess(persistedProcess)"));
  });

  it("passes verified terminal transcript evidence into native cleanup", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const server = readFileSync(join(root, "server.ts"), "utf8");
    const stopStart = server.indexOf("async function stopManagedDesktopTask(");
    const stopEnd = server.indexOf("function repairHooks()", stopStart);
    const stopBody = server.slice(stopStart, stopEnd);

    expect(stopBody).toContain("const terminalTranscriptProven = Boolean(");
    expect(stopBody).toContain("hasTerminalTranscript(");
    expect(stopBody).toContain("terminalTranscriptProven\n  ))");
  });

  it("publishes the native process identity before launch verification can block", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const publish = launcher.indexOf("onNativeProcessStarted?.({");
    const initialize = launcher.indexOf('await session.request("initialize"');
    expect(publish).toBeGreaterThan(0);
    expect(publish).toBeLessThan(initialize);
  });

  it("publishes the native session identity immediately after turn start", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const turnStart = launcher.indexOf('await session.request("turn/start"');
    const publish = launcher.indexOf("onNativeSessionStarted?.({");
    const transcriptVerification = launcher.indexOf("await waitForVerifiedTranscript(");
    expect(turnStart).toBeGreaterThan(0);
    expect(publish).toBeGreaterThan(turnStart);
    expect(publish).toBeLessThan(transcriptVerification);
  });

  it("uses authoritative thread status for launch viability", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const verifyStart = launcher.indexOf("async verifyLaunchViability");
    const verifyEnd = launcher.indexOf("\n  close(): void", verifyStart);
    const verifyBody = launcher.slice(verifyStart, verifyEnd);
    expect(verifyBody).toContain("await this.readTurnStatus(timeoutMs)");
    expect(verifyBody).toContain("nativeLaunchStatusFailure");
    expect(verifyBody).not.toContain("state.hasNativeActivity");
    expect(verifyBody).not.toContain("desktop_launch_turn_activity_timeout");
  });

  it("rejects only authoritative launch failure states", () => {
    expect(nativeLaunchStatusFailure()).toBeUndefined();
    expect(nativeLaunchStatusFailure("inProgress")).toBeUndefined();
    expect(nativeLaunchStatusFailure("completed")).toBeUndefined();
    expect(nativeLaunchStatusFailure("failed")).toBe("desktop_launch_turn_failed:native_turn_failed");
    expect(nativeLaunchStatusFailure("interrupted")).toBe("desktop_launch_turn_interrupted");
    expect(nativeLaunchStatusFailure("cancelled")).toBe("desktop_launch_turn_cancelled");
  });

  it("treats every non-running native turn status as conclusive stop proof", () => {
    expect(isTerminalNativeTurnStatus("completed")).toBe(true);
    expect(isTerminalNativeTurnStatus("interrupted")).toBe(true);
    expect(isTerminalNativeTurnStatus("failed")).toBe(true);
    expect(isTerminalNativeTurnStatus("cancelled")).toBe(true);
    expect(isTerminalNativeTurnStatus("inProgress")).toBe(false);
    expect(isTerminalNativeTurnStatus(undefined)).toBe(false);
  });

  it("requires a controllable native turn before reporting stop success", () => {
    expect(nativeStopCapability("", "")).toBe("unavailable");
    expect(nativeStopCapability("thread-1", "")).toBe("unavailable");
    expect(nativeStopCapability("thread-1", "turn-1")).toBe("controllable");
  });

  it("reads the exact managed turn status instead of trusting a racing interrupt response", () => {
    expect(nativeTurnStatus({
      thread: {
        turns: [
          { id: "turn-old", status: "completed" },
          { id: "turn-managed", status: "interrupted" }
        ]
      }
    }, "turn-managed")).toBe("interrupted");
    expect(nativeTurnStatus({ thread: { turns: [] } }, "turn-managed")).toBeUndefined();
  });

  it("recognizes only the exact persisted Codex app-server process after a restart", () => {
    const expected = {
      processId: 1234,
      processStartedAt: "2026-07-14T12:00:00.000Z"
    };
    expect(isManagedNativeProcess({
      processId: 1234,
      name: "codex-x86_64-pc-windows-msvc.exe",
      commandLine: "\"C:\\Program Files\\OpenAI\\codex.exe\" app-server --stdio",
      creationDate: "2026-07-14T12:00:01.000Z"
    }, expected)).toBe(true);
    expect(isManagedNativeProcess({
      processId: 1234,
      name: "codex.exe",
      commandLine: "\"C:\\Program Files\\OpenAI\\codex.exe\" exec",
      creationDate: "2026-07-14T12:00:01.000Z"
    }, expected)).toBe(false);
    expect(isManagedNativeProcess({
      processId: 1234,
      name: "codex.exe",
      commandLine: "\"C:\\Program Files\\OpenAI\\codex.exe\" app-server --stdio",
      creationDate: "2026-07-14T12:10:00.000Z"
    }, expected)).toBe(false);
  });
});
