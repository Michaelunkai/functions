# GIGABYTE Control Center Ryzen Master Install Loop Fix

This project archives and packages the fix for a GIGABYTE Control Center problem where **AMD Ryzen Master** keeps appearing as an available install after it has already been installed and the computer/GCC is relaunched.

## What this fixes

GIGABYTE Control Center reads its update/install detection data from local CSV metadata and registry markers. On this PC, Windows showed **AMD Ryzen Master 3.1.0.5185** installed, but the marker GIGABYTE expects was missing:

- Expected marker: `HKLM:\SOFTWARE\AMD\RyzenMaster\VersionNumber`
- Existing marker before fix: `HKLM:\SOFTWARE\AMD\RyzenMaster\EnableAT=false`

Because `VersionNumber` was missing, GCC treated Ryzen Master as `N/A` and repeatedly offered an older Ryzen Master package (`3.0.0.4199`).

The main script repairs this class of problem by reading installed application versions from Windows uninstall registry entries, writing the version markers that GCC expects, stopping GCC updater processes, and clearing GCC's cached update list.

## Main entry point

Run this from **PowerShell 5 as Administrator**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Administration\Hardware\Vendors\GIGABYTE\Control_Center\Installer_Fixes\gcc-ryzen-master-install-loop-fix-20260527\scripts\Fix-GCCInstallLoop.ps1"
```

A production copy was also installed at:

```powershell
C:\ProgramData\Hermes\Fix-GCCInstallLoop.ps1
```

That production copy was copied into this repository, not moved, so the one-liner already saved to the clipboard in the original mission keeps working.

## Prerequisites

- Windows 11 or compatible Windows system
- PowerShell 5
- Administrator PowerShell window
- GIGABYTE Control Center installed
- AMD Ryzen Master or another GCC-detected utility already installed but still falsely offered by GCC

## Usage

1. Open **Windows PowerShell** as Administrator.
2. Run the command shown in **Main entry point**.
3. Reopen GIGABYTE Control Center.
4. Refresh/check the update list.
5. AMD Ryzen Master should no longer be shown as needing installation if it is already installed.

## What the script does

- Confirms it is running elevated.
- Reads installed app names and versions from:
  - `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
  - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*`
  - `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`
- Writes GCC-compatible version markers, especially:
  - `HKLM:\SOFTWARE\AMD\RyzenMaster\VersionNumber`
- Parses GIGABYTE metadata under:
  - `C:\Program Files\GIGABYTE\Control Center\Lib\GBT_MB_Update\Drvdata`
- Stops GCC updater processes so stale state is not held open.
- Backs up and removes:
  - `C:\Program Files\GIGABYTE\Control Center\GCCUpdate.txt`

## Important files

- `scripts/Fix-GCCInstallLoop.ps1` — runnable fix script inside this repo.
- `diagnostics/` — investigation scripts used to find the culprit registry/key/cache behavior.
- `artifacts/gcc_install_loop_fix_oneliner.txt` — archived long encoded one-liner that was generated during the mission.
- `screenshots/` — copied screenshots from the original Telegram report.
- `ARTIFACT_MANIFEST.json` — machine-readable list of moved/copied artifacts and source locations.

## Troubleshooting

### PowerShell says to run elevated

Open Start Menu, search **Windows PowerShell**, right-click, choose **Run as administrator**, then run the command again.

### GCC still shows Ryzen Master after running the script

1. Fully close GIGABYTE Control Center.
2. Check Task Manager for `GCC.exe`, `GigabyteUpdateService.exe`, or `GBT_DL_LIB.exe` and end them if still running.
3. Run the script again as Administrator.
4. Reopen GCC.

### You want to inspect what changed

Check:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\AMD\RyzenMaster'
```

Expected value:

```text
VersionNumber = 3.1.0.5185
```

### Safety notes

The script does not uninstall AMD drivers, chipset drivers, Ryzen Master, or GIGABYTE Control Center. It only repairs version marker registry entries and clears GCC's stale update cache.
