import { afterEach, describe, expect, it, vi } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { AdapterStore } from "./store.js";
import {
  acknowledgeNativeStop,
  claimTask,
  completeTask,
  failTask,
  queueRejectedTaskLaunch,
  rejectTaskLaunch,
  flushPendingStopAcknowledgements,
  flushOutbox,
  markPendingLaunchRejectionNativeStopCompleted,
  pendingLaunchRejectionRequiresNativeStop,
  reconcileManagedTask,
  reconcileManagedTasks,
  registerAgent,
  sendHeartbeat,
  updateTaskStage
} from "./sync.js";

afterEach(() => vi.unstubAllGlobals());

describe("agent presence", () => {
  it("durably retries a failed launch rejection after an adapter restart", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-retry-"));
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    queueRejectedTaskLaunch(first, {
      id: "task-launch-retry",
      title: "Test",
      description: "Test",
      status: "IN_PROGRESS",
      version: 7
    }, "desktop_pin_helper_failed");
    first.close();

    const reopened = new AdapterStore(path);
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("{}", { status: 503 }))
      .mockResolvedValueOnce(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushPendingStopAcknowledgements(
      reopened, "https://control.example", "owner"
    )).toBe(0);
    expect(reopened.pendingStopAcknowledgements()).toHaveLength(1);

    expect(await flushPendingStopAcknowledgements(
      reopened, "https://control.example", "owner"
    )).toBe(1);
    expect(reopened.pendingStopAcknowledgements()).toEqual([]);
    expect(fetchMock.mock.calls[0][0]).toBe(
      "https://control.example/v1/tasks/task-launch-retry/transition"
    );
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))).toEqual({
      to: "FAILED",
      reason: expect.stringContaining("desktop_pin_helper_failed"),
      expectedVersion: 7
    });
    reopened.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not fail a newer active claim after a stale launch rejection", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-version-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    queueRejectedTaskLaunch(store, {
      id: "task-version-conflict",
      title: "Test",
      description: "Test",
      status: "IN_PROGRESS",
      version: 7
    }, "desktop_route_unverified");
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "version_conflict" }), {
        status: 409,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        tasks: [{ id: "task-version-conflict", status: "IN_PROGRESS", version: 8 }]
      }), {
        status: 200,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "claim_superseded" }), {
        status: 409,
        headers: { "content-type": "application/json" }
      }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(store.pendingStopAcknowledgements()).toHaveLength(1);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body)).expectedVersion)
      .toBe(7);
    expect(fetchMock.mock.calls[1][0]).toBe("https://control.example/v1/tasks/statuses");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps a launch rejection durable when a 409 cannot be reconciled", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-version-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    queueRejectedTaskLaunch(store, {
      id: "task-invalid-transition",
      title: "Test",
      description: "Test",
      status: "IN_PROGRESS",
      version: 7
    }, "desktop_route_unverified");
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "version_conflict" }), {
        status: 409,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        tasks: [{ id: "task-invalid-transition", status: "IN_PROGRESS", version: 8 }]
      }), {
        status: 200,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "invalid_status_transition" }), {
        status: 409,
        headers: { "content-type": "application/json" }
      }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(store.pendingStopAcknowledgements()).toHaveLength(1);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("accepts an owner-superseded launch rejection without forcing a new failure", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "version_conflict" }), {
        status: 409,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        tasks: [{ id: "task-owner-moved", status: "READY", version: 9 }]
      }), {
        status: 200,
        headers: { "content-type": "application/json" }
      }));
    vi.stubGlobal("fetch", fetchMock);

    await rejectTaskLaunch(
      "https://control.example",
      "owner",
      { id: "task-owner-moved", title: "Test", description: "Test", status: "IN_PROGRESS", version: 7 },
      "desktop_route_unverified"
    );
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("retries and clears a durable native stop acknowledgement after an adapter restart", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-retry-"));
    const path = join(root, "adapter.db");
    const first = new AdapterStore(path);
    first.recordPendingStopAcknowledgement("task-restart", "Native Codex stop acknowledged");
    first.close();

    const reopened = new AdapterStore(path);
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushPendingStopAcknowledgements(
      reopened, "https://control.example", "owner"
    )).toBe(1);
    expect(reopened.pendingStopAcknowledgements()).toEqual([]);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://control.example/v1/tasks/task-restart/progress",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          progressPercent: null,
          currentStep: "Native Codex stop acknowledged"
        })
      })
    );
    reopened.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not clear a replacement session acknowledgement while an old request is in flight", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-generation-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-generation", "session-old");
    store.recordPendingStopAcknowledgement("task-generation", "Old stop acknowledged");
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => {
      store.bindManagedSession("task-generation", "session-new");
      store.recordPendingStopAcknowledgement("task-generation", "New stop acknowledged");
      return new Response("{}", { status: 200 });
    }));

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(store.managedSessionForTask("task-generation")).toBe("session-new");
    expect(store.pendingStopAcknowledgement("task-generation")).toBe("New stop acknowledged");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not clear a replacement acknowledgement with the same binding generation", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-generation-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-generation", "session-generation");
    store.recordPendingStopAcknowledgement("task-generation", "Old stop acknowledged");
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => {
      store.recordPendingStopAcknowledgement("task-generation", "New stop acknowledged");
      return new Response("{}", { status: 200 });
    }));

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(store.pendingStopAcknowledgement("task-generation")).toBe("New stop acknowledged");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not clear a replacement claim generation while an old stop request is in flight", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-generation-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-generation");
    store.recordPendingStopAcknowledgement("task-generation", "Old stop acknowledged");
    vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => {
      store.clearManagedTask("task-generation");
      store.trackManagedTask("task-generation");
      return new Response("{}", { status: 200 });
    }));

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(store.managedTaskIds()).toEqual(["task-generation"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not reconcile a fresh generation created while statuses are loading", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-generation-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-generation", "session-old");
    const fetchMock = vi.fn().mockImplementation(async () => {
      store.clearManagedTask("task-generation");
      store.bindManagedSession("task-generation", "session-new");
      return new Response(JSON.stringify({
        cursor: 2,
        tasks: [{ id: "task-generation", status: "CANCELLED" }]
      }), { status: 200, headers: { "content-type": "application/json" } });
    });
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", fetchMock);

    expect(await reconcileManagedTasks(
      store, "https://control.example", "owner", stop
    )).toBe(0);
    expect(stop).not.toHaveBeenCalled();
    expect(store.managedSessionForTask("task-generation")).toBe("session-new");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not flush a stop acknowledgement after the same session gets a new process", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-stop-generation-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession(
      "task-generation",
      "session-generation",
      4200,
      "2026-07-15T03:02:00.000Z"
    );
    store.recordPendingStopAcknowledgement("task-generation", "Old stop acknowledged");
    store.recordManagedProcess(
      "task-generation",
      4300,
      "2026-07-15T03:03:00.000Z"
    );
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner"
    )).toBe(0);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(store.pendingStopAcknowledgement("task-generation")).toBeUndefined();
    expect(store.managedProcessForTask("task-generation")).toEqual({
      processId: 4300,
      processStartedAt: "2026-07-15T03:03:00.000Z"
    });
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("records native stop acknowledgement only after the Desktop stop succeeds", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await acknowledgeNativeStop(
      "https://control.example", "owner", "task-1", "Native Codex stop acknowledged"
    )).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://control.example/v1/tasks/task-1/progress",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          progressPercent: null,
          currentStep: "Native Codex stop acknowledged"
        })
      })
    );
  });

  it("registers the Windows Codex executor", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await registerAgent("https://control.example", "owner", "desktop-1", "Workstation")).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://control.example/v1/agents/desktop-1",
      expect.objectContaining({ method: "PUT" })
    );
  });

  it("reports the active task in heartbeats", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await sendHeartbeat("https://control.example/", "owner", "desktop-1", ["codex:session-7"])).toBe(true);
    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(String(options.body))).toEqual({
      availability: "busy",
      currentTaskId: "codex:session-7"
    });
  });

  it("reports idle state without a stale task id", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await sendHeartbeat("https://control.example", "owner", "desktop-1")).toBe(true);
    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(String(options.body))).toEqual({ availability: "online" });
  });

  it("reports a busy executor for multiple sessions without falsely naming only one task", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await sendHeartbeat("https://control.example", "owner", "desktop-1", ["task-one", "task-two"])).toBe(true);
    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(String(options.body))).toEqual({ availability: "busy" });
  });

  it("flushes successful hooks and retains retryable failures", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.enqueue({
      id: "one", eventName: "SessionStart", sessionId: "session-1",
      occurredAt: new Date().toISOString(), payload: {}
    });
    store.enqueue({
      id: "two", eventName: "Stop", sessionId: "session-1",
      occurredAt: new Date().toISOString(), payload: {}
    });
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("{}", { status: 202 }))
      .mockResolvedValueOnce(new Response("{}", { status: 503 }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await flushOutbox(store, "https://control.example", "owner")).toBe(1);
    expect(store.pending()).toHaveLength(1);
    expect(store.pending()[0].attempts).toBe(1);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("records network failures and stops the flush cycle", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.enqueue({
      id: "network", eventName: "SessionStart", sessionId: "session-2",
      occurredAt: new Date().toISOString(), payload: {}
    });
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("offline")));

    expect(await flushOutbox(store, "https://control.example", "owner")).toBe(0);
    expect(store.pending()[0].lastError).toBe("TypeError");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps a managed binding until reconciliation verifies the native stop", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-managed", "session-managed");
    store.enqueue({
      id: "managed-stop", eventName: "SessionEnd", sessionId: "session-managed",
      occurredAt: new Date().toISOString(), payload: {}
    });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ status: "DONE" }), {
      status: 200, headers: { "content-type": "application/json" }
    })));
    expect(await flushOutbox(store, "https://control.example", "owner")).toBe(1);
    expect(store.managedTaskId()).toBe("task-managed");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps a terminal hook from erasing a protected native-stop rejection", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession(
      "task-protected",
      "session-protected",
      4100,
      "2026-07-15T03:00:00.000Z"
    );
    queueRejectedTaskLaunch(
      store,
      {
        id: "task-protected",
        title: "Protected",
        description: "Protected",
        status: "IN_PROGRESS",
        version: 7
      },
      "desktop_route_unverified",
      true
    );
    store.enqueue({
      id: "protected-stop",
      eventName: "SessionEnd",
      sessionId: "session-protected",
      taskId: "task-protected",
      occurredAt: new Date().toISOString(),
      payload: {}
    });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      status: "FAILED"
    }), {
      status: 200,
      headers: { "content-type": "application/json" }
    })));

    expect(await flushOutbox(store, "https://control.example", "owner")).toBe(1);
    expect(store.managedSessionForTask("task-protected")).toBe("session-protected");
    expect(store.managedProcessForTask("task-protected")).toEqual({
      processId: 4100,
      processStartedAt: "2026-07-15T03:00:00.000Z"
    });
    expect(store.pendingStopAcknowledgement("task-protected")).toContain(
      "agent-control-launch-rejection:"
    );
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("retries a protected native stop before reporting the launch rejection", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-protected", "session-protected");
    queueRejectedTaskLaunch(
      store,
      {
        id: "task-protected",
        title: "Protected",
        description: "Protected",
        status: "IN_PROGRESS",
        version: 7
      },
      "desktop_route_unverified",
      true
    );
    const pending = store.pendingStopAcknowledgement("task-protected")!;
    expect(pendingLaunchRejectionRequiresNativeStop(pending)).toBe(true);

    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    const retryNativeStop = vi.fn().mockImplementation(async (taskId: string) => {
      expect(taskId).toBe("task-protected");
      return markPendingLaunchRejectionNativeStopCompleted(store, taskId);
    });
    vi.stubGlobal("fetch", fetchMock);
    expect(await flushPendingStopAcknowledgements(
      store, "https://control.example", "owner", retryNativeStop
    )).toBe(1);
    expect(retryNativeStop).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://control.example/v1/tasks/task-protected/transition",
      expect.objectContaining({
        method: "POST",
        body: expect.stringContaining("desktop_route_unverified")
      })
    );
    expect(store.pendingStopAcknowledgement("task-protected")).toBeUndefined();
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("clears a stale managed task when the control plane marks it cancelled", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.setManagedTask("task-cancelled");
    const stop = vi.fn().mockResolvedValue(true);
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 1,
      tasks: [{ id: "task-cancelled", status: "CANCELLED" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await reconcileManagedTask(store, "https://control.example", "owner", stop)).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://control.example/v1/tasks/statuses",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ ids: ["task-cancelled"] })
      })
    );
    expect(stop).toHaveBeenCalledWith("task-cancelled", "CANCELLED");
    expect(store.managedTaskId()).toBeUndefined();
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("reconciles managed task statuses in bounded batches", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    for (let index = 0; index < 101; index += 1) {
      store.setManagedTask(`task-${index}`);
    }
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ tasks: [] }), {
        status: 200,
        headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ tasks: [] }), {
        status: 200,
        headers: { "content-type": "application/json" }
      }));
    vi.stubGlobal("fetch", fetchMock);

    expect(await reconcileManagedTasks(store, "https://control.example", "owner")).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetchMock.mock.calls[0]![1]!.body as string).ids).toHaveLength(100);
    expect(JSON.parse(fetchMock.mock.calls[1]![1]!.body as string).ids).toHaveLength(1);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("stops the exact managed Codex session before returning a running task to Listed", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-relisted", "session-relisted");
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 2,
      tasks: [{ id: "task-relisted", status: "INBOX" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTask(store, "https://control.example", "owner", stop)).toBe(true);
    expect(stop).toHaveBeenCalledOnce();
    expect(stop).toHaveBeenCalledWith("task-relisted", "INBOX");
    expect(store.managedTaskId()).toBeUndefined();
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps a relisted task tracked until its Desktop stop is actually accepted", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-opening", "session-opening");
    const stop = vi.fn().mockResolvedValue(false);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 2,
      tasks: [{ id: "task-opening", status: "INBOX" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTask(store, "https://control.example", "owner", stop)).toBe(false);
    expect(stop).toHaveBeenCalledWith("task-opening", "INBOX");
    expect(store.managedTaskId()).toBe("task-opening");
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps an opening Listed launch tracked until native stop proof is accepted", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-opening-listed");
    const stop = vi.fn().mockResolvedValue(false);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 2,
      tasks: [{ id: "task-opening-listed", status: "INBOX" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(
      store, "https://control.example", "owner", stop
    )).toBe(0);
    expect(stop).toHaveBeenCalledWith("task-opening-listed", "INBOX");
    expect(store.managedTaskIds()).toEqual(["task-opening-listed"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not clear a replacement session bound while the old stop is in flight", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-rebound", "session-old");
    const stop = vi.fn().mockImplementation(async () => {
      store.bindManagedSession("task-rebound", "session-new");
      return true;
    });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 2,
      tasks: [{ id: "task-rebound", status: "CANCELLED" }]
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(0);
    expect(store.managedSessionForTask("task-rebound")).toBe("session-new");
    expect(store.managedTaskIds()).toEqual(["task-rebound"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not clear managed work for an unrelated task omitted from a partial snapshot", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-visible", "session-visible");
    store.bindManagedSession("task-omitted", "session-omitted");
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 3,
      tasks: [{ id: "task-visible", status: "DONE" }]
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(1);
    expect(stop).toHaveBeenCalledWith("task-visible", "DONE");
    expect(store.managedTaskIds()).toEqual(["task-omitted"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("reconciles every live dashboard session instead of blocking Ready work behind one task", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-relisted", "session-relisted");
    store.bindManagedSession("task-running", "session-running");
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 3,
      tasks: [
        { id: "task-relisted", status: "INBOX" },
        { id: "task-running", status: "IN_PROGRESS" }
      ],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(1);
    expect(stop).toHaveBeenCalledWith("task-relisted", "INBOX");
    expect(store.managedTaskIds()).toEqual(["task-running"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it.each([
    "INBOX",
    "WAITING_NETWORK",
    "WAITING_PC",
    "WAITING_ANDROID",
    "WAITING_QUOTA",
    "WAITING_APPROVAL",
    "BLOCKED",
    "REVIEW",
    "FAILED",
    "DONE",
    "CANCELLED"
  ])("requires an acknowledged Desktop stop before clearing a managed %s task", async (status) => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    const taskId = `task-${status.toLowerCase()}`;
    store.bindManagedSession(taskId, `session-${status.toLowerCase()}`);
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 4,
      tasks: [{ id: taskId, status }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(1);
    expect(stop).toHaveBeenCalledOnce();
    expect(stop).toHaveBeenCalledWith(taskId, status);
    expect(store.managedTaskIds()).toEqual([]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it.each(["READY", "QUEUED"])(
    "does not stop a managed session while launch propagation still reports %s",
    async (status) => {
      const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
      const store = new AdapterStore(join(root, "adapter.db"));
      const taskId = `task-opening-${status.toLowerCase()}`;
      store.trackManagedTask(taskId);
      const stop = vi.fn().mockResolvedValue(true);
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
        cursor: 4,
        tasks: [{ id: taskId, status }],
        events: []
      }), { status: 200, headers: { "content-type": "application/json" } })));

      expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(0);
      expect(stop).not.toHaveBeenCalled();
      expect(store.managedTaskIds()).toEqual([taskId]);
      store.close();
      rmSync(root, { recursive: true, force: true });
    }
  );

  it.each(["READY", "QUEUED"])(
    "stops a pre-bind native process when ownership returns to %s",
    async (status) => {
      const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
      const store = new AdapterStore(join(root, "adapter.db"));
      const taskId = `task-pre-bind-${status.toLowerCase()}`;
      store.recordManagedProcess(taskId, 4200, "2026-07-15T03:01:00.000Z");
      const stop = vi.fn().mockResolvedValue(true);
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
        cursor: 4,
        tasks: [{ id: taskId, status }],
        events: []
      }), { status: 200, headers: { "content-type": "application/json" } })));

      expect(await reconcileManagedTasks(
        store,
        "https://control.example",
        "owner",
        stop
      )).toBe(1);
      expect(stop).toHaveBeenCalledWith(taskId, status);
      expect(store.managedTaskIds()).toEqual([]);
      store.close();
      rmSync(root, { recursive: true, force: true });
    }
  );

  it.each(["READY", "QUEUED"])(
    "stops an already-bound session when the owner returns it to %s",
    async (status) => {
      const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
      const store = new AdapterStore(join(root, "adapter.db"));
      const taskId = `task-bound-${status.toLowerCase()}`;
      store.bindManagedSession(taskId, `session-bound-${status.toLowerCase()}`);
      const stop = vi.fn().mockResolvedValue(true);
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
        cursor: 4,
        tasks: [{ id: taskId, status }],
        events: []
      }), { status: 200, headers: { "content-type": "application/json" } })));

      expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(1);
      expect(stop).toHaveBeenCalledWith(taskId, status);
      expect(store.managedTaskIds()).toEqual([]);
      store.close();
      rmSync(root, { recursive: true, force: true });
    }
  );

  it("does not stop a claim while the control plane still reports DISPATCHING", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-dispatching");
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 4,
      tasks: [{ id: "task-dispatching", status: "DISPATCHING" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(0);
    expect(stop).not.toHaveBeenCalled();
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("keeps a non-running task tracked when Desktop stop fails and still reconciles other sessions", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-stop-failed", "session-stop-failed");
    store.bindManagedSession("task-stop-ok", "session-stop-ok");
    const stop = vi.fn()
      .mockRejectedValueOnce(new Error("window_not_found"))
      .mockResolvedValueOnce(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 5,
      tasks: [
        { id: "task-stop-failed", status: "CANCELLED" },
        { id: "task-stop-ok", status: "DONE" }
      ],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(1);
    expect(stop).toHaveBeenCalledTimes(2);
    expect(store.managedTaskIds()).toEqual(["task-stop-failed"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("does not stop a session while its task is actively running or verifying", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-sync-"));
    const store = new AdapterStore(join(root, "adapter.db"));
    store.bindManagedSession("task-progress", "session-progress");
    const stop = vi.fn().mockResolvedValue(true);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      cursor: 6,
      tasks: [{ id: "task-progress", status: "VERIFYING" }],
      events: []
    }), { status: 200, headers: { "content-type": "application/json" } })));

    expect(await reconcileManagedTasks(store, "https://control.example", "owner", stop)).toBe(0);
    expect(stop).not.toHaveBeenCalled();
    expect(store.managedTaskIds()).toEqual(["task-progress"]);
    store.close();
    rmSync(root, { recursive: true, force: true });
  });

  it("claims compatible work and handles an empty queue", async () => {
    const task = { id: "task-1", title: "Test task", description: "Run it", status: "IN_PROGRESS", version: 3 };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ task }), {
        status: 200, headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetchMock);
    expect(await claimTask("https://control.example", "owner", "desktop-1")).toEqual(task);
    expect(await claimTask("https://control.example", "owner", "desktop-1")).toBeUndefined();
  });

  it("reports managed executor stages and returns the updated task version", async () => {
    const changed = {
      id: "task-1", title: "Test", description: "Run it", status: "IN_PROGRESS", version: 4,
      progressPercent: 15, currentStep: "Preparing"
    };
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify(changed), {
      status: 200, headers: { "content-type": "application/json" }
    }));
    vi.stubGlobal("fetch", fetchMock);
    const result = await updateTaskStage(
      "https://control.example", "owner",
      { id: "task-1", title: "Test", description: "Run it", status: "IN_PROGRESS", version: 3 },
      "Preparing", 15
    );
    expect(result).toEqual(changed);
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))).toEqual({
      currentStep: "Preparing",
      progressPercent: 15,
      expectedVersion: 3
    });
  });

  it("uploads evidence, verifies, and completes successful work", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("{}", { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ version: 4 }), {
        status: 200, headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ version: 5 }), {
        status: 200, headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await completeTask(
      "https://control.example",
      "owner",
      { id: "task-1", title: "Test", description: "Test", status: "IN_PROGRESS", version: 3 },
      "All checks passed",
      "windows-local:codex-final.txt",
      {
        source: "transcript",
        sessionId: "session-1",
        turnId: "turn-1",
        result: "DONE"
      }
    );
    expect(fetchMock.mock.calls.map((call) => String(call[0]))).toEqual([
      "https://control.example/v1/tasks/task-1/evidence",
      "https://control.example/v1/tasks/task-1/transition",
      "https://control.example/v1/tasks/task-1/progress",
      "https://control.example/v1/tasks/task-1/complete"
    ]);
    expect(JSON.parse(String((fetchMock.mock.calls[2][1] as RequestInit).body))).toEqual({
      currentStep: "Complete",
      progressPercent: 100,
      expectedVersion: 4
    });
  });

  it("refuses to send Done without transcript completion evidence", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    await expect(completeTask(
      "https://control.example",
      "owner",
      { id: "task-1", title: "Test", description: "Test", status: "IN_PROGRESS", version: 3 },
      "All checks passed",
      "windows-local:codex-final.txt"
    )).rejects.toThrow("completion_transcript_evidence_required");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("still completes after a non-authoritative final progress failure", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("{}", { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ version: 4 }), {
        status: 200, headers: { "content-type": "application/json" }
      }))
      .mockResolvedValueOnce(new Response("progress failed", { status: 503 }))
      .mockResolvedValueOnce(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await completeTask(
      "https://control.example", "owner",
      { id: "task-1", title: "Test", description: "Test", status: "IN_PROGRESS", version: 3 },
      "Session started", "windows-local:session.txt",
      {
        source: "transcript",
        sessionId: "session-1",
        turnId: "turn-1",
        result: "DONE"
      }
    );
    expect(String(fetchMock.mock.calls[3][0])).toBe("https://control.example/v1/tasks/task-1/complete");
  });

  it("reports failed Codex execution", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await failTask(
      "https://control.example",
      "owner",
      { id: "task-1", title: "Test", description: "Test", status: "IN_PROGRESS", version: 3 },
      "Codex exited with code 1"
    );
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))).toEqual({
      to: "FAILED",
      reason: "Codex exited with code 1",
      expectedVersion: 3
    });
  });

  it("fails a rejected native launch with the exact reason instead of silently relisting it", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await rejectTaskLaunch(
      "https://control.example",
      "owner",
      { id: "task-1", title: "Test", description: "Test", status: "IN_PROGRESS", version: 3 },
      "desktop_launch_model_unavailable:gpt-5.6-sol"
    );
    expect(String(fetchMock.mock.calls[0][0])).toBe("https://control.example/v1/tasks/task-1/transition");
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))).toEqual({
      to: "FAILED",
      reason: "Native Codex launch rejected: desktop_launch_model_unavailable:gpt-5.6-sol. No mission was accepted because native workspace, model, effort, running-turn, and Desktop-open proof did not all pass.",
      expectedVersion: 3
    });
  });
});
