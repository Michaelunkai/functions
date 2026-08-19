import { describe, expect, it } from "vitest";
import {
  extractTranscriptActivity,
  findTerminalTranscript,
  hasCompletionTranscript,
  hasTerminalTranscript,
  redactTranscriptText,
  sanitizeHookPayload
} from "./transcript-activity.js";

describe("extractTranscriptActivity", () => {
  it("preserves sanitized assistant commentary and allowlisted tool status in transcript order", () => {
    const lines = [
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "I am checking the live logs." } }),
      JSON.stringify({ type: "response_item", payload: {
        type: "function_call_output",
        output: "BUILD SUCCESSFUL\nInstalled version 16\nowner_token=do-not-copy"
      } })
    ];

    expect(extractTranscriptActivity(lines)).toEqual([
      { key: "0:agent_message", output: "I am checking the live logs." },
      { key: "1:function_call_output", output: "Tool status: BUILD SUCCESSFUL" }
    ]);
  });

  it("ignores private reasoning and empty records", () => {
    expect(extractTranscriptActivity([
      JSON.stringify({ type: "event_msg", payload: { type: "agent_reasoning", text: "private" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "" } })
    ])).toEqual([]);
  });

  it("coalesces repeated visible activity within one transcript lifecycle", () => {
    expect(extractTranscriptActivity([
      JSON.stringify({ type: "event_msg", payload: { type: "task_started", turn_id: "turn-1" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "Still working" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "Still working" } }),
      JSON.stringify({ type: "response_item", payload: {
        type: "function_call_output", output: "BUILD SUCCESSFUL"
      } }),
      JSON.stringify({ type: "response_item", payload: {
        type: "function_call_output", output: "BUILD SUCCESSFUL"
      } })
    ])).toEqual([
      { key: "1:agent_message", output: "Still working" },
      { key: "3:function_call_output", output: "Tool status: BUILD SUCCESSFUL" }
    ]);
  });

  it("does not emit stale activity after a completed lifecycle until a new task starts", () => {
    expect(extractTranscriptActivity([
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "Before completion" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "task_complete", turn_id: "turn-1" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "Stale tail" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "task_started", turn_id: "turn-2" } }),
      JSON.stringify({ type: "event_msg", payload: { type: "agent_message", message: "New lifecycle" } })
    ])).toEqual([
      { key: "0:agent_message", output: "Before completion" },
      { key: "4:agent_message", output: "New lifecycle" }
    ]);
  });

  it("does not persist arbitrary structured tool output", () => {
    const lines = [JSON.stringify({
      type: "response_item",
      payload: { type: "custom_tool_call_output", output: [
        { type: "input_text", text: "Private file contents\nWall time 0.0 seconds\nOutput:\n" },
        { type: "input_text", text: "arbitrary secret-bearing output" }
      ] }
    })];
    expect(extractTranscriptActivity(lines)).toEqual([
      {
        key: "0:custom_tool_call_output",
        output: "Tool completed; detailed output retained only in the native Codex session."
      }
    ]);
  });

  it("redacts configured and common credential forms from visible commentary", () => {
    const ownerToken = "live-owner-token-value";
    const lines = [JSON.stringify({
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: [
          `Owner token: ${ownerToken}`,
          "Authorization: Bearer bearer-value",
          "api_key=api-value",
          "OPENAI_API_KEY=openai-value",
          "client_secret=client-value",
          "github_token=github-value",
          "DATABASE_URL=postgres-value",
          '{"api_key":"json-api-value","AWS_SECRET_ACCESS_KEY":"aws-secret-value"}',
          "providerCredentials=opaque-provider-value",
          "password: password-value",
          "sk-proj-abcdefghijklmnop"
        ].join("\n")
      }
    })];

    const [activity] = extractTranscriptActivity(lines, [ownerToken]);
    expect(activity.output).not.toContain(ownerToken);
    expect(activity.output).not.toContain("bearer-value");
    expect(activity.output).not.toContain("api-value");
    expect(activity.output).not.toContain("openai-value");
    expect(activity.output).not.toContain("client-value");
    expect(activity.output).not.toContain("github-value");
    expect(activity.output).not.toContain("postgres-value");
    expect(activity.output).not.toContain("json-api-value");
    expect(activity.output).not.toContain("aws-secret-value");
    expect(activity.output).not.toContain("opaque-provider-value");
    expect(activity.output).not.toContain("password-value");
    expect(activity.output).not.toContain("abcdefghijklmnop");
    expect(activity.output.match(/\[REDACTED]/g)?.length).toBeGreaterThanOrEqual(12);
  });

  it("redacts terminal summaries while leaving the result marker intact", () => {
    expect(redactTranscriptText(
      "Finished with owner_token=top-secret\nAGENT_CONTROL_RESULT: DONE"
    )).toBe("Finished with owner_token=[REDACTED]\nAGENT_CONTROL_RESULT: DONE");
  });

  it("redacts complete quoted credential values including whitespace", () => {
    const text = [
      'owner_token="quoted owner token with spaces"',
      "api_key='quoted api key with spaces'",
      'DATABASE_URL="postgres://user:password with spaces@database/private"'
    ].join("\n");

    expect(redactTranscriptText(text)).toBe([
      'owner_token="[REDACTED]"',
      "api_key='[REDACTED]'",
      'DATABASE_URL="[REDACTED]"'
    ].join("\n"));
  });

  it("recursively sanitizes hook credentials, working directories, and arbitrary tool output", () => {
    const ownerToken = "live-owner-token-value";
    expect(sanitizeHookPayload({
      hook_event_name: "PostToolUse",
      session_id: "session-safe",
      cwd: "C:\\Users\\operator\\private-repository",
      authorization: `Bearer ${ownerToken}`,
      nested: {
        api_key: "api-secret",
        OPENAI_API_KEY: "openai-secret",
        client_secret: "client-secret",
        AWS_SECRET_ACCESS_KEY: "aws-secret",
        providerCredentials: "provider-secret",
        message: `owner_token=${ownerToken}`,
        tool_output: "Private file contents and credentials"
      }
    }, "PostToolUse", [ownerToken])).toEqual({
      hook_event_name: "PostToolUse",
      session_id: "session-safe",
      cwd: "private-repository",
      authorization: "[REDACTED]",
      nested: {
        api_key: "[REDACTED]",
        OPENAI_API_KEY: "[REDACTED]",
        client_secret: "[REDACTED]",
        AWS_SECRET_ACCESS_KEY: "[REDACTED]",
        providerCredentials: "[REDACTED]",
        message: "owner_token=[REDACTED]",
        tool_output: "Tool completed; detailed output retained only in the native Codex session."
      }
    });
  });

  it("uses a native task_complete record as durable proof that a bound turn is no longer running", () => {
    expect(hasTerminalTranscript([
      JSON.stringify({ type: "event_msg", payload: { type: "task_started" } }),
      JSON.stringify({ type: "event_msg", payload: {
        type: "task_complete", turn_id: "turn-1", last_agent_message: null
      } })
    ])).toBe(true);
    expect(hasTerminalTranscript([
      JSON.stringify({ type: "event_msg", payload: { type: "task_started" } })
    ])).toBe(false);
  });

  it("requires the DONE result marker in addition to task_complete for completion evidence", () => {
    const incomplete = [
      JSON.stringify({ type: "event_msg", payload: { type: "task_complete", turn_id: "turn-1" } })
    ];
    const complete = [
      JSON.stringify({ type: "event_msg", payload: {
        type: "task_complete",
        turn_id: "turn-1",
        last_agent_message: "Verified\nAGENT_CONTROL_RESULT: DONE"
      } })
    ];
    expect(hasCompletionTranscript(incomplete)).toBe(false);
    expect(hasCompletionTranscript(complete)).toBe(true);
  });

  it("accepts the previous hyphenated terminal marker contract", () => {
    const record = JSON.stringify({
      timestamp: "2026-07-15T12:00:01.000Z",
      type: "event_msg",
      payload: {
        type: "task_complete",
        turn_id: "turn-hyphenated",
        last_agent_message:
          "Verified\nAGENT_CONTROL_RESULT: DONE - only after the requested result is implemented and verified"
      }
    });
    expect(findTerminalTranscript([record], "2026-07-15T12:00:00.000Z")).toEqual({
      turnId: "turn-hyphenated",
      lastAgentMessage:
        "Verified\nAGENT_CONTROL_RESULT: DONE - only after the requested result is implemented and verified",
      result: "DONE"
    });
  });

  it("ignores a historical completion before the managed process and imports the current completion", () => {
    const processStartedAt = "2026-07-14T12:00:00.000Z";
    const historicalCompletion = JSON.stringify({
      timestamp: "2026-07-14T11:59:59.000Z",
      type: "event_msg",
      payload: {
        type: "task_complete",
        turn_id: "turn-old",
        last_agent_message: "Old result\nAGENT_CONTROL_RESULT: DONE"
      }
    });
    const currentTurnStarted = JSON.stringify({
      timestamp: "2026-07-14T12:00:01.000Z",
      type: "event_msg",
      payload: { type: "task_started", turn_id: "turn-current" }
    });
    const currentCompletion = JSON.stringify({
      timestamp: "2026-07-14T12:00:02.000Z",
      type: "event_msg",
      payload: {
        type: "task_complete",
        turn_id: "turn-current",
        last_agent_message: "Current result\nAGENT_CONTROL_RESULT: DONE"
      }
    });

    const beforeCurrentCompletion = [historicalCompletion, currentTurnStarted];
    expect(hasTerminalTranscript(beforeCurrentCompletion, processStartedAt)).toBe(false);
    expect(findTerminalTranscript(beforeCurrentCompletion, processStartedAt)).toBeUndefined();

    const transcript = [...beforeCurrentCompletion, currentCompletion];
    expect(hasTerminalTranscript(transcript, processStartedAt)).toBe(true);
    expect(findTerminalTranscript(transcript, processStartedAt)).toEqual({
      turnId: "turn-current",
      lastAgentMessage: "Current result\nAGENT_CONTROL_RESULT: DONE",
      result: "DONE"
    });
  });
});
