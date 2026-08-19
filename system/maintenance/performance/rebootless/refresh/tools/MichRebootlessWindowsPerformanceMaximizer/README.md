# MichRebootlessWindowsPerformanceMaximizer

MichRebootlessWindowsPerformanceMaximizer is a Windows 11 no-reboot performance refresh tool built from the completed Hermes Telegram mission. It opens a live progress window, runs the strongest safe refresh workflow we can do without intentionally closing normal running applications, and prints before/after/difference metrics at the end. The worker has a hard 15-second fast contract: every external command and cleanup pass is deadline-aware, and slow uninterruptible paths are skipped instead of letting the app look alive while it overruns.

## What it does

The runnable app triggers the elevated Windows Scheduled Task named `Hermes Ultimate Performance Refresh`, which runs the PowerShell worker in `%LOCALAPPDATA%\HermesUltimateRefresh`. The repository stores a copy of the production executable, source, worker script, wrappers, and verification evidence. The production files are intentionally copied instead of moved so the already-installed hotkey/task setup keeps working.

Main refresh stages:

- Native per-process working-set trim plus EmptyWorkingSet pass without closing applications.
- Fast standby/file-cache trimming with slow memory-pressure allocation skipped under the 15-second contract.
- Managed runtime garbage collection sweep.
- DNS resolver flush, NetBIOS cache refresh, ARP refresh, and IPv4/IPv6 destination-cache refresh; slow DNS re-registration/cmdlet paths are intentionally skipped inside the fast contract.
- WinHTTP/proxy/TCP state touch without network reset.
- Environment, policy, shell, app-model, icon, and UI-setting broadcasts.
- Graphics/compositor nudge using the Windows graphics reset hotkey path.
- Explorer icon, thumbnail, jump-list, font-cache, and Windows shell cache cleanup where files are unlocked.
- WER, Delivery Optimization, DirectX shader, GPU vendor shader, browser GPU/shader/code/media cache cleanup where files are unlocked.
- App runtime communication caches, Windows app-model package caches, recent-file/history telemetry caches, and shell session cache touches where files are unlocked.
- Bounded developer-runtime cache cleanup for old unlocked package/build caches.
- Bounded temp cleanup of unlocked stale top-level temp trees.
- Extra shell/session/system-parameter broadcasts plus service-control-manager, WMI, and performance-counter touches.
- Fast fixed-volume/storage state touch without a slow retrim pass.
- Immediate Ultimate Performance activation without duplicating schemes every run, plus AC CPU/disk/PCIe/USB latency-oriented settings.
- Final trim pass and before/after/delta summary including RAM, load, process, handle, thread, temp, and disk evidence.

## Hard safety contract

This tool does **not** intentionally close normal running applications and does **not** reboot Windows. Some Windows UI surfaces may flicker because shell/display/compositor refreshes are part of the job. Files that are locked or in use are skipped.

The tool prioritizes finishing under 15 seconds over exhaustive slow cleanup. Broad recursive scans, long DISM/SFC-style servicing work, DNS re-registration, retrim, and large memory-pressure allocations are intentionally not part of the hot path because they cannot be guaranteed to finish quickly on every live Windows state.

## Prerequisites

- Windows 11.
- Existing installed production task/files from the mission:
  - `%LOCALAPPDATA%\HermesUltimateRefresh\UltimatePerformanceRefresh.ps1`
  - Scheduled Task: `Hermes Ultimate Performance Refresh`
- Optional for rebuilding: .NET Framework C# compiler (`csc.exe`) included with Windows/.NET Framework.

## Usage

Run the repository copy:

```powershell
F:\study\Platforms\windows\system\maintenance\performance\rebootless\refresh\tools\MichRebootlessWindowsPerformanceMaximizer\app\MichRebootlessWindowsPerformanceMaximizer.exe
```

Or run the production copy:

```powershell
%LOCALAPPDATA%\HermesUltimateRefresh\UltimatePerformanceRefresh.exe
```

The app opens a live GUI window. Leave it open until it shows the final BEFORE / AFTER / DIFF section.

## Important files

- `app/MichRebootlessWindowsPerformanceMaximizer.exe` — runnable project copy.
- `src/UltimatePerformanceRefreshProgress.cs` — WinForms progress-window executable source.
- `scripts/UltimatePerformanceRefresh.ps1` — elevated refresh worker.
- `scripts/Run-UltimatePerformanceRefresh.ps1` — production launcher wrapper, if present.
- `scripts/compile_and_verify.ps1` — production compile/verify helper, if present.
- `logs/` — copied proof logs from the completed mission.

## Rebuild notes

The executable source is C#/.NET Framework WinForms. The worker is PowerShell 5 compatible. The production executable currently delegates to the installed scheduled task, so installing/updating the production task remains separate from this archived project copy.

## Troubleshooting

- If the app opens but no progress appears, verify the scheduled task exists: `Get-ScheduledTask -TaskName 'Hermes Ultimate Performance Refresh'`.
- If the run shows little RAM improvement, Windows may already have little reclaimable standby/cache memory at that moment. The tool can only release what Windows can safely release without closing apps or rebooting.
- If temp cleanup reports skipped files, those files are locked/in use and are intentionally preserved.
