import { createServer, type Server } from "node:http";
import { randomUUID, timingSafeEqual } from "node:crypto";
import { AdapterStore, type HookEnvelope } from "./store.js";

const resultMarker =
  /^\s*AGENT_CONTROL_RESULT:\s*(DONE|WAITING|FAILED)(?:\s+-\s+[^\r\n]+)?\s*$/i;
const MAX_HOOK_BODY_BYTES = 64 * 1024;
const HOOK_SECRET_HEADER = "x-agent-control-hook-secret";

export function normalizeHookPayload(payload: Record<string, unknown>): Record<string, unknown> {
  if (payload.hook_event_name !== "Stop" || typeof payload.last_assistant_message !== "string") {
    return payload;
  }
  const message = payload.last_assistant_message.trim();
  const lines = message.split(/\r?\n/);
  const matches = lines
    .map((line, index) => ({ index, match: line.match(resultMarker) }))
    .filter((entry): entry is { index: number; match: RegExpMatchArray } => entry.match !== null);
  let finalLine = lines.length - 1;
  while (finalLine >= 0 && lines[finalLine]?.trim().length === 0) finalLine -= 1;
  if (matches.length !== 1 || matches[0]?.index !== finalLine) return payload;
  const result = matches[0].match[1];
  const resultSummary = lines.slice(0, finalLine).join("\n").trim().slice(0, 4_000);
  return {
    ...payload,
    agent_control_result: result,
    result_summary: resultSummary || `Codex reported ${result.toLowerCase()}`
  };
}

export function createAdapterHttpServer(
  store: AdapterStore,
  hookSecret: string,
  createId: () => string = randomUUID
): Server {
  if (hookSecret.trim().length === 0) {
    throw new Error("Agent Control hook secret is required.");
  }

  return createServer((request, response) => {
    const authorized = (): boolean => {
      const providedSecret = request.headers[HOOK_SECRET_HEADER];
      return typeof providedSecret === "string" &&
        Buffer.byteLength(providedSecret) === Buffer.byteLength(hookSecret) &&
        timingSafeEqual(Buffer.from(providedSecret), Buffer.from(hookSecret));
    };
    const rejectUnauthorized = () => {
      response.writeHead(401, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "unauthorized" }));
    };
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ status: "ok" }));
      return;
    }
    if (request.method === "GET" && request.url === "/health/details") {
      if (!authorized()) {
        rejectUnauthorized();
        return;
      }
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        status: "ok",
        pending: store.pending().length,
        managedTaskId: store.managedTaskId() ?? null
      }));
      return;
    }
    if (request.method !== "POST" || request.url !== "/hooks") {
      response.writeHead(404).end();
      return;
    }
    if (!authorized()) {
      request.resume();
      rejectUnauthorized();
      return;
    }
    const chunks: Buffer[] = [];
    let bodyBytes = 0;
    let rejected = false;
    request.on("data", (chunk: Buffer) => {
      if (rejected) return;
      bodyBytes += chunk.length;
      if (bodyBytes > MAX_HOOK_BODY_BYTES) {
        rejected = true;
        response.writeHead(413, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "hook_payload_too_large" }));
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      if (rejected) return;
      try {
        const rawPayload = JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
        const rawEventName = String(rawPayload.hook_event_name ?? rawPayload.event ?? "");
        const payload = normalizeHookPayload(store.sanitizePayload(rawPayload, rawEventName));
        const eventName = String(payload.hook_event_name ?? payload.event ?? "");
        const sessionId = String(payload.session_id ?? "");
        if (!eventName || !sessionId) {
          response.writeHead(400, { "content-type": "application/json" });
          response.end(JSON.stringify({ error: "event_and_session_required" }));
          return;
        }
        const envelope: HookEnvelope = {
          id: String(payload.event_id ?? createId()),
          eventName,
          sessionId,
          occurredAt: new Date().toISOString(),
          payload
        };
        store.enqueue(envelope);
        response.writeHead(202, { "content-type": "application/json" });
        response.end(JSON.stringify({ id: envelope.id }));
      } catch {
        response.writeHead(400, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "invalid_json" }));
      }
    });
  });
}
