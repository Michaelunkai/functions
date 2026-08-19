import {
  existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync
} from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const root = dirname(fileURLToPath(import.meta.url));
const scriptPath = join(root, "..", "scripts", "Start-CodexDesktopTask.ps1");

function launcherSource(): string {
  return readFileSync(scriptPath, "utf8");
}

function functionSection(source: string, name: string): string {
  const start = source.indexOf(`function ${name}`);
  expect(start, `missing PowerShell function ${name}`).toBeGreaterThanOrEqual(0);
  const next = source.indexOf("\nfunction ", start + 1);
  return source.slice(start, next < 0 ? source.length : next);
}

describe("legacy Codex Desktop diagnostic launcher hardening", () => {
  it("requires one exact normalized workspace window before every synthetic input", () => {
    const source = launcherSource();
    const windowMatcher = functionSection(source, "Get-CodexWindowForWorkspace");

    expect(source).toContain("function ConvertTo-NormalizedWorkspacePath");
    expect(windowMatcher).toContain(
      "$candidatePath.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)"
    );
    expect(windowMatcher).toContain("if ($matchingWindows.Count -gt 1)");
    expect(windowMatcher).toContain("More than one Codex Desktop window proved the exact workspace");
    expect(source).not.toContain("$workspaceLeaf");
    expect(source).not.toMatch(/-like\s+["']\*\$workspaceLeaf\*["']/);
    expect(source).toContain(
      "$window = Wait-Until { Get-CodexWindowForWorkspace -ExpectedWorkspace $workspacePath }"
    );
    expect(source).toContain("Find-CodexButton -Window $window -Name 'New task'");

    const sendKeys = [...source.matchAll(/\[System\.Windows\.Forms\.SendKeys\]::SendWait/g)];
    const inputGuards = [...source.matchAll(
      /Assert-CodexInputTarget -Window \$window -ExpectedWorkspace \$workspacePath/g
    )];
    expect(sendKeys.length).toBeGreaterThan(0);
    expect(inputGuards).toHaveLength(sendKeys.length);
    for (let index = 0; index < sendKeys.length; index += 1) {
      expect(inputGuards[index].index).toBeLessThan(sendKeys[index].index);
    }

    const clipboardMutation = source.indexOf(
      "[System.Windows.Forms.Clipboard]::SetText($prompt)"
    );
    const lastGuardBeforeMutation = source.lastIndexOf(
      "Assert-CodexInputTarget -Window $window -ExpectedWorkspace $workspacePath",
      clipboardMutation
    );
    expect(clipboardMutation).toBeGreaterThan(0);
    expect(lastGuardBeforeMutation).toBeGreaterThan(0);
  });

  it("recovers an atomic config restore journal before mutation and removes it only after byte-exact restore", () => {
    const source = launcherSource();
    const createJournal = functionSection(source, "New-ConfigRestoreJournal");
    const restoreJournal = functionSection(source, "Restore-ConfigFromJournal");

    expect(createJournal).toContain("[Convert]::ToBase64String($OriginalBytes)");
    expect(createJournal).toContain("[System.IO.File]::WriteAllText($journalTempPath");
    expect(createJournal).toContain("[System.IO.File]::Move($journalTempPath, $JournalPath)");
    expect(restoreJournal).toContain("[Convert]::FromBase64String");
    expect(restoreJournal).toContain("[System.IO.File]::WriteAllBytes($restoreTempPath, $originalBytes)");
    expect(restoreJournal).toContain("Test-ByteArrayEqual");
    expect(restoreJournal).toContain("Config restoration verification failed");

    const verification = restoreJournal.indexOf("Test-ByteArrayEqual");
    const journalRemoval = restoreJournal.indexOf("Remove-Item -LiteralPath $JournalPath");
    expect(verification).toBeGreaterThanOrEqual(0);
    expect(journalRemoval).toBeGreaterThan(verification);

    const lockAcquired = source.indexOf(
      "if (-not $mutexHeld) { throw 'Timed out waiting for the Agent Control exact-settings launch lock.' }"
    );
    const recovery = source.indexOf(
      "Restore-ConfigFromJournal -JournalPath $configRestoreJournalPath -ConfigPath $configPath",
      lockAcquired
    );
    const originalRead = source.indexOf(
      "$originalConfigBytes = [System.IO.File]::ReadAllBytes($configPath)",
      recovery
    );
    const journalCreation = source.indexOf(
      "New-ConfigRestoreJournal -JournalPath $configRestoreJournalPath",
      originalRead
    );
    const firstMutation = source.indexOf("Set-CodexTopLevelSetting", journalCreation);
    expect(lockAcquired).toBeGreaterThan(0);
    expect(recovery).toBeGreaterThan(lockAcquired);
    expect(originalRead).toBeGreaterThan(recovery);
    expect(journalCreation).toBeGreaterThan(originalRead);
    expect(firstMutation).toBeGreaterThan(journalCreation);
  });

  it("round-trips the restore journal under Windows PowerShell 5.1", () => {
    const temp = mkdtempSync(join(tmpdir(), "agent-control-journal-"));
    const configPath = join(temp, "config.toml");
    const journalPath = `${configPath}.agent-control.restore.json`;
    const original = Buffer.from([0, 1, 2, 10, 13, 127, 128, 255]);
    writeFileSync(configPath, original);

    const quote = (value: string) => value.replaceAll("'", "''");
    const script = [
      "$ErrorActionPreference = 'Stop'",
      `$scriptPath = '${quote(scriptPath)}'`,
      "$tokens = $null",
      "$errors = $null",
      "$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)",
      "if ($errors.Count -gt 0) { throw ($errors | ForEach-Object { $_.ToString() } | Out-String) }",
      "$names = @('Get-ByteArraySha256', 'Test-ByteArrayEqual', 'New-ConfigRestoreJournal', 'Restore-ConfigFromJournal')",
      "foreach ($name in $names) {",
      "  $functionAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)",
      "  if ($null -eq $functionAst) { throw \"Missing function $name\" }",
      "  Invoke-Expression $functionAst.Extent.Text",
      "}",
      `$configPath = '${quote(configPath)}'`,
      `$journalPath = '${quote(journalPath)}'`,
      "$originalBytes = [System.IO.File]::ReadAllBytes($configPath)",
      "New-ConfigRestoreJournal -JournalPath $journalPath -ConfigPath $configPath -OriginalBytes $originalBytes",
      "[System.IO.File]::WriteAllBytes($configPath, [byte[]]@(9, 9, 9))",
      "Restore-ConfigFromJournal -JournalPath $journalPath -ConfigPath $configPath | Out-Null",
      "$restoredBytes = [System.IO.File]::ReadAllBytes($configPath)",
      "if (-not (Test-ByteArrayEqual -Left $originalBytes -Right $restoredBytes)) { throw 'Restored bytes differ.' }",
      "if (Test-Path -LiteralPath $journalPath) { throw 'Journal remained after exact restoration.' }",
      "Write-Output 'PS5_JOURNAL_ROUNDTRIP_OK'"
    ].join("\r\n");
    const encoded = Buffer.from(script, "utf16le").toString("base64");

    try {
      const result = spawnSync(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
        { encoding: "utf8" }
      );
      expect(result.status, `${result.stdout}\n${result.stderr}`).toBe(0);
      expect(result.stdout).toContain("PS5_JOURNAL_ROUNDTRIP_OK");
      expect(readFileSync(configPath)).toEqual(original);
      expect(existsSync(journalPath)).toBe(false);
    } finally {
      rmSync(temp, { recursive: true, force: true });
    }
  }, 15_000);

  it("materializes every clipboard format before mutation and verifies restoration in finally", () => {
    const source = launcherSource();
    const capture = functionSection(source, "New-ClipboardSnapshot");
    const restore = functionSection(source, "Restore-ClipboardSnapshot");

    expect(capture).toContain("[System.Windows.Forms.DataObject]::new()");
    expect(capture).toContain("GetFormats($true)");
    expect(capture).toContain("GetDataPresent($format, $true)");
    expect(capture).toContain("GetData($format, $true)");
    expect(capture).toContain("SetData($format, $false, $value)");
    expect(capture).toContain("Clipboard format '$format' could not be materialized");
    expect(restore).toContain(
      "[System.Windows.Forms.Clipboard]::SetDataObject($Snapshot.DataObject, $true)"
    );
    expect(restore).toContain("Assert-ClipboardSnapshotRestored -Snapshot $Snapshot");
    expect(source).toContain("function Test-ClipboardValueEqual");

    const snapshot = source.indexOf("$clipboardSnapshot = New-ClipboardSnapshot");
    const mutation = source.indexOf("[System.Windows.Forms.Clipboard]::SetText($prompt)");
    expect(snapshot).toBeGreaterThan(0);
    expect(mutation).toBeGreaterThan(snapshot);
    expect(source).toMatch(
      /finally\s*\{[\s\S]*Restore-ClipboardSnapshot -Snapshot \$clipboardSnapshot[\s\S]*\}/
    );
  });
});
