import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import { dirname } from "node:path";
import { mkdirSync } from "node:fs";
import { sanitizeHookPayload } from "./transcript-activity.js";

export interface HookEnvelope {
  id: string;
  eventName: string;
  sessionId: string;
  taskId?: string;
  occurredAt: string;
  payload: Record<string, unknown>;
}

export interface OutboxItem {
  sequence: number;
  envelope: HookEnvelope;
  attempts: number;
  lastError?: string;
}

export interface ManagedSessionDetails {
  taskId: string;
  sessionId: string;
  generation?: string;
  processId?: number;
  processStartedAt?: string;
}

export interface ManagedTaskDetails {
  taskId: string;
  claimedAt: string;
  generation?: string;
  processId?: number;
  processStartedAt?: string;
}

export interface PendingStopAcknowledgementDetails {
  taskId: string;
  generation?: string;
  sessionId?: string;
  processId?: number;
  processStartedAt?: string;
  claimedAt?: string;
  message: string;
}

export interface AdapterStoreOptions {
  maxOutboxRows?: number;
}

export class AdapterStore {
  private readonly database: DatabaseSync;
  private readonly sensitiveValues: readonly string[];
  private readonly maxOutboxRows: number;

  constructor(
    path: string,
    sensitiveValues: readonly string[] = [process.env.AgentControl__OwnerToken ?? ""],
    options: AdapterStoreOptions = {}
  ) {
    const maxOutboxRows = options.maxOutboxRows ?? 10_000;
    if (!Number.isSafeInteger(maxOutboxRows) || maxOutboxRows < 0) {
      throw new RangeError("Outbox limit must be a non-negative integer.");
    }
    this.sensitiveValues = sensitiveValues.filter(Boolean);
    this.maxOutboxRows = maxOutboxRows;
    mkdirSync(dirname(path), { recursive: true });
    this.database = new DatabaseSync(path);
    this.database.exec(`
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        event_name TEXT NOT NULL,
        session_id TEXT NOT NULL,
        task_id TEXT,
        occurred_at TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      );
      CREATE TABLE IF NOT EXISTS adapter_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS managed_sessions (
        session_id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL UNIQUE,
        bound_at TEXT NOT NULL,
        generation TEXT,
        process_id INTEGER,
        process_started_at TEXT
      );
      CREATE TABLE IF NOT EXISTS managed_tasks (
        task_id TEXT PRIMARY KEY,
        claimed_at TEXT NOT NULL,
        generation TEXT,
        process_id INTEGER,
        process_started_at TEXT
      );
      CREATE TABLE IF NOT EXISTS resumable_sessions (
        task_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        stopped_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS transcript_activity (
        activity_key TEXT PRIMARY KEY,
        seen_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS pending_stop_acknowledgements (
        task_id TEXT PRIMARY KEY,
        generation TEXT,
        session_id TEXT,
        process_id INTEGER,
        process_started_at TEXT,
        claimed_at TEXT,
        message TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      );
    `);
    for (const statement of [
      "ALTER TABLE outbox ADD COLUMN task_id TEXT",
      "ALTER TABLE managed_sessions ADD COLUMN process_id INTEGER",
      "ALTER TABLE managed_sessions ADD COLUMN process_started_at TEXT",
      "ALTER TABLE managed_sessions ADD COLUMN generation TEXT",
      "ALTER TABLE managed_tasks ADD COLUMN process_id INTEGER",
      "ALTER TABLE managed_tasks ADD COLUMN process_started_at TEXT",
      "ALTER TABLE managed_tasks ADD COLUMN generation TEXT"
    ]) {
      try {
        this.database.exec(statement);
      } catch (error) {
        if (!String(error).includes("duplicate column name")) throw error;
      }
    }
    for (const statement of [
      "ALTER TABLE pending_stop_acknowledgements ADD COLUMN generation TEXT",
      "ALTER TABLE pending_stop_acknowledgements ADD COLUMN session_id TEXT",
      "ALTER TABLE pending_stop_acknowledgements ADD COLUMN process_id INTEGER",
      "ALTER TABLE pending_stop_acknowledgements ADD COLUMN process_started_at TEXT",
      "ALTER TABLE pending_stop_acknowledgements ADD COLUMN claimed_at TEXT"
    ]) {
      try {
        this.database.exec(statement);
      } catch (error) {
        if (!String(error).includes("duplicate column name")) throw error;
      }
    }
    this.database.exec(`
      UPDATE pending_stop_acknowledgements
      SET
        session_id = COALESCE(
          session_id,
          (
            SELECT session_id FROM managed_sessions
            WHERE managed_sessions.task_id = pending_stop_acknowledgements.task_id
          )
        ),
        process_id = COALESCE(
          process_id,
          (
            SELECT COALESCE(managed_sessions.process_id, managed_tasks.process_id)
            FROM managed_tasks
            LEFT JOIN managed_sessions
              ON managed_sessions.task_id=managed_tasks.task_id
            WHERE managed_tasks.task_id=pending_stop_acknowledgements.task_id
          )
        ),
        process_started_at = COALESCE(
          process_started_at,
          (
            SELECT COALESCE(
              managed_sessions.process_started_at,
              managed_tasks.process_started_at
            )
            FROM managed_tasks
            LEFT JOIN managed_sessions
              ON managed_sessions.task_id=managed_tasks.task_id
            WHERE managed_tasks.task_id=pending_stop_acknowledgements.task_id
          )
        ),
        claimed_at = COALESCE(
          claimed_at,
          (
            SELECT claimed_at FROM managed_tasks
            WHERE managed_tasks.task_id=pending_stop_acknowledgements.task_id
          )
        )
    `);
    // Bring pre-multi-session adapter databases forward without dropping an in-flight task.
    this.database.prepare(`
      INSERT OR IGNORE INTO managed_tasks(task_id,claimed_at)
      SELECT value,datetime('now') FROM adapter_state WHERE key='managed_task'
    `).run();
    this.database.prepare(`
      INSERT OR IGNORE INTO managed_tasks(task_id,claimed_at)
      SELECT task_id,bound_at FROM managed_sessions
    `).run();
    for (const row of this.database.prepare(
      "SELECT task_id FROM managed_tasks WHERE generation IS NULL"
    ).all() as Array<{ task_id: string }>) {
      this.database.prepare(
        "UPDATE managed_tasks SET generation=? WHERE task_id=?"
      ).run(randomUUID(), row.task_id);
    }
    this.database.exec(`
      UPDATE managed_sessions
      SET generation = COALESCE(
        generation,
        (
          SELECT generation FROM managed_tasks
          WHERE managed_tasks.task_id=managed_sessions.task_id
        )
      )
      WHERE generation IS NULL
    `);
    for (const row of this.database.prepare(
      "SELECT session_id FROM managed_sessions WHERE generation IS NULL"
    ).all() as Array<{ session_id: string }>) {
      this.database.prepare(
        "UPDATE managed_sessions SET generation=? WHERE session_id=?"
      ).run(randomUUID(), row.session_id);
    }
    this.database.exec(`
      UPDATE pending_stop_acknowledgements
      SET generation = COALESCE(
        generation,
        (
          SELECT COALESCE(managed_sessions.generation,managed_tasks.generation)
          FROM managed_tasks
          LEFT JOIN managed_sessions
            ON managed_sessions.task_id=managed_tasks.task_id
          WHERE managed_tasks.task_id=pending_stop_acknowledgements.task_id
        )
      )
      WHERE generation IS NULL
    `);
    this.database.exec(`
      UPDATE pending_stop_acknowledgements
      SET claimed_at = (
        SELECT claimed_at FROM managed_tasks
        WHERE managed_tasks.task_id=pending_stop_acknowledgements.task_id
      )
      WHERE claimed_at IS NULL
    `);
  }

  sanitizePayload(
    payload: Record<string, unknown>,
    eventName = String(payload.hook_event_name ?? payload.event ?? "")
  ): Record<string, unknown> {
    return sanitizeHookPayload(payload, eventName, this.sensitiveValues);
  }

  enqueue(envelope: HookEnvelope): void {
    const payload = this.sanitizePayload(envelope.payload, envelope.eventName);
    const taskId = envelope.taskId ?? this.taskForSession(envelope.sessionId);
    this.database.prepare(`
      INSERT OR IGNORE INTO outbox (id,event_name,session_id,task_id,occurred_at,payload)
      VALUES (?,?,?,?,?,?)
    `).run(
      envelope.id,
      envelope.eventName,
      envelope.sessionId,
      taskId ?? null,
      envelope.occurredAt,
      JSON.stringify(payload)
    );
    if (envelope.eventName === "SessionStart" || envelope.eventName === "UserPromptSubmit") {
      const activeTaskId = taskId ?? `codex:${envelope.sessionId}`;
      this.database.prepare(
        "INSERT INTO adapter_state(key,value) VALUES('active_task',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"
      ).run(activeTaskId);
    } else if (envelope.eventName === "Stop" || envelope.eventName === "SessionEnd") {
      const activeTaskId = taskId ?? `codex:${envelope.sessionId}`;
      this.database.prepare("DELETE FROM adapter_state WHERE key='active_task' AND value=?")
        .run(activeTaskId);
    }
    this.pruneOutbox();
  }

  private pruneOutbox(): void {
    this.database.prepare(`
      DELETE FROM outbox
      WHERE sequence IN (
        SELECT sequence
        FROM outbox
        WHERE event_name NOT IN ('Stop','SessionEnd')
        ORDER BY sequence
        LIMIT MAX(
          0,
          (SELECT COUNT(*) FROM outbox) - ?
        )
      )
    `).run(this.maxOutboxRows);
  }

  activeTaskId(): string | undefined {
    const row = this.database.prepare("SELECT value FROM adapter_state WHERE key='active_task'")
      .get() as { value: string } | undefined;
    return row?.value;
  }

  setManagedTask(id?: string): void {
    if (id) {
      this.trackManagedTask(id);
    } else {
      this.clearManagedTask();
    }
  }

  managedTaskId(): string | undefined {
    return this.managedTaskIds()[0];
  }

  managedTaskIds(): string[] {
    return (this.database.prepare("SELECT task_id FROM managed_tasks ORDER BY claimed_at,task_id").all() as Array<{ task_id: string }>)
      .map((row) => row.task_id);
  }

  managedSessions(): ManagedSessionDetails[] {
    return this.database.prepare(`
      SELECT task_id,session_id,process_id,process_started_at
        ,generation
      FROM managed_sessions ORDER BY bound_at
    `)
      .all()
      .map((row) => this.managedSessionDetails(row as Record<string, unknown>));
  }

  managedSessionForTask(taskId: string): string | undefined {
    return this.managedSessionDetailsForTask(taskId)?.sessionId;
  }

  managedSessionDetailsForTask(taskId: string): ManagedSessionDetails | undefined {
    const row = this.database.prepare(`
      SELECT task_id,session_id,process_id,process_started_at
        ,generation
      FROM managed_sessions WHERE task_id=?
    `).get(taskId) as Record<string, unknown> | undefined;
    return row ? this.managedSessionDetails(row) : undefined;
  }

  managedProcessForTask(taskId: string): {
    processId: number;
    processStartedAt: string;
  } | undefined {
    const row = this.database.prepare(`
      SELECT process_id,process_started_at FROM managed_tasks WHERE task_id=?
    `).get(taskId) as Record<string, unknown> | undefined;
    const processId = Number(row?.process_id);
    const processStartedAt = row?.process_started_at ? String(row.process_started_at) : "";
    return Number.isInteger(processId) && processId > 0 && processStartedAt
      ? { processId, processStartedAt }
      : undefined;
  }

  managedTaskDetailsForTask(taskId: string): ManagedTaskDetails | undefined {
    const row = this.database.prepare(`
      SELECT task_id,claimed_at,process_id,process_started_at
        ,generation
      FROM managed_tasks WHERE task_id=?
    `).get(taskId) as Record<string, unknown> | undefined;
    if (!row) return undefined;
    const processId = Number(row.process_id);
    const processStartedAt = row.process_started_at ? String(row.process_started_at) : undefined;
    return {
      taskId: String(row.task_id),
      claimedAt: String(row.claimed_at),
      ...(row.generation ? { generation: String(row.generation) } : {}),
      ...(Number.isInteger(processId) && processId > 0 ? { processId } : {}),
      ...(processStartedAt ? { processStartedAt } : {})
    };
  }

  private managedSessionDetails(row: Record<string, unknown>): ManagedSessionDetails {
    const processId = Number(row.process_id);
    const processStartedAt = row.process_started_at ? String(row.process_started_at) : undefined;
    return {
      taskId: String(row.task_id),
      sessionId: String(row.session_id),
      ...(row.generation ? { generation: String(row.generation) } : {}),
      ...(Number.isInteger(processId) && processId > 0 ? { processId } : {}),
      ...(processStartedAt ? { processStartedAt } : {})
    };
  }

  trackManagedTask(taskId: string): void {
    this.database.prepare(
      "INSERT OR IGNORE INTO managed_tasks(task_id,claimed_at,generation) VALUES(?,?,?)"
    ).run(taskId, `${new Date().toISOString()}-${randomUUID()}`, randomUUID());
    const task = this.managedTaskDetailsForTask(taskId);
    if (task) {
      this.database.prepare(`
        DELETE FROM pending_stop_acknowledgements
        WHERE task_id=? AND claimed_at IS NOT NULL AND claimed_at IS NOT ?
      `).run(taskId, task.claimedAt);
    }
  }

  recordManagedProcess(taskId: string, processId: number, processStartedAt: string): void {
    if (!Number.isInteger(processId) || processId <= 0 || !processStartedAt.trim()) {
      throw new Error("managed_process_identity_invalid");
    }
    this.trackManagedTask(taskId);
    const current = this.managedTaskDetailsForTask(taskId);
    const sameProcess = current?.processId === processId &&
      current.processStartedAt === processStartedAt;
    this.database.prepare(`
      UPDATE managed_tasks
      SET process_id=?,process_started_at=?,generation=?
      WHERE task_id=?
    `).run(
      processId,
      processStartedAt,
      sameProcess ? current?.generation ?? randomUUID() : randomUUID(),
      taskId
    );
  }

  clearManagedTask(taskId = this.managedTaskId()): void {
    if (!taskId) return;
    const task = this.managedTaskDetailsForTask(taskId);
    if (task) {
      this.database.prepare(`
        DELETE FROM pending_stop_acknowledgements
        WHERE task_id=? AND claimed_at IS ?
      `).run(taskId, task.claimedAt);
    }
    this.database.prepare("DELETE FROM managed_sessions WHERE task_id=?").run(taskId);
    this.database.prepare("DELETE FROM managed_tasks WHERE task_id=?").run(taskId);
    this.database.prepare("DELETE FROM adapter_state WHERE key='managed_task' AND value=?").run(taskId);
  }

  saveResumableSession(taskId: string, sessionId: string): void {
    if (!taskId.trim() || !sessionId.trim()) throw new Error("resumable_session_identity_invalid");
    this.database.prepare(`
      INSERT INTO resumable_sessions(task_id,session_id,stopped_at)
      VALUES(?,?,?)
      ON CONFLICT(task_id) DO UPDATE SET
        session_id=excluded.session_id,
        stopped_at=excluded.stopped_at
    `).run(taskId, sessionId, new Date().toISOString());
  }

  resumableSessionForTask(taskId: string): string | undefined {
    const row = this.database.prepare(
      "SELECT session_id FROM resumable_sessions WHERE task_id=?"
    ).get(taskId) as { session_id: string } | undefined;
    return row?.session_id;
  }

  clearResumableSession(taskId: string): void {
    this.database.prepare("DELETE FROM resumable_sessions WHERE task_id=?").run(taskId);
  }

  bindManagedSession(
    taskId: string,
    sessionId: string,
    processId?: number,
    processStartedAt?: string
  ): void {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      this.trackManagedTask(taskId);
      if (processId && processStartedAt) {
        this.recordManagedProcess(taskId, processId, processStartedAt);
      }
      const task = this.managedTaskDetailsForTask(taskId);
      const process = this.managedProcessForTask(taskId);
      const generation = task?.generation;
      this.database.prepare(`
        DELETE FROM pending_stop_acknowledgements
        WHERE task_id=? AND NOT (
          generation IS ? AND
          session_id IS ? AND
          process_id IS ? AND
          process_started_at IS ? AND
          claimed_at IS ?
        )
      `).run(
        taskId,
        generation ?? null,
        sessionId,
        process?.processId ?? null,
        process?.processStartedAt ?? null,
        this.managedTaskDetailsForTask(taskId)?.claimedAt ?? null
      );
      this.database.prepare("DELETE FROM managed_sessions WHERE task_id=? OR session_id=?").run(taskId, sessionId);
      this.database.prepare(
        `INSERT INTO managed_sessions(
          session_id,task_id,bound_at,generation,process_id,process_started_at
        ) VALUES(?,?,?,?,?,?)`
      ).run(
        sessionId,
        taskId,
        new Date().toISOString(),
        generation ?? null,
        processId ?? process?.processId ?? null,
        processStartedAt ?? process?.processStartedAt ?? null
      );
      this.clearResumableSession(taskId);
      this.database.prepare(
        "UPDATE adapter_state SET value=? WHERE key='active_task' AND value=?"
      ).run(taskId, `codex:${sessionId}`);
      this.database.exec("COMMIT");
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }

  taskForSession(sessionId: string): string | undefined {
    const row = this.database.prepare("SELECT task_id FROM managed_sessions WHERE session_id=?")
      .get(sessionId) as { task_id: string } | undefined;
    return row?.task_id;
  }

  clearManagedSession(sessionId: string): void {
    const taskId = this.taskForSession(sessionId);
    this.database.prepare("DELETE FROM managed_sessions WHERE session_id=?").run(sessionId);
    if (taskId) this.clearManagedTask(taskId);
  }

  /** Returns true once per transcript record, including after an adapter restart. */
  recordTranscriptActivity(activityKey: string): boolean {
    const result = this.database.prepare(
      "INSERT OR IGNORE INTO transcript_activity(activity_key,seen_at) VALUES(?,?)"
    ).run(activityKey, new Date().toISOString());
    return result.changes > 0;
  }

  pruneTranscriptActivity(limit = 10_000): void {
    if (!Number.isSafeInteger(limit) || limit < 0) {
      throw new RangeError("Transcript activity limit must be a non-negative integer.");
    }
    this.database.prepare(`
      DELETE FROM transcript_activity
      WHERE rowid NOT IN (
        SELECT rowid
        FROM transcript_activity
        ORDER BY seen_at DESC, rowid DESC
        LIMIT ?
      )
    `).run(limit);
  }

  recordPendingStopAcknowledgement(taskId: string, message: string): void {
    const session = this.managedSessionDetailsForTask(taskId);
    const process = this.managedProcessForTask(taskId);
    const task = this.managedTaskDetailsForTask(taskId);
    this.database.prepare(`
      INSERT INTO pending_stop_acknowledgements(
        task_id,generation,session_id,process_id,process_started_at,claimed_at,message,recorded_at
      )
      VALUES(?,?,?,?,?,?,?,?)
      ON CONFLICT(task_id) DO UPDATE SET
        generation=excluded.generation,
        session_id=excluded.session_id,
        process_id=excluded.process_id,
        process_started_at=excluded.process_started_at,
        claimed_at=excluded.claimed_at,
        message=excluded.message,
        recorded_at=excluded.recorded_at
    `).run(
      taskId,
      session?.generation ?? task?.generation ?? null,
      session?.sessionId ?? null,
      process?.processId ?? session?.processId ?? null,
      process?.processStartedAt ?? session?.processStartedAt ?? null,
      this.managedTaskDetailsForTask(taskId)?.claimedAt ?? null,
      message,
      new Date().toISOString()
    );
  }

  pendingStopAcknowledgementDetails(taskId: string): PendingStopAcknowledgementDetails | undefined {
    const row = this.database.prepare(`
      SELECT
        pending.task_id,
        pending.generation,
        pending.session_id,
        pending.process_id,
        pending.process_started_at,
        pending.claimed_at,
        pending.message
      FROM pending_stop_acknowledgements AS pending
      LEFT JOIN managed_sessions AS managed ON managed.task_id=pending.task_id
      LEFT JOIN managed_tasks AS task ON task.task_id=pending.task_id
      WHERE pending.task_id=? AND
        pending.generation IS COALESCE(managed.generation,task.generation) AND
        pending.session_id IS managed.session_id AND
        pending.process_id IS COALESCE(managed.process_id,task.process_id) AND
        pending.process_started_at IS COALESCE(
          managed.process_started_at,
          task.process_started_at
        ) AND
        pending.claimed_at IS task.claimed_at
    `).get(taskId) as Record<string, unknown> | undefined;
    if (!row) return undefined;
    const processId = Number(row.process_id);
    return {
      taskId: String(row.task_id),
      ...(row.generation ? { generation: String(row.generation) } : {}),
      ...(row.session_id ? { sessionId: String(row.session_id) } : {}),
      ...(Number.isInteger(processId) && processId > 0 ? { processId } : {}),
      ...(row.process_started_at ? { processStartedAt: String(row.process_started_at) } : {}),
      ...(row.claimed_at ? { claimedAt: String(row.claimed_at) } : {}),
      message: String(row.message)
    };
  }

  pendingStopAcknowledgement(taskId: string): string | undefined {
    return this.pendingStopAcknowledgementDetails(taskId)?.message;
  }

  pendingStopAcknowledgements(): Array<{ taskId: string; message: string }> {
    return this.database.prepare(`
      SELECT pending.task_id,pending.message
      FROM pending_stop_acknowledgements AS pending
      LEFT JOIN managed_sessions AS managed ON managed.task_id=pending.task_id
      LEFT JOIN managed_tasks AS task ON task.task_id=pending.task_id
      WHERE
        pending.generation IS COALESCE(managed.generation,task.generation) AND
        pending.session_id IS managed.session_id AND
        pending.process_id IS COALESCE(managed.process_id,task.process_id) AND
        pending.process_started_at IS COALESCE(
          managed.process_started_at,
          task.process_started_at
        ) AND
        pending.claimed_at IS task.claimed_at
      ORDER BY pending.recorded_at,pending.task_id
    `).all().map((row) => ({
      taskId: String((row as { task_id: string }).task_id),
      message: String((row as { message: string }).message)
    }));
  }

  clearPendingStopAcknowledgement(
    taskId: string,
    expected?: PendingStopAcknowledgementDetails
  ): boolean {
    if (!expected) {
      return this.database.prepare(
        "DELETE FROM pending_stop_acknowledgements WHERE task_id=?"
      ).run(taskId).changes > 0;
    }
    return this.database.prepare(`
      DELETE FROM pending_stop_acknowledgements
      WHERE task_id=? AND
        generation IS ? AND
        session_id IS ? AND
        process_id IS ? AND
        process_started_at IS ? AND
        claimed_at IS ? AND
        message=?
    `).run(
      taskId,
      expected.generation ?? null,
      expected.sessionId ?? null,
      expected.processId ?? null,
      expected.processStartedAt ?? null,
      expected.claimedAt ?? null,
      expected.message
    ).changes > 0;
  }

  pending(limit = 50): OutboxItem[] {
    const rows = this.database.prepare(`
      SELECT sequence,id,event_name,session_id,task_id,occurred_at,payload,attempts,last_error
      FROM outbox ORDER BY sequence LIMIT ?
    `).all(limit) as Array<Record<string, unknown>>;
    return rows.map((row) => ({
      sequence: Number(row.sequence),
      envelope: {
        id: String(row.id),
        eventName: String(row.event_name),
        sessionId: String(row.session_id),
        taskId: row.task_id === null || row.task_id === undefined
          ? this.taskForSession(String(row.session_id))
          : String(row.task_id),
        occurredAt: String(row.occurred_at),
        payload: JSON.parse(String(row.payload)) as Record<string, unknown>
      },
      attempts: Number(row.attempts),
      lastError: row.last_error ? String(row.last_error) : undefined
    }));
  }

  complete(sequence: number): void {
    this.database.prepare("DELETE FROM outbox WHERE sequence=?").run(sequence);
  }

  fail(sequence: number, error: string): void {
    this.database.prepare(
      "UPDATE outbox SET attempts=attempts+1,last_error=? WHERE sequence=?"
    ).run(error.slice(0, 500), sequence);
  }

  close(): void {
    this.database.close();
  }
}
