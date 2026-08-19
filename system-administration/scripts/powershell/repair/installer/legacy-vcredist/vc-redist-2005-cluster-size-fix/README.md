# VC++ 2005 Cluster Size Error Fix

A small Windows PowerShell 5.1 repair utility for old Microsoft Visual C++ 2005 Redistributable / InstallShield installers that fail with this message:

> The cluster size in this system is not supported.

The error commonly appears when a legacy installer uses a temporary directory located on an unsupported filesystem or allocation-unit layout, for example an exFAT/Ventoy USB drive, FAT volume, ReFS volume, or another non-NTFS/large-cluster path. Old VC++ 2005 bootstrapper logic expects a normal local NTFS temp location and can abort before installation begins.

This project makes the fix repeatable: run one PowerShell 5 script and it permanently redirects Windows `TEMP` and `TMP` to a safe local NTFS 4 KB temp folder.

## What the script does

`Repair-VcRedist2005ClusterSize.ps1`:

1. Creates a safe temp folder, defaulting to `C:\Temp`.
2. Verifies that the selected temp folder is on NTFS.
3. Verifies the NTFS cluster size is 4096 bytes.
4. Verifies that the folder is writable.
5. Updates the current PowerShell process `TEMP` and `TMP` values immediately.
6. Permanently updates the current user `TEMP` and `TMP` environment variables.
7. If run as Administrator, also permanently updates machine-wide `TEMP` and `TMP`.
8. Provides a wrapper function that can run old installers from the safe temp folder so they do not execute directly from an unsupported USB/exFAT/source volume.
9. Prints machine-readable `RESULT=PASS` or `RESULT=FAIL` output for verification.

## When to use it

Use this when an old installer, especially VC++ 2005 Redistributable or an application bundle that includes it, shows:

```text
Error 2727 / The cluster size in this system is not supported
```

or a dialog titled similar to:

```text
Microsoft Visual C++ 2005 Redistributable
The cluster size in this system is not supported.
```

## Requirements

- Windows PowerShell 5.1
- Windows with a normal NTFS system drive
- Administrator is recommended for machine-wide repair
- No PowerShell 7 features are required

## Quick start

Open **Windows PowerShell as Administrator** and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\installer\legacy-vcredist\vc-redist-2005-cluster-size-fix\Repair-VcRedist2005ClusterSize.ps1"
```

Expected success output includes:

```text
RESULT=PASS
SAFE_TEMP=C:\Temp
USER_TEMP=C:\Temp
USER_TMP=C:\Temp
MACHINE_TEMP=C:\Temp
MACHINE_TMP=C:\Temp
```

After running it, close the broken VC++ installer and launch it again.

## Run an installer through the safe temp wrapper

If the installer still fails because it is being executed from an unsupported USB/exFAT source, pass the installer path to the script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\system-administration\scripts\powershell\repair\installer\legacy-vcredist\vc-redist-2005-cluster-size-fix\Repair-VcRedist2005ClusterSize.ps1" -InstallerPath "F:\Downloads\vcredist_x86.exe"
```

The script copies the installer into `C:\Temp\LegacyInstallerSafeRun` and starts it with safe `TEMP` and `TMP` variables.

## Options

### `-SafeTemp <path>`

Use a custom safe temp folder. It must be writable, NTFS, and 4096-byte cluster size.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Repair-VcRedist2005ClusterSize.ps1" -SafeTemp "C:\Temp"
```

### `-SelfTestOnly`

Runs the repair/verification path without searching for or launching installers.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Repair-VcRedist2005ClusterSize.ps1" -SelfTestOnly
```

### `-InstallerPath <path>`

Runs one or more installer executables from the safe temp directory after applying the environment fix.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Repair-VcRedist2005ClusterSize.ps1" -InstallerPath "D:\setup\vcredist_x86.exe","D:\setup\vcredist_x64.exe"
```

### `-AutoRunVCRedist`

Searches near common download/script locations for VC++ redistributable installers and runs matches through the safe wrapper.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Repair-VcRedist2005ClusterSize.ps1" -AutoRunVCRedist
```

## Safety notes

- The script does not delete applications, drivers, games, saves, profiles, or installer files.
- It only creates/uses a safe temp folder and changes Windows environment variables for `TEMP` and `TMP`.
- Running as Administrator is recommended so elevated installers and all users can inherit the machine-wide fix.
- Existing already-open programs may keep their old environment block until restarted.
- If the installer window is already open, close it and launch it again after the fix.

## Troubleshooting

### The script says it is not elevated

The user-level fix still applies, but machine-wide `TEMP/TMP` will not be changed. Re-run PowerShell as Administrator and execute the script again.

### The installer still fails

Run the installer via `-InstallerPath` so it executes from the safe NTFS temp folder instead of directly from USB/exFAT/Ventoy media.

### Custom safe temp is rejected

Choose a folder on an NTFS volume with 4096-byte clusters. The default `C:\Temp` is usually correct.

## Verification history

This utility was validated with Windows PowerShell 5.1 by:

- Parsing the script successfully with the PowerShell 5 parser.
- Running the repair repeatedly.
- Confirming the final `TEMP` and `TMP` values resolved to `C:\Temp` for user and machine scopes.

## License

MIT License. See `LICENSE`.
