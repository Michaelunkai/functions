import { afterEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { AdapterStore } from "./store.js";
import { stopOpenedSessionBeforeBinding } from "./launch-race.js";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("stopOpenedSessionBeforeBinding", () => {
  it("preserves the exact opened thread before stopping a pre-bind launch", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-race-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-opening");

    let stoppedSessionId = "";
    expect(await stopOpenedSessionBeforeBinding(
      store,
      "task-opening",
      "thread-exact",
      async (openedSessionId) => {
        stoppedSessionId = openedSessionId;
        return true;
      }
    )).toBe(true);
    expect(stoppedSessionId).toBe("thread-exact");
    expect(store.managedTaskIds()).toEqual([]);
    store.close();
  });

  it("keeps ownership and the exact thread durable while a pre-bind stop still needs retry", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-race-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-opening");

    let stoppedSessionId = "";
    expect(await stopOpenedSessionBeforeBinding(
      store,
      "task-opening",
      "thread-exact",
      async (openedSessionId) => {
        stoppedSessionId = openedSessionId;
        return false;
      }
    )).toBe(false);
    expect(stoppedSessionId).toBe("thread-exact");
    expect(store.managedTaskIds()).toEqual(["task-opening"]);
    store.close();
  });

  it("does not clear the managed claim before the native stop proves terminal state", async () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-launch-race-"));
    roots.push(root);
    const store = new AdapterStore(join(root, "adapter.db"));
    store.trackManagedTask("task-opening");
    store.recordManagedProcess(
      "task-opening",
      4321,
      "2026-07-15T16:00:00.000Z"
    );

    let stopAttempts = 0;
    expect(await stopOpenedSessionBeforeBinding(
      store,
      "task-opening",
      "thread-exact",
      async () => {
        stopAttempts += 1;
        return false;
      }
    )).toBe(false);
    expect(stopAttempts).toBe(1);
    expect(store.managedTaskIds()).toEqual(["task-opening"]);
    expect(store.managedProcessForTask("task-opening")).toEqual({
      processId: 4321,
      processStartedAt: "2026-07-15T16:00:00.000Z"
    });
    store.close();
  });
});
