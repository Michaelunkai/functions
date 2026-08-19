# Learned Errors

## 2026-05-05 - Vault Import PowerShell Backtick Quoting

- Context: Importing `F:\Downloads\Documentation(job).csv` into the Obsidian vault with `vault-save-note.ps1`.
- Error: Inline PowerShell parser failed on a markdown line after using a backtick before a closing double quote in `"- SHA-256: `$hash`"`.
- Fix: Avoid backtick-delimited inline code inside double-quoted PowerShell strings; build those lines with single-quoted literals plus concatenation or omit markdown backticks in generated text.

## 2026-05-05 - Nested PowerShell Native Stdout Encoding Failure

- Context: Calling `powershell.exe -NoProfile -ExecutionPolicy Bypass -File F:\backup\obsidion\scripts\vault-save-note.ps1` from the current shell during the same vault import.
- Error: `Program 'powershell.exe' failed to run: StandardOutputEncoding is only supported when standard output is redirected.`
- Fix: Dot-call or invoke `vault-save-note.ps1` directly in the current PowerShell host with `& 'F:\backup\obsidion\scripts\vault-save-note.ps1' ...` instead of spawning a nested `powershell.exe`.

## 2026-05-05 - LASTEXITCODE Blank After Successful PowerShell Script

- Context: Verifying `vault-save-note.ps1` after direct invocation during the TovTech documentation vault import.
- Error: The script printed `Vault Note Created`, but the wrapper checked `$LASTEXITCODE -ne 0`; for a PowerShell script `$LASTEXITCODE` can be blank, so the wrapper threw a false failure.
- Fix: For PowerShell script invocations, rely on thrown exceptions or `$?`, not `$LASTEXITCODE`, unless the script explicitly sets a process exit code.

## 2026-05-05 - LinkedIn Job Tracker Summary Encoding

- Context: Running `job_progress.py summary --workspace linkedin-auto-apply` from Windows PowerShell after a LinkedIn Easy Apply batch.
- Error: The summary hit `UnicodeEncodeError: 'charmap' codec can't encode characters` when an older Hebrew role name was printed through the default console encoding.
- Fix: Set `$env:PYTHONIOENCODING='utf-8'` before running the tracker summary command.

## 2026-08-03 - PowerShell Built-in Variable Collision

- Context: Verifying AutoHotkey hotkey ownership and the live DS2 Ctrl+H/Alt+H cycle.
- Error: Probe assignments to `$pid` and `$error` failed because PowerShell reserves `$PID` and `$Error`.
- Fix: Use explicit names such as `$targetPid` and `$win32Error` in PowerShell verification probes.

## 2026-08-12 - Windows 11 Notepad Launcher PID Is Not the Window Owner

- Context: Running a disposable Ctrl+H/Alt+H acceptance test against Notepad.
- Error: `Start-Process notepad.exe -PassThru` returned a launcher process that never acquired a main window.
- Fix: Snapshot existing Notepad PIDs, launch Notepad, then discover the new `Notepad.exe` process with a nonzero `MainWindowHandle` before testing.

## 2026-08-12 - AutoHotkey FileDelete Throws for a Missing Probe Marker

- Context: Starting the disposable Ctrl+H/Alt+H GUI acceptance probe.
- Error: `FileDelete` stopped the probe before it created its GUI-ready marker when the marker was already absent.
- Fix: Use `try FileDelete(...)` for optional stale-marker cleanup.

## 2026-08-12 - Power Throttling Query Requires Version Initialization

- Context: Capturing exact process power-throttling state before the Ctrl+H game low-resource mode.
- Error: `GetProcessInformation(ProcessPowerThrottling)` returned `ERROR_INVALID_PARAMETER` when the 12-byte structure was zero-initialized.
- Fix: Set `Version` to `PROCESS_POWER_THROTTLING_CURRENT_VERSION` (`1`) before the query.

## 2026-08-12 - Exact Function Declaration Needed for Line-Range Audits

- Context: Auditing `LoadFrozenProcesses()` for forbidden automatic resume calls.
- Error: A loose search matched both the startup invocation and function declaration, producing an array where one line number was expected.
- Fix: Anchor the search to the declaration form, such as `^LoadFrozenProcesses\(\) \{`, before slicing source lines.

## 2026-08-12 - ScheduledTasks Cmdlet Unavailable

- Context: Auditing startup routes for the authoritative Ctrl+H/Alt+H AutoHotkey controller.
- Error: `Get-ScheduledTask` was unavailable in the current Windows PowerShell session.
- Fix: Use the explicit `C:\Windows\System32\schtasks.exe /Query /FO CSV /V` path and inspect its output before adding another startup route.

## 2026-08-12 - WINDIR Was Empty in the Tool Environment

- Context: Backing up the registry Run key before installing the AutoHotkey controller startup entry.
- Error: `$env:WINDIR` expanded to an empty string, producing the invalid executable path `\System32\reg.exe`.
- Fix: Use the explicit `C:\Windows\System32\reg.exe` path for Windows system utilities in this environment.

## 2026-08-12 - Direct AutoHotkey Invocation Left LASTEXITCODE Blank

- Context: Syntax-checking `current.ahk` before replacing the live Ctrl+H/Alt+H controller.
- Error: A direct executable invocation left `$LASTEXITCODE` blank, and a numeric comparison incorrectly treated that as a syntax failure.
- Fix: Launch the syntax check with `Start-Process -Wait -PassThru` and inspect the returned process object's `ExitCode`.

## 2026-08-12 - Self-Activating Hotkey Probe Lost Foreground

- Context: Testing Ctrl+H with a disposable AutoHotkey GUI while another window could take foreground.
- Error: The probe's delayed Ctrl+H targeted an Administrator Windows PowerShell window instead of the probe.
- Fix: Do not use delayed self-sending probes for a global foreground hotkey. Verify the exact foreground PID immediately before dispatch and fail closed if it differs.

## 2026-08-12 - Synchronous Working-Set Trim Blocked Game Restore

- Context: Reducing a multi-gigabyte game's RAM after true suspension.
- Error: `EmptyWorkingSet` blocked the controller hotkey thread long enough that Alt+H could not be processed immediately.
- Fix: Games use `game_suspend`: true suspension plus VERY_LOW memory priority, but no synchronous working-set trim. Windows may reclaim pages asynchronously while the controller remains immediately responsive.

## 2026-08-12 - Pipeline After Foreach Needs Grouping

- Context: Reporting multiple AutoHotkey syntax-check results in one PowerShell command.
- Error: Piping directly after a `foreach` statement produced `An empty pipe element is not allowed`.
- Fix: Assign the loop output to a variable or wrap the entire loop in `@(...)` before piping it to `Format-Table`.
