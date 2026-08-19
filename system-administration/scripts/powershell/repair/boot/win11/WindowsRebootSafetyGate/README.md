# Windows Reboot Safety Gate

A small, repeatable Windows 11 safety-check project for the PowerShell script `a.ps1`.

The script was created after serious boot/recovery symptoms such as:

- `CRITICAL_SERVICE_FAILED`
- `SECURE_BOOT_VIOLATION`
- `PAGE_FAULT_IN_NONPAGED_AREA`
- recovery / boot error `0xc000000f`

It checks and repairs the common software-side reasons Windows might fail to boot cleanly after a reboot. It does **not** reboot the computer by itself.

## What this project does

When you run `a.ps1` as Administrator, it performs a reboot-readiness gate:

1. Confirms the script is running elevated.
2. Checks the real Windows system drive and Windows directory.
3. Refreshes UEFI boot files with `bcdboot` when fixes are enabled.
4. Verifies the default Windows boot loader points to the correct `C:\Windows` installation.
5. Clears unsafe boot flags such as test-signing / integrity-bypass flags where possible.
6. Resets Driver Verifier so it cannot force a verifier-induced boot loop.
7. Checks pagefile and critical boot/service conditions.
8. Runs Windows integrity checks such as DISM RestoreHealth and SFC in full mode.
9. Reviews recent crash, Kernel-Power, BugCheck, service-control, Setup, and critical Application events.
10. Reports stopped automatic services and selected critical service/driver state.
11. Configures CrashControl for automatic reboot after bugcheck and memory dump capture.
12. Sets BCD recovery/display policy so boot failures are visible and recovery remains enabled.
13. Checks system-drive free space, BitLocker status, problem devices, physical disk health, Secure Boot, and boot-driver signatures.
14. Writes a text report and JSON report to `C:\Temp\reboot_safety_gate`.
15. Ends with either `REBOOT SAFETY GATE: PASS` or a failure with hard blockers listed.

A `PASS` means the script did not find remaining software-side blockers in the checks it performs. It is evidence-based readiness, not a magic guarantee that hardware, firmware, future updates, or power loss cannot cause problems.

## Files

- `a.ps1` — the reboot-safety gate script.
- `README.md` — this tutorial.
- `.gitignore` — keeps temporary/local files out of Git.
- `LICENSE` — MIT license for this project wrapper.

## Requirements

- Windows 11.
- PowerShell 5.1 or newer.
- Administrator PowerShell window.
- UEFI Windows installation for the boot-file refresh checks.

## How to run it from anywhere

Open **Windows Terminal** or **PowerShell** as Administrator, then run this exact command:

```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\WindowsRebootSafetyGate\a.ps1"
```

That is the normal repair-and-verify mode.

## Safe check-only mode

If you want to inspect without making repairs, use `-NoFix`:

```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\WindowsRebootSafetyGate\a.ps1" -NoFix
```

## Faster mode

If you want a quicker run, use `-Quick`:

```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\WindowsRebootSafetyGate\a.ps1" -Quick
```

Use the normal full command when you want the strongest check.

## JSON-only mode

For automation, use `-JsonOnly`:

```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\WindowsRebootSafetyGate\a.ps1" -JsonOnly
```

## How to read the result

After every run, check these files:

```text
C:\Temp\reboot_safety_gate\latest.txt
C:\Temp\reboot_safety_gate\latest.json
C:\Temp\reboot_safety_gate\run_YYYYMMDD_HHMMSS.log
```

The most important fields are:

- `status` / headline: should be `PASS`.
- `hardBlockerCount`: should be `0`.
- `warningCount`: warnings are not always boot blockers; read them.
- `repairCount`: tells you what the script repaired during that run.
- `transcript`: the detailed log for that exact run.

## Step-by-step for a non-technical person

1. Save any open work.
2. Press the Windows key.
3. Type `PowerShell`.
4. Right-click **Windows PowerShell**.
5. Click **Run as administrator**.
6. Copy the normal command from the section above.
7. Paste it into the Administrator PowerShell window.
8. Press Enter.
9. Wait until it finishes.
10. Look for `REBOOT SAFETY GATE: PASS`.
11. If it says PASS and `Hard blockers: 0`, the script found no hard reboot blockers in its checks.
12. If it lists hard blockers, do not treat the system as ready; read the report and fix the listed blockers first.

## Troubleshooting

### “Script is not elevated”

You opened a normal PowerShell window. Close it and reopen PowerShell using **Run as administrator**.

### Execution policy blocks the script

Use the documented command with `-ExecutionPolicy Bypass`. That bypass is only for this PowerShell process.

### The script reports warnings

Warnings are evidence you should read. They are not automatically hard boot blockers. The script separates warnings from hard blockers so you can see what matters most.

### The script reports hard blockers

Do not reboot based only on hope. Open `C:\Temp\reboot_safety_gate\latest.txt`, read the hard blocker list, fix those items, and run the script again.

## Security notes

- The script is intended for the local Windows machine where it is run.
- It should be reviewed before use on another person's PC.
- It writes reports locally under `C:\Temp\reboot_safety_gate`.
- It records event-log and service evidence in local transcripts/reports.
- It changes boot/recovery/dump settings only when fixes are enabled; use `-NoFix` for inspection-only mode.
- It does not upload reports or secrets.
- It does not reboot the computer automatically.

## GitHub usage

This folder is designed to be a normal Git repository. Typical maintenance commands from this folder are:

```powershell
git status
git add .
git commit -m "Update reboot safety gate"
git push --force-with-lease origin main
```
