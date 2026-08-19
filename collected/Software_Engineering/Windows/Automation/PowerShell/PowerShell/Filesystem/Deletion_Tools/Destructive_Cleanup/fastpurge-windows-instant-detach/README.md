# FastPurge Windows Instant Detach

FastPurge is a Windows command-line utility created from the completed Hermes `/project` mission. It provides a practical way to make a folder disappear from its original path quickly, then continue the expensive physical deletion work in a hidden background worker.

## What it does

`app.exe <folder to purge>`:

1. Validates the requested folder is not an unsafe system/protected target.
2. Refuses drive roots, Windows/System/Program Files/ProgramData targets, the current user-profile root, 8.3 protected-path aliases such as `C:\PROGRA~1`, and top-level junction/symlink/reparse-point targets.
3. Moves the target directory to a hidden same-drive `.fastpurge-graveyard` folder.
4. Starts a hidden worker process that recursively deletes the moved graveyard folder.

This gives the useful effect of an immediate path detach. Physical deletion of huge data still depends on disk speed, file count, permissions, locks, antivirus, and Windows filesystem behavior.

## Important honesty note

No normal Windows user-mode tool can guarantee that a 1TB+ folder is physically deleted in under 5 seconds. FastPurge is engineered to make the original path disappear quickly when Windows allows a same-volume rename/move. The background worker then finishes deletion asynchronously.

If another process holds a non-delete-sharing handle, Windows can block even the fast detach. In that case the app returns a clear failure instead of silently claiming success.

## Prerequisites

- Windows 10/11.
- For using the already-built binary: no .NET SDK required on this machine because `dist\app.exe` is built with the system C# compiler target used during verification.
- For rebuilding from source: Windows PowerShell 5 and `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.

## Usage

From Windows PowerShell:

```powershell
& 'F:\study\Software_Engineering\Windows\Automation\PowerShell\Filesystem\Deletion_Tools\Destructive_Cleanup\fastpurge-windows-instant-detach\dist\app.exe' 'C:\path\to\folder'
```

Multiple folders are supported:

```powershell
& 'F:\study\Software_Engineering\Windows\Automation\PowerShell\Filesystem\Deletion_Tools\Destructive_Cleanup\fastpurge-windows-instant-detach\dist\app.exe' 'C:\folder1' 'D:\folder2'
```

Expected output looks like:

```text
DETACHED C:\path\to\folder -> C:\path\to\.fastpurge-graveyard\folder.purging.<timestamp-guid> in 0.002s
```

## Build

```powershell
& 'F:\study\Software_Engineering\Windows\Automation\PowerShell\Filesystem\Deletion_Tools\Destructive_Cleanup\fastpurge-windows-instant-detach\build.ps1'
```

This creates:

- `dist\app.exe` — primary runnable tool.
- `build\FastPurge.dll` — test/reference build artifact.
- `build\FastPurge.Tests.exe` — local test executable.

## Test and smoke verification

Run the unit-style test executable after building:

```powershell
& 'F:\study\Software_Engineering\Windows\Automation\PowerShell\Filesystem\Deletion_Tools\Destructive_Cleanup\fastpurge-windows-instant-detach\build\FastPurge.Tests.exe'
```

Run the practical smoke test:

```powershell
& 'F:\study\Software_Engineering\Windows\Automation\PowerShell\Filesystem\Deletion_Tools\Destructive_Cleanup\fastpurge-windows-instant-detach\smoke.ps1'
```

The smoke test creates 1,000 small files under `C:\Temp\HermesFastPurge_smoke_victim`, runs `dist\app.exe`, verifies the original path is gone, and checks for graveyard leftovers.

## Important files

- `src/FastPurge/Program.cs` — CLI, safety checks, detach logic, and background purge worker.
- `tests/FastPurge.Tests/Program.cs` — regression tests for unsafe roots, protected descendants, 8.3 aliases, worker bypass protection, junction refusal, detach, multi-folder usage, and read-only file cleanup.
- `build.ps1` — Windows PowerShell 5 build script.
- `smoke.ps1` — real runtime smoke test.
- `dist/app.exe` — runnable compiled tool.

## Troubleshooting

- **`FAILED ... process may hold a non-delete-sharing handle`**: close apps using files inside that folder and retry.
- **`REFUSED unsafe target`**: the path is a protected/system/root/reparse target and is intentionally blocked.
- **Background deletion takes time**: this is expected for huge folders; the original path has been detached, while physical disk deletion continues.
- **Antivirus slows deletion**: Defender or another scanner can slow the background worker on very large trees.
- **Cross-drive graveyard error**: instant detach requires the graveyard to be on the same drive/volume as the target.

## Repository

Public GitHub repository: https://github.com/Michaelunkai/fastpurge-windows-instant-detach

Repository name: `fastpurge-windows-instant-detach`
