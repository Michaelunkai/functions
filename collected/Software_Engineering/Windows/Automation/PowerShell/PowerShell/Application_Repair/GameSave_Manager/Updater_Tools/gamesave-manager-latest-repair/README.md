# GameSave Manager Latest Repair

Repository: https://github.com/Michaelunkai/gamesave-manager-latest-repair

This repository packages the PowerShell repair/update script created during the Telegram mission that fixed GameSave Manager's visible **File not found** error dialog and upgraded the installed app to the latest version.

## What it does

The main script downloads the current GameSave Manager ZIP from the official `gamesave-manager.com` site, verifies the published hashes, backs up existing settings, stops any running `gs_mngr_3.exe`, extracts the new release into the existing install folder, launches the app, and checks the visible desktop for `File not found`, `Error`, or exception dialogs.

The mission repaired this installed copy:

`F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe`

Verified fixed version: **3.1.580.0**.

## Prerequisites

- Windows PowerShell 5 or newer.
- Internet access to `https://www.gamesave-manager.com/`.
- Existing or writable install folder at `F:\backup\windowsapps\installed\gamesavemanager`.
- Desktop session access for the UI error-dialog probe.

## Usage

From PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Software_Engineering\Windows\Automation\PowerShell\Application_Repair\GameSave_Manager\Updater_Tools\gamesave-manager-latest-repair\run-gamesave-manager-latest-repair.ps1"
```

Or run the payload script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Software_Engineering\Windows\Automation\PowerShell\Application_Repair\GameSave_Manager\Updater_Tools\gamesave-manager-latest-repair\scripts\repair_gamesavemanager_latest.ps1"
```

## Inputs and outputs

- Input: the official GameSave Manager website and the existing install folder.
- Output: the latest GameSave Manager files installed in the configured install folder.
- Working/log directory: `C:\Temp\gsm_latest_repair` when the script runs.
- Settings backup: a timestamped `settings_backup_*` folder under `C:\Temp\gsm_latest_repair`.

## Important files

- `run-gamesave-manager-latest-repair.ps1` — stable repo-local launcher.
- `scripts/repair_gamesavemanager_latest.ps1` — full updater/repair script.
- `tests/verify_gsm.ps1` — reads the installed executable version, running process, and last repair log.
- `artifacts/logs/last_run.log` — proof log from the successful mission run.
- `artifact-manifest.json` — copied mission artifact inventory.

## Verification performed during the mission

- Downloaded official latest release: `GameSaveManager_3.1.580.0.zip`.
- Verified MD5: `b7ea1eef4def5307fd4493ddddf4220f`.
- Verified SHA1: `610330a78f197e2b6421a9e41eadbe9680421ce1`.
- Installed ProductVersion/FileVersion: `3.1.580.0`.
- Launched GameSave Manager and observed no visible `File not found` / `Error` dialog during the probe.

## Troubleshooting

- If PowerShell says the script cannot run, use `-ExecutionPolicy Bypass` as shown above.
- If the app is locked, close GameSave Manager and rerun the launcher.
- If the website changes its download page format, the script may fail while reading the latest version or ZIP URL; update the regexes in `scripts/repair_gamesavemanager_latest.ps1`.
- If the UI probe reports an error dialog, rerun after closing other unrelated error dialogs so only GameSave Manager windows are visible.
