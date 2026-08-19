import { afterEach, describe, expect, it } from "vitest";
import { appendFileSync, mkdtempSync, readFileSync, rmSync, truncateSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import {
  MAX_TRANSCRIPT_READ_BYTES,
  TranscriptAppendReader
} from "./transcript-reader.js";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("TranscriptAppendReader", () => {
  it("reads only a bounded complete-record tail while preserving terminal records", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-transcript-"));
    roots.push(root);
    const path = join(root, "session.jsonl");
    const terminal = JSON.stringify({
      timestamp: "2026-07-15T10:00:00.000Z",
      type: "event_msg",
      payload: {
        type: "task_complete",
        turn_id: "turn-large",
        last_agent_message: "AGENT_CONTROL_RESULT: DONE"
      }
    });
    writeFileSync(path, `${"x".repeat(MAX_TRANSCRIPT_READ_BYTES * 4)}\n${terminal}\n`, "utf8");

    const reader = new TranscriptAppendReader();

    const tail = reader.readTail(path);

    expect(tail).toEqual([terminal]);
  });

  it("uses the bounded tail for exact-session terminal fallback", () => {
    const serverPath = join(dirname(fileURLToPath(import.meta.url)), "server.ts");
    const server = readFileSync(serverPath, "utf8");
    const fallback = server.slice(
      server.indexOf("const terminalTranscript = boundSession"),
      server.indexOf("const message = boundSession")
    );

    expect(fallback).toContain("transcriptReader.readTail(terminalTranscript)");
    expect(fallback).not.toContain("readFileSync(terminalTranscript");
  });

  it("bounds the initial tail and returns only newly appended complete records", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-transcript-"));
    roots.push(root);
    const path = join(root, "session.jsonl");
    const oldRecord = `${JSON.stringify({ payload: { type: "agent_message", message: "old" } })}\n`;
    const recentRecord = `${JSON.stringify({ payload: { type: "agent_message", message: "recent" } })}\n`;
    writeFileSync(
      path,
      `${oldRecord}${"x".repeat(MAX_TRANSCRIPT_READ_BYTES)}\n${recentRecord}`,
      "utf8"
    );

    const reader = new TranscriptAppendReader();
    const initial = reader.read(path);
    expect(initial.at(-1)?.text).toBe(recentRecord.trim());
    expect(initial.map((record) => record.text)).not.toContain(oldRecord.trim());
    expect(initial.reduce((length, record) => length + Buffer.byteLength(record.text), 0))
      .toBeLessThanOrEqual(MAX_TRANSCRIPT_READ_BYTES);
    expect(initial[0].byteOffset).toBeGreaterThan(0);
    expect(reader.read(path)).toEqual([]);

    const appended = `${JSON.stringify({ payload: { type: "agent_message", message: "appended" } })}\n`;
    appendFileSync(path, appended, "utf8");
    const update = reader.read(path);
    expect(update.map((record) => record.text)).toEqual([appended.trim()]);
    expect(update[0].byteOffset).toBeGreaterThan(initial[0].byteOffset);
  });

  it("keeps partial records until completion and recovers after truncation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-transcript-"));
    roots.push(root);
    const path = join(root, "session.jsonl");
    writeFileSync(path, '{"payload":{"type":"agent_message"', "utf8");
    const reader = new TranscriptAppendReader();

    expect(reader.read(path)).toEqual([]);
    appendFileSync(path, ',"message":"complete"}}\n', "utf8");
    expect(reader.read(path).map((record) => record.text)).toEqual([
      '{"payload":{"type":"agent_message","message":"complete"}}'
    ]);

    truncateSync(path, 0);
    const replacement = `${JSON.stringify({ payload: { type: "agent_message", message: "replacement" } })}\n`;
    appendFileSync(path, replacement, "utf8");
    expect(reader.read(path).map((record) => record.text)).toEqual([replacement.trim()]);
  });

  it("discards an oversized unterminated record while preserving later records", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-transcript-"));
    roots.push(root);
    const path = join(root, "session.jsonl");
    writeFileSync(path, '{"payload":{"type":"agent_message","message":"', "utf8");
    const reader = new TranscriptAppendReader();
    expect(reader.read(path)).toEqual([]);

    for (let index = 0; index < 6; index += 1) {
      appendFileSync(path, "x".repeat(MAX_TRANSCRIPT_READ_BYTES / 2), "utf8");
      expect(reader.read(path)).toEqual([]);
    }

    const recent = JSON.stringify({
      payload: { type: "agent_message", message: "bounded recovery" }
    });
    appendFileSync(path, `"}\n${recent}\n`, "utf8");
    expect(reader.read(path).map((record) => record.text)).toEqual([recent]);
  });
});
