# Windows Safe Reboot Guardian ISO Installer

Windows Safe Reboot Guardian is a PowerShell toolkit for Windows 11 pre-reboot readiness checks and safe repair workflows. This repository ships it as a GitHub Release ISO so any Windows user can install the latest release with one PowerShell command.

## What gets installed

The release ISO contains:

- `fix.ps1` — the Windows Safe Reboot Guardian toolkit.
- `install.ps1` — the ISO installer that copies the toolkit to `%LOCALAPPDATA%\WindowsSafeRebootGuardian`.
- launcher commands under `%LOCALAPPDATA%\WindowsSafeRebootGuardian`.
- a Start Menu shortcut named **Windows Safe Reboot Guardian**.

The installer does **not** require Administrator by default and does **not** reboot, reset, format, wipe data, disable security, or flash firmware.

## One-line automatic install from the latest GitHub Release ISO

Open **Windows PowerShell** and run this one-liner. It automatically finds the latest release ISO, downloads it, mounts it, runs the ISO installer, and dismounts the ISO:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$repo='Michaelunkai/windows-safe-reboot-guardian-iso-installer'; $api='https://api.github.com/repos/'+$repo+'/releases/latest'; $rel=Invoke-RestMethod -Uri $api; $asset=$rel.assets | Where-Object { $_.name -match '\.iso$' } | Select-Object -First 1; if(-not $asset){ throw 'No .iso asset found in latest release for '+$repo }; $iso=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $iso; $img=Mount-DiskImage -ImagePath $iso -PassThru; try { $drive=(($img | Get-Volume).DriveLetter + ':'); powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $drive 'install.ps1') -Install } finally { Dismount-DiskImage -ImagePath $iso }"
```

## After install

Run the fast under-30-second readiness gate:

```powershell
%LOCALAPPDATA%\WindowsSafeRebootGuardian\Run-WindowsSafeRebootGuardian.cmd
```

Run maximum-protection mode only when you intentionally want deeper, slower repair checks:

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

## Verification

Each release is built only after these checks pass:

- Windows PowerShell 5.1 parser check for `fix.ps1`.
- Windows PowerShell 5.1 parser check for `install.ps1`.
- `install.ps1 -SelfTest`.
- ISO contains both `fix.ps1` and `install.ps1`.
- Release asset is downloaded from GitHub and inspected as an ISO.

## Honesty note

No script can guarantee that Windows will never fail to boot. Hardware failure, firmware bugs, storage/RAM instability, malware, bad drivers, and interrupted Windows servicing can still break a machine. This tool reduces risk through safe checks, evidence collection, repair gates, and clear readiness labels.
