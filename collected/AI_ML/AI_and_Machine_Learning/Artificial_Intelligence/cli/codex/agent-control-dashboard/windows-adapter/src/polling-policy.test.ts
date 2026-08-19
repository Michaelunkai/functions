import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  controlPlanePollMillis,
  controlPlaneRequestTimeoutMillis,
  heartbeatIntervalMillis,
  intervalDue,
  maxClaimsPerPoll,
  maxConcurrentSessions,
  reconciliationIntervalMillis,
  registrationRetryMillis
} from "./polling-policy.js";

describe("adapter polling policy", () => {
  it("keeps dispatch responsive without continuously rewriting presence state", () => {
    expect(controlPlanePollMillis()).toBe(1_000);
    expect(heartbeatIntervalMillis()).toBe(30_000);
    expect(registrationRetryMillis()).toBe(30_000);
    expect(reconciliationIntervalMillis()).toBe(3_000);
    expect(controlPlaneRequestTimeoutMillis()).toBe(15_000);
    expect(maxConcurrentSessions()).toBe(Infinity);
    expect(maxClaimsPerPoll()).toBe(Infinity);
  });

  it("fails closed to defaults for invalid interval overrides", () => {
    expect(controlPlanePollMillis("249")).toBe(1_000);
    expect(heartbeatIntervalMillis("999")).toBe(30_000);
    expect(registrationRetryMillis("invalid")).toBe(30_000);
    expect(reconciliationIntervalMillis("2999")).toBe(3_000);
    expect(controlPlaneRequestTimeoutMillis("999")).toBe(15_000);
    expect(maxConcurrentSessions("0")).toBe(Infinity);
    expect(maxClaimsPerPoll("invalid")).toBe(Infinity);
  });

  it("runs work immediately and then only when its interval is due", () => {
    expect(intervalDue(0, 10_000, 30_000)).toBe(true);
    expect(intervalDue(10_000, 39_999, 30_000)).toBe(false);
    expect(intervalDue(10_000, 40_000, 30_000)).toBe(true);
  });

  it("wires the throttled policy into the live server", () => {
    const root = dirname(fileURLToPath(import.meta.url));
    const server = readFileSync(join(root, "server.ts"), "utf8");
    expect(server).toContain("controlPlanePollMillis()");
    expect(server).toContain("heartbeatIntervalMillis()");
    expect(server).toContain("registrationRetryMillis()");
    expect(server).toContain("reconciliationIntervalMillis()");
    expect(server).toContain("maxConcurrentSessions()");
    expect(server).toContain("maxClaimsPerPoll()");
    expect(server).toContain("markPendingLaunchRejectionNativeStopCompleted");
    expect(server).not.toContain("CONTROL_PLANE_POLL_MILLIS = 250");
    expect(server).not.toContain("Number.MAX_SAFE_INTEGER");

    const sync = readFileSync(join(root, "sync.ts"), "utf8");
    expect(sync).toContain("controlPlaneRequestTimeoutMillis()");
    expect(sync).toContain("AbortSignal.timeout");
  });
});
