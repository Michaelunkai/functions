import type { AdapterStore, PendingStopAcknowledgementDetails } from "./store.js";
import { controlPlaneRequestTimeoutMillis } from "./polling-policy.js";

export interface ClaimedTask {
  id: string;
  title: string;
  description: string;
  status: string;
  version: number;
  progressPercent?: number | null;
  currentStep?: string | null;
}

export interface CompletionEvidence {
  source: "transcript";
  sessionId: string;
  turnId: string;
  result: "DONE";
}

const ACTIVE_MANAGED_STATUSES = new Set([
  "DISPATCHING",
  "IN_PROGRESS",
  "VERIFYING"
]);
const LAUNCH_REJECTION_PREFIX = "agent-control-launch-rejection:";
const CONTROL_PLANE_REQUEST_TIMEOUT_MILLIS = controlPlaneRequestTimeoutMillis();

interface PendingLaunchRejection {
  kind: "launch-rejection";
  version: number;
  reason: string;
  requiresNativeStop: boolean;
}

interface ManagedBindingIdentity {
  sessionId?: string;
  processId?: number;
  processStartedAt?: string;
  claimedAt?: string;
}

interface TaskStatusSnapshot {
  id: string;
  status: string;
  version: number;
}

function headers(ownerToken: string): Record<string, string> {
  return { "content-type": "application/json", authorization: `Bearer ${ownerToken}` };
}

function withControlPlaneTimeout(signal?: AbortSignal | null): AbortSignal {
  const timeoutSignal = AbortSignal.timeout(CONTROL_PLANE_REQUEST_TIMEOUT_MILLIS);
  return signal ? AbortSignal.any([signal, timeoutSignal]) : timeoutSignal;
}

async function controlPlaneFetch(
  input: string,
  init: RequestInit = {}
): Promise<Response> {
  return await fetch(input, {
    ...init,
    signal: withControlPlaneTimeout(init.signal)
  });
}

function managedBindingIdentity(store: AdapterStore, taskId: string): ManagedBindingIdentity {
  const session = store.managedSessionDetailsForTask(taskId);
  const process = store.managedProcessForTask(taskId);
  const task = store.managedTaskDetailsForTask(taskId);
  return {
    sessionId: session?.sessionId,
    processId: process?.processId ?? session?.processId,
    processStartedAt: process?.processStartedAt ?? session?.processStartedAt,
    claimedAt: task?.claimedAt
  };
}

function sameManagedBinding(
  before: ManagedBindingIdentity,
  after: ManagedBindingIdentity
): boolean {
  return before.sessionId === after.sessionId &&
    before.processId === after.processId &&
    before.processStartedAt === after.processStartedAt &&
    before.claimedAt === after.claimedAt;
}

function pendingBindingIdentity(
  pending: PendingStopAcknowledgementDetails
): ManagedBindingIdentity {
  return {
    sessionId: pending.sessionId,
    processId: pending.processId,
    processStartedAt: pending.processStartedAt,
    claimedAt: pending.claimedAt
  };
}

export async function registerAgent(
  apiUrl: string,
  ownerToken: string,
  agentId: string,
  name: string
): Promise<boolean> {
  const response = await controlPlaneFetch(`${apiUrl.replace(/\/$/, "")}/v1/agents/${encodeURIComponent(agentId)}`, {
    method: "PUT",
    headers: headers(ownerToken),
    body: JSON.stringify({
      name,
      kind: "windows",
      capabilities: ["coding", "codex", "filesystem", "powershell"],
      availability: "online"
    })
  });
  return response.ok;
}

export async function sendHeartbeat(
  apiUrl: string,
  ownerToken: string,
  agentId: string,
  currentTaskIds: readonly string[] = []
): Promise<boolean> {
  const response = await controlPlaneFetch(
    `${apiUrl.replace(/\/$/, "")}/v1/agents/${encodeURIComponent(agentId)}/heartbeat`,
    {
      method: "POST",
      headers: headers(ownerToken),
      body: JSON.stringify({
        availability: currentTaskIds.length > 0 ? "busy" : "online",
        ...(currentTaskIds.length === 1 ? { currentTaskId: currentTaskIds[0] } : {})
      })
    }
  );
  return response.ok;
}

export async function acknowledgeNativeStop(
  apiUrl: string,
  ownerToken: string,
  taskId: string,
  currentStep: string
): Promise<boolean> {
  const response = await controlPlaneFetch(
    `${apiUrl.replace(/\/$/, "")}/v1/tasks/${encodeURIComponent(taskId)}/progress`,
    {
      method: "POST",
      headers: headers(ownerToken),
      body: JSON.stringify({
        progressPercent: null,
        currentStep
      })
    }
  );
  return response.ok;
}

export function queueRejectedTaskLaunch(
  store: AdapterStore,
  task: ClaimedTask,
  reason: string,
  requiresNativeStop = false
): void {
  const payload: PendingLaunchRejection = {
    kind: "launch-rejection",
    version: task.version,
    reason: reason.trim() || "desktop_launch_failed",
    requiresNativeStop
  };
  store.recordPendingStopAcknowledgement(
    task.id,
    `${LAUNCH_REJECTION_PREFIX}${JSON.stringify(payload)}`
  );
}

function parsePendingLaunchRejection(message: string): PendingLaunchRejection | undefined {
  if (!message.startsWith(LAUNCH_REJECTION_PREFIX)) return undefined;
  try {
    const payload = JSON.parse(message.slice(LAUNCH_REJECTION_PREFIX.length)) as Partial<PendingLaunchRejection>;
    if (
      payload.kind !== "launch-rejection" ||
      !Number.isInteger(payload.version) ||
      typeof payload.reason !== "string" ||
      typeof payload.requiresNativeStop !== "boolean"
    ) return undefined;
    return payload as PendingLaunchRejection;
  } catch {
    return undefined;
  }
}

export function pendingLaunchRejectionRequiresNativeStop(message: string): boolean {
  return parsePendingLaunchRejection(message)?.requiresNativeStop === true;
}

export function markPendingLaunchRejectionNativeStopCompleted(
  store: AdapterStore,
  taskId: string
): boolean {
  const message = store.pendingStopAcknowledgement(taskId);
  if (!message) return false;
  const rejection = parsePendingLaunchRejection(message);
  if (!rejection?.requiresNativeStop) return false;
  queueRejectedTaskLaunch(
    store,
    { id: taskId, version: rejection.version } as ClaimedTask,
    rejection.reason,
    false
  );
  return true;
}

export async function flushPendingStopAcknowledgements(
  store: AdapterStore,
  apiUrl: string,
  ownerToken: string,
  retryNativeStop?: (taskId: string) => Promise<boolean>
): Promise<number> {
  let completed = 0;
  for (const pending of store.pendingStopAcknowledgements()) {
    try {
      let pendingDetails = store.pendingStopAcknowledgementDetails(pending.taskId);
      if (!pendingDetails) continue;
      let bindingBeforeFlush = pendingBindingIdentity(pendingDetails);
      if (!sameManagedBinding(
        bindingBeforeFlush,
        managedBindingIdentity(store, pending.taskId)
      )) {
        store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails);
        continue;
      }
      let rejection = parsePendingLaunchRejection(pendingDetails.message);
      if (rejection) {
        if (
          rejection.requiresNativeStop &&
          (store.managedSessionForTask(pending.taskId) || store.managedProcessForTask(pending.taskId))
        ) {
          if (!retryNativeStop) continue;
          await retryNativeStop(pending.taskId);
          const refreshed = store.pendingStopAcknowledgement(pending.taskId);
          rejection = refreshed ? parsePendingLaunchRejection(refreshed) : undefined;
          if (!rejection || rejection.requiresNativeStop) continue;
          pendingDetails = store.pendingStopAcknowledgementDetails(pending.taskId);
          if (!pendingDetails) continue;
          bindingBeforeFlush = pendingBindingIdentity(pendingDetails);
          if (!sameManagedBinding(
            bindingBeforeFlush,
            managedBindingIdentity(store, pending.taskId)
          )) {
            store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails);
            continue;
          }
        }
        const rejectionApplied = await rejectTaskLaunch(
          apiUrl,
          ownerToken,
          { id: pending.taskId, version: rejection.version } as ClaimedTask,
          rejection.reason
        );
        if (!rejectionApplied) continue;
        if (!sameManagedBinding(bindingBeforeFlush, managedBindingIdentity(store, pending.taskId))) {
          store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails);
          continue;
        }
        if (!store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails)) continue;
        store.clearManagedTask(pending.taskId);
        completed += 1;
        continue;
      }
      if (!await acknowledgeNativeStop(apiUrl, ownerToken, pending.taskId, pendingDetails.message)) continue;
      if (!sameManagedBinding(bindingBeforeFlush, managedBindingIdentity(store, pending.taskId))) {
        store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails);
        continue;
      }
      if (!store.clearPendingStopAcknowledgement(pending.taskId, pendingDetails)) continue;
      completed += 1;
    } catch {
      // The durable row remains queued for the next synchronization pass.
    }
  }
  return completed;
}

export async function flushOutbox(
  store: AdapterStore,
  apiUrl: string,
  ownerToken: string,
  signal?: AbortSignal
): Promise<number> {
  let completed = 0;
  for (const item of store.pending()) {
    try {
      const response = await controlPlaneFetch(`${apiUrl.replace(/\/$/, "")}/v1/hooks/codex`, {
        method: "POST",
        headers: headers(ownerToken),
        body: JSON.stringify(item.envelope),
        signal
      });
      if (!response.ok) {
        store.fail(item.sequence, `HTTP ${response.status}`);
        if (response.status >= 500) break;
        continue;
      }
      // Terminal server state is not proof that the native session was
      // stopped. Reconciliation owns that verified cleanup path.
      store.complete(item.sequence);
      completed += 1;
    } catch (error) {
      store.fail(item.sequence, error instanceof Error ? error.name : "network_error");
      break;
    }
  }
  return completed;
}

export async function reconcileManagedTasks(
  store: AdapterStore,
  apiUrl: string,
  ownerToken: string,
  stopManagedTask?: (taskId: string, status: string) => Promise<boolean>,
  signal?: AbortSignal
): Promise<number> {
  const managedTaskIds = store.managedTaskIds();
  if (managedTaskIds.length === 0) return 0;
  const bindingsAtSnapshot = new Map(
    managedTaskIds.map((taskId) => [taskId, managedBindingIdentity(store, taskId)])
  );
  const statuses = new Map<string, string>();
  for (let offset = 0; offset < managedTaskIds.length; offset += 100) {
    const response = await controlPlaneFetch(`${apiUrl.replace(/\/$/, "")}/v1/tasks/statuses`, {
      method: "POST",
      headers: headers(ownerToken),
      body: JSON.stringify({ ids: managedTaskIds.slice(offset, offset + 100) }),
      signal
    });
    if (!response.ok) throw new Error(`managed_task_reconcile_failed:${response.status}`);
    const snapshot = await response.json() as { tasks?: Array<{ id: string; status: string }> };
    for (const task of snapshot.tasks ?? []) statuses.set(task.id, task.status);
  }
  let reconciled = 0;
  for (const managedTaskId of managedTaskIds) {
    const status = statuses.get(managedTaskId);
    // Do not act on a task absent from a snapshot: a partial/old response is
    // not proof that the server deleted or moved the task.
    if (!status || ACTIVE_MANAGED_STATUSES.has(status)) continue;
    // The status request can yield while a replacement claim binds the same
    // task ID. A status from the previous local generation must never stop or
    // clear that replacement.
    const bindingBeforeSnapshot = bindingsAtSnapshot.get(managedTaskId);
    if (!bindingBeforeSnapshot || !sameManagedBinding(
      bindingBeforeSnapshot,
      managedBindingIdentity(store, managedTaskId)
    )) continue;
    // READY/QUEUED are expected while a newly claimed task is propagating into
    // Desktop. Once a session is bound, those statuses instead mean the owner
    // moved established work out of its current run and its exact session must
    // be stopped before the binding is cleared.
    if (
      (status === "READY" || status === "QUEUED") &&
      !store.managedSessionForTask(managedTaskId) &&
      !store.managedProcessForTask(managedTaskId)
    ) continue;
    // The adapter's production caller always supplies the stop operation. If
    // a caller cannot stop Desktop, retaining the managed record is safer than
    // claiming the session ended while it may still be running.
    if (!stopManagedTask) continue;
    const bindingBeforeStop = managedBindingIdentity(store, managedTaskId);
    let stopAccepted = false;
    try {
      stopAccepted = await stopManagedTask(managedTaskId, status);
    } catch {
      // A missing/stale window is retryable on the next reconciliation pass;
      // do not let one task prevent other sessions from being reconciled.
      stopAccepted = false;
    }
    if (!stopAccepted) continue;
    // The stop callback can yield while a new claim or resumed session binds
    // the same task ID. Never let cleanup for the old owner delete that new
    // binding.
    if (!sameManagedBinding(
      bindingBeforeStop,
      managedBindingIdentity(store, managedTaskId)
    )) continue;
    store.clearManagedTask(managedTaskId);
    reconciled += 1;
  }
  return reconciled;
}

/** Compatibility helper for callers that only need to know whether a task was reconciled. */
export async function reconcileManagedTask(
  store: AdapterStore,
  apiUrl: string,
  ownerToken: string,
  stopManagedTask?: (taskId: string, status: string) => Promise<boolean>,
  signal?: AbortSignal
): Promise<boolean> {
  return (await reconcileManagedTasks(store, apiUrl, ownerToken, stopManagedTask, signal)) > 0;
}

export async function claimTask(
  apiUrl: string,
  ownerToken: string,
  agentId: string
): Promise<ClaimedTask | undefined> {
  const response = await controlPlaneFetch(
    `${apiUrl.replace(/\/$/, "")}/v1/agents/${encodeURIComponent(agentId)}/claim`,
    {
      method: "POST",
      headers: headers(ownerToken),
      body: JSON.stringify({ capabilities: ["coding", "codex", "filesystem", "powershell"] })
    }
  );
  if (response.status === 204) return undefined;
  if (!response.ok) throw new Error(`claim_failed:${response.status}`);
  return (await response.json() as { task: ClaimedTask }).task;
}

async function postJson(
  url: string,
  ownerToken: string,
  body: Record<string, unknown>
): Promise<Response> {
  return await controlPlaneFetch(url, {
    method: "POST",
    headers: headers(ownerToken),
    body: JSON.stringify(body)
  });
}

async function taskStatusSnapshot(
  apiUrl: string,
  ownerToken: string,
  taskId: string
): Promise<TaskStatusSnapshot> {
  const response = await postJson(
    `${apiUrl.replace(/\/$/, "")}/v1/tasks/statuses`,
    ownerToken,
    { ids: [taskId] }
  );
  if (!response.ok) throw new Error(`task_status_refresh_failed:${response.status}`);
  const payload = await response.json() as { tasks?: TaskStatusSnapshot[] };
  const snapshot = payload.tasks?.find((item) =>
    item.id === taskId &&
    typeof item.status === "string" &&
    Number.isInteger(item.version)
  );
  if (!snapshot) throw new Error("task_status_refresh_missing");
  return snapshot;
}

export async function updateTaskStage(
  apiUrl: string,
  ownerToken: string,
  task: ClaimedTask,
  currentStep: string,
  progressPercent: number | null
): Promise<ClaimedTask> {
  const response = await postJson(
    `${apiUrl.replace(/\/$/, "")}/v1/tasks/${encodeURIComponent(task.id)}/progress`,
    ownerToken,
    { currentStep, progressPercent, expectedVersion: task.version }
  );
  if (!response.ok) throw new Error(`progress_update_failed:${response.status}`);
  return await response.json() as ClaimedTask;
}

export async function completeTask(
  apiUrl: string,
  ownerToken: string,
  task: ClaimedTask,
  summary: string,
  reference: string,
  completionEvidence?: CompletionEvidence
): Promise<void> {
  if (
    !completionEvidence ||
    completionEvidence.source !== "transcript" ||
    !completionEvidence.sessionId.trim() ||
    !completionEvidence.turnId.trim() ||
    completionEvidence.result !== "DONE"
  ) {
    throw new Error("completion_transcript_evidence_required");
  }
  const base = apiUrl.replace(/\/$/, "");
  const encoded = encodeURIComponent(task.id);
  const evidence = await postJson(`${base}/v1/tasks/${encoded}/evidence`, ownerToken, {
    kind: "artifact",
    summary: summary.slice(0, 2_000),
    reference: reference.slice(0, 2_000),
    transcriptSessionId: completionEvidence.sessionId,
    transcriptTurnId: completionEvidence.turnId,
    transcriptResult: completionEvidence.result
  });
  if (!evidence.ok) throw new Error(`evidence_failed:${evidence.status}`);
  const verifying = await postJson(`${base}/v1/tasks/${encoded}/transition`, ownerToken, {
    to: "VERIFYING",
    reason: "codex_execution_completed",
    expectedVersion: task.version
  });
  if (!verifying.ok) throw new Error(`verify_transition_failed:${verifying.status}`);
  const changed = await verifying.json() as ClaimedTask;
  try {
    await updateTaskStage(base, ownerToken, { ...task, ...changed }, "Complete", 100);
  } catch {
    // Completion is authoritative; a final cosmetic progress update must not strand VERIFYING work.
  }
  const completed = await postJson(`${base}/v1/tasks/${encoded}/complete`, ownerToken, {});
  if (!completed.ok) throw new Error(`completion_failed:${completed.status}:${changed.version}`);
}

export async function failTask(
  apiUrl: string,
  ownerToken: string,
  task: ClaimedTask,
  reason: string
): Promise<void> {
  const response = await postJson(
    `${apiUrl.replace(/\/$/, "")}/v1/tasks/${encodeURIComponent(task.id)}/transition`,
    ownerToken,
    { to: "FAILED", reason: reason.slice(0, 500), expectedVersion: task.version }
  );
  if (!response.ok && response.status !== 409) throw new Error(`failure_report_failed:${response.status}`);
}

export async function rejectTaskLaunch(
  apiUrl: string,
  ownerToken: string,
  task: ClaimedTask,
  reason: string
): Promise<boolean> {
  const detail = reason.trim() || "desktop_launch_failed";
  const transitionUrl =
    `${apiUrl.replace(/\/$/, "")}/v1/tasks/${encodeURIComponent(task.id)}/transition`;
  const transitionReason =
    `Native Codex launch rejected: ${detail}. No mission was accepted because native workspace, model, effort, running-turn, and Desktop-open proof did not all pass.`.slice(0, 500);
  let expectedVersion = task.version;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const response = await postJson(transitionUrl, ownerToken, {
      to: "FAILED",
      reason: transitionReason,
      expectedVersion
    });
    if (response.ok) return true;
    if (response.status !== 409) {
      throw new Error(`launch_rejection_report_failed:${response.status}`);
    }
    const snapshot = await taskStatusSnapshot(apiUrl, ownerToken, task.id);
    if (!ACTIVE_MANAGED_STATUSES.has(snapshot.status)) return true;
    if (snapshot.version === expectedVersion) {
      throw new Error(`launch_rejection_conflict:${snapshot.status}:${snapshot.version}`);
    }
    // A version change is an immutable claim boundary. The original launch
    // rejection cannot be safely retried against a newer active claim because
    // that claim may already belong to a different Desktop session.
    return false;
  }
  throw new Error("launch_rejection_conflict_retry_exhausted");
}
