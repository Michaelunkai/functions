import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const credentialScriptPath = fileURLToPath(
  new URL("../scripts/AgentControlCredential.ps1", import.meta.url)
);

function readCredential(functionName: "Read-AgentControlOwnerToken" | "Read-AgentControlHookSecret"): string {
  const scriptPath = credentialScriptPath.replaceAll("'", "''");
  const command = [
    "$ErrorActionPreference = 'Stop'",
    `. '${scriptPath}'`,
    `$value = ${functionName}`,
    "if ([string]::IsNullOrWhiteSpace($value)) { exit 2 }",
    "[Console]::Out.Write($value)"
  ].join("; ");
  const result = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
    { encoding: "utf8", windowsHide: true }
  );
  const value = result.stdout.trim();
  if (result.status !== 0 || value.length === 0) {
    throw new Error(`Agent Control ${functionName} failed.`);
  }
  return value;
}

export function readOwnerToken(): string {
  return readCredential("Read-AgentControlOwnerToken");
}

export function readHookSecret(): string {
  return readCredential("Read-AgentControlHookSecret");
}
