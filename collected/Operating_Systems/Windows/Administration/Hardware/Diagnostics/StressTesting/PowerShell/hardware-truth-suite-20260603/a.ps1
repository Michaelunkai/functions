#requires -version 5.0
<#
Hardware Truth Suite - local Windows diagnostics + optional stress runner.
It produces current-run evidence, a human-readable fix list, and a one-liner for repeated runs.
Important limitation: software cannot directly inspect PSU internals, cable conductor quality, wall power quality, or every physical connector; it infers issues from exposed telemetry, Windows events, symptoms, and stress behavior.
#>
[CmdletBinding()]
param(
    [ValidateSet('Inventory','FullStress','SelfTest')]
    [string]$Mode = 'Inventory',
    [ValidateRange(1,240)]
    [int]$DurationMinutes = 10,
    [ValidateRange(30,7200)]
    [int]$TimeoutSeconds = 900,
    [string]$RootDir = 'C:\HWStressTest',
    [switch]$WhatIfOnly,
    [switch]$NoGui
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

function New-ResultBag {
    [ordered]@{
        schema_version = '2.0'
        started_at = (Get-Date).ToString('o')
        mode = $Mode
        duration_minutes = $DurationMinutes
        root = $RootDir
        clear_understanding = $false
        ClearUnderstanding = 'partial_until_all_current_checks_complete'
        overall = [ordered]@{ severity = 'info'; score = 100; summary = 'Scan not finished yet' }
        inventory = [ordered]@{}
        checks = @()
        stress = @()
        needs_fixing_or_improving = @()
        limitations = @(
            'Software cannot directly inspect PSU internals such as ripple, capacitor health, transient response, every rail condition, or wall outlet quality.',
            'Cable health is inferred from link speed, disconnect/errors, display/storage events, and user-observable symptoms; a physical cable tester or replacement test is definitive.',
            'Some SMART/NVMe, voltage, fan, and temperature sensors are vendor-gated and may be unavailable to Windows without HWiNFO/LibreHardwareMonitor.',
            'No script can honestly prove there is no possible hardware error left; it can only report current evidence and unknowns.'
        )
        report_paths = [ordered]@{}
        timeline = @()
        deadline_utc = $null
        OneLiner = ''
    }
}

function Write-Heartbeat {
    param([string]$Phase, [int]$Percent)
    $stamp = Get-Date -Format 'HH:mm:ss'
    Write-Host ("[{0}] {1} ({2}%)" -f $stamp, $Phase, $Percent) -ForegroundColor Cyan
    Write-Progress -Activity 'Hardware Truth Suite' -Status $Phase -PercentComplete ([Math]::Min(100,[Math]::Max(0,$Percent)))
    if ($script:HardwareTruthBag) {
        $script:HardwareTruthBag.timeline += [ordered]@{ at=(Get-Date).ToString('o'); phase=$Phase; percent=$Percent }
    }
}

function Assert-NotTimedOut {
    param([System.Collections.IDictionary]$Bag)
    if ($Bag.deadline_utc -and ((Get-Date).ToUniversalTime() -gt ([datetime]$Bag.deadline_utc))) {
        Add-Check $Bag 'runtime' 'Timeout guard tripped' 'warning' 'high' ("TimeoutSeconds=$TimeoutSeconds") 'A diagnostic phase exceeded the allowed wall-clock time' 'Rerun with a larger -TimeoutSeconds or inspect the last timeline phase for a hung provider.'
        throw "Timed out after $TimeoutSeconds seconds"
    }
}

function Add-Check {
    param([System.Collections.IDictionary]$Bag,[string]$Category,[string]$Name,[string]$Severity,[string]$Confidence,[string]$Evidence,[string]$LikelyCause,[string]$NextStep)
    $item = [ordered]@{
        category = $Category; name = $Name; severity = $Severity; confidence = $Confidence
        evidence = $Evidence; likely_cause = $LikelyCause; next_step = $NextStep
    }
    $Bag.checks += $item
    if ($Severity -in @('critical','warning')) { $Bag.needs_fixing_or_improving += $item }
}

function Invoke-Safe {
    param([scriptblock]$Script,[object]$Default = $null)
    try { & $Script } catch { $Default }
}

function Get-RecentEvents {
    param([string[]]$Providers,[int]$Max = 30)
    $all = @()
    foreach ($provider in $Providers) {
        $events = Invoke-Safe { Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=$provider; StartTime=(Get-Date).AddDays(-14)} -MaxEvents $Max | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message } @()
        $all += @($events)
    }
    $all | Select-Object -First $Max
}

function Collect-CpuMemoryGpuHealth {
    param([System.Collections.IDictionary]$Bag)
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Collecting CPU, RAM and GPU inventory/events' 10
    $Bag.inventory.computer = Invoke-Safe { Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory } @{}
    $Bag.inventory.cpu = Invoke-Safe { Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed } @()
    $Bag.inventory.memory = Invoke-Safe { Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed } @()
    $Bag.inventory.gpu = Invoke-Safe { Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM,DriverVersion,VideoModeDescription } @()
    $whea = @(Get-RecentEvents -Providers @('Microsoft-Windows-WHEA-Logger') -Max 20)
    $bugchecks = @(Get-RecentEvents -Providers @('Microsoft-Windows-WER-SystemErrorReporting','Microsoft-Windows-Kernel-Power') -Max 20)
    if ($whea.Count -gt 0) { Add-Check $Bag 'cpu_memory_gpu' 'Recent WHEA hardware errors' 'critical' 'high' ("{0} WHEA events in last 14 days" -f $whea.Count) 'CPU/RAM/PCIe/GPU instability, driver/device failure, or power delivery issue' 'Open the JSON report event list; if recurring under load, reduce overclock/EXPO, reseat RAM/GPU, update BIOS/chipset/GPU drivers, then retest.' }
    if ($bugchecks.Count -gt 0) { Add-Check $Bag 'power_reliability' 'Recent Kernel-Power/BugCheck events' 'warning' 'medium' ("{0} power/bugcheck events in last 14 days" -f $bugchecks.Count) 'Crash, unsafe shutdown, PSU/VRM transient, driver fault, or user power loss' 'Correlate timestamps with freezes/reboots; if stress reproduces, test PSU/cables and remove unstable tuning.' }
    if ($whea.Count -eq 0 -and $bugchecks.Count -eq 0) { Add-Check $Bag 'cpu_memory_gpu' 'No recent WHEA/bugcheck evidence found' 'info' 'medium' 'No matching events found in the last 14 days' 'No current Windows event evidence of CPU/RAM/GPU hardware faults' 'Still run sustained stress and MemTest86+ for higher confidence.' }
    $Bag.inventory.whea_events = $whea
    $Bag.inventory.power_events = $bugchecks
}

function Collect-StorageHealth {
    param([System.Collections.IDictionary]$Bag)
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Collecting disk, SMART/NVMe and filesystem signals' 25
    $Bag.inventory.physical_disks = Invoke-Safe { Get-PhysicalDisk | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size } @()
    $Bag.inventory.volumes = Invoke-Safe { Get-Volume | Select-Object DriveLetter,FileSystemLabel,HealthStatus,SizeRemaining,Size } @()
    $diskEvents = @(Get-RecentEvents -Providers @('Disk','Ntfs','storahci','stornvme','volmgr') -Max 40)
    foreach ($disk in @($Bag.inventory.physical_disks)) {
        if (($disk.HealthStatus -ne 'Healthy') -or ($disk.OperationalStatus -notcontains 'OK' -and [string]$disk.OperationalStatus -ne 'OK')) {
            Add-Check $Bag 'storage' ("Disk health: {0}" -f $disk.FriendlyName) 'critical' 'high' ("Health={0}; Operational={1}" -f $disk.HealthStatus,($disk.OperationalStatus -join ',')) 'Drive, controller, cable, or power issue' 'Back up immediately; check SMART with vendor tool; reseat/replace SATA/NVMe/USB cable/enclosure if applicable; retest.'
        }
    }
    foreach ($vol in @($Bag.inventory.volumes)) {
        if ($vol.Size -gt 0) {
            $freePct = [math]::Round((100.0 * $vol.SizeRemaining / $vol.Size),1)
            if ($freePct -lt 10) { Add-Check $Bag 'storage' ("Low free space {0}:" -f $vol.DriveLetter) 'warning' 'high' ("{0}% free" -f $freePct) 'Disk nearly full can cause installers, paging, and logs to fail' 'Free space or move workloads; keep at least 10-15% free on SSDs.' }
        }
    }
    if ($diskEvents.Count -gt 0) { Add-Check $Bag 'storage' 'Recent disk/filesystem/controller events' 'warning' 'medium' ("{0} Disk/Ntfs/storage events found" -f $diskEvents.Count) 'Drive media fault, loose cable, controller/driver issue, or unsafe shutdown' 'Inspect event timestamps/messages; reseat/replace cable for SATA/USB drives; update storage firmware/driver; rerun.' }
    $Bag.inventory.storage_events = $diskEvents
}

function Collect-NetworkHealth {
    param([System.Collections.IDictionary]$Bag)
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Collecting network adapter, cable/link, DNS and latency signals' 40
    $adapters = Invoke-Safe { Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress,DriverVersion } @()
    $Bag.inventory.network_adapters = $adapters
    $Bag.inventory.dns = Invoke-Safe { Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,ServerAddresses } @()
    $targets = @('1.1.1.1','8.8.8.8')
    $latency = @()
    foreach ($target in $targets) {
        Assert-NotTimedOut $Bag
        $pings = Invoke-Safe { Invoke-WithTimeoutJob -TimeoutSeconds ([Math]::Min(20,$TimeoutSeconds)) -ArgumentList @($target) -Script { param($t) Test-Connection -ComputerName $t -Count 4 -ErrorAction Stop | Select-Object Address,ResponseTime } } @()
        $latency += [ordered]@{ target=$target; replies=@($pings); count=@($pings).Count }
    }
    $Bag.inventory.network_latency = $latency
    foreach ($adapter in @($adapters)) {
        if ($adapter.Status -eq 'Up' -and ([string]$adapter.LinkSpeed -match '100 Mbps')) {
            Add-Check $Bag 'network_cables' ("Possible Ethernet cable/link downgrade: {0}" -f $adapter.Name) 'warning' 'medium' ("LinkSpeed={0}" -f $adapter.LinkSpeed) 'Bad Ethernet cable, wrong port, switch/router issue, or adapter negotiation problem' 'Try a known-good Cat5e/Cat6 cable and another router/switch port; retest link speed before changing drivers.'
        }
        if ($adapter.Status -ne 'Up') {
            Add-Check $Bag 'network' ("Adapter not up: {0}" -f $adapter.Name) 'info' 'medium' ("Status={0}" -f $adapter.Status) 'Unused/disconnected adapter or device issue' 'Ignore if unused; otherwise inspect cable/device and Device Manager.'
        }
    }
    foreach ($result in $latency) {
        if ($result.count -lt 2) { Add-Check $Bag 'network' ("Ping loss to {0}" -f $result.target) 'warning' 'medium' ("Replies={0}/4" -f $result.count) 'Network outage, DNS/gateway/ISP issue, cable/router problem, or firewall' 'Check router/switch/cable, then run again; compare with another device on same network.' }
    }
}

function Collect-PowerAndElectricitySignals {
    param([System.Collections.IDictionary]$Bag)
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Collecting power, electricity and reliability signals' 55
    $Bag.inventory.power_plan = Invoke-Safe { powercfg /GETACTIVESCHEME } ''
    $thermal = Invoke-Safe { Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | Select-Object InstanceName,CurrentTemperature } @()
    $Bag.inventory.thermal_zones = $thermal
    $powerEvents = @(Get-RecentEvents -Providers @('Microsoft-Windows-Kernel-Power','Microsoft-Windows-Power-Troubleshooter') -Max 40)
    if ($powerEvents.Count -gt 0) { Add-Check $Bag 'electricity_psu' 'Power-loss/sleep/wake evidence exists' 'warning' 'medium' ("{0} power events in last 14 days" -f $powerEvents.Count) 'Normal sleep/wake, forced shutdown, outage, PSU/VRM transient, or crash' 'Compare timestamps with real symptoms. For definitive wall/PSU validation use UPS logs, outlet tester, PSU tester, or load tester.' }
    Add-Check $Bag 'electricity_psu' 'PSU and wall power direct inspection unavailable' 'info' 'high' 'Windows has no direct PSU ripple/capacitor/wall-quality sensor' 'Not a software-readable component' 'If symptoms persist under load, test with a known-good PSU/cables/UPS or technician load tester.'
}

function Collect-CableAndConnectionSignals {
    param([System.Collections.IDictionary]$Bag)
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Collecting cable and physical connection inference signals' 65
    $usbEvents = @(Get-RecentEvents -Providers @('Microsoft-Windows-DriverFrameworks-UserMode','Microsoft-Windows-Kernel-PnP') -Max 40)
    $Bag.inventory.connection_events = $usbEvents
    if ($usbEvents.Count -gt 15) { Add-Check $Bag 'cables_connections' 'Many recent plug/device events' 'warning' 'low' ("{0} PnP/driver-framework events" -f $usbEvents.Count) 'Loose USB/display/storage cable, dock instability, or normal device churn' 'If a device disconnects, replace that cable/dock/port and retest while moving the cable gently.' }
    Add-Check $Bag 'cables_connections' 'Physical cable certainty limitation' 'info' 'high' 'No direct continuity tester is available through Windows' 'Software can only infer cable problems from link speed, disconnects and errors' 'Use a known-good replacement cable or dedicated cable tester for certainty.'
}

function Invoke-StressPhase {
    param([System.Collections.IDictionary]$Bag)
    if ($Mode -ne 'FullStress') { return }
    Assert-NotTimedOut $Bag
    Write-Heartbeat 'Preparing optional stress tools' 72
    if ($WhatIfOnly) {
        $Bag.stress += [ordered]@{ name='FullStress'; status='skipped_by_whatif'; evidence='WhatIfOnly was set' }
        return
    }
    $tools = @(
        [ordered]@{ name='Prime95'; url='https://www.mersenne.org/ftp_root/gimps/p95v3017b3.win64.zip'; note='CPU/RAM torture test' },
        [ordered]@{ name='FurMark'; url='https://geeks3d.com/dl/get/latest/furmark_win_setup.exe'; note='GPU burn test installer' },
        [ordered]@{ name='MemTest86Plus'; url='https://www.memtest86plus.org/download.htm'; note='Bootable RAM test source page' }
    )
    foreach ($tool in $tools) {
        $Bag.stress += [ordered]@{ name=$tool.name; status='manual_or_external_tool_required'; evidence=$tool.note; url=$tool.url }
    }
    Add-Check $Bag 'stress' 'FullStress is a bounded observation window unless external stress tools are started manually' 'info' 'high' ("Requested {0} minute stress window" -f $DurationMinutes) 'Stress tools can heat CPU/GPU and may expose instability' 'Watch temperatures in HWiNFO/OCCT; stop if temperatures, smell, noise, artifacts, or crashes occur.'
    $deadline = (Get-Date).AddMinutes($DurationMinutes)
    while ((Get-Date) -lt $deadline) {
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        $pct = 72 + [int](20 * (1 - ($remaining / [double]($DurationMinutes * 60))))
        Assert-NotTimedOut $Bag
        Write-Heartbeat ("FullStress/manual stress observation window; remaining {0}s" -f $remaining) $pct
        Start-Sleep -Seconds ([Math]::Min(10,[Math]::Max(1,$remaining)))
    }
}

function Complete-Report {
    param([System.Collections.IDictionary]$Bag)
    Write-Heartbeat 'Scoring and writing reports' 93
    $critical = @($Bag.needs_fixing_or_improving | Where-Object { $_.severity -eq 'critical' }).Count
    $warning = @($Bag.needs_fixing_or_improving | Where-Object { $_.severity -eq 'warning' }).Count
    $unknownPenalty = @($Bag.limitations).Count * 2
    $score = [Math]::Max(0, 100 - ($critical * 30) - ($warning * 10) - $unknownPenalty)
    $Bag.overall = [ordered]@{ severity = $(if($critical){'critical'}elseif($warning){'warning'}else{'info'}); score = $score; summary = ("{0} critical, {1} warning, {2} known limitations" -f $critical,$warning,@($Bag.limitations).Count) }
    $Bag.clear_understanding = $true
    $Bag.ClearUnderstanding = 'current_software_visible_evidence_collected_with_explicit_physical_limitations'
    $Bag.completed_at = (Get-Date).ToString('o')
    $scriptForOneLiner = if ($PSCommandPath) { $PSCommandPath } else { (Join-Path (Get-Location) 'a.ps1') }
    $one = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptForOneLiner`" -Mode FullStress -DurationMinutes $DurationMinutes -TimeoutSeconds $TimeoutSeconds -RootDir `"$RootDir`""
    if ($NoGui) { $one = $one + ' -NoGui' }
    if ($WhatIfOnly) { $one = $one + ' -WhatIfOnly' }
    $Bag.OneLiner = $one
    New-Item -ItemType Directory -Path $RootDir -Force | Out-Null
    $json = Join-Path $RootDir ('hardware_truth_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $md = [IO.Path]::ChangeExtension($json,'.md')
    $Bag.report_paths.json = $json
    $Bag.report_paths.markdown = $md
    $Bag | ConvertTo-Json -Depth 8 | Set-Content -Path $json -Encoding UTF8
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Hardware Truth Suite report')
    $lines.Add(('Generated: {0}' -f $Bag.completed_at))
    $lines.Add(('Overall: {0}; score {1}/100; {2}' -f $Bag.overall.severity,$Bag.overall.score,$Bag.overall.summary))
    $lines.Add('')
    $lines.Add('## Needs fixing or improving')
    if (@($Bag.needs_fixing_or_improving).Count -eq 0) { $lines.Add('- No critical/warning software-visible findings in this run. Review limitations below before assuming physical certainty.') }
    foreach ($f in @($Bag.needs_fixing_or_improving)) {
        $lines.Add(('- [{0}] {1} / {2}: {3}' -f $f.severity,$f.category,$f.name,$f.evidence))
        $lines.Add(('  - Why: {0}' -f $f.likely_cause))
        $lines.Add(('  - Fix: {0}' -f $f.next_step))
    }
    $lines.Add('')
    $lines.Add('## Limitations')
    foreach ($l in @($Bag.limitations)) { $lines.Add(('- {0}' -f $l)) }
    $lines.Add('')
    $lines.Add('## OneLiner')
    $lines.Add($Bag.OneLiner)
    $lines | Set-Content -Path $md -Encoding UTF8
    Write-Progress -Activity 'Hardware Truth Suite' -Completed
    Write-Host "Report JSON: $json" -ForegroundColor Green
    Write-Host "Report Markdown: $md" -ForegroundColor Green
    Write-Host 'needs_fixing_or_improving:' -ForegroundColor Yellow
    if (@($Bag.needs_fixing_or_improving).Count -eq 0) { Write-Host '- None found by current software-visible checks; physical limitations remain.' }
    foreach ($f in @($Bag.needs_fixing_or_improving)) { Write-Host ("- [{0}] {1}: {2} -> {3}" -f $f.severity,$f.name,$f.evidence,$f.next_step) }
    Write-Host "OneLiner: $($Bag.OneLiner)" -ForegroundColor Green
}

function Invoke-WithTimeoutJob {
    param([scriptblock]$Script,[int]$TimeoutSeconds,[object[]]$ArgumentList = @())
    $job = Start-Job -ScriptBlock $Script -ArgumentList $ArgumentList
    $done = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $done) {
        Stop-Job -Job $job -Force
        throw "Timed out after $TimeoutSeconds seconds"
    }
    Receive-Job -Job $job
    Remove-Job -Job $job -Force
}

function Invoke-HardwareTruthSuite {
    New-Item -ItemType Directory -Path $RootDir -Force | Out-Null
    $Bag = New-ResultBag
    $script:HardwareTruthBag = $Bag
    $Bag.deadline_utc = ((Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)).ToString('o')
    if ($Mode -eq 'SelfTest') {
        Add-Check $Bag 'selftest' 'SelfTest synthetic check' 'info' 'high' 'Script loaded, report model initialized, no stress launched' 'N/A' 'Run Inventory or FullStress for real diagnostics.'
        Complete-Report $Bag
        return $Bag
    }
    Collect-CpuMemoryGpuHealth $Bag
    Collect-StorageHealth $Bag
    Collect-NetworkHealth $Bag
    Collect-PowerAndElectricitySignals $Bag
    Collect-CableAndConnectionSignals $Bag
    Invoke-StressPhase $Bag
    Complete-Report $Bag
    if (-not $NoGui) {
        Invoke-Safe { Start-Process notepad.exe -ArgumentList $Bag.report_paths.markdown } | Out-Null
        Invoke-Safe { Start-Process explorer.exe -ArgumentList $RootDir } | Out-Null
    }
    return $Bag
}

Invoke-HardwareTruthSuite | Out-Null
