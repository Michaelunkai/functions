# allstart safe startup bootstrap

This project is the stable production entrypoint for the `allstart` PowerShell profile launcher:

`F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1`

The live profile dot-sources this script and forwards arguments. Keep startup entries pointed at this production script, not at scratch copies.

## Modes

- `-SelfTest` returns script/function/config metadata without side effects.
- `-Mode Startup` is safe for automatic logon. It preserves required launchers, writes a bounded log, snapshots lazily before any required repair, and enforces the explicit required-startup allowlist.
- `-Mode Audit -DryRun` performs broader non-destructive inventory and creates a restore snapshot.
- `-Mode SafeApply` is the same conservative apply path as startup, intended for manual repair runs.
- `-Mode Verify -DryRun` checks protected launchers and bounded OpenClaw readiness.
- `-Mode Restore -DryRun` locates the latest snapshot and reports what would be restored. Remove `-DryRun` only when you intentionally want to restore registry Run values, startup-folder files, and exported scheduled tasks from that snapshot.

## Protected behavior

The config file `allstart.config.psd1` marks required and protected launch points. Required automation includes:

- `Autorun_current_ahk` through `AutoHotkey64.exe "...\current.ahk"` with no duplicate Run key or Startup shortcut
- `FullScreenSnip` at `F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe`
- `OpenSpeedy_Tray` through hidden `wscript.exe ...\openspeedy-silent.vbs`
- `OpenWhisper_Tray` through hidden `wscript.exe ...\openwhisper-silent.vbs`
- Phone Link through the native `YourPhone.Start` app startup task so it stays in tray without the visible `Phone` Run-key popup
- installed Phone Link and Cross-device packages for Android clipboard/device integration
- `ClawdBotTray` through hidden `wscript.exe //B //Nologo ...\ClawdbotTray.vbs`
- OpenClaw Telegram `dmScope=per-account-channel-peer`
- four Telegram account and binding expectations when the OpenClaw config exists

The allowlist is now exact and minimal: only the required Run entries and required root logon tasks remain allowed on supported startup surfaces. Unknown registry Run entries, user/common Startup-folder files, and enabled root scheduled tasks with logon triggers are disabled or moved to quarantine after a restore snapshot is created. Microsoft task-folder entries, services, packages, application folders, and non-startup scheduled tasks are not touched.

## Safety model

The old blind allowlist cleanup was replaced with a bounded allowlist. This project does not uninstall apps, remove packages, delete application folders, disable services, disable Windows Update, or disable Defender. Startup-folder entries are moved to `quarantine\` rather than deleted; registry Run values and scheduled tasks are captured in snapshots before mutation.

All startup-surface changes are preceded by a snapshot under `snapshots\`. Healthy no-op startup runs do not snapshot, export tasks, or run broad audits. Startup-folder files are copied into the snapshot. Scheduled tasks are exported as XML where possible. Registry Run values are captured in `manifest.json`.

Logs are bounded JSONL files under `logs\`. Each mode writes to its own `allstart-<mode>-latest.jsonl`, overwriting the previous run for that mode instead of creating unbounded log files.

## Performance target

The default healthy `-Mode Startup` path is intentionally minimal: no broad scheduled-task enumeration, no unconditional snapshot, no full OpenClaw restart probe when port `18789` is already listening, and fast `schtasks.exe` checks for the two protected logon tasks. Use `-Mode Audit` or `-Mode Verify` for heavier proof.

## Manual commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1" -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1" -Mode Audit -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1" -Mode Startup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1" -Mode Verify -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Invoke-allstart.ps1" -Mode Restore -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartBootstrap\Test-allstart.ps1"
```

## Adding optimization rules

Only add exact, audited entries to `RequiredRegistryRun`, `RequiredScheduledTasks`, or `ProtectedNames`. Do not use broad fuzzy names, publisher guesses, or path prefixes. The startup policy is intentionally exact so it can enforce zero-delay required startup without breaking unrelated Windows internals.
