import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  DesktopPreTurnLaunchError,
  invokeNativeDesktopPinHelper,
  nativeDesktopPinCommand,
  parseNativeDesktopPinResult
} from "./desktop-launcher.js";

const sessionId = "019f610d-dae2-7171-9b28-08e27fdafe11";

function functionSection(source: string, name: string): string {
  const start = source.indexOf(`function ${name}`);
  expect(start, `missing PowerShell function ${name}`).toBeGreaterThanOrEqual(0);
  const next = source.indexOf("\nfunction ", start + 1);
  return source.slice(start, next < 0 ? source.length : next);
}

describe("native Desktop pin helper", () => {
  it("builds a PS5 STA command with a secret-free child environment", () => {
    const command = nativeDesktopPinCommand(sessionId, {
      PATH: "C:\\Windows",
      USERPROFILE: "C:\\Users\\operator",
      LOCALAPPDATA: "C:\\Users\\operator\\AppData\\Local",
      OPENAI_API_KEY: "must-not-leak",
      AgentControl__OwnerToken: "must-not-leak",
      DATABASE_URL: "postgres://user:password@host/database",
      VERCEL_TOKEN: "must-not-leak",
      GITHUB_TOKEN: "must-not-leak",
      HTTPS_PROXY: "https://proxy.example",
      HTTP_PROXY: "https://user:password@proxy.example"
    });

    expect(command.executable).toBe("powershell.exe");
    expect(command.args).toEqual([
      "-NoProfile",
      "-NonInteractive",
      "-STA",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      expect.stringMatching(/Pin-CodexDesktopTask\.ps1$/),
      "-SessionId",
      sessionId
    ]);
    expect(command.windowsHide).toBe(true);
    expect(command.timeoutMs).toBe(180_000);
    expect(command.env).toEqual({
      PATH: "C:\\Windows",
      USERPROFILE: "C:\\Users\\operator",
      LOCALAPPDATA: "C:\\Users\\operator\\AppData\\Local",
      HTTPS_PROXY: "https://proxy.example"
    });
  });

  it("accepts only the exact compact helper result", () => {
    expect(parseNativeDesktopPinResult(
      `{"sessionId":"${sessionId}","routeVerified":true,"pinned":true}\r\n`,
      sessionId
    )).toEqual({ sessionId, routeVerified: true, pinned: true });

    expect(() => parseNativeDesktopPinResult(
      `noise\n{"sessionId":"${sessionId}","routeVerified":true,"pinned":true}`,
      sessionId
    )).toThrow("desktop_pin_helper_output_invalid");
    expect(() => parseNativeDesktopPinResult(
      '{"sessionId":"different","routeVerified":true,"pinned":true}',
      sessionId
    )).toThrow("desktop_pin_helper_session_mismatch");
    expect(() => parseNativeDesktopPinResult(
      `{"sessionId":"${sessionId}","routeVerified":false,"pinned":true}`,
      sessionId
    )).toThrow("desktop_pin_helper_route_unverified");
    expect(() => parseNativeDesktopPinResult(
      `{"sessionId":"${sessionId}","routeVerified":true,"pinned":false}`,
      sessionId
    )).toThrow("desktop_pin_helper_pin_unverified");
  });

  it("parses successful execution and rejects process failures", async () => {
    let captured: ReturnType<typeof nativeDesktopPinCommand> | undefined;
    expect(await invokeNativeDesktopPinHelper(sessionId, {
      parentEnv: { PATH: "C:\\Windows", OPENAI_API_KEY: "must-not-leak" },
      run: async (command) => {
        captured = command;
        return {
          code: 0,
          stdout: `{"sessionId":"${sessionId}","routeVerified":true,"pinned":true}\n`,
          stderr: ""
        };
      }
    })).toEqual({ sessionId, routeVerified: true, pinned: true });
    expect(captured?.env).toEqual({ PATH: "C:\\Windows" });

    await expect(invokeNativeDesktopPinHelper(sessionId, {
      run: async () => ({ code: 1, stdout: "", stderr: "helper failed" })
    })).rejects.toThrow("desktop_pin_helper_failed:helper failed");
    await expect(invokeNativeDesktopPinHelper(sessionId, {
      run: async () => ({
        code: -1,
        stdout: "",
        stderr: "desktop_pin_helper_timeout"
      })
    })).rejects.toThrow("desktop_pin_helper_failed:desktop_pin_helper_timeout");
    await expect(invokeNativeDesktopPinHelper(sessionId, {
      run: async () => ({
        code: 1,
        stdout: "",
        stderr: 'rpc failed: owner_token="quoted owner token with spaces"'
      })
    })).rejects.toThrow(
      'desktop_pin_helper_failed:rpc failed: owner_token="[REDACTED]"'
    );
  });

  it("defines a recoverable pre-turn error with the exact session id", () => {
    const error = new DesktopPreTurnLaunchError("desktop_pin_helper_failed", sessionId);
    expect(error.name).toBe("DesktopPreTurnLaunchError");
    expect(error.sessionId).toBe(sessionId);
    expect(error.message).toBe("desktop_pin_helper_failed");
  });

  it("creates one isolated helper window through the native app command before routing", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(
      join(root, "..", "scripts", "Pin-CodexDesktopTask.ps1"),
      "utf8"
    );

    expect(script).toContain("'File'");
    expect(script).toContain("'New Window'");
    expect(script).toContain("'Task actions'");
    expect(script).toContain("'Copy'");
    expect(script).toContain("'Copy Session ID'");
    expect(script).toContain("'Pin task'");
    expect(script).toContain("'Unpin task'");
    expect(script).toContain("GetFormats($true)");
    expect(script).toContain("System.Windows.Forms.DataObject");
    expect(script).toContain("Clipboard]::SetDataObject");
    expect(script).toContain("PostMessage");
    expect(script).toContain("Set-UiaFocusWithinWindow");
    expect(script).toContain("Test-AutomationElementWithinWindow");
    expect(script).toContain("GetRuntimeId");
    expect(script).toContain("Start-CodexDesktopIfNeeded");
    expect(script).toContain("Get-ArgumentFreePackagedDesktopProcess");
    expect(script).toContain("New-IsolatedDesktopWindow");
    expect(script).toContain("[AllowEmptyCollection()]");
    expect(script).toContain("$candidateState.NewHandles.Count -ne 1");
    expect(script).toContain("$helperCreationState.ObservedNewHandles");
    expect(script).toContain("$cleanupHelperHandle");
    expect(script).not.toContain("'Open in new window'");
    expect(script).not.toContain("Open-DesktopThreadRoute");
    expect(script).not.toContain("Get-CurrentDesktopRoute");
    expect(script).not.toContain("Restore-DesktopRoute");
    expect(script).not.toContain("Restore-ChangedDesktopRoutes");
    expect(script).not.toContain("Confirm-DesktopRouteUnchanged");
    expect(script).toContain("ExpandCollapseState");
    expect(script).toContain(".Collapse()");
    expect(script).toContain("for ($attempt = 0; $attempt -lt 3; $attempt++)");
    expect(script).toContain("SelectionItemPattern");
    expect(script).not.toContain("LegacyIAccessiblePattern");
    const mainStart = script.indexOf("$desktopState = Start-CodexDesktopIfNeeded");
    const openNewWindow = script.indexOf("$helperHandle = New-IsolatedDesktopWindow", mainStart);
    const helperReady = script.indexOf(
      "Set-UiaFocusWithinWindow -WindowHandle $helperHandle",
      openNewWindow
    );
    const route = script.indexOf('Start-Process -FilePath "codex://threads/$SessionId"', helperReady);
    expect(openNewWindow).toBeGreaterThan(mainStart);
    expect(helperReady).toBeGreaterThan(openNewWindow);
    expect(route).toBeGreaterThan(helperReady);
    expect(script).toContain("Desktop did not create exactly one isolated helper window");
    expect(script).not.toContain("SendWait('^+n')");
    expect(script).not.toMatch(/SendKeys|SendInput|keybd_event|mouse_event/);
    expect(script).not.toContain("AttachThreadInput");
    expect(script).not.toMatch(/Set-Content|Add-Content|Out-File|WriteAllText|WriteAllBytes/);
  });

  it("verifies shared GUI handoff with an exact clipboard route probe before pinning", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(
      join(root, "..", "scripts", "Pin-CodexDesktopTask.ps1"),
      "utf8"
    );
    const routeProbe = functionSection(script, "Get-ExactSessionIdFromWindow");

    expect(routeProbe).toContain(
      '$probe = "agent-control-route-probe-$([Guid]::NewGuid().ToString(\'N\'))"'
    );
    expect(routeProbe).toContain("[System.Windows.Forms.Clipboard]::SetText($probe)");
    expect(routeProbe).toContain("-ItemName 'Copy Session ID'");
    expect(routeProbe).toContain("return $state.Value -ne $probe");
    expect(routeProbe).toContain("$state.Value -notmatch '^[0-9a-fA-F-]{36}$'");
    expect(routeProbe).toContain("did not expose an exact native session ID");

    const routeStart = script.indexOf('Start-Process -FilePath "codex://threads/$SessionId"');
    const routeProbeCall = script.indexOf("Get-ExactSessionIdFromWindow", routeStart);
    const pinAttempt = script.indexOf("-ItemName 'Pin task'", routeProbeCall);
    expect(routeStart).toBeGreaterThan(0);
    expect(routeProbeCall).toBeGreaterThan(routeStart);
    expect(pinAttempt).toBeGreaterThan(routeProbeCall);
  });

  it("passes persisted process identity when rejecting an opened native session", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const server = readFileSync(join(root, "server.ts"), "utf8");
    const rejectionBranch = server.indexOf(
      "if (error instanceof DesktopLaunchError && error.sessionId)"
    );
    const stopCall = server.indexOf("await stopPinnedDesktopTask(", rejectionBranch);
    const rejectionReport = server.indexOf("await rejectTaskLaunch(", stopCall);
    expect(rejectionBranch).toBeGreaterThan(0);
    expect(stopCall).toBeGreaterThan(rejectionBranch);
    expect(server.slice(rejectionBranch, stopCall)).toContain(
      "const persistedProcess = store.managedProcessForTask(task.id)"
    );
    expect(server.slice(stopCall, rejectionReport)).toContain("persistedProcess");
  });

  it("retains an opened native session when cleanup fails before its stop is confirmed", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const server = readFileSync(join(root, "server.ts"), "utf8");
    const rejectionBranch = server.indexOf(
      "if (error instanceof DesktopLaunchError && error.sessionId)"
    );
    const rejectionReport = server.indexOf("await rejectTaskLaunch(", rejectionBranch);
    const cleanupCatch = server.indexOf("} catch (stopError) {", rejectionReport);

    expect(rejectionBranch).toBeGreaterThan(0);
    expect(rejectionReport).toBeGreaterThan(rejectionBranch);
    expect(cleanupCatch).toBeGreaterThan(rejectionReport);
    expect(server.slice(rejectionBranch, rejectionReport)).toContain(
      "let nativeStopConfirmed = false"
    );
    expect(server.slice(rejectionBranch, rejectionReport)).toContain(
      "nativeStopConfirmed = true"
    );
    expect(server.slice(cleanupCatch, cleanupCatch + 300)).toContain(
      "queueRejectedTaskLaunch(store, task, error.message, !nativeStopConfirmed)"
    );
  });

  it("keeps per-button verification exact and confines GUI fallback to Copy Session ID", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const script = readFileSync(
      join(root, "..", "scripts", "Pin-CodexDesktopTask.ps1"),
      "utf8"
    );
    const openExactMenuItem = functionSection(script, "Open-ExactMenuItem");
    const getTaskAction = functionSection(script, "Get-TaskAction");

    expect(openExactMenuItem).toContain("Get-UniqueVisibleExactElement");
    expect(openExactMenuItem).toContain("-Name $ButtonName");
    expect(openExactMenuItem).toContain("-Name $ItemName");
    expect(openExactMenuItem).toContain("-MenuItemOnly");
    expect(openExactMenuItem).toContain(
      "The native '$ItemName' action did not appear under '$ButtonName'."
    );

    expect(getTaskAction).toContain("if ($ItemName -ne 'Copy Session ID')");
    expect(getTaskAction).toContain("-ButtonName 'Task actions'");
    expect(getTaskAction).toContain("-ItemName $ItemName");
    expect(getTaskAction).toContain("-Name 'Copy'");
    expect(getTaskAction).toContain("-Name 'Copy Session ID'");
    expect(getTaskAction).toContain("The native 'Copy Session ID' action did not appear.");
    expect(getTaskAction).not.toContain("-ButtonName 'Copy'");
  });

  it("names and activates the persistent native task before starting its turn", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const threadStart = launcher.indexOf('session.request("thread/start"');
    const materialized = launcher.indexOf(
      '"thread/metadata/update"',
      threadStart
    );
    const launchEnd = launcher.indexOf("export function nativeStopCapability", threadStart);
    const launchBody = launcher.slice(threadStart, launchEnd);
    const missionTurnStart = launcher.indexOf(
      'session.request("turn/start"',
      materialized
    );
    const taskName = launcher.indexOf('"thread/name/set"', materialized);
    const taskGoal = launcher.indexOf('"thread/goal/set"', taskName);

    expect(threadStart).toBeGreaterThan(0);
    expect(materialized).toBeGreaterThan(threadStart);
    expect(taskName).toBeGreaterThan(materialized);
    expect(taskGoal).toBeGreaterThan(taskName);
    expect(missionTurnStart).toBeGreaterThan(taskGoal);
    expect(launchBody).toContain("nativeAppServerMissionPrompt(task, sessionId)");
    expect(launchBody).toContain("pinned: false");
    expect(launchBody).not.toContain("invokeNativeDesktopPinHelper(sessionId)");
    expect(launchBody).toContain('session.request("thread/start", params.thread)');
    expect(launchBody).not.toContain('session.request("thread/resume"');
    expect(launcher).not.toContain("nativeBootstrapTurnParams");
    expect(launcher).not.toContain("waitForBootstrapMaterialization");
    expect(launcher).not.toContain("settleBootstrapTurn");
    expect(launcher).toContain('version: "0.5.17"');
    expect(launcher).not.toContain('version: "0.5.16"');
    expect(launcher).not.toContain("pinNativeThreadState");
    expect(launcher).not.toContain("stabilizeNativeThreadPin");
    expect(launcher).not.toContain("waitForNativeThreadPin");
    expect(launcher).not.toContain("openVerifiedNativeThread");
    expect(launcher).not.toContain('spawn("explorer.exe"');
    expect(launcher).not.toContain('session.request("thread/settings/update"');
  });

  it("rejects terminal turn/start responses before accepting the task launch", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const launcher = readFileSync(join(root, "desktop-launcher.ts"), "utf8");
    const turnStart = launcher.indexOf('session.request("turn/start"');
    const launchEnd = launcher.indexOf("const result: DesktopLaunchResult", turnStart);
    const launchBody = launcher.slice(turnStart, launchEnd);

    expect(launchBody).toContain("verifiedNativeTurnStart(startedTurn, sessionId)");
    expect(launchBody).toContain("await waitForVerifiedTranscript");
    expect(launchBody).toContain("await session.verifyLaunchViability()");
    expect(launchEnd).toBeGreaterThan(turnStart);
  });

  it("rejects a pre-turn app-server failure without persisting a resume target", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const server = readFileSync(join(root, "server.ts"), "utf8");
    const preTurnBranch = server.indexOf("if (error instanceof DesktopPreTurnLaunchError)");
    const rejectRecoverable = server.indexOf(
      "await rejectTaskLaunch(apiUrl, ownerToken, task, error.message)",
      preTurnBranch
    );
    const liveTurnBranch = server.indexOf(
      "if (error instanceof DesktopLaunchError && error.sessionId)",
      rejectRecoverable
    );

    expect(preTurnBranch).toBeGreaterThan(0);
    expect(rejectRecoverable).toBeGreaterThan(preTurnBranch);
    expect(liveTurnBranch).toBeGreaterThan(rejectRecoverable);
    expect(server).not.toContain(
      "store.saveResumableSession("
    );
  });
});
