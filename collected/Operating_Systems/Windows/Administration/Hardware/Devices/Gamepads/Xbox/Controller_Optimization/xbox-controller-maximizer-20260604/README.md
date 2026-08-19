# xbox-controller-maximizer-20260604

A Windows PowerShell toolkit created from the Telegram controller-repair mission for an Xbox Elite Wireless Controller connected over Bluetooth.

## What this project is for

The project provides a repeatable controller health/optimization script that can be run before gaming sessions or whenever controller input feels delayed, ignored, or unreliable. It focuses on safe Windows-side fixes that do not remap buttons, uninstall drivers, reset pairing, or break other controller features.

It was built after a live mission where the controller was visible through Bluetooth/HID/XInput, KCD2 was using XInput/GameInput modules, and the Windows-side `A` button was proven through XInput while `RB` did not register during the live sample. The script maximizes the parts Windows can safely improve: services, stale Game Bar interference, high-performance power plan, controller power-saving flags, and live XInput verification.

## Important limitation

No software script can permanently repair a physically failing bumper/microswitch. If `RB` still does not register in the script's XInput probe, test by USB and update firmware in Xbox Accessories; persistent RB failure after that is likely hardware.

## Main usage

From Windows PowerShell 5+:

```powershell
& 'F:\study\Operating_Systems\Windows\Administration\Hardware\Devices\Gamepads\Xbox\Controller_Optimization\xbox-controller-maximizer-20260604\run-controller-maximizer.ps1' -Quick -NoPause
```

Probe only, without applying optimization steps:

```powershell
& 'F:\study\Operating_Systems\Windows\Administration\Hardware\Devices\Gamepads\Xbox\Controller_Optimization\xbox-controller-maximizer-20260604\run-controller-maximizer.ps1' -ProbeOnly -Quick -NoPause
```

Install/update the convenient LocalAppData copy and put the short one-liner on the clipboard:

```powershell
& 'F:\study\Operating_Systems\Windows\Administration\Hardware\Devices\Gamepads\Xbox\Controller_Optimization\xbox-controller-maximizer-20260604\install-to-localappdata.ps1'
```

## What it does

- Starts/checks `GameInputSvc`, `XboxGipSvc`, `bthserv`, and `BthAvctpSvc`.
- Closes stale `GameBar.exe` because it showed HID access errors during the mission.
- Selects the best existing high-performance/ultimate-performance power plan.
- Disables enhanced power management only for the Xbox/Bluetooth controller device path.
- Samples XInput slot 0 and reports whether the controller is reachable.
- Logs every run.

## Project files

- `run-controller-maximizer.ps1` — repo-local entry point.
- `scripts/Invoke-ControllerMaximizer.ps1` — main implementation.
- `install-to-localappdata.ps1` — refreshes the live convenience copy under `%LOCALAPPDATA%`.
- `artifacts/live-copies/AppDataLocal-HermesControllerMaximizer/` — copy of the live production script/logs; copied, not moved, to avoid breaking the existing one-liner.
- `artifacts/live-copies/KCD2-launcher/` — copy of the KCD2 launcher and backups; copied, not moved, because the real launcher must stay in the game folder.
- `artifacts/mission-temp-scripts/` — temporary probe/repair scripts used during the Telegram mission.

## Troubleshooting

- If `XINPUT slot0 NOT-DETECTED`, reconnect the controller, try USB, or re-pair Bluetooth.
- If only RB/LB is unreliable while other buttons register, update firmware in Xbox Accessories and consider hardware repair.
- If a specific game still ignores controller `A`, restart that game after running the maximizer because many games initialize controller state only at startup.
- Run PowerShell as Administrator if power-management registry edits are skipped by permission.

## Verification performed

- Main script parsed with Windows PowerShell 5 parser.
- Repo launcher parsed with Windows PowerShell 5 parser.
- Repo launcher ran successfully with `-Quick -NoPause`.
- XInput slot 0 returned OK during verification.
- Production LocalAppData script was copied-not-moved to preserve the existing working one-liner.
