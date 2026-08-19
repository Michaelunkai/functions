# collected/ — Windows-related content consolidated here

Everything "Windows" scattered across `F:\study` was moved here on **2026-08-09** and organized by
the study-area it came from. Each subfolder mirrors the original path, so it is always clear where
something came from (and easy to move back if ever needed).

```
collected/
├── AI_ML/                 Windows bits from F:\study\AI_ML\...
├── Containers/            docker desktop / kubernetes registry cache Windows parts
├── Dev_Toolchain/         Dev_Toolchain\Windows, Android SDK/NDK windows prebuilts, zig, mingw, scripts
├── Devops/                WindowsInstalled, WindowsPowerShell profile backup, MacriumReflect, DotNET builds
├── Learning/              Learning\01\01 mirror (docs, fixes, how-tos, tweaks)
├── Operating_Systems/     Operating_Systems\Windows
├── Software_Engineering/  Software_Engineering\Windows + Android automation windows parts
├── Systems/               Systems\Windows
├── Windows/               The big F:\study\Windows tree (Applications, Backup, Maintenance, Repair, ...)
├── networking/            networking\Performance\Windows
├── projects/              windows-related projects, toolchains, build outputs, caches
└── repos/                 git mirrors of windows repos/study content
```

## What happened

- **155 source items** (folders + files whose names contain "windows") were moved from across
  `F:\study` into this folder; every move is logged in `MANIFEST.tsv` (source → destination).
- **Perfect duplicates** (verified byte-for-byte identical) were removed, keeping one copy each:
  `windowsoptimize` ×5, `WindowsForcePurge` ×4, `CoolDownGpuNcpu/windows` ×4, flutter-windows stubs ×3,
  mingw cmake Templates ×1, whisper setup doc ×3, `Windows-11-Fix-Tweaks`, `windows11_management`,
  `Perfect Windows`, Firewall `windows`, Devops `System\Windows` mirrors, and one duplicate
  `qemu/windows-x86_64` (≈445 MB). One copy of each was kept.
- **Empty / garbage folders** (e.g. empty `Speech\Windows`, empty SWC/Prisma caches, empty
  `windowsforcepurge` archive) were removed.
- Empty directories left behind at the source locations were removed (92 dirs); pre-existing empty
  dirs were left untouched.

## What was NOT moved (still at original location — do not delete)

These were left in place on purpose because **running processes** have them open (their working
directory / live files), so moving them would break something you are actively using:

| Still at source | Because |
|---|---|
| `F:\study\Windows\Applications\Desktop\Utilities\System\Startup\Managers\mich-startup-master\build` | `MichStartupMaster.exe` is running |
| `F:\study\Windows\Applications\Mobile\Android\Automation\RemoteCommandCenter` | `RemoteCommandCenterTray.exe` is running |
| `F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync-RebootReady` | `MichAutoClipSyncTray.exe` is running |
| `F:\study\Systems\Windows\Media\GameStreaming\MoonlightBackgroundGamepad` | `MoonlightBackgroundGamepad.exe` is running |
| `F:\study\Software_Engineering\Windows\Automation\RemoteAccess\TrayCompanions\CodexPcBridge\release\windows` + `runtime` | two `CodexPcBridge.exe` processes are running |
| `F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\system\hardware-tools` | the Freebuff desktop client keeps its live database here (`.freebuff\desktop-v2.db`) |

Once those apps are closed (and Freebuff is not running), the remaining folders can be moved into
`collected/` the same way.

Note: `F:\study\Devops\backup\backup\profile\backup-data\WindowsPowerShell` was moved, but your
backup tooling **re-created it** at its old location on 2026-08-09 16:55 with a fresh copy — that is
live backup data and was left in place.

---

## Space optimization (2026-08-09, second pass)

The folder was slimmed from **44 GB → 9.4 GB** (~79% reduction) by removing only
regenerable / re-downloadable content. **Nothing irreplaceable was deleted**:

Removed:
- All `node_modules`, `.venv*`, `__pycache__`, `.gradle`, `.next`, `bin/obj` build outputs,
  `target/` (Rust), `*.log`, `.nuget` / `.dotnet` / `.tools/dotnet` SDK caches
- Re-downloadable toolchains: Zig, Android NDK windows prebuilts, qemu `windows-x86_64` ×2,
  mingw cmake templates
- Windows 11 install media (`install.esd` + `boot.wim`, ~6.4 GB) — see
  `system-administration/.../WinSetup/sources/RESTORE-INSTALL-MEDIA.txt` to restore
- AVD quick-boot `snapshots` (regenerated on next boot) + Android SDK platforms/build-tools
- FitGirl auto-install `extracted-packages` (re-extractable) + `dist` build output
- 735 accumulated PowerShell profile `.bak-*` snapshots (active profile + newer backups kept)
- Temp dirs, diagnostic snapshot caches, decompilation proof dumps (original APKs kept),
  disk-cleaner download/log caches, WinPE `media/` (ISO kept)

Kept on purpose:
- All source code, scripts, docs, configs, git history (93 `.git` dirs)
- All backup data: MacriumReflect (1.7 GB), WindowsPowerShell profile backups (1.3 GB),
  FitGirl `historical-backup-*.7z`, mich-startup-master backup archive
- The WindowsFixer `WinPE_AutoRepair.iso` (their repair media)
- The `DaymarkApi34.avd` emulator disk image (2.6 GB) — delete only if the emulator is no longer used
- The running `AssLatestGameBackup` app and everything owned by running processes
