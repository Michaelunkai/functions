# allstart2-silent-launchers-20260604

This project repairs the missing silent startup launcher files used by the Windows PowerShell 5 `allstart2` startup function.

## Purpose

`allstart2` manages the user's no-popup Windows startup profile. Three C-drive VBS launcher files were referenced by startup tasks but no longer existed:

- `openspeedy-silent.vbs`
- `murmure-silent.vbs`
- `trayquiet-start.vbs`

This project recreates them under `F:\study` and provides a patched `Invoke-allstart2.ps1` target that points to these durable repo-local launchers.

## What it creates

- `openspeedy-silent/openspeedy-silent.vbs` launches OpenSpeedy hidden from `F:\backup\windowsapps\installed\OpenSpeedy\Speedy.exe`.
- `murmure-silent/murmure-silent.vbs` launches Murmure hidden from `C:\Program Files\murmure\murmure.exe`.
- `trayquiet-start/trayquiet-start.vbs` accepts a target executable path and launches it with a hidden window style, after optional startup wait/retry arguments.
- `Invoke-allstart2.ps1` is the allstart2 runtime script with the launcher paths updated to this project.
- `allstart2.custom.psd1` preserves the current custom startup application list.

## Prerequisites

- Windows PowerShell 5.1
- Windows Script Host (`C:\Windows\System32\wscript.exe`)
- Existing target applications:
  - `F:\backup\windowsapps\installed\OpenSpeedy\Speedy.exe`
  - `C:\Program Files\murmure\murmure.exe`
  - any custom target configured in `allstart2.custom.psd1`

## Usage

From Windows PowerShell 5:

```powershell
. 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\Invoke-allstart2.ps1' -Mode Verify -DryRun
```

To run the startup enforcement/update path:

```powershell
. 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604\Invoke-allstart2.ps1' -Mode Startup
```

The PowerShell profile function `allstart2` is patched separately to call this project-local script.

## Testing

Use Windows PowerShell 5 only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-AllStart2SilentLaunchers.ps1
```

The test checks parser validity, path existence, and that each VBS file can be invoked without opening a terminal window.

## Troubleshooting

- If `openspeedy-silent.vbs` exits `2`, OpenSpeedy is missing at the configured F-drive path.
- If `murmure-silent.vbs` exits `2`, Murmure is missing at `C:\Program Files\murmure\murmure.exe`.
- If `trayquiet-start.vbs` exits `64`, it was called without a target path.
- If a startup task still references `C:\Users\micha\.claude\scripts\...`, rerun `allstart2 -Mode Startup` from a fresh Windows PowerShell 5 session after dot-sourcing the patched profile.

## Repository

https://github.com/Michaelunkai/allstart2-silent-launchers-20260604

