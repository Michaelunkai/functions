function intervalMillis(
  value: string | undefined,
  minimum: number,
  fallback: number
): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= minimum ? parsed : fallback;
}

export function controlPlanePollMillis(
  value = process.env.AgentControl__ControlPlanePollMillis
): number {
  return intervalMillis(value, 1_000, 1_000);
}

export function heartbeatIntervalMillis(
  value = process.env.AgentControl__HeartbeatIntervalMillis
): number {
  return intervalMillis(value, 1_000, 30_000);
}

export function registrationRetryMillis(
  value = process.env.AgentControl__RegistrationRetryMillis
): number {
  return intervalMillis(value, 1_000, 30_000);
}

export function reconciliationIntervalMillis(
  value = process.env.AgentControl__ReconciliationIntervalMillis
): number {
  return intervalMillis(value, 3_000, 3_000);
}

export function controlPlaneRequestTimeoutMillis(
  value = process.env.AgentControl__RequestTimeoutMillis
): number {
  return intervalMillis(value, 1_000, 15_000);
}

export function maxConcurrentSessions(
  value = process.env.AgentControl__MaxConcurrentTasks
): number {
  return intervalMillis(value, 1, Infinity);
}

export function maxClaimsPerPoll(
  value = process.env.AgentControl__MaxClaimsPerPoll
): number {
  return intervalMillis(value, 1, Infinity);
}

export function intervalDue(
  lastAttemptAt: number,
  now: number,
  interval: number
): boolean {
  return lastAttemptAt === 0 || now - lastAttemptAt >= interval;
}
