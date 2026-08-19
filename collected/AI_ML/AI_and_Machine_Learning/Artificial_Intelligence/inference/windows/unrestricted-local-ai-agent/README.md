# Unrestricted Local AI Agent for Windows

A self-contained Windows local AI agent that can inspect and modify files, run
PowerShell and Python, launch and stop processes, browse the web, automate a
browser, inspect the desktop, install isolated Python packages, and verify its
own work with persistent tool logs.

The project name describes the agent's local machine access. Windows security,
network availability, hardware, and third-party services still define the real
execution boundary. The runtime is designed to act first, inspect results,
retry reasonable failures, and report concrete tool errors instead of falsely
claiming that it has no machine access.

## Quick Start

Build the three small Windows launchers:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-Executables.ps1"
```

Install or fully update the local AI:

```powershell
.\Install-UnrestrictedLocalAI.exe
```

After installation, start interactive chat:

```powershell
.\Talk-To-UnrestrictedLocalAI.exe
```

To inspect what a complete removal would delete without changing anything:

```powershell
.\Purge-UnrestrictedLocalAI.exe -PlanOnly
```

The default deployment root is:

```text
%USERPROFILE%\UnrestrictedAgent
```

Each successful install records its selected deployment root in protected
machine-level state:

```text
%ProgramData%\UnrestrictedLocalAI\deployment-root.txt
```

`Talk-To-UnrestrictedLocalAI.exe` uses that recorded root automatically, so an
installation created with `-Root "D:\LocalAI"` remains the normal interactive
target without setting an environment variable. If that recorded deployment is
missing or incomplete, the launcher stops with a clear reinstall message rather
than silently starting a different installation.

The installer and interactive launcher stream human-readable child-process
output in the same console.

## Installer Options

Arguments passed to `Install-UnrestrictedLocalAI.exe` are forwarded to
`setup_agent.ps1`.

```powershell
.\Install-UnrestrictedLocalAI.exe -Root "D:\LocalAI"
.\Install-UnrestrictedLocalAI.exe -Model "qwen3.5:9b" -ContextLength 32768
.\Install-UnrestrictedLocalAI.exe -PlanOnly
.\Install-UnrestrictedLocalAI.exe -SelfTest
```

Supported setup switches include:

- `-Root`
- `-Model`
- `-ContextLength`
- `-SkipModel`
- `-SkipBrowser`
- `-PlanOnly`
- `-SelfTest`
- `-AdoptRoot`

The ownership guard refuses to overwrite a non-empty directory that was not
created by this installer unless `-AdoptRoot` is explicitly supplied.
`-AdoptRoot` clears that target directory before deployment; use it only for a
root whose contents may be replaced.

## Interactive And One-Shot Use

Start the normal interactive prompt:

```powershell
.\Talk-To-UnrestrictedLocalAI.exe
```

Run one unattended prompt:

```powershell
.\Talk-To-UnrestrictedLocalAI.exe --prompt "Inspect the current directory and summarize the largest files."
```

`--max-turns` is an automatic continuation checkpoint rather than a hard stop.
The default is unbounded; a value such as `--max-turns 48` emits a readable
checkpoint and keeps the same task running instead of raising a turn-limit
error.

Override the installed root for the current process:

```powershell
$env:UNRESTRICTED_AGENT_ROOT = "D:\LocalAI"
.\Talk-To-UnrestrictedLocalAI.exe
```

## Installed Runtime

The setup script installs a private, portable stack under the deployment root:

- Embedded Python and locked Python packages
- Private Ollama service on `127.0.0.1:11435`
- Hardware-aware local model selection
- Private Playwright Chromium
- Portable MinGit
- `local_agent.py`
- `run_agent.ps1`
- Deployment metadata, action logs, and validation artifacts

The installer does not use `winget`, Chocolatey, MSI, or a global Python
environment.

## Agent Tools

The generated agent includes:

- PowerShell and Python execution
- Text and binary file read/write
- Recursive directory listing and search
- File metadata and SHA-256 inspection
- Copy, move, archive, extraction, and deletion
- Detached process start, inspection, and exact-PID stop
- HTTPS fetch and file download
- Isolated Python package installation
- Download-and-install workflows for EXE, MSI, MSIX/AppX, ZIP, and Python-wheel packages
- Installed-command capability discovery
- Browser DOM automation
- Safe desktop automation

Tool calls and results are recorded so acceptance validators can compare the
claimed proof with what actually ran.

## Verification

Run the deterministic source and deployed-runtime tests:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-SetupAgent.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-ExecutableLaunchers.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-LocalAgent.ps1"
```

```powershell
& "$env:USERPROFILE\UnrestrictedAgent\runtime\python\python.exe" ".\tests\Test-AgentRuntime.py"
& "$env:USERPROFILE\UnrestrictedAgent\runtime\python\python.exe" ".\tests\Test-ComplexAcceptanceHarness.py"
```

Run the model-driven 20-task suite:

```powershell
& "$env:USERPROFILE\UnrestrictedAgent\runtime\python\python.exe" `
  ".\tests\Run-ComplexAcceptance.py" `
  --agent-root "$env:USERPROFILE\UnrestrictedAgent" `
  --keep-going `
  --max-turns 48 `
  --timeout-seconds 600
```

The suite independently validates these workflows:

1. Privileged filesystem, identity, verification, and cleanup
2. Deterministic binary creation, decoding, and hashing
3. Nested file generation, recursive search, and indexing
4. Deterministic CSV generation and aggregation
5. Generated and tested Python JSON statistics CLI
6. Generated and executed Windows PowerShell 5.1 digest CLI
7. Copy, move, archive, extract, inventory, and cleanup transaction
8. HTTPS fetch, download, HTML parsing, and persisted proof
9. Real browser navigation and DOM extraction
10. Mixed-DPI multi-monitor desktop geometry inspection
11. Online package installation into an isolated target
12. Installed-command discovery and verified use
13. Binary SQLite creation, query, and inspection
14. XML generation and filtered JSON transformation
15. Multilingual UTF-8 round trip with independent hashes
16. Private local HTTP service lifecycle and browser verification
17. Live Ollama process, executable, GPU, context, and model inspection
18. Protected hosts-file read with sanitized output only
19. Concurrent PowerShell hash workers cross-checked by Python
20. Autonomous red-green debugging of a generated mini-project

## Automatic Downloads And Installation

The agent can fetch online release pages, inspect source metadata, download a
file with an optional SHA-256, and install or extract it automatically. The
tool surface includes `download_file`, `install_windows_package`, and
`download_and_install`. MSI installers default to unattended `/qn /norestart`;
for EXE installers the agent uses the publisher's documented unattended
arguments and records the executable, arguments, exit code, and output.

## Complete Purge

`Purge-UnrestrictedLocalAI.exe` removes the installed deployment root, stops
only processes whose executable is inside that root, removes the matching
machine-level root binding and pointer, and reports the bytes freed. It refuses
to delete a directory unless both the root marker and protected binding agree.

```powershell
.\Purge-UnrestrictedLocalAI.exe -PlanOnly
.\Purge-UnrestrictedLocalAI.exe
```

The purge executable intentionally remains beside `purge_agent.ps1` in the
package so it can remove the installation without deleting its own removal
tool.

## Build Outputs

`Build-Executables.ps1` creates:

```text
Install-UnrestrictedLocalAI.exe
Talk-To-UnrestrictedLocalAI.exe
Purge-UnrestrictedLocalAI.exe
```

The build reports each executable's full path, byte size, and SHA-256 hash.

## Logs

The installed runtime keeps operational evidence under:

```text
%USERPROFILE%\UnrestrictedAgent\logs
%USERPROFILE%\UnrestrictedAgent\validation
```

These directories are intentionally excluded from the source repository.
They can contain tool arguments and output from local tasks; do not store
credentials or other secrets in prompts or commands that you do not want
retained in local operational logs.
