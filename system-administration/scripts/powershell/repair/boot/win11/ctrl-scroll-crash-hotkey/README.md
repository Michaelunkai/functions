# Ctrl Scroll Crash Hotkey

PowerShell 5 script for enabling the Windows keyboard crash hotkey with automatic reboot.

## Usage

Run from an elevated Windows PowerShell 5 session:

```powershell
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\ctrl-scroll-crash-hotkey\Enable-CtrlScrollCrashAutoReboot.ps1
```

Safe verification:

```powershell
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\boot\win11\ctrl-scroll-crash-hotkey\Enable-CtrlScrollCrashAutoReboot.ps1 -SelfTest
```

After enabling, reboot once. Then hold right Ctrl and press Scroll Lock twice to trigger a crash and automatic reboot.

The script uses .NET registry APIs directly and does not invoke `reg.exe` or any other external executable.
