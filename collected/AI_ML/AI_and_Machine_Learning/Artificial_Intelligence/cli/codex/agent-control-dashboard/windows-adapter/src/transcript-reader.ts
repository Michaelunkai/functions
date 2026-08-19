import {
  closeSync,
  openSync,
  readSync,
  statSync
} from "node:fs";
import type { TranscriptRecord } from "./transcript-activity.js";

export const MAX_TRANSCRIPT_READ_BYTES = 256 * 1024;

interface TranscriptReadState {
  size: number;
  trailing: Buffer;
  trailingOffset: number;
  suffix: Buffer;
  discardingPartial: boolean;
}

function readRange(path: string, start: number, length: number): Buffer {
  if (length <= 0) return Buffer.alloc(0);
  const descriptor = openSync(path, "r");
  try {
    const buffer = Buffer.allocUnsafe(length);
    const bytesRead = readSync(descriptor, buffer, 0, length, start);
    return buffer.subarray(0, bytesRead);
  } finally {
    closeSync(descriptor);
  }
}

export class TranscriptAppendReader {
  private readonly states = new Map<string, TranscriptReadState>();

  readTail(path: string): string[] {
    const size = statSync(path).size;
    const start = Math.max(0, size - MAX_TRANSCRIPT_READ_BYTES);
    const content = readRange(path, start, size - start);
    const firstNewline = start > 0 ? content.indexOf(0x0a) : -1;
    const complete = firstNewline >= 0 ? content.subarray(firstNewline + 1) : content;
    const text = complete.toString("utf8");
    return text.split(/\r?\n/).filter(Boolean);
  }

  read(path: string): TranscriptRecord[] {
    const size = statSync(path).size;
    const previous = this.states.get(path);
    if (previous && size === previous.size) return [];

    const previousSuffixStart = previous
      ? Math.max(0, previous.size - previous.suffix.length)
      : 0;
    const previousSuffixMatches = previous
      ? readRange(path, previousSuffixStart, previous.suffix.length).equals(previous.suffix)
      : false;
    const canAppend = previous && size > previous.size &&
      size - previous.size <= MAX_TRANSCRIPT_READ_BYTES &&
      previousSuffixMatches;
    let start = canAppend ? previous.size : Math.max(0, size - MAX_TRANSCRIPT_READ_BYTES);
    let baseOffset = canAppend ? previous.trailingOffset : start;
    let content = canAppend ? previous.trailing : Buffer.alloc(0);
    const appended = readRange(path, start, size - start);
    let discardingPartial = Boolean(canAppend && previous.discardingPartial);
    if (discardingPartial) {
      const firstNewline = appended.indexOf(0x0a);
      if (firstNewline < 0) {
        this.states.set(path, {
          size,
          trailing: Buffer.alloc(0),
          trailingOffset: size,
          suffix: readRange(path, Math.max(0, size - 64), Math.min(64, size)),
          discardingPartial: true
        });
        return [];
      }
      content = appended.subarray(firstNewline + 1);
      baseOffset = start + firstNewline + 1;
      discardingPartial = false;
    } else {
      content = Buffer.concat([content, appended]);
    }

    if (!canAppend && start > 0) {
      const firstNewline = content.indexOf(0x0a);
      if (firstNewline < 0) {
        this.states.set(path, {
          size,
          trailing: Buffer.alloc(0),
          trailingOffset: size,
          suffix: readRange(path, Math.max(0, size - 64), Math.min(64, size)),
          discardingPartial: true
        });
        return [];
      }
      content = content.subarray(firstNewline + 1);
      baseOffset = start + firstNewline + 1;
    }

    const records: TranscriptRecord[] = [];
    let lineStart = 0;
    for (;;) {
      const newline = content.indexOf(0x0a, lineStart);
      if (newline < 0) break;
      const lineEnd = newline > lineStart && content[newline - 1] === 0x0d
        ? newline - 1
        : newline;
      const text = content.subarray(lineStart, lineEnd).toString("utf8");
      if (text) records.push({ text, byteOffset: baseOffset + lineStart });
      lineStart = newline + 1;
    }

    let trailing = content.subarray(lineStart);
    let trailingOffset = baseOffset + lineStart;
    if (trailing.length > MAX_TRANSCRIPT_READ_BYTES) {
      trailing = Buffer.alloc(0);
      trailingOffset = size;
      discardingPartial = true;
    }
    this.states.set(path, {
      size,
      trailing,
      trailingOffset,
      suffix: readRange(path, Math.max(0, size - 64), Math.min(64, size)),
      discardingPartial
    });
    return records;
  }
}
