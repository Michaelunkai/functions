# Windows Safe Reboot Guardian

Windows Safe Reboot Guardian is a PowerShell-based pre-reboot readiness and repair toolkit for Windows 11 systems that have shown boot instability, blue screens, or service/startup failures such as:

```text
CRITICAL_SERVICE_FAILED (0x5A)
```

The project was built for one very practical question:

> Before I reboot Windows, can I run one command that checks whether the reboot is likely to come back safely instead of falling into recovery or a boot-loop?

The main script is [`fix.ps1`](./fix.ps1).

## What this project is for

Use this project when you want to reduce the risk of rebooting a Windows 11 machine after symptoms such as:

- blue screens around boot or shutdown
- `CRITICAL_SERVICE_FAILED`
- repeated Windows Recovery boot loops
- broken or disabled critical services/drivers
- suspected Windows component-store corruption
- suspected boot configuration problems
- suspected disk/storage health problems
- uncertainty before rebooting after updates, driver changes, or system repairs

The script has two different operating modes because there is a hard trade-off:

1. **Fast readiness gate** — finishes quickly and tells you whether the current machine state looks safe enough to reboot.
2. **Maximum protection repair** — runs deeper Windows repair actions, but can take minutes because DISM/SFC/CHKDSK are controlled by Windows.

## Important honesty note

No script can guarantee that Windows will never fail to boot. Hardware failure, SSD/NVMe failure, RAM instability, firmware bugs, bad drivers, power loss, malware, and interrupted Windows servicing can still break a system.

This project does **not** claim magic certainty. It does the highest-value safe checks and repairs available from inside Windows, then reports whether it can honestly call the current state ready.

## Quick start: normal under-30-second pre-reboot check

Open **Windows PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\windows-safe-reboot-guardian\fix.ps1
```

The default no-argument command runs the fast readiness gate.

Only treat the reboot as high-confidence if the output says:

```text
FAST READINESS: FAST_READY_95_PLUS
```

If it says anything else, do **not** assume the reboot is safe. Read the generated report under:

```text
F:\DOWNLOADS\Windows_PreReboot_Fix_Logs\<timestamp>\fast-readiness-30.json
```

## Full repair mode

If the fast check does not pass, or if you want a deeper repair pass before rebooting, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\windows-safe-reboot-guardian\fix.ps1 -MaximumProtection
```

Full repair mode may take much longer than 30 seconds. That is expected. It can run Windows servicing commands that often take minutes.

Only treat the full repair mode as 90%+ ready if the final output says:

```text
REBOOT READINESS: READY_90_PLUS
```

## Self-test mode

To verify that the script can start, parse, create logs, and exit cleanly without doing repairs:

```powershell
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\windows-safe-reboot-guardian\fix.ps1 -SelfTest -NoPause
```

Expected output:

```text
SELFTEST_OK
```

## What the fast readiness gate checks

The default fast mode is designed to finish under 30 seconds. It checks high-signal boot safety indicators, including:

- current BCD boot entry is readable
- no accidental Safe Mode boot flag is set
- Windows recovery configuration is visible/enabled where possible
- core Windows boot files exist
- core boot files have valid signatures
- known boot-critical driver service keys exist
- known boot-critical drivers are not disabled
- physical disks report healthy through Windows storage APIs when available
- SMART failure prediction is clear when exposed through WMI
- system drive has at least 10 GB free

It writes a JSON result file named:

```text
fast-readiness-30.json
```

## What MaximumProtection does

`-MaximumProtection` is the slower, deeper mode. It is meant for times when you are willing to wait for Windows repairs to finish before rebooting.

It can:

- self-elevate to Administrator
- create a restore point when possible
- export BCD backup
- export key registry hives before changes
- collect system, boot, crash, driver, disk, and update evidence
- collect PnP device problem reports
- collect storage health and SMART failure-prediction evidence where available
- validate core boot files and signatures
- repair disabled boot-critical service/driver start values when obviously unsafe
- ensure essential Windows services are not disabled
- disable Fast Startup to reduce hybrid-boot problems
- enable Windows recovery and boot logging
- remove accidental Safe Mode flags from the current BCD entry
- run DISM component-store checks/repairs
- run SFC verification/repair passes
- run online disk scans and schedule offline disk repair when needed
- optionally reset Windows Update components
- configure crash dump collection for future diagnosis
- write a strict reboot readiness report

## Reports and logs

Every run writes logs under:

```text
F:\DOWNLOADS\Windows_PreReboot_Fix_Logs\<timestamp>\
```

Important files include:

- `transcript.txt` — console transcript
- `summary.json` — step-by-step summary
- `warnings.txt` — warnings found during the run
- `failures.txt` — failures found during the run
- `fast-readiness-30.json` — fast mode result
- `reboot-readiness-gate.json` — full repair mode final gate
- `core-boot-files.json` — boot file existence/signature evidence
- `disk-findings.json` — disk scan findings
- `system-info.json` — system inventory

## Exit codes

- `0` — readiness gate passed / self-test passed / command completed successfully
- `2` — readiness gate did not pass the required confidence threshold
- `3` — readiness report could not be read or interpreted
- non-zero from PowerShell/Windows tools — inspect the generated logs

## Safety design

The script intentionally avoids destructive actions by default. It does **not**:

- reboot the PC
- shut down the PC
- format disks
- wipe partitions
- reset Windows
- delete personal files
- disable Windows Recovery
- import or replace the entire BCD store

It backs up important boot/registry data before making targeted safety repairs.

## Recommended workflow before rebooting

1. Open Windows PowerShell as Administrator.
2. Run the default fast readiness gate.
3. If it says `FAST_READY_95_PLUS`, reboot confidence is high.
4. If it does not pass, run `-MaximumProtection`.
5. If full mode says `READY_90_PLUS`, reboot confidence is high.
6. If neither mode passes, read the JSON report and fix the specific blocker before rebooting.

## Project file

Main script:

```text
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\windows-safe-reboot-guardian\fix.ps1
```
