# sak-utility-launcher-20260605

PowerShell launcher and archival package for downloading, verifying, installing, and launching **S.A.K. Utility** for Windows.

This project packages the completed Codex/Hermes mission artifacts from `C:\Users\micha\Documents\Codex\2026-06-05\codex-cmd-long-find-the-absolute-3` into a durable `F:\study` repository. The main runnable entry point is `run-sak-utility.ps1`.

## What it does

`run-sak-utility.ps1`:

1. Queries the latest GitHub release from `RandyNorthrup/S.A.K.-Utility`.
2. Finds the `SAK-Utility-Windows-x64.zip` release asset.
3. Downloads it into a temporary working folder.
4. Verifies the ZIP SHA256 when the release includes `SHA256SUMS.txt`.
5. Extracts and installs the tool under `%LOCALAPPDATA%\SAK-Utility\<release-tag>`.
6. Launches `sak_utility.exe` and reports whether the process is still running after 3 seconds.
7. Reuses an existing install for the same release tag instead of downloading again.

## Prerequisites

- Windows 10/11.
- Windows PowerShell 5.1 (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`).
- Internet access to GitHub releases.
- User permission to write to `%LOCALAPPDATA%` and `%TEMP%`.

No API keys or credentials are required.

## Setup

Clone or open this repository, then run commands from the repository root. No package installation is needed.

## Usage

From Windows PowerShell 5:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-sak-utility.ps1
```

From WSL, calling Windows PowerShell:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w ./run-sak-utility.ps1)"
```

## Inputs and outputs

- Input: no command-line arguments.
- Network input: latest release metadata and assets from `https://api.github.com/repos/RandyNorthrup/S.A.K.-Utility/releases/latest`.
- Installed output: `%LOCALAPPDATA%\SAK-Utility\<release-tag>\...\sak_utility.exe`.
- Console output: download/install status, SHA256 verification when available, launched executable path, process ID, and `RunningAfter3s` status.

## Important files

- `run-sak-utility.ps1` — primary runnable launcher.
- `scripts/make-sak-encoded-oneliner.ps1` — helper from the original mission that produced encoded one-liner variants.
- `artifacts/original-codex-session/` — moved original files from the completed Codex session.
- `tests/Test-PowerShellSyntax.ps1` — parse-only syntax check that avoids downloading or launching anything.

## Verification

Run the parse-only check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PowerShellSyntax.ps1
```

Expected result:

```text
PowerShell syntax OK: <path-to-run-sak-utility.ps1>
```

## Troubleshooting

- If GitHub blocks or rate-limits unauthenticated requests, retry later or download the release asset manually.
- If PowerShell script execution is restricted, use the documented `-ExecutionPolicy Bypass` command for this invocation only.
- If no SHA256 is printed, the upstream release did not include a matching `SHA256SUMS.txt` entry; the script still extracts the downloaded ZIP.
- If `RunningAfter3s: False`, the program may have exited quickly or Windows may have blocked the launch; check Windows Defender/SmartScreen and the installed folder under `%LOCALAPPDATA%\SAK-Utility`.
