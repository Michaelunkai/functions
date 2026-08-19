# allstart2

`allstart2` is the non-agent startup profile. It enforces the same personal utility startup set as `allstart`, except it has no explicit agent startup logic.

## Required Startup

- `Autorun_current_ahk` through `AutoHotkey64.exe "...\current.ahk"` with no duplicate Run key or Startup shortcut
- `FullScreenSnip`
- `OpenSpeedy_Tray`
- `OpenWhisper_Tray`
- Phone Link through the native `YourPhone.Start` startup task so it stays in tray without the visible popup Run entry
- Phone Link and Cross-device package presence checks for Android device and clipboard integration
- no OpenClaw or ClawdBot startup task enabled

## Safety Model

- Required startup entries are created or repaired with zero-delay logon triggers.
- Unauthorized registry Run entries are removed only after a snapshot.
- Unauthorized Startup-folder files are moved to `quarantine\`, not deleted.
- Unauthorized enabled root logon scheduled tasks are disabled only after a snapshot.
- Microsoft task-folder entries, services, packages, application folders, Defender, and Windows Update are not touched.

## Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartTwoBootstrap\Invoke-allstart2.ps1" -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartTwoBootstrap\Invoke-allstart2.ps1" -Mode Startup -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartTwoBootstrap\Invoke-allstart2.ps1" -Mode Startup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\AllStartTwoBootstrap\Invoke-allstart2.ps1" -Mode Verify -DryRun
```
