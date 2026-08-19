# Hardware Truth Suite

GitHub: https://github.com/Michaelunkai/hardware-truth-suite-20260603

Hardware Truth Suite is a local Windows PowerShell diagnostic project that packages the completed Telegram mission into a reusable `F:\study` repository. It collects software-visible evidence about PC hardware health, shows live progress while it runs, and writes a human-readable list of anything that needs fixing or improving.

## What it does

- Runs from Windows PowerShell 5.1 with no cloud service required.
- Collects CPU, RAM, GPU, storage, network, cable/link inference, power/electricity inference, thermal zones, WHEA, Kernel-Power, BugCheck, Disk/Ntfs/storage, PnP and reliability signals.
- Shows real-time heartbeat/progress so the run does not look frozen.
- Writes JSON and Markdown reports.
- Produces a `needs_fixing_or_improving` list with severity, confidence, evidence, likely cause and exact next step.
- Includes a root one-click launcher: `run-hardware-truth-suite.ps1`.

## Important honesty limit

No software-only project can prove that every possible hardware fault is absent. PSU internals, wall power quality, cable continuity, connector wear and intermittent physical faults require external testers, known-good replacement parts, UPS/outlet logs or a qualified technician/load tester. This tool reports current software-visible evidence and explicitly lists what remains unknown.

## Prerequisites

- Windows 10/11.
- Windows PowerShell 5.1.
- Administrator is recommended for the fullest event/device visibility, but the inventory mode can still run with partial evidence.
- Internet is not required for the built-in inventory scan. Optional stress tools may require manual download/use.

## Exact usage

### Full reusable runner

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\run-hardware-truth-suite.ps1"
```

### Safer quick inventory only

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\a.ps1" -Mode Inventory -RootDir "F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\reports" -NoGui
```

### Short smoke test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\run-hardware-truth-suite.ps1" -DurationMinutes 1 -TimeoutSeconds 180 -NoGui
```

## Outputs

Reports are written under:

```text
F:\study\Operating_Systems\Windows\Administration\Hardware\Diagnostics\StressTesting\PowerShell\hardware-truth-suite-20260603\reports
```

Each run creates:

- `hardware_truth_YYYYMMDD_HHMMSS.json` — complete machine-readable report.
- `hardware_truth_YYYYMMDD_HHMMSS.md` — human-readable report and fix list.

## Important files

- `run-hardware-truth-suite.ps1` — easiest local entry point.
- `a.ps1` — main diagnostic engine.
- `tests/test_hardware_truth_suite.py` — acceptance checks for required script features.
- `artifacts/` — reports and verification artifacts collected from the completed mission.
- `ARTIFACTS_MANIFEST.txt` — what was moved/copied into this repository.

## Troubleshooting

- If PowerShell blocks execution, keep `-ExecutionPolicy Bypass` in the one-liner.
- If the run times out, increase `-TimeoutSeconds` or inspect the last `timeline` phase in the JSON report.
- If network ping checks warn, compare with another device and try a known-good Ethernet cable/router port before driver changes.
- If storage warnings appear, back up first, inspect the event message, then reseat/replace the relevant cable/enclosure or update storage firmware/driver.
- If power warnings appear, correlate event timestamps with symptoms; definitive PSU/wall validation needs UPS logs, outlet tester, PSU tester or load tester.

## Verification performed

- Acceptance tests passed: `5 tests passed`.
- Windows PowerShell 5.1 parser check passed: `PARSE_OK`.
- SelfTest passed.
- Inventory run passed and produced reports.
- Final one-liner smoke test was run with `DurationMinutes 1` and produced reports under this repository.
