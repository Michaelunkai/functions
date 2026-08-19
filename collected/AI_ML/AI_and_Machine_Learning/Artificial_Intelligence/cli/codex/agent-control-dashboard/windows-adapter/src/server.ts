import { homedir, hostname } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync, readdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { AdapterStore } from "./store.js";
import {
  acknowledgeNativeStop, claimTask, flushOutbox, flushPendingStopAcknowledgements,
  markPendingLaunchRejectionNativeStopCompleted,
  pendingLaunchRejectionRequiresNativeStop,
  queueRejectedTaskLaunch, rejectTaskLaunch,
  reconcileManagedTasks, registerAgent, sendHeartbeat,
  type ClaimedTask, updateTaskStage
} from "./sync.js";
import { importHookFallbackFiles } from "./fallback.js";
import { createAdapterHttpServer } from "./http-server.js";
import { executeTask } from "./executor.js";
import {
  DesktopLaunchError,
  DesktopPreTurnLaunchError,
  stopPinnedDesktopTask
} from "./desktop-launcher.js";
import { stopOpenedSessionBeforeBinding } from "./launch-race.js";
import { repairHookRegistration } from "./hook-registration.js";
import { readHookSecret, readOwnerToken } from "./credential-reader.js";
import {
  extractTranscriptActivityRecords,
  findTerminalTranscript,
  hasTerminalTranscript,
  redactTranscriptText
} from "./transcript-activity.js";
import { TranscriptAppendReader } from "./transcript-reader.js";
import {
  controlPlanePollMillis,
  heartbeatIntervalMillis,
  intervalDue,
  maxClaimsPerPoll,
  maxConcurrentSessions,
  reconciliationIntervalMillis,
  registrationRetryMillis
} from "./polling-policy.js";

const dataRoot = process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local");
const agentControlRoot = join(dataRoot, "AgentControl");
const ownerToken = readOwnerToken();
const hookSecret = readHookSecret();
const configuredApiUrl = process.env.AgentControl__ApiUrl?.trimEnd();
if (!configuredApiUrl) {
  throw new Error("Agent Control API URL is unavailable.");
}
const apiUrl: string = configuredApiUrl;
const store = new AdapterStore(join(agentControlRoot, "adapter.db"), [ownerToken]);
const fallbackPath = join(agentControlRoot, "hook-fallback.jsonl");
const taskRoot = join(agentControlRoot, "tasks");
const hooksPath = join(homedir(), ".codex", "hooks.json");
const codexSessionsPath = join(homedir(), ".codex", "sessions");
const hookScriptPath = fileURLToPath(new URL("../hooks/Invoke-AgentControlHook.ps1", import.meta.url));
const agentId = process.env.AgentControl__AgentId ?? `windows-${hostname().toLowerCase()}`;
let registered = false;
let syncInProgress = false;
let reconciliationInProgress = false;
let lastRegistrationAttemptAt = 0;
let lastHeartbeatAttemptAt = 0;
let lastReconciliationAttemptAt = 0;
const CONTROL_PLANE_POLL_MILLIS = controlPlanePollMillis();
const HEARTBEAT_INTERVAL_MILLIS = heartbeatIntervalMillis();
const REGISTRATION_RETRY_MILLIS = registrationRetryMillis();
const RECONCILIATION_INTERVAL_MILLIS = reconciliationIntervalMillis();
const MAX_CONCURRENT_SESSIONS = maxConcurrentSessions();
const MAX_CLAIMS_PER_POLL = maxClaimsPerPoll();
type LaunchState = {
  stopRequested: boolean;
  sessionOpened: boolean;
  launchFailed: boolean;
};
const launches = new Map<string, LaunchState>();
const transcriptPaths = new Map<string, string>();
const transcriptReader = new TranscriptAppendReader();

function workspaceForTask(taskId: string): string {
  return join(taskRoot, taskId.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120));
}

/**
 * A task can be relisted while its Desktop window is still opening. Keep the
 * managed record until that launch observes the stop request; otherwise a
 * late-opened session could be orphaned after the owner has stopped it.
 */
async function stopManagedDesktopTask(
  taskId: string,
  expectedSessionId?: string
): Promise<boolean> {
  const launch = launches.get(taskId);
  if (launch) {
    // Propagate the stop before consulting durable acknowledgements. A
    // relisted task may already have a queued acknowledgement while its
    // replacement launch is still opening.
    launch.stopRequested = true;
  }
  const acknowledge = async (message: string): Promise<boolean> => {
    const accepted = await acknowledgeNativeStop(apiUrl, ownerToken, taskId, message);
    if (accepted) store.clearPendingStopAcknowledgement(taskId);
    return accepted;
  };
  const pendingAcknowledgement = store.pendingStopAcknowledgement(taskId);
  const protectedLaunchRejection = pendingAcknowledgement !== undefined &&
    pendingLaunchRejectionRequiresNativeStop(pendingAcknowledgement);
  if (pendingAcknowledgement && !protectedLaunchRejection) {
    return await acknowledge(pendingAcknowledgement);
  }

  const boundSession = store.managedSessionDetailsForTask(taskId);
  const persistedProcess = store.managedProcessForTask(taskId) ??
    (boundSession?.processId && boundSession.processStartedAt
      ? {
          processId: boundSession.processId,
          processStartedAt: boundSession.processStartedAt
        }
      : undefined);
  const terminalTranscript = boundSession ? findTranscript(boundSession.sessionId) : undefined;
  const terminalTranscriptProven = Boolean(boundSession && terminalTranscript && hasTerminalTranscript(
    transcriptReader.readTail(terminalTranscript),
    boundSession.processStartedAt
  ));
  if (!await stopPinnedDesktopTask(
    workspaceForTask(taskId),
    taskId,
    persistedProcess,
    expectedSessionId,
    terminalTranscriptProven
  )) {
    if (protectedLaunchRejection) return false;
    // A restart can preserve the claim before launch acceptance binds a
    // native session. With no live launch and no bound session, acknowledge
    // that cancelled pre-open launch so it cannot block future Ready work.
    if ((launch && !launch.launchFailed) || (boundSession && (
      !terminalTranscript ||
      !terminalTranscriptProven
    ))) return false;
    const message = boundSession
      ? "Native Codex stop confirmed by terminal transcript"
      : "Native Codex launch cancelled before session opened";
    store.recordPendingStopAcknowledgement(taskId, message);
    return await acknowledge(message);
  }
  if (protectedLaunchRejection) {
    // Keep the exact binding until the durable launch-rejection transition is
    // accepted. The next pending-ack flush clears the rejection and binding
    // atomically; returning true here would let reconciliation orphan the row.
    markPendingLaunchRejectionNativeStopCompleted(store, taskId);
    return false;
  }
  const message = "Native Codex stop acknowledged";
  store.recordPendingStopAcknowledgement(taskId, message);
  return await acknowledge(message);
}

function repairHooks(): void {
  try {
    repairHookRegistration(hooksPath, hookScriptPath);
  } catch (error) {
    console.error("Agent Control hook registration repair failed:", error);
  }
}

function reconcileWithoutBlockingReadyClaims(apiUrl: string, ownerToken: string): void {
  if (reconciliationInProgress) return;
  reconciliationInProgress = true;
  void reconcileManagedTasks(
    store,
    apiUrl,
    ownerToken,
    (taskId) => stopManagedDesktopTask(taskId)
  )
    .catch((error) => console.error("Agent Control launch reconciliation failed:", error))
    .finally(() => { reconciliationInProgress = false; });
}

function findTranscript(sessionId: string): string | undefined {
  const cached = transcriptPaths.get(sessionId);
  if (cached && existsSync(cached)) return cached;
  if (!existsSync(codexSessionsPath)) return undefined;
  const pending = [codexSessionsPath];
  while (pending.length > 0) {
    const directory = pending.pop()!;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const fullPath = join(directory, entry.name);
      if (entry.isDirectory()) pending.push(fullPath);
      else if (entry.isFile() && entry.name.endsWith(`${sessionId}.jsonl`)) {
        transcriptPaths.set(sessionId, fullPath);
        return fullPath;
      }
    }
  }
  return undefined;
}

function importManagedTranscriptUpdates(): void {
  // A Desktop hook is the fast path. This transcript bridge is the durable
  // fallback when Desktop misses a Stop callback, so a completed mission can
  // never remain stranded in Working.
  for (const managed of store.managedSessions()) {
    const transcript = findTranscript(managed.sessionId);
    if (!transcript) continue;
    const records = transcriptReader.read(transcript);
    if (records.length === 0) continue;
    const completion = findTerminalTranscript(
      records.map((record) => record.text),
      managed.processStartedAt
    );
    if (completion?.lastAgentMessage) {
      try {
        const message = completion.lastAgentMessage;
        const turnId = completion.turnId;
        const result = message.match(
          /(?:^|\r?\n)AGENT_CONTROL_RESULT:\s*(DONE|WAITING|FAILED)(?:\s+-\s+[^\r\n]+)?\s*$/i
        )?.[1]?.toUpperCase();
        if (result) {
          const sensitiveValues = [ownerToken];
          const resultSummary = redactTranscriptText(
            message.replace(
              /(?:^|\r?\n)AGENT_CONTROL_RESULT:\s*(DONE|WAITING|FAILED)(?:\s+-\s+[^\r\n]+)?\s*$/i,
              ""
            ).trim(),
            sensitiveValues
          );
          const safeMessage = [
            resultSummary,
            `AGENT_CONTROL_RESULT: ${result}`
          ].filter(Boolean).join("\n");
          store.enqueue({
            id: `transcript-complete:${managed.sessionId}:${turnId}`,
            eventName: "Stop",
            sessionId: managed.sessionId,
            taskId: managed.taskId,
            occurredAt: new Date().toISOString(),
            payload: {
              event_id: randomUUID(),
              hook_event_name: "Stop",
              session_id: managed.sessionId,
              managed_task_id: managed.taskId,
              last_assistant_message: safeMessage,
              agent_control_result: result,
              result_summary: resultSummary,
              turn_id: turnId
            }
          });
        }
      } catch { /* A partial transcript write is retried on the next poll. */ }
    }
    // Codex's user-visible commentary and tool output are written to the local
    // transcript even when a Desktop hook omits PostToolUse.
    for (const activity of extractTranscriptActivityRecords(
      records,
      [ownerToken]
    )) {
      const activityKey = `${managed.sessionId}:${activity.key}`;
      if (!store.recordTranscriptActivity(activityKey)) continue;
      store.enqueue({
        id: `transcript-activity:${activityKey}`,
        eventName: "PostToolUse",
        sessionId: managed.sessionId,
        taskId: managed.taskId,
        occurredAt: new Date().toISOString(),
        payload: {
          event_id: randomUUID(), hook_event_name: "PostToolUse", session_id: managed.sessionId,
          managed_task_id: managed.taskId, tool_output: activity.output
        }
      });
    }
  }
  store.pruneTranscriptActivity();
}

repairHooks();
const hookRepairTimer = setInterval(repairHooks, 30_000);

const server = createAdapterHttpServer(store, hookSecret);
server.listen(17867, "127.0.0.1");

function launchClaimedTask(task: ClaimedTask, apiUrl: string, ownerToken: string): void {
  const launch: LaunchState = {
    stopRequested: false,
    sessionOpened: false,
    launchFailed: false
  };
  launches.set(task.id, launch);
  void (async () => {
    try {
      await sendHeartbeat(apiUrl, ownerToken, agentId, store.managedTaskIds());
      if (launch.stopRequested) {
        if (await stopManagedDesktopTask(task.id)) store.clearManagedTask(task.id);
        return;
      }
      // Launch milestones are real adapter state, but are not Codex output.
      // Do not turn them into invented percentages or dashboard activity.
      const stagedTask = task;
      if (launch.stopRequested) {
        if (await stopManagedDesktopTask(task.id)) store.clearManagedTask(task.id);
        return;
      }
      const result = await executeTask(
        stagedTask,
        taskRoot,
        (process) => store.recordManagedProcess(
          stagedTask.id,
          process.processId,
          process.processStartedAt
        ),
        (session) => {
          launch.sessionOpened = true;
          store.bindManagedSession(
            stagedTask.id,
            session.sessionId,
            session.processId,
            session.processStartedAt
          );
        }
      );
      if (!launch.sessionOpened) {
        launch.sessionOpened = true;
        store.bindManagedSession(
          stagedTask.id,
          result.sessionId,
          result.processId,
          result.processStartedAt
        )
      }
      if (launch.stopRequested) {
        await stopOpenedSessionBeforeBinding(
          store,
          task.id,
          result.sessionId,
          (openedSessionId) => stopManagedDesktopTask(task.id, openedSessionId)
        );
        return;
      }
      // The transcript mirror emits the first visible Codex text as soon as it
      // is written. Until then the dashboard intentionally stays indeterminate.
    } catch (error) {
      launch.launchFailed = true;
      if (launch.stopRequested) {
        const sessionId = error instanceof DesktopLaunchError || error instanceof DesktopPreTurnLaunchError
          ? error.sessionId
          : undefined;
        try {
          if (await stopManagedDesktopTask(task.id, sessionId)) {
            store.clearManagedTask(task.id);
          }
        } catch (stopError) {
          console.error("Agent Control could not stop a cancelled launch:", stopError);
        }
        return;
      }
      if (error instanceof DesktopPreTurnLaunchError) {
        try {
          if (!await stopManagedDesktopTask(task.id, error.sessionId)) {
            queueRejectedTaskLaunch(store, task, error.message, true);
            return;
          }
          if (await rejectTaskLaunch(apiUrl, ownerToken, task, error.message)) {
            store.clearManagedTask(task.id);
          } else {
            queueRejectedTaskLaunch(store, task, error.message);
          }
        } catch (failureError) {
          queueRejectedTaskLaunch(store, task, error.message, true);
          console.error(
            "Agent Control failed to report recoverable pre-turn launch rejection:",
            failureError
          );
        }
        return;
      }
      if (error instanceof DesktopLaunchError && error.sessionId) {
        // A native session exists but failed a later proof check. Stop it
        // before relisting, so rejected work cannot continue off-dashboard.
        launch.sessionOpened = true;
        let nativeStopConfirmed = false;
        try {
          const persistedProcess = store.managedProcessForTask(task.id);
          if (!await stopPinnedDesktopTask(
            workspaceForTask(task.id),
            task.id,
            persistedProcess,
            error.sessionId
          )) {
            queueRejectedTaskLaunch(store, task, error.message, true);
            console.error("Agent Control rejected launch could not stop native Codex session:", task.id);
            return;
          }
          nativeStopConfirmed = true;
          if (await rejectTaskLaunch(
            apiUrl, ownerToken, task,
            error.message
          )) {
            store.clearManagedTask(task.id);
          } else {
            queueRejectedTaskLaunch(store, task, error.message);
          }
        } catch (stopError) {
          queueRejectedTaskLaunch(store, task, error.message, !nativeStopConfirmed);
          console.error("Agent Control could not safely reject an opened native session:", stopError);
        }
        return;
      }
      if (launch.sessionOpened) {
        // The session was successfully opened. Do not clear its binding or
        // falsely mark it failed because a late status update raced a stop.
        console.error("Agent Control session launched but stage update failed:", error);
        try {
          await reconcileManagedTasks(
            store,
            apiUrl,
            ownerToken,
            (taskId) => stopManagedDesktopTask(taskId)
          );
        } catch (reconcileError) {
          console.error("Agent Control launch reconciliation failed:", reconcileError);
        }
        return;
      }
      try {
        const sessionId = error instanceof DesktopLaunchError || error instanceof DesktopPreTurnLaunchError
          ? error.sessionId
          : undefined;
        if (!await stopManagedDesktopTask(task.id, sessionId)) {
          queueRejectedTaskLaunch(
            store,
            task,
            error instanceof Error ? error.message : "desktop_launch_failed",
            true
          );
          return;
        }
        if (await rejectTaskLaunch(
          apiUrl, ownerToken, task,
          error instanceof Error ? error.message : "desktop_launch_failed"
        )) {
          store.clearManagedTask(task.id);
        } else {
          queueRejectedTaskLaunch(
            store,
            task,
            error instanceof Error ? error.message : "desktop_launch_failed"
          );
        }
      } catch (failureError) {
        queueRejectedTaskLaunch(
          store,
          task,
          error instanceof Error ? error.message : "desktop_launch_failed"
        );
        console.error("Agent Control failed to report recoverable desktop launch rejection:", failureError);
      }
    } finally {
      launches.delete(task.id);
    }
  })();
}

async function synchronize(): Promise<void> {
  if (syncInProgress) return;
  syncInProgress = true;
  importHookFallbackFiles(store, fallbackPath);
    try {
      await flushPendingStopAcknowledgements(
        store,
        apiUrl,
        ownerToken,
        (taskId) => stopManagedDesktopTask(taskId)
      );
      const now = Date.now();
      if (
        !registered &&
        intervalDue(lastRegistrationAttemptAt, now, REGISTRATION_RETRY_MILLIS)
      ) {
        lastRegistrationAttemptAt = now;
        registered = await registerAgent(apiUrl, ownerToken, agentId, `Codex on ${hostname()}`);
      }
      if (registered) {
        // A stale UI Automation stop must never hold up a fresh Ready claim.
        // Reconciliation still owns its terminal cleanup, but it is independent
        // of the one-second claim loop.
        if (intervalDue(lastReconciliationAttemptAt, now, RECONCILIATION_INTERVAL_MILLIS)) {
          lastReconciliationAttemptAt = now;
          reconcileWithoutBlockingReadyClaims(apiUrl, ownerToken);
        }
        importManagedTranscriptUpdates();
        if (intervalDue(lastHeartbeatAttemptAt, now, HEARTBEAT_INTERVAL_MILLIS)) {
          lastHeartbeatAttemptAt = now;
          await sendHeartbeat(apiUrl, ownerToken, agentId, store.managedTaskIds());
        }
        await flushOutbox(store, apiUrl, ownerToken);
        const availableSlots = Math.max(0, MAX_CONCURRENT_SESSIONS - store.managedTaskIds().length);
        const claimsThisPoll = Math.min(availableSlots, MAX_CLAIMS_PER_POLL);
        for (let slot = 0; slot < claimsThisPoll; slot += 1) {
          const task = await claimTask(apiUrl, ownerToken, agentId);
          if (!task) break;
          store.trackManagedTask(task.id);
          launchClaimedTask(task, apiUrl, ownerToken);
        }
      }
    } catch (error) {
      console.error("Agent Control synchronization failed:", error);
    } finally {
      syncInProgress = false;
    }
}

void synchronize();
const timer = setInterval(() => { void synchronize(); }, CONTROL_PLANE_POLL_MILLIS);

function shutdown(): void {
  clearInterval(timer);
  clearInterval(hookRepairTimer);
  server.close(() => {
    store.close();
    process.exit(0);
  });
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
