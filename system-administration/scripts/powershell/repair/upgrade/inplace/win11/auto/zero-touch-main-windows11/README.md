# zero-touch-main-windows11

Zero-touch Windows 11 repair/main-install launcher for this machine.

The real launcher is:

```text
F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\zero-touch-main-windows11\executables\ZeroTouch-Reboot-Into-Main-Windows11.exe
```

It is designed to run Windows Setup automatically with the supported keep path:

```text
setup.exe /auto upgrade /quiet /eula accept /dynamicupdate enable
```

That is the Windows Setup mode that keeps files, apps, and settings when the current install, edition, language, architecture, and installer source allow it. If Windows Setup itself decides keeping apps/settings is not possible, this project fails closed instead of silently wiping data.

## What Real Mode Does

1. Elevates itself if needed.
2. Finds a Windows 11 installer automatically from mounted ISO/DVD/USB paths and common local locations.
3. Registers a post-boot SYSTEM cleanup task before setup starts.
4. Runs Windows Setup in quiet upgrade mode.
5. Lets Windows Setup reboot into the repaired/main Windows installation.
6. After the new Windows boots, the post-boot worker removes `C:\Windows.old` as fast as safely possible and removes its one-shot triggers.

## Safety Defaults

- No prompts or `Read-Host`.
- No requested details from the user.
- No fallback to clean wipe.
- Dry-run and self-test modes never run setup, reboot, write BCD, or delete `Windows.old`.
- `C:\Windows.old` cleanup is scoped to that path only.

## Commands

Dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-ZeroTouchMainWindows11.ps1 -DryRun -AutoReboot
```

Self-test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ZeroTouchMainWindows11.ps1
```

Real run:

```text
RUN-ZERO-TOUCH-MAIN-WINDOWS11.cmd
```

or run the executable:

```text
executables\ZeroTouch-Reboot-Into-Main-Windows11.exe
```
