import { afterEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import { AdapterStore } from "./store.js";
import { createAdapterHttpServer } from "./http-server.js";

const cleanups: Array<() => void> = [];
const hookSecret = randomUUID();
const authenticatedHookHeaders = {
  "content-type": "application/json",
  "x-agent-control-hook-secret": hookSecret
};
afterEach(() => {
  for (const cleanup of cleanups.splice(0).reverse()) cleanup();
});

describe("adapter HTTP server", () => {
  it("rejects unauthenticated hook posts without mutating the outbox", async () => {
    const { baseUrl, store } = await startServer();

    const response = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        hook_event_name: "SessionStart",
        session_id: "unauthenticated-hook"
      })
    });

    expect(response.status).toBe(401);
    expect(store.pending()).toEqual([]);
  });

  it("accepts authenticated hooks without exposing adapter activity in health", async () => {
    const { baseUrl, store } = await startServer();
    const hook = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({ hook_event_name: "SessionStart", session_id: "session-http" })
    });
    expect(hook.status).toBe(202);
    expect(await hook.json()).toEqual({ id: "generated-id" });
    const health = await fetch(`${baseUrl}/health`);
    expect(await health.json()).toEqual({ status: "ok" });
    expect(store.activeTaskId()).toBe("codex:session-http");
  });

  it("requires the hook credential for adapter activity details", async () => {
    const { baseUrl, store } = await startServer();
    store.trackManagedTask("task-private-health");

    expect((await fetch(`${baseUrl}/health/details`)).status).toBe(401);
    const response = await fetch(`${baseUrl}/health/details`, {
      headers: { "x-agent-control-hook-secret": hookSecret }
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      pending: 0,
      managedTaskId: "task-private-health"
    });
  });

  it("rejects invalid routes and payloads", async () => {
    const { baseUrl } = await startServer();
    expect((await fetch(`${baseUrl}/missing`)).status).toBe(404);
    expect((await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: "{"
    })).status).toBe(400);
    expect((await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({ session_id: "missing-event" })
    })).status).toBe(400);
  });

  it("rejects oversized hook payloads before persistence", async () => {
    const { baseUrl, store } = await startServer();
    const response = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({
        hook_event_name: "PostToolUse",
        session_id: "oversized",
        tool_output: "x".repeat(70 * 1024)
      })
    });
    expect(response.status).toBe(413);
    expect(store.pending()).toEqual([]);
  });

  it("derives a verified mission result from the documented Stop message", async () => {
    const { baseUrl, store } = await startServer();
    const response = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({
        hook_event_name: "Stop",
        session_id: "session-result",
        last_assistant_message: "Tests passed.\n\nAGENT_CONTROL_RESULT: DONE"
      })
    });
    expect(response.status).toBe(202);
    expect(store.pending()[0]?.envelope.payload).toEqual(expect.objectContaining({
      agent_control_result: "DONE",
      result_summary: "Tests passed."
    }));
  });

  it("normalizes the previous hyphenated mission result contract", async () => {
    const { baseUrl, store } = await startServer();
    const response = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({
        hook_event_name: "Stop",
        session_id: "session-hyphenated-result",
        last_assistant_message:
          "Verified the mission.\nAGENT_CONTROL_RESULT: DONE - only after verification"
      })
    });
    expect(response.status).toBe(202);
    expect(store.pending()[0]?.envelope.payload).toEqual(expect.objectContaining({
      agent_control_result: "DONE",
      result_summary: "Verified the mission."
    }));
  });

  it("sanitizes direct HTTP hook payloads before durable persistence", async () => {
    const ownerToken = "http-owner-token";
    const { baseUrl, store } = await startServer([ownerToken]);
    const response = await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({
        hook_event_name: "PostToolUse",
        session_id: "session-private-http",
        cwd: "C:\\Users\\operator\\private-repository",
        owner_token: ownerToken,
        tool_output: `Private output ${ownerToken}`
      })
    });

    expect(response.status).toBe(202);
    const serialized = JSON.stringify(store.pending()[0].envelope.payload);
    expect(serialized).not.toContain(ownerToken);
    expect(serialized).not.toContain("C:\\\\Users\\\\operator");
    expect(serialized).not.toContain("Private output");
  });

  it("does not infer completion when a Stop message has no result marker", async () => {
    const { baseUrl, store } = await startServer();
    await fetch(`${baseUrl}/hooks`, {
      method: "POST",
      headers: authenticatedHookHeaders,
      body: JSON.stringify({
        hook_event_name: "Stop",
        session_id: "session-interrupted",
        last_assistant_message: "Partial work only"
      })
    });
    expect(store.pending()[0]?.envelope.payload).not.toHaveProperty("agent_control_result");
  });

  it("rejects duplicate or non-final result markers as ambiguous", async () => {
    const { baseUrl, store } = await startServer();
    for (const [index, lastAssistantMessage] of [
      "AGENT_CONTROL_RESULT: DONE\nAGENT_CONTROL_RESULT: FAILED",
      "AGENT_CONTROL_RESULT: DONE\nAdditional unverified text"
    ].entries()) {
      await fetch(`${baseUrl}/hooks`, {
        method: "POST",
        headers: authenticatedHookHeaders,
        body: JSON.stringify({
          hook_event_name: "Stop",
          session_id: `session-ambiguous-${index}`,
          last_assistant_message: lastAssistantMessage
        })
      });
    }
    for (const pending of store.pending()) {
      expect(pending.envelope.payload).not.toHaveProperty("agent_control_result");
    }
  });
});

async function startServer(
  sensitiveValues: readonly string[] = []
): Promise<{ baseUrl: string; store: AdapterStore }> {
  const root = mkdtempSync(join(tmpdir(), "agent-control-http-"));
  const store = new AdapterStore(join(root, "adapter.db"), sensitiveValues);
  const server = createAdapterHttpServer(store, hookSecret, () => "generated-id");
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  cleanups.push(() => {
    server.close();
    store.close();
    rmSync(root, { recursive: true, force: true });
  });
  return { baseUrl: `http://127.0.0.1:${port}`, store };
}
