# WSL2 Permanent Repair Kit

This project packages a Windows PowerShell 5 compatible WSL2 and WSLg repair script under `F:\study`.

## Main Script

```powershell
F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1
```

## What It Repairs

- Re-enables the Windows optional features required by WSL2.
- Downloads and repair-installs the Microsoft WSL MSI release configured by `-WslVersion`.
- Restarts and hardens `WSLService`.
- Repairs the `wsl.exe` App Paths registration.
- Recreates a valid `C:\Program Files\WSL\wslg.rdp` when it is missing or corrupt.
- Writes `%USERPROFILE%\.wslgconfig` with `WSL2_RDP_CONFIG_OVERRIDE=wslg.rdp`.
- Repairs `.rdp` association to Windows `mstsc.exe`.
- Closes active Remote Desktop error dialogs in real time during repair.
- Stops stale WSLg `msrdc.exe` / `mstsc.exe` clients whose command line references `/wslg`, `wslg.rdp`, or `WSLDVC_PACKAGE`.
- Verifies `wsl --status`; optionally verifies `wsl -l -v` with `-DeepVerify`.
- Stores script-owned cache, logs, and diagnostics under this F-drive project.

The script must still touch Windows-owned OS paths such as `C:\Windows\System32` and `C:\Program Files\WSL`, because those are the WSL installation targets being repaired. It does not depend on the old C-drive Codex workspace.

## Usage

Audit current state without making changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1" -AuditOnly
```

Run the full repair:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1" -DeepVerify
```

Run the full repair and keep closing Remote Desktop WSLg error popups for two minutes after verification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1" -DeepVerify -PopupWatchSeconds 120
```

Run project tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\tests\Test-RepairWSL2Permanent.ps1"
```
