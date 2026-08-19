import {
  closeSync,
  existsSync,
  openSync,
  readSync,
  renameSync,
  unlinkSync,
  writeFileSync
} from "node:fs";
import { randomUUID } from "node:crypto";
import { AdapterStore, type HookEnvelope } from "./store.js";
import { normalizeHookPayload } from "./http-server.js";

export interface FallbackImportResult {
  imported: number;
  invalid: number;
}

export const MAX_FALLBACK_LINE_BYTES = 64 * 1024;
export const MAX_FALLBACK_INVALID_LINES = 128;
const FALLBACK_READ_CHUNK_BYTES = 64 * 1024;

function* readFallbackLines(path: string): Generator<string | undefined> {
  const descriptor = openSync(path, "r");
  const buffer = Buffer.allocUnsafe(FALLBACK_READ_CHUNK_BYTES);
  let fragments: Buffer[] = [];
  let fragmentBytes = 0;
  let discardingOversize = false;
  try {
    for (;;) {
      const bytesRead = readSync(descriptor, buffer, 0, buffer.length, null);
      if (bytesRead === 0) break;
      const chunk = Buffer.from(buffer.subarray(0, bytesRead));
      let start = 0;
      for (;;) {
        const newline = chunk.indexOf(0x0a, start);
        const end = newline < 0 ? chunk.length : newline;
        const segment = chunk.subarray(start, end);
        if (!discardingOversize) {
          if (fragmentBytes + segment.length > MAX_FALLBACK_LINE_BYTES) {
            fragments = [];
            fragmentBytes = 0;
            discardingOversize = true;
          } else if (segment.length > 0) {
            fragments.push(segment);
            fragmentBytes += segment.length;
          }
        }
        if (newline < 0) break;
        if (discardingOversize) {
          yield undefined;
        } else {
          const line = Buffer.concat(fragments, fragmentBytes).toString("utf8")
            .replace(/^\uFEFF/, "")
            .replace(/\r$/, "");
          yield line;
        }
        fragments = [];
        fragmentBytes = 0;
        discardingOversize = false;
        start = newline + 1;
      }
    }
    if (discardingOversize) yield undefined;
    else if (fragmentBytes > 0) {
      yield Buffer.concat(fragments, fragmentBytes).toString("utf8")
        .replace(/^\uFEFF/, "")
        .replace(/\r$/, "");
    }
  } finally {
    closeSync(descriptor);
  }
}

export function importHookFallback(store: AdapterStore, path: string): FallbackImportResult {
  if (!existsSync(path)) return { imported: 0, invalid: 0 };

  const claimedPath = `${path}.${process.pid}.${Date.now()}.processing`;
  try {
    renameSync(path, claimedPath);
  } catch {
    return { imported: 0, invalid: 0 };
  }

  const invalidLines: string[] = [];
  let imported = 0;
  let invalid = 0;
  for (const line of readFallbackLines(claimedPath)) {
    if (line === undefined) {
      if (invalid < MAX_FALLBACK_INVALID_LINES) invalid += 1;
      if (invalidLines.length < MAX_FALLBACK_INVALID_LINES) {
        invalidLines.push(JSON.stringify({
          error: "invalid_hook_payload",
          occurred_at: new Date().toISOString()
        }));
      }
      continue;
    }
    if (!line.trim()) continue;
    try {
      const rawPayload = JSON.parse(line) as Record<string, unknown>;
      const rawEventName = String(rawPayload.hook_event_name ?? rawPayload.event ?? "");
      const payload = normalizeHookPayload(store.sanitizePayload(rawPayload, rawEventName));
      const eventName = String(payload.hook_event_name ?? payload.event ?? "");
      const sessionId = String(payload.session_id ?? "");
      if (!eventName || !sessionId) throw new Error("event_and_session_required");
      const envelope: HookEnvelope = {
        id: String(payload.event_id ?? randomUUID()),
        eventName,
        sessionId,
        occurredAt: new Date().toISOString(),
        payload
      };
      store.enqueue(envelope);
      imported += 1;
    } catch {
      if (invalid < MAX_FALLBACK_INVALID_LINES) invalid += 1;
      if (invalidLines.length < MAX_FALLBACK_INVALID_LINES) {
        invalidLines.push(JSON.stringify({
          error: "invalid_hook_payload",
          occurred_at: new Date().toISOString()
        }));
      }
    }
  }

  if (invalidLines.length > 0) {
    writeFileSync(`${claimedPath}.invalid`, `${invalidLines.join("\n")}\n`, "utf8");
  }
  unlinkSync(claimedPath);
  return { imported, invalid };
}

export function importHookFallbackFiles(
  store: AdapterStore,
  path: string
): FallbackImportResult {
  const previous = importHookFallback(store, `${path}.previous`);
  const current = importHookFallback(store, path);
  return {
    imported: previous.imported + current.imported,
    invalid: previous.invalid + current.invalid
  };
}
