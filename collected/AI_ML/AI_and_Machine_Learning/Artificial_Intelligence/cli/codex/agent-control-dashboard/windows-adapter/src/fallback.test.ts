import { afterEach, describe, expect, it } from "vitest";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  MAX_FALLBACK_INVALID_LINES,
  MAX_FALLBACK_LINE_BYTES,
  importHookFallback,
  importHookFallbackFiles
} from "./fallback.js";
import { AdapterStore } from "./store.js";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("importHookFallback", () => {
  it("atomically imports valid hook events into the durable outbox", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `${JSON.stringify({
      event_id: "fallback-1",
      hook_event_name: "SessionStart",
      session_id: "session-1"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 0 });
    expect(store.pending()[0].envelope.id).toBe("fallback-1");
    expect(store.activeTaskId()).toBe("codex:session-1");
    expect(existsSync(path)).toBe(false);
    store.close();
  });

  it("sanitizes legacy fallback entries before importing them", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    const ownerToken = "fallback-owner-token";
    writeFileSync(path, `${JSON.stringify({
      event_id: "fallback-private",
      hook_event_name: "PostToolUse",
      session_id: "session-private",
      cwd: "C:\\Users\\operator\\private-repository",
      owner_token: ownerToken,
      tool_output: `Private output ${ownerToken}`
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"), [ownerToken]);

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 0 });
    const serialized = JSON.stringify(store.pending()[0].envelope.payload);
    expect(serialized).not.toContain(ownerToken);
    expect(serialized).not.toContain("C:\\\\Users\\\\operator");
    expect(serialized).not.toContain("Private output");
    store.close();
  });

  it("normalizes an exact final Stop result marker during fallback replay", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `${JSON.stringify({
      event_id: "fallback-stop",
      hook_event_name: "Stop",
      session_id: "session-stop",
      last_assistant_message: "Implemented and verified.\nAGENT_CONTROL_RESULT: DONE"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 0 });
    expect(store.pending()[0].envelope.payload).toMatchObject({
      agent_control_result: "DONE",
      result_summary: "Implemented and verified."
    });
    store.close();
  });

  it("does not normalize an embedded result marker as terminal completion", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `${JSON.stringify({
      event_id: "fallback-embedded-result",
      hook_event_name: "Stop",
      session_id: "session-embedded-result",
      last_assistant_message: "AGENT_CONTROL_RESULT: DONE while still explaining the work"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 0 });
    expect(store.pending()[0].envelope.payload).not.toHaveProperty("agent_control_result");
    store.close();
  });

  it("retains only a privacy-safe malformed-line marker without blocking valid events", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `not-json\n${JSON.stringify({
      hook_event_name: "Stop",
      session_id: "session-2"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 1 });
    const invalid = findFile(root, ".invalid");
    const invalidContents = readFileSync(invalid, "utf8");
    expect(invalidContents).toContain("invalid_hook_payload");
    expect(invalidContents).not.toContain("not-json");
    store.close();
  });

  it("streams fallback replay and rejects oversized lines without retaining their contents", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `${"s".repeat(MAX_FALLBACK_LINE_BYTES + 1)}\n${JSON.stringify({
      event_id: "fallback-after-oversize",
      hook_event_name: "SessionStart",
      session_id: "session-after-oversize"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({ imported: 1, invalid: 1 });
    expect(store.pending()[0].envelope.id).toBe("fallback-after-oversize");
    const invalidContents = readFileSync(findFile(root, ".invalid"), "utf8");
    expect(invalidContents).not.toContain("ssss");
    store.close();
  });

  it("bounds malformed-line accounting and diagnostics without blocking later valid events", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(path, `${"not-json\n".repeat(MAX_FALLBACK_INVALID_LINES + 25)}${JSON.stringify({
      event_id: "fallback-after-invalid-burst",
      hook_event_name: "SessionStart",
      session_id: "session-after-invalid-burst"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallback(store, path)).toEqual({
      imported: 1,
      invalid: MAX_FALLBACK_INVALID_LINES
    });
    expect(store.pending()[0].envelope.id).toBe("fallback-after-invalid-burst");
    const invalidContents = readFileSync(findFile(root, ".invalid"), "utf8");
    expect(invalidContents.trim().split("\n")).toHaveLength(MAX_FALLBACK_INVALID_LINES);
    expect(invalidContents.length).toBeLessThan(16 * 1024);
    store.close();
  });

  it("replays a rotated fallback before the active file and accepts a UTF-8 BOM", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-fallback-"));
    roots.push(root);
    const path = join(root, "hook-fallback.jsonl");
    writeFileSync(`${path}.previous`, `\uFEFF${JSON.stringify({
      event_id: "fallback-previous",
      hook_event_name: "SessionStart",
      session_id: "session-previous"
    })}\n`, "utf8");
    writeFileSync(path, `${JSON.stringify({
      event_id: "fallback-current",
      hook_event_name: "SessionEnd",
      session_id: "session-current"
    })}\n`, "utf8");
    const store = new AdapterStore(join(root, "adapter.db"));

    expect(importHookFallbackFiles(store, path)).toEqual({ imported: 2, invalid: 0 });
    expect(store.pending().map((item) => item.envelope.id)).toEqual([
      "fallback-previous",
      "fallback-current"
    ]);
    store.close();
  });
});

function findFile(root: string, suffix: string): string {
  const match = readdirSync(root).find((name) => name.endsWith(suffix));
  if (!match) throw new Error(`No ${suffix} file found`);
  return join(root, match);
}
