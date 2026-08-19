# Driver Mega Updater

`Driver Mega Updater` is a Windows-first PowerShell 5 orchestrator for driver and firmware maintenance on mixed-vendor machines. It is designed to be ambitious about discovery, conservative about risk, and honest about the places where full automation would be irresponsible.

It was built around a system with:

- `Gigabyte X870E AORUS PRO`
- `AMD Ryzen 7 9800X3D`
- `AMD Radeon(TM) Graphics`
- `NVIDIA GeForce RTX 5080`
- `Qualcomm FastConnect 7800`
- `Realtek LAN / audio`
- common Bluetooth and USB peripherals such as Logitech and Xbox devices

The goal is not reckless "update everything blindly" automation. The goal is truthful automation:

- automatically detect ordinary driver updates where the source is verifiable
- refuse obvious downgrades
- stage BIOS and peripheral firmware behind manual approval
- keep machine-readable audit state and resumable runs
- make it obvious what was updated, what was deferred, and why

## At A Glance

| Area | Behavior |
| --- | --- |
| Ordinary device drivers | Audit automatically and install conservatively in `Apply` mode |
| BIOS and firmware | Detect and stage behind explicit approval |
| Downgrade protection | Refuses older cached vendor packages |
| Reboot behavior | Never forces a reboot unless explicitly allowed |
| Reporting | Writes JSON reports and resume state |
| Philosophy | Prefer a truthful defer over a fake "success" |

## Why This Exists

Windows driver upkeep is fragmented across several channels:

- Windows Update
- motherboard vendor bundles
- GPU vendor installers
- chipset packages
- peripheral vendor apps

Those channels do not always agree, and local vendor caches can be stale or even older than what is already installed. This project exists to reduce that chaos while staying conservative where the risk is real.

## What It Does

The main script:

- inventories hardware through CIM, PnP, and installed-package metadata
- checks Windows Update driver applicability via the Windows Update Agent COM API
- inspects Gigabyte local GCC download cache and blocks downgrade paths
- inspects AMD’s local install-manager path for supported AMD-owned updates
- inspects NVIDIA App update metadata/cache when available
- stages peripheral firmware paths instead of forcing unsafe headless flashes
- writes JSON reports and JSON resume state

## Quick Start

Run all commands from the repository root in an elevated PowerShell 5 window.

### 1. Audit the machine

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DriverMega.ps1 -Mode Audit -IncludePeripheralVendors
```

This performs discovery only. It inventories hardware, checks supported update channels, and writes a JSON report describing what is current, what is actionable, and what was deferred for safety.

### 2. Apply conservative updates

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DriverMega.ps1 -Mode Apply
```

This applies the safe, supported update paths the script can validate without crossing into high-risk firmware behavior.

### 3. Enable vendor auto-install paths when desired

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DriverMega.ps1 -Mode Apply -AutoInstallVendorDrivers
```

Use this when you want the script to act on vendor-managed driver channels that are appropriate for the detected hardware.

### 4. Resume after interruption or reboot

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DriverMega.ps1 -Mode Apply -Resume
```

If a run is interrupted or a reboot splits the workflow, the script resumes from persisted state instead of starting blindly from scratch.

## Safety Model

This project intentionally does **not** promise “zero risk”.

It follows these rules instead:

- no blind BIOS flashing
- no blind Bluetooth peripheral firmware flashing
- no downgrades
- no forced reboot unless explicitly allowed
- no pretending that a cached vendor bundle is newer just because it exists

If the script cannot prove that an action is safe and appropriate, it reports and defers it.

## Repository Layout

```text
driver-mega-updater/
├── Invoke-DriverMega.ps1
├── Invoke-DriverMega.Tests.ps1
├── README.md
├── .gitignore
├── downloads/   # generated at runtime
├── reports/     # generated at runtime
├── scratch/     # generated at runtime
└── state/       # generated at runtime
```

Only the source files belong in version control. Runtime artifacts are ignored.

## Requirements

- Windows
- PowerShell 5 compatible execution target
- Administrator shell for real audit/apply work
- `Pester` available for tests
- internet access for live vendor/update checks

Optional but useful:

- `gh` CLI for repository operations
- `7z` for some vendor package extraction flows

## Important Parameters

- `-Mode Audit|Apply`
- `-IncludeFirmware`
- `-IncludePeripheralVendors`
- `-AutoInstallVendorDrivers`
- `-AutoReboot`
- `-ReportPath <path>`
- `-Resume`

## Example Output Behavior

The script prints sections like:

- `Inventory`
- `Updates Found`
- `Installed`
- `Deferred`
- `Needs Reboot`
- `Needs Manual Approval`

It also writes:

- a JSON report
- a JSON state file for resume flow

## Typical Workflow

1. Run `Audit` first and read the report.
2. Review anything marked `blocked_downgrade`, `manual_review`, or firmware-related.
3. Run `Apply` for the safe installable set.
4. Rerun `Audit` to confirm the remaining items are either resolved or intentionally deferred.

## Validation Approach

This project was validated with:

- PowerShell 5 parsing
- Pester tests for version/downgrade logic
- live audit runs after relocation
- safe apply runs without forcing risky vendor actions
- resume-path verification

## Known Boundaries

- BIOS updates remain manually gated by design
- peripheral firmware remains manually gated by design
- some vendor channels are detectable locally but not safely auto-invokable in every environment
- the updater is conservative on purpose; “deferred” can be the correct result

## If You Want To Extend It

Good next improvements:

- richer live Gigabyte support-page parsing
- explicit NVIDIA App utility auto-update path
- more vendor-specific peripheral support
- better packaging and command wrapper integration
- CI lint/test checks for PowerShell

## Philosophy

This project prefers an honest "not safe enough to automate" over a fake success message.
