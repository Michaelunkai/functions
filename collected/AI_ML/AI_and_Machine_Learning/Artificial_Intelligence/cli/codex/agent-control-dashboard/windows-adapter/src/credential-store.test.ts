import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("Windows owner-token credential store", () => {
  it("does not accept the owner credential as an installer command-line parameter", () => {
    const installer = readFileSync(
      join(dirname(fileURLToPath(import.meta.url)), "..", "Install-AgentControlAdapter.ps1"),
      "utf8"
    );

    expect(installer).not.toMatch(/\[string\]\s*\$OwnerToken/i);
    expect(installer).toContain("Read-AgentControlOwnerToken");
    expect(installer).toContain("Read-Host -Prompt 'Agent Control owner token' -AsSecureString");
    expect(installer).toContain("[Runtime.InteropServices.Marshal]::ZeroFreeBSTR");
  });

  it("does not export the owner credential to the adapter child environment", () => {
    const launcher = readFileSync(
      join(dirname(fileURLToPath(import.meta.url)), "..", "Start-AgentControlAdapter.ps1"),
      "utf8"
    );

    expect(launcher).not.toMatch(/\$env:AgentControl__OwnerToken\s*=/i);
    expect(launcher).toContain("Read-AgentControlOwnerToken");
    expect(launcher).toContain("Remove-Item Env:AgentControl__OwnerToken -ErrorAction SilentlyContinue");
    expect(launcher).toContain("Remove-Item Env:AgentControl__HookSecret -ErrorAction SilentlyContinue");
  });

  it("initializes a stable loopback hook secret through CurrentUser DPAPI", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-hook-credential-"));
    roots.push(root);
    const script = join(
      dirname(fileURLToPath(import.meta.url)),
      "..",
      "scripts",
      "AgentControlCredential.ps1"
    );
    const command = [
      `$ErrorActionPreference = 'Stop'`,
      `. '${script.replaceAll("'", "''")}'`,
      `$root = '${root.replaceAll("'", "''")}'`,
      `$first = Initialize-AgentControlHookSecret -Root $root`,
      `$second = Initialize-AgentControlHookSecret -Root $root`,
      `if ([string]::IsNullOrWhiteSpace($first) -or $first.Length -lt 32) { throw 'hook_secret_generation_failed' }`,
      `if ($first -cne $second) { throw 'hook_secret_not_stable' }`,
      `$path = Get-AgentControlHookSecretPath -Root $root`,
      `$raw = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))`,
      `if ($raw.Contains($first)) { throw 'hook_secret_stored_plaintext' }`,
      `Remove-AgentControlHookSecret -Root $root`,
      `if (Test-Path -LiteralPath $path) { throw 'hook_secret_remove_failed' }`
    ].join("; ");
    const result = spawnSync(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
      { encoding: "utf8" }
    );

    expect(result.status, result.stderr).toBe(0);
  }, 15_000);

  it("round-trips through CurrentUser DPAPI without storing plaintext", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-control-credential-"));
    roots.push(root);
    const script = join(
      dirname(fileURLToPath(import.meta.url)),
      "..",
      "scripts",
      "AgentControlCredential.ps1"
    );
    const token = "test-owner-token-not-for-production";
    const command = [
      `$ErrorActionPreference = 'Stop'`,
      `. '${script.replaceAll("'", "''")}'`,
      `$root = '${root.replaceAll("'", "''")}'`,
      `$token = '${token}'`,
      `Write-AgentControlOwnerToken -Token $token -Root $root`,
      `$read = Read-AgentControlOwnerToken -Root $root`,
      `if ($read -cne $token) { throw 'credential_round_trip_failed' }`,
      `Remove-AgentControlOwnerToken -Root $root`,
      `if (Test-Path -LiteralPath (Get-AgentControlCredentialPath -Root $root)) { throw 'credential_remove_failed' }`
    ].join("; ");
    const result = spawnSync(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
      { encoding: "utf8" }
    );

    expect(result.status, result.stderr).toBe(0);
    const credentialPath = join(root, "owner-token.dpapi");
    expect(existsSync(credentialPath)).toBe(false);

    const persistOnly = spawnSync(
      "powershell.exe",
      [
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        `. '${script.replaceAll("'", "''")}'; Write-AgentControlOwnerToken -Token '${token}' -Root '${root.replaceAll("'", "''")}'`
      ],
      { encoding: "utf8" }
    );
    expect(persistOnly.status, persistOnly.stderr).toBe(0);
    expect(readFileSync(credentialPath).includes(Buffer.from(token, "utf8"))).toBe(false);
  }, 15_000);
});
