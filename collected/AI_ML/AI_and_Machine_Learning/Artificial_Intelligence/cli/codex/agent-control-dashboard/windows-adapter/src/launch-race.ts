import { AdapterStore } from "./store.js";

export async function stopOpenedSessionBeforeBinding(
  store: AdapterStore,
  taskId: string,
  sessionId: string,
  stop: (sessionId: string) => Promise<boolean>
): Promise<boolean> {
  // The exact session is already live in the launcher registry. Keep the
  // managed claim until the native stop callback proves terminal state, and
  // never persist it as a resume target for a later READY mission.
  const stopped = await stop(sessionId);
  if (stopped) store.clearManagedTask(taskId);
  return stopped;
}
