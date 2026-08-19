# Windows Safe Reboot Guardian Latest ISO Installer

Windows Safe Reboot Guardian is a PowerShell toolkit for Windows 11 pre-reboot readiness checks and safe repair workflows. This repository ships it as a GitHub Release ISO so any Windows user can install the latest release with one PowerShell command.

## One-line automatic install from the latest GitHub Release ISO

Open **Windows PowerShell** and run this one-liner. It automatically finds the latest release ISO, downloads it, mounts it, runs the ISO installer, and dismounts the ISO:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$repo='Michaelunkai/windows-safe-reboot-guardian-latest-iso-installer'; $api='https://api.github.com/repos/'+$repo+'/releases/latest'; $rel=Invoke-RestMethod -Uri $api; $asset=$rel.assets | Where-Object { $_.name -match '\.iso$' } | Select-Object -First 1; if(-not $asset){ throw 'No .iso asset found in latest release for '+$repo }; $iso=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $iso; $img=Mount-DiskImage -ImagePath $iso -PassThru; try { $drive=(($img | Get-Volume).DriveLetter + ':'); powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $drive 'install.ps1') -Install } finally { Dismount-DiskImage -ImagePath $iso }"
```

## What gets installed

- `fix.ps1` — Windows Safe Reboot Guardian toolkit.
- `install.ps1` — automatic ISO installer.
- `%LOCALAPPDATA%\WindowsSafeRebootGuardian\Run-WindowsSafeRebootGuardian.cmd` — fast readiness launcher.
- `%LOCALAPPDATA%\WindowsSafeRebootGuardian\Run-WindowsSafeRebootGuardian-MaximumProtection.cmd` — slower maximum-protection launcher.
- Start Menu shortcut: **Windows Safe Reboot Guardian**.

The installer is per-user, fully automatic, and does **not** require Administrator/UAC by default. It does **not** reboot, reset, format, wipe data, disable security, or flash firmware.

## After install

Run the fast readiness gate:

```powershell
%LOCALAPPDATA%\WindowsSafeRebootGuardian\Run-WindowsSafeRebootGuardian.cmd
```

Run maximum-protection mode only when you intentionally want deeper, slower checks:

```powershell
%LOCALAPPDATA%\WindowsSafeRebootGuardian\Run-WindowsSafeRebootGuardian-MaximumProtection.cmd
```

## Manual ISO use

1. Download the `.iso` from the latest GitHub Release.
2. Double-click the ISO in Windows to mount it.
3. Open PowerShell and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <MountedDrive>:\install.ps1 -Install
```

## Release verification

The release ISO is validated by:

- Windows PowerShell 5.1 parser check for `fix.ps1`.
- Windows PowerShell 5.1 parser check for `install.ps1`.
- `install.ps1 -SelfTest`.
- ISO content inspection for `fix.ps1`, `install.ps1`, `README.md`, and `LICENSE`.
- End-to-end latest-release one-liner test.

## Honesty note

No script can guarantee that Windows will never fail to boot. Hardware failure, firmware bugs, storage/RAM instability, malware, bad drivers, and interrupted Windows servicing can still break a machine. This tool reduces risk through safe checks, evidence collection, repair gates, and clear readiness labels.
