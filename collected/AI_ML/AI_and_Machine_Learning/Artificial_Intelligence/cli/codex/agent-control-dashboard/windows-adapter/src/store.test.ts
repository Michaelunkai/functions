import { afterEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { DatabaseSync } from "node:sqlite";
import { AdapterStore } from "./store.js";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("AdapterStore", () => {
  it("persists a cancelled-before-open acknowledgement across adapter restarts", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.recordPendingStopAcknowledgement(
      "task-stop",
      "Native Codex launch cancelled before session opened"
    );
    first.close();

    const reopened = new AdapterStore(path);
    expect(reopened.pendingStopAcknowledgement("task-stop")).toBe(
      "Native Codex launch cancelled before session opened"
    );
    expect(reopened.pendingStopAcknowledgements()).toEqual([{
      taskId: "task-stop",
      message: "Native Codex launch cancelled before session opened"
    }]);
    reopened.clearPendingStopAcknowledgement("task-stop");
    expect(reopened.pendingStopAcknowledgement("task-stop")).toBeUndefined();
    expect(reopened.pendingStopAcknowledgements()).toEqual([]);
    reopened.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not replay a stopped session acknowledgement after the task is rebound", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.bindManagedSession("task-stop", "session-stopped");
    first.recordPendingStopAcknowledgement("task-stop", "Native Codex stop acknowledged");
    first.close();

    const reopened = new AdapterStore(path);
    expect(reopened.pendingStopAcknowledgement("task-stop")).toBe(
      "Native Codex stop acknowledged"
    );

    reopened.bindManagedSession("task-stop", "session-replacement");

    const replacementSession = reopened.managedSessionForTask("task-stop");
    const pendingAcknowledgement = reopened.pendingStopAcknowledgement("task-stop");
    const pendingAcknowledgements = reopened.pendingStopAcknowledgements();
    reopened.close();

    expect(replacementSession).toBe("session-replacement");
    expect(pendingAcknowledgement).toBeUndefined();
    expect(pendingAcknowledgements).toEqual([]);
  });

  it("does not replay an acknowledgement after the same session starts a new process generation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession(
      "task-resumed",
      "session-resumed",
      4300,
      "2026-07-15T03:02:00.000Z"
    );
    store.recordPendingStopAcknowledgement(
      "task-resumed",
      "Native Codex stop acknowledged"
    );

    store.bindManagedSession(
      "task-resumed",
      "session-resumed",
      4301,
      "2026-07-15T03:03:00.000Z"
    );

    expect(store.pendingStopAcknowledgement("task-resumed")).toBeUndefined();
    expect(store.pendingStopAcknowledgements()).toEqual([]);
    store.close();
  });

  it("does not let a stale pre-bind acknowledgement clear a fresh same-task process generation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-pre-bind-generation");
    store.recordManagedProcess(
      "task-pre-bind-generation",
      4300,
      "2026-07-15T03:02:00.000Z"
    );
    store.recordPendingStopAcknowledgement(
      "task-pre-bind-generation",
      "Old stop acknowledged"
    );
    const old = store.pendingStopAcknowledgementDetails("task-pre-bind-generation")!;

    store.recordManagedProcess(
      "task-pre-bind-generation",
      4301,
      "2026-07-15T03:03:00.000Z"
    );
    expect(store.pendingStopAcknowledgement("task-pre-bind-generation")).toBeUndefined();

    store.recordPendingStopAcknowledgement(
      "task-pre-bind-generation",
      "New stop acknowledged"
    );
    expect(store.clearPendingStopAcknowledgement("task-pre-bind-generation", old)).toBe(false);
    expect(store.pendingStopAcknowledgement("task-pre-bind-generation")).toBe(
      "New stop acknowledged"
    );
    store.close();
  });

  it("does not replay a pre-open acknowledgement after the task is claimed again", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-reclaimed");
    store.recordPendingStopAcknowledgement(
      "task-reclaimed",
      "Native Codex launch cancelled before session opened"
    );
    store.clearManagedTask("task-reclaimed");
    store.trackManagedTask("task-reclaimed");

    expect(store.pendingStopAcknowledgement("task-reclaimed")).toBeUndefined();
    expect(store.pendingStopAcknowledgements()).toEqual([]);
    store.close();
  });

  it("removes only the acknowledgement belonging to the cleared claim generation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-generation");
    store.recordPendingStopAcknowledgement("task-generation", "Old stop acknowledged");
    const old = store.pendingStopAcknowledgementDetails("task-generation")!;
    store.clearManagedTask("task-generation");
    store.trackManagedTask("task-generation");
    store.recordPendingStopAcknowledgement("task-generation", "New stop acknowledged");

    store.clearPendingStopAcknowledgement("task-generation", old);

    expect(store.pendingStopAcknowledgement("task-generation")).toBe("New stop acknowledged");
    store.close();
  });

  it("migrates legacy acknowledgements without losing a pre-open cancellation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-store-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const legacy = new DatabaseSync(path);
    legacy.exec(`
      CREATE TABLE managed_sessions (
        session_id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL UNIQUE,
        bound_at TEXT NOT NULL
      );
      CREATE TABLE pending_stop_acknowledgements (
        task_id TEXT PRIMARY KEY,
        message TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      );
      INSERT INTO managed_sessions(session_id,task_id,bound_at)
      VALUES('session-stopped','task-stopped','2026-07-14T12:00:00.000Z');
      INSERT INTO pending_stop_acknowledgements(task_id,message,recorded_at)
      VALUES
        ('task-stopped','Native Codex stop acknowledged','2026-07-14T12:01:00.000Z'),
        (
          'task-pre-open',
          'Native Codex launch cancelled before session opened',
          '2026-07-14T12:02:00.000Z'
        );
    `);
    legacy.close();

    const migrated = new AdapterStore(path);
    expect(migrated.pendingStopAcknowledgement("task-stopped")).toBe(
      "Native Codex stop acknowledged"
    );
    expect(migrated.pendingStopAcknowledgement("task-pre-open")).toBe(
      "Native Codex launch cancelled before session opened"
    );

    migrated.bindManagedSession("task-stopped", "session-replacement");

    const stoppedAcknowledgement = migrated.pendingStopAcknowledgement("task-stopped");
    const preOpenAcknowledgement = migrated.pendingStopAcknowledgement("task-pre-open");
    const pendingAcknowledgements = migrated.pendingStopAcknowledgements();
    migrated.close();

    expect(stoppedAcknowledgement).toBeUndefined();
    expect(preOpenAcknowledgement).toBe(
      "Native Codex launch cancelled before session opened"
    );
    expect(pendingAcknowledgements).toEqual([{
      taskId: "task-pre-open",
      message: "Native Codex launch cancelled before session opened"
    }]);
  });

  it("persists hook events idempotently", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    const envelope = {
      id: "event-1",
      eventName: "SessionStart",
      sessionId: "session-1",
      occurredAt: new Date().toISOString(),
      payload: { session_id: "session-1" }
    };
    first.enqueue(envelope);
    first.enqueue(envelope);
    first.close();
    const reopened = new AdapterStore(path);
    expect(reopened.pending()).toHaveLength(1);
    expect(reopened.pending()[0].envelope.sessionId).toBe("session-1");
    reopened.close();
  });

  it("sanitizes every hook payload before it reaches the durable outbox", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const ownerToken = "owner-token-that-must-not-persist";
    const store = new AdapterStore(join(root, "adapter.db"), [ownerToken]);
    store.enqueue({
      id: "event-private",
      eventName: "PostToolUse",
      sessionId: "session-private",
      occurredAt: new Date().toISOString(),
      payload: {
        cwd: "C:\\Users\\operator\\private-repository",
        owner_token: ownerToken,
        tool_output: `Secret output ${ownerToken}`
      }
    });

    const payload = store.pending()[0].envelope.payload;
    const serialized = JSON.stringify(payload);
    expect(serialized).not.toContain(ownerToken);
    expect(serialized).not.toContain("C:\\\\Users\\\\operator");
    expect(serialized).not.toContain("Secret output");
    expect(payload).toEqual(expect.objectContaining({
      cwd: "private-repository",
      owner_token: "[REDACTED]",
      tool_output: "Tool completed; detailed output retained only in the native Codex session."
    }));
    store.close();
  });

  it("retains failures until completion", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.enqueue({
      id: "event-2",
      eventName: "Stop",
      sessionId: "session-2",
      occurredAt: new Date().toISOString(),
      payload: {}
    });
    const item = store.pending()[0];
    store.fail(item.sequence, "offline");
    expect(store.pending()[0].attempts).toBe(1);
    store.complete(item.sequence);
    expect(store.pending()).toHaveLength(0);
    store.close();
  });

  it("caps the durable outbox without evicting terminal lifecycle events", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"), [], { maxOutboxRows: 2 });

    store.enqueue({
      id: "activity-old",
      eventName: "PostToolUse",
      sessionId: "session-cap",
      occurredAt: new Date().toISOString(),
      payload: {}
    });
    store.enqueue({
      id: "stop-one",
      eventName: "Stop",
      sessionId: "session-cap",
      occurredAt: new Date().toISOString(),
      payload: {}
    });
    store.enqueue({
      id: "activity-new",
      eventName: "PostToolUse",
      sessionId: "session-cap",
      occurredAt: new Date().toISOString(),
      payload: {}
    });
    store.enqueue({
      id: "session-end",
      eventName: "SessionEnd",
      sessionId: "session-cap",
      occurredAt: new Date().toISOString(),
      payload: {}
    });

    expect(store.pending().map((item) => item.envelope.id)).toEqual([
      "stop-one",
      "session-end"
    ]);
    store.close();
  });

  it("retains terminal events beyond the nominal cap", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"), [], { maxOutboxRows: 1 });

    for (const id of ["stop-one", "stop-two", "stop-three"]) {
      store.enqueue({
        id,
        eventName: "Stop",
        sessionId: "session-terminal",
        occurredAt: new Date().toISOString(),
        payload: {}
      });
    }

    expect(store.pending().map((item) => item.envelope.id)).toEqual([
      "stop-one",
      "stop-two",
      "stop-three"
    ]);
    store.close();
  });

  it("tracks the active Codex task across process restarts", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const store = new AdapterStore(path);
    store.enqueue({
      id: "start-1", eventName: "UserPromptSubmit", sessionId: "session-9",
      occurredAt: new Date().toISOString(), payload: {}
    });
    expect(store.activeTaskId()).toBe("codex:session-9");
    store.close();
    const reopened = new AdapterStore(path);
    expect(reopened.activeTaskId()).toBe("codex:session-9");
    reopened.enqueue({
      id: "stop-1", eventName: "Stop", sessionId: "session-9",
      occurredAt: new Date().toISOString(), payload: {}
    });
    expect(reopened.activeTaskId()).toBeUndefined();
    reopened.close();
  });

  it("binds managed desktop sessions to their existing dashboard task", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-managed", "session-managed");
    store.enqueue({
      id: "managed-event", eventName: "PostToolUse", sessionId: "session-managed",
      occurredAt: new Date().toISOString(), payload: { tool_name: "shell_command" }
    });
    expect(store.managedTaskId()).toBe("task-managed");
    expect(store.managedSessionForTask("task-managed")).toBe("session-managed");
    expect(store.managedSessionForTask("task-missing")).toBeUndefined();
    expect(store.pending()[0].envelope.taskId).toBe("task-managed");
    store.clearManagedSession("session-managed");
    expect(store.managedTaskId()).toBeUndefined();
    store.close();
  });

  it("preserves an explicit outbox task after its managed session is cleared and the store reopens", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.bindManagedSession("task-explicit", "session-explicit");
    first.enqueue({
      id: "explicit-managed-event",
      eventName: "Stop",
      sessionId: "session-explicit",
      taskId: "task-explicit",
      occurredAt: new Date().toISOString(),
      payload: { managed_task_id: "task-explicit" }
    });

    first.clearManagedSession("session-explicit");
    const pendingTaskId = first.pending()[0].envelope.taskId;
    first.close();
    expect(pendingTaskId).toBe("task-explicit");

    const reopened = new AdapterStore(path);
    const reopenedTaskId = reopened.pending()[0].envelope.taskId;
    reopened.close();
    expect(reopenedTaskId).toBe("task-explicit");
  });

  it("persists an inferred outbox task before its managed session is cleared", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.bindManagedSession("task-inferred", "session-inferred");
    first.enqueue({
      id: "inferred-managed-event",
      eventName: "Stop",
      sessionId: "session-inferred",
      occurredAt: new Date().toISOString(),
      payload: { hook_event_name: "Stop" }
    });
    first.clearManagedSession("session-inferred");
    first.close();

    const reopened = new AdapterStore(path);
    expect(reopened.pending()[0].envelope.taskId).toBe("task-inferred");
    reopened.close();
  });

  it("reads legacy outbox rows through a session binding and without one", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const legacy = new DatabaseSync(path);
    legacy.exec(`
      CREATE TABLE outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        event_name TEXT NOT NULL,
        session_id TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    `);
    legacy.prepare(`
      INSERT INTO outbox (id,event_name,session_id,occurred_at,payload)
      VALUES (?,?,?,?,?)
    `).run(
      "legacy-managed-event",
      "Stop",
      "session-legacy",
      new Date().toISOString(),
      JSON.stringify({ managed_task_id: "task-legacy" })
    );
    legacy.close();

    const migrated = new AdapterStore(path);
    migrated.bindManagedSession("task-legacy", "session-legacy");
    expect(migrated.pending()[0].envelope.taskId).toBe("task-legacy");
    migrated.clearManagedSession("session-legacy");
    migrated.close();

    const reopened = new AdapterStore(path);
    expect(reopened.pending()[0].envelope.id).toBe("legacy-managed-event");
    expect(reopened.pending()[0].envelope.taskId).toBeUndefined();
    reopened.close();
  });

  it("persists the exact native app-server process identity across adapter restarts", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.bindManagedSession(
      "task-managed",
      "session-managed",
      4321,
      "2026-07-14T12:00:00.000Z"
    );
    first.close();

    const reopened = new AdapterStore(path);
    expect(reopened.managedSessionDetailsForTask("task-managed")).toEqual({
      taskId: "task-managed",
      sessionId: "session-managed",
      generation: expect.any(String),
      processId: 4321,
      processStartedAt: "2026-07-14T12:00:00.000Z"
    });
    reopened.close();
  });

  it("persists a launch process before the native session has finished opening", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.trackManagedTask("task-opening");
    first.recordManagedProcess("task-opening", 9876, "2026-07-14T12:30:00.000Z");
    first.close();

    const reopened = new AdapterStore(path);
    expect(reopened.managedProcessForTask("task-opening")).toEqual({
      processId: 9876,
      processStartedAt: "2026-07-14T12:30:00.000Z"
    });
    expect(reopened.managedSessionForTask("task-opening")).toBeUndefined();
    reopened.close();
  });

  it("tracks each claimed dashboard task independently so Ready work is not blocked by another session", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-one");
    store.trackManagedTask("task-two");
    store.bindManagedSession("task-one", "session-one");
    store.bindManagedSession("task-two", "session-two");

    expect(store.managedTaskIds()).toEqual(["task-one", "task-two"]);
    store.clearManagedTask("task-one");
    expect(store.managedTaskIds()).toEqual(["task-two"]);
    expect(store.taskForSession("session-one")).toBeUndefined();
    expect(store.taskForSession("session-two")).toBe("task-two");
    store.close();
  });

  it("preserves a paused task thread for one-click resume after managed state is cleared", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-paused", "session-paused");
    store.saveResumableSession("task-paused", "session-paused");

    store.clearManagedTask("task-paused");

    expect(store.managedSessionForTask("task-paused")).toBeUndefined();
    expect(store.resumableSessionForTask("task-paused")).toBe("session-paused");
    store.clearResumableSession("task-paused");
    expect(store.resumableSessionForTask("task-paused")).toBeUndefined();
    store.close();
  });

  it("bounds durable transcript activity deduplication rows", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    expect(store.recordTranscriptActivity("oldest")).toBe(true);
    expect(store.recordTranscriptActivity("middle")).toBe(true);
    expect(store.recordTranscriptActivity("newest")).toBe(true);

    store.pruneTranscriptActivity(2);

    expect(store.recordTranscriptActivity("oldest")).toBe(true);
    expect(store.recordTranscriptActivity("newest")).toBe(false);
    store.close();
  });
});
