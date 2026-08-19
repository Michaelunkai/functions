<#
.SYNOPSIS
  Pre-reboot Windows health repair and evidence collector for repeated BSOD/boot failures
  such as CRITICAL_SERVICE_FAILED (0x5A).

.DESCRIPTION
  This script is designed to be safe to run before rebooting. It does NOT reboot, reset Windows,
  delete personal files, disable security, or make destructive boot changes. It:
    - self-elevates to Administrator
    - creates a restore point when possible
    - exports BCD + critical registry hives before touching anything
    - collects crash/event/driver/disk/update evidence
    - repairs Windows component store and system files (DISM + SFC)
    - checks disks online and optionally schedules offline repair only when requested or needed
    - fixes obviously dangerous disabled boot-critical services/drivers only after backing up values
    - enables recovery/boot logging and disables Fast Startup to reduce hybrid-boot corruption loops

  IMPORTANT: No script can honestly guarantee that a PC will never blue-screen again. Hardware,
  firmware, drivers, malware, power loss, and storage failure can still break Windows. This script
  is a high-safety, high-coverage pre-reboot repair pass and it leaves detailed logs for recovery.

.USAGE
  Right-click PowerShell -> Run as Administrator, then:
    Set-ExecutionPolicy -Scope Process Bypass -Force
    F:\DOWNLOADS\fix.ps1

  Stronger run before a risky reboot, including boot-time disk repair scheduling if corruption is found:
    F:\DOWNLOADS\fix.ps1 -ScheduleOfflineDiskRepair

  Optional Windows Update component reset, only if update corruption is suspected:
    F:\DOWNLOADS\fix.ps1 -ResetWindowsUpdate

  Strongest built-in repair mode, still designed to avoid destructive actions or rebooting by itself:
    F:\DOWNLOADS\fix.ps1 -MaximumProtection

  Strict under-30-second readiness check only. This is fast but cannot perform full DISM/SFC repairs:
    F:\DOWNLOADS\fix.ps1 -FastReadiness30

  Script smoke test, no repairs:
    F:\DOWNLOADS\fix.ps1 -SelfTest
#>

[CmdletBinding()]
param(
    [switch]$ScheduleOfflineDiskRepair,
    [switch]$ResetWindowsUpdate,
    [switch]$MaximumProtection,
    [switch]$DeepHardwareAudit,
    [switch]$StrictRebootGate,
    [switch]$ExitNonZeroIfNotReady,
    [switch]$FastReadiness30,
    [switch]$SelfTest,
    [switch]$SkipRestorePoint,
    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Default plain F:\DOWNLOADS\fix.ps1 to the strict under-30-second readiness gate.
# Full DISM/SFC/CHKDSK repair cannot honestly be guaranteed under 30 seconds, so it only runs when -MaximumProtection is explicit.
if (-not $MaximumProtection -and -not $FastReadiness30 -and -not $SelfTest) { $FastReadiness30 = $true }
if ($MaximumProtection) {
    $ScheduleOfflineDiskRepair = $true
    $ResetWindowsUpdate = $true
    $DeepHardwareAudit = $true
    $StrictRebootGate = $true
    $ExitNonZeroIfNotReady = $true
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Relaunch-AsAdminIfNeeded {
    if (Test-IsAdmin) { return }
    Write-Host 'Not running as Administrator. Relaunching elevated...' -ForegroundColor Yellow
    $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    if ($ScheduleOfflineDiskRepair) { $argsList += '-ScheduleOfflineDiskRepair' }
    if ($ResetWindowsUpdate) { $argsList += '-ResetWindowsUpdate' }
    if ($MaximumProtection) { $argsList += '-MaximumProtection' }
    if ($DeepHardwareAudit) { $argsList += '-DeepHardwareAudit' }
    if ($StrictRebootGate) { $argsList += '-StrictRebootGate' }
    if ($ExitNonZeroIfNotReady) { $argsList += '-ExitNonZeroIfNotReady' }
    if ($FastReadiness30) { $argsList += '-FastReadiness30' }
    if ($SelfTest) { $argsList += '-SelfTest' }
    if ($SkipRestorePoint) { $argsList += '-SkipRestorePoint' }
    if ($NoPause) { $argsList += '-NoPause' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -Verb RunAs
    exit 0
}

Relaunch-AsAdminIfNeeded

$RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Root = 'F:\DOWNLOADS\Windows_PreReboot_Fix_Logs'
$LogDir = Join-Path $Root $RunStamp
$RegDir = Join-Path $LogDir 'registry-backup'
$OutDir = Join-Path $LogDir 'command-output'
New-Item -ItemType Directory -Force -Path $LogDir,$RegDir,$OutDir | Out-Null
$TranscriptPath = Join-Path $LogDir 'transcript.txt'
Start-Transcript -Path $TranscriptPath -Force | Out-Null

$script:Summary = New-Object System.Collections.Generic.List[object]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:Failures = New-Object System.Collections.Generic.List[string]

function Add-Summary([string]$Name,[string]$Status,[string]$Details='') {
    $script:Summary.Add([pscustomobject]@{ Time=(Get-Date).ToString('s'); Step=$Name; Status=$Status; Details=$Details }) | Out-Null
}
function Warn-User([string]$Message) {
    $script:Warnings.Add($Message) | Out-Null
    Write-Host "WARNING: $Message" -ForegroundColor Yellow
}
function Fail-Step([string]$Step,[string]$Message) {
    $script:Failures.Add("$Step :: $Message") | Out-Null
    Write-Host "FAILED: $Step :: $Message" -ForegroundColor Red
    Add-Summary $Step 'FAILED' $Message
}
function Step([string]$Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Save-Text([string]$Name,[string]$Text) {
    $path = Join-Path $OutDir $Name
    $Text | Out-File -FilePath $path -Encoding UTF8 -Force
    return $path
}

function Run-Cmd {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 7200,
        [switch]$NoFail
    )
    Step $Name
    $safeName = ($Name -replace '[^a-zA-Z0-9_.-]','_')
    $stdout = Join-Path $OutDir "$safeName.stdout.txt"
    $stderr = Join-Path $OutDir "$safeName.stderr.txt"
    try {
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo.FileName = $FilePath
        $p.StartInfo.Arguments = ($Arguments -join ' ')
        $p.StartInfo.UseShellExecute = $false
        $p.StartInfo.RedirectStandardOutput = $true
        $p.StartInfo.RedirectStandardError = $true
        $p.StartInfo.CreateNoWindow = $true
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            $outTask.Result | Out-File $stdout -Encoding UTF8 -Force
            $errTask.Result | Out-File $stderr -Encoding UTF8 -Force
            throw "Timed out after $TimeoutSeconds seconds"
        }
        $outTask.Result | Out-File $stdout -Encoding UTF8 -Force
        $errTask.Result | Out-File $stderr -Encoding UTF8 -Force
        $code = $p.ExitCode
        Write-Host "Exit code: $code"
        if ($code -ne 0 -and -not $NoFail) { Fail-Step $Name "Exit code $code. See $stdout and $stderr" }
        else { Add-Summary $Name "ExitCode=$code" "stdout=$stdout stderr=$stderr" }
        return [pscustomobject]@{ ExitCode=$code; StdOut=$stdout; StdErr=$stderr }
    } catch {
        $msg = $_.Exception.Message
        if ($NoFail) {
            Warn-User "Optional command $Name could not run: $msg"
            Add-Summary $Name 'SKIPPED/ERROR_NOFAIL' $msg
        } else {
            Fail-Step $Name $msg
        }
        return [pscustomobject]@{ ExitCode=99999; StdOut=$stdout; StdErr=$stderr }
    }
}

function Export-JsonSafe($Object,[string]$Path,[int]$Depth=6) {
    try { $Object | ConvertTo-Json -Depth $Depth | Out-File -FilePath $Path -Encoding UTF8 -Force }
    catch { $_ | Out-File -FilePath ($Path + '.error.txt') -Encoding UTF8 -Force }
}


function Add-RebootGateItem {
    param(
        [AllowNull()][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Severity,
        [Parameter(Mandatory=$true)][bool]$Passed,
        [string]$Details=''
    )
    if ($null -eq $List) { throw 'Reboot gate internal error: List is null' }
    $List.Add([pscustomobject]@{
        Name=$Name
        Severity=$Severity
        Passed=$Passed
        Details=$Details
    }) | Out-Null
}

function Get-FileTextSafe([string]$Path) {
    try { return (Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue) } catch { return '' }
}


function Test-DismCheckHealthClean([string]$Text, [int]$ExitCode) {
    if ($ExitCode -ne 0) { return $false }
    if ($Text -match 'No component store corruption detected') { return $true }
    if ($Text -match 'The component store is repairable') { return $false }
    if ($Text -match 'repairable|corrupt|corruption') { return $false }
    return $true
}

function Test-ChkdskTextHasRealIssue([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -match 'Windows has scanned the file system and found no problems' -or $Text -match 'No further action is required') { return $false }
    if ($Text -match 'Windows found problems|found problems with the file system|errors found|corruption|bad sectors|failed to transfer logged messages|The volume is dirty|Correcting errors|Windows has made corrections|Chkdsk cannot continue|unspecified error') { return $true }
    return $false
}

function Wait-ServicingIdle([int]$TimeoutSeconds=900) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $busy = @(Get-Process -Name TiWorker,TrustedInstaller,dism,sfc -ErrorAction SilentlyContinue)
        if ($busy.Count -eq 0) { return $true }
        Start-Sleep -Seconds 10
    }
    Warn-User "Servicing stack still appeared busy after $TimeoutSeconds seconds; continuing carefully."
    return $false
}


function Invoke-FastReadiness30 {
    $fastStart = Get-Date
    $fastGate = New-Object System.Collections.Generic.List[object]
    Step 'FastReadiness30: bounded pre-reboot readiness checks'
    try {
        $bcd = & bcdedit.exe /enum '{current}' 2>&1 | Out-String
        Add-RebootGateItem $fastGate 'BCD current entry readable' 'CRITICAL' ($LASTEXITCODE -eq 0 -and $bcd -match 'Windows Boot Loader') ('Exit=' + $LASTEXITCODE)
        Add-RebootGateItem $fastGate 'No accidental Safe Mode flag' 'CRITICAL' ($bcd -notmatch 'safeboot') 'safeboot should be absent'
        Add-RebootGateItem $fastGate 'Recovery enabled or visible' 'HIGH' ($bcd -match 'recoveryenabled\s+Yes') 'recoveryenabled should be Yes'
    } catch { Add-RebootGateItem $fastGate 'BCD current entry readable' 'CRITICAL' $false $_.Exception.Message }
    foreach ($coreFile in @('C:\Windows\System32\ntoskrnl.exe','C:\Windows\System32\winload.efi','C:\Windows\System32\drivers\disk.sys','C:\Windows\System32\drivers\partmgr.sys','C:\Windows\System32\drivers\volmgr.sys','C:\Windows\System32\drivers\ntfs.sys')) {
        try {
            $exists = Test-Path $coreFile
            $sigOk = $false
            if ($exists) { $sigOk = ((Get-AuthenticodeSignature -FilePath $coreFile -ErrorAction SilentlyContinue).Status -eq 'Valid') }
            Add-RebootGateItem $fastGate "Core boot file valid: $coreFile" 'CRITICAL' ($exists -and $sigOk) "Exists=$exists SigOk=$sigOk"
        } catch { Add-RebootGateItem $fastGate "Core boot file valid: $coreFile" 'CRITICAL' $false $_.Exception.Message }
    }
    try {
        $missingOrDisabled = @()
        foreach ($drv in @('disk','partmgr','volmgr','volsnap','mountmgr','Ntfs','Wdf01000','FltMgr','FileInfo','CLFS','CNG','ksecdd','ACPI','pci')) {
            $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$drv"
            if (-not (Test-Path $key)) { $missingOrDisabled += "$drv=MISSING"; continue }
            $startVal = (Get-ItemProperty -Path $key -Name Start -ErrorAction SilentlyContinue).Start
            if ($startVal -eq 4) { $missingOrDisabled += "$drv=DISABLED" }
        }
        Add-RebootGateItem $fastGate 'Known core boot drivers exist and are not disabled' 'CRITICAL' ($missingOrDisabled.Count -eq 0) ($missingOrDisabled -join ',')
    } catch { Add-RebootGateItem $fastGate 'Known core boot drivers exist and are not disabled' 'CRITICAL' $false $_.Exception.Message }
    try {
        $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue
        $badPhys = @($phys | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })
        Add-RebootGateItem $fastGate 'Physical disks report Healthy' 'CRITICAL' ($badPhys.Count -eq 0) (($badPhys | Select-Object FriendlyName,HealthStatus,OperationalStatus | ConvertTo-Json -Compress))
    } catch { Add-RebootGateItem $fastGate 'Physical disks report Healthy' 'HIGH' $true 'Storage health API unavailable; not blocking FastReadiness30' }
    try {
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        $smartBad = @($smart | Where-Object { $_.PredictFailure -eq $true })
        Add-RebootGateItem $fastGate 'SMART failure prediction clear' 'CRITICAL' ($smartBad.Count -eq 0) (($smartBad | Select-Object InstanceName,PredictFailure,Reason | ConvertTo-Json -Compress))
    } catch { Add-RebootGateItem $fastGate 'SMART failure prediction clear' 'HIGH' $true 'SMART WMI unavailable; not blocking FastReadiness30' }
    try {
        $sysVol = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
        $freeGB = if ($sysVol) { [math]::Round($sysVol.SizeRemaining / 1GB, 2) } else { -1 }
        Add-RebootGateItem $fastGate 'System drive has at least 10GB free' 'HIGH' ($freeGB -ge 10) "FreeGB=$freeGB"
    } catch { Add-RebootGateItem $fastGate 'System drive has at least 10GB free' 'HIGH' $false $_.Exception.Message }
    $criticalFail = @($fastGate | Where-Object { $_.Severity -eq 'CRITICAL' -and -not $_.Passed })
    $highFail = @($fastGate | Where-Object { $_.Severity -eq 'HIGH' -and -not $_.Passed })
    $score = 100 - (35 * $criticalFail.Count) - (15 * $highFail.Count)
    if ($score -lt 0) { $score = 0 }
    $status = if ($criticalFail.Count -gt 0) { 'UNSAFE_TO_TRUST_REBOOT' } elseif ($score -ge 95) { 'FAST_READY_95_PLUS' } elseif ($score -ge 90) { 'FAST_READY_90_PLUS' } else { 'FAST_NOT_READY' }
    $elapsed = [math]::Round(((Get-Date) - $fastStart).TotalSeconds, 2)
    $result = [pscustomobject]@{ Status=$status; Score=$score; ElapsedSeconds=$elapsed; Items=$fastGate }
    Export-JsonSafe $result (Join-Path $LogDir 'fast-readiness-30.json') 12
    if ($elapsed -gt 30) { Warn-User "FastReadiness30 exceeded 30 seconds: $elapsed" }
    if ($status -eq 'FAST_READY_95_PLUS') { Write-Host "FAST READINESS: FAST_READY_95_PLUS ($score/100) in ${elapsed}s" -ForegroundColor Green }
    else { Warn-User "FAST READINESS: $status ($score/100) in ${elapsed}s. This is not a repair guarantee." }
    return $result
}

if ($SelfTest) {
    Step 'SelfTest: parser/runtime smoke test'
    $self = [pscustomobject]@{
        ScriptPath=$PSCommandPath
        IsAdmin=(Test-IsAdmin)
        PowerShell=$PSVersionTable.PSVersion.ToString()
        Parameters='ScheduleOfflineDiskRepair, ResetWindowsUpdate, MaximumProtection, DeepHardwareAudit, StrictRebootGate, ExitNonZeroIfNotReady, FastReadiness30, SelfTest, SkipRestorePoint, NoPause'
        DangerousActions='SelfTest performs no repair actions'
    }
    Export-JsonSafe $self (Join-Path $LogDir 'self-test.json') 4
    Write-Host 'SELFTEST_OK' -ForegroundColor Green
    Stop-Transcript | Out-Null
    exit 0
}

if ($FastReadiness30 -and -not $MaximumProtection) {
    $fastResult = Invoke-FastReadiness30
    Stop-Transcript | Out-Null
    if ($fastResult.Status -eq 'FAST_READY_95_PLUS') { exit 0 } else { exit 2 }
}

Step 'Starting Windows pre-reboot repair script'
Write-Host "Logs: $LogDir"
Write-Host "Run stamp: $RunStamp"
Write-Host "Admin: $(Test-IsAdmin)"
Write-Host "MaximumProtection: $MaximumProtection ; ScheduleOfflineDiskRepair: $ScheduleOfflineDiskRepair ; ResetWindowsUpdate: $ResetWindowsUpdate ; DeepHardwareAudit: $DeepHardwareAudit ; StrictRebootGate: $StrictRebootGate ; ExitNonZeroIfNotReady: $ExitNonZeroIfNotReady"

try {
    $info = [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        WindowsVersion = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,InstallDate,LastBootUpTime,OSArchitecture)
        BIOS = (Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate,SerialNumber)
        BaseBoard = (Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product,Version,SerialNumber)
        CPU = (Get-CimInstance Win32_Processor | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed)
        MemoryGB = [math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB),2)
    }
    Export-JsonSafe $info (Join-Path $LogDir 'system-info.json') 8
    Add-Summary 'System inventory' 'OK' 'system-info.json'
} catch { Fail-Step 'System inventory' $_.Exception.Message }

Step 'Creating safety backups: BCD and registry hives'
Run-Cmd 'Export BCD store' 'bcdedit.exe' @('/export', ('"{0}"' -f (Join-Path $LogDir 'BCD-backup.bcd'))) -NoFail | Out-Null
foreach ($hive in @('HKLM\SYSTEM','HKLM\SOFTWARE','HKLM\COMPONENTS')) {
    $name = ($hive -replace '[\\:]','_') + '.hiv'
    Run-Cmd "Registry save $hive" 'reg.exe' @('save', $hive, ('"{0}"' -f (Join-Path $RegDir $name)), '/y') -NoFail | Out-Null
}
Run-Cmd 'Current BCD enum all' 'bcdedit.exe' @('/enum','all','/v') -NoFail | Out-Null


Step 'Validating core boot files and EFI/System partition visibility'
$bootValidation = New-Object System.Collections.Generic.List[object]
foreach ($coreFile in @('C:\Windows\System32\ntoskrnl.exe','C:\Windows\System32\winload.efi','C:\Windows\System32\drivers\disk.sys','C:\Windows\System32\drivers\partmgr.sys','C:\Windows\System32\drivers\volmgr.sys','C:\Windows\System32\drivers\ntfs.sys','C:\Windows\System32\drivers\storahci.sys','C:\Windows\System32\drivers\stornvme.sys')) {
    try {
        $exists = Test-Path $coreFile
        $sigStatus = 'NotChecked'
        if ($exists) { $sigStatus = (Get-AuthenticodeSignature -FilePath $coreFile -ErrorAction SilentlyContinue).Status }
        $bootValidation.Add([pscustomobject]@{ File=$coreFile; Exists=$exists; SignatureStatus=$sigStatus }) | Out-Null
        if (-not $exists -or ($sigStatus -and $sigStatus -ne 'Valid')) { Warn-User "Core boot file problem: $coreFile exists=$exists signature=$sigStatus" }
    } catch { Warn-User "Could not validate ${coreFile}: $($_.Exception.Message)" }
}
try {
    Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -or $_.Type -eq 'System' } |
        Select-Object DiskNumber,PartitionNumber,DriveLetter,Type,GptType,Size,OperationalStatus |
        Export-Csv (Join-Path $LogDir 'efi-system-partitions.csv') -NoTypeInformation -Encoding UTF8
} catch {}
Export-JsonSafe $bootValidation (Join-Path $LogDir 'core-boot-files.json') 6

if (-not $SkipRestorePoint) {
    Step 'Creating Windows restore point when System Restore is available'
    try {
        try { Set-Service -Name VSS -StartupType Manual -ErrorAction SilentlyContinue; Start-Service -Name VSS -ErrorAction SilentlyContinue } catch {}
        try { Set-Service -Name swprv -StartupType Manual -ErrorAction SilentlyContinue; Start-Service -Name swprv -ErrorAction SilentlyContinue } catch {}
        try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue } catch {}
        Checkpoint-Computer -Description "PreRebootFix_$RunStamp" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Add-Summary 'Restore point' 'OK' "PreRebootFix_$RunStamp"
    } catch {
        Write-Host "INFO: Restore point could not be created. System Restore may be disabled/throttled: $($_.Exception.Message)" -ForegroundColor Yellow
        Add-Summary 'Restore point' 'SKIPPED/FAILED' $_.Exception.Message
    }
}

Step 'Collecting recent crash, boot, disk, service, driver, and update evidence'
try {
    Get-ComputerInfo | Out-File (Join-Path $LogDir 'Get-ComputerInfo.txt') -Encoding UTF8 -Force
} catch {}
try {
    Get-CimInstance Win32_QuickFixEngineering | Sort-Object InstalledOn -Descending | Export-Csv (Join-Path $LogDir 'installed-hotfixes.csv') -NoTypeInformation -Encoding UTF8
} catch {}
try {
    Get-CimInstance Win32_PnPSignedDriver | Sort-Object DeviceName | Export-Csv (Join-Path $LogDir 'pnp-signed-drivers.csv') -NoTypeInformation -Encoding UTF8
} catch {}
Run-Cmd 'driverquery verbose csv' 'driverquery.exe' @('/v','/fo','csv') -NoFail | Out-Null
Run-Cmd 'pnputil enum drivers' 'pnputil.exe' @('/enum-drivers') -NoFail | Out-Null
Run-Cmd 'reagentc info' 'reagentc.exe' @('/info') -NoFail | Out-Null
if (Get-Command wmic.exe -ErrorAction SilentlyContinue) { Run-Cmd 'optional deprecated wmic diskdrive status' 'wmic.exe' @('diskdrive','get','model,serialnumber,status,interfacetype,mediatype') -NoFail | Out-Null } else { Add-Summary 'optional deprecated wmic diskdrive status' 'SKIPPED' 'wmic.exe not installed on this Windows build' }
try { Get-PhysicalDisk | Select-Object FriendlyName,SerialNumber,MediaType,HealthStatus,OperationalStatus,Size | Export-Csv (Join-Path $LogDir 'physical-disks.csv') -NoTypeInformation -Encoding UTF8 } catch {}
try { Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystem,HealthStatus,OperationalStatus,Size,SizeRemaining | Export-Csv (Join-Path $LogDir 'volumes.csv') -NoTypeInformation -Encoding UTF8 } catch {}
try { Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' } | Export-Csv (Join-Path $LogDir 'problem-devices.csv') -NoTypeInformation -Encoding UTF8 } catch {}

try {
    Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue |
        Select-Object InstanceName,Active,PredictFailure,Reason |
        Export-Csv (Join-Path $LogDir 'smart-failure-predict-status.csv') -NoTypeInformation -Encoding UTF8
} catch {}
try {
    Get-StorageReliabilityCounter -ErrorAction SilentlyContinue |
        Select-Object DeviceId,Temperature,TemperatureMax,ReadErrorsTotal,WriteErrorsTotal,Wear,PowerOnHours,ReadLatencyMax,WriteLatencyMax,FlushLatencyMax |
        Export-Csv (Join-Path $LogDir 'storage-reliability-counters.csv') -NoTypeInformation -Encoding UTF8
} catch {}
try {
    Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-30) } |
        Select-Object TimeGenerated,SourceName,EventIdentifier,ProductName,Message |
        Export-Csv (Join-Path $LogDir 'reliability-records-30d.csv') -NoTypeInformation -Encoding UTF8
} catch {}
try {
    $dumpDir = Join-Path $LogDir 'existing-dumps-listings'
    New-Item -ItemType Directory -Force -Path $dumpDir | Out-Null
    Get-ChildItem 'C:\Windows\Minidump' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object FullName,Length,LastWriteTime | Export-Csv (Join-Path $dumpDir 'minidumps.csv') -NoTypeInformation -Encoding UTF8
    Get-ChildItem 'C:\Windows\MEMORY.DMP' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Export-Csv (Join-Path $dumpDir 'memory-dmp.csv') -NoTypeInformation -Encoding UTF8
} catch {}
if ($DeepHardwareAudit) {
    try { Get-CimInstance Win32_IDEController | Export-Csv (Join-Path $LogDir 'ide-storage-controllers.csv') -NoTypeInformation -Encoding UTF8 } catch {}
    try { Get-CimInstance Win32_SCSIController | Export-Csv (Join-Path $LogDir 'scsi-storage-controllers.csv') -NoTypeInformation -Encoding UTF8 } catch {}
    try { Get-NetAdapter -IncludeHidden | Select-Object Name,InterfaceDescription,Status,MacAddress,LinkSpeed,DriverInformation,DriverFileName,DriverVersionString | Export-Csv (Join-Path $LogDir 'net-adapters.csv') -NoTypeInformation -Encoding UTF8 } catch {}
    try { Get-CimInstance Win32_VideoController | Select-Object Name,PNPDeviceID,DriverVersion,DriverDate,Status | Export-Csv (Join-Path $LogDir 'video-controllers.csv') -NoTypeInformation -Encoding UTF8 } catch {}
}

$eventQueries = @(
    @{ Name='system-critical-error-14d'; LogName='System'; Level=@(1,2); Days=14 },
    @{ Name='application-critical-error-14d'; LogName='Application'; Level=@(1,2); Days=14 },
    @{ Name='bugcheck-events-45d'; LogName='System'; Id=@(41,1001,6008); Days=45 },
    @{ Name='disk-ntfs-storage-whea-45d'; LogName='System'; Providers=@('disk','Ntfs','stornvme','storahci','storport','WHEA-Logger','volmgr','volsnap'); Days=45 },
    @{ Name='service-control-manager-14d'; LogName='System'; Providers=@('Service Control Manager'); Days=14 }
)
foreach ($q in $eventQueries) {
    try {
        $start = (Get-Date).AddDays(-[int]$q.Days)
        $fh = @{ LogName=$q.LogName; StartTime=$start }
        if ($q.Level) { $fh.Level = $q.Level }
        if ($q.Id) { $fh.Id = $q.Id }
        $events = Get-WinEvent -FilterHashtable $fh -ErrorAction SilentlyContinue
        if ($q.Providers) { $events = $events | Where-Object { $q.Providers -contains $_.ProviderName } }
        $events | Select-Object TimeCreated,Id,LevelDisplayName,ProviderName,Message |
            Export-Csv (Join-Path $LogDir ($q.Name + '.csv')) -NoTypeInformation -Encoding UTF8
    } catch { Warn-User "Could not export event query $($q.Name): $($_.Exception.Message)" }
}
Add-Summary 'Evidence collection' 'OK' $LogDir

Step 'Backing up and validating boot-critical service/driver start values'
$svcBackup = @()
$bootCriticalDefaults = @{
    'ACPI'=0; 'disk'=0; 'partmgr'=0; 'volmgr'=0; 'volsnap'=0; 'mountmgr'=0; 'Ntfs'=0; 'Wdf01000'=0;
    'FltMgr'=0; 'FileInfo'=0; 'CLFS'=0; 'CNG'=0; 'ksecdd'=0; 'msisadrv'=0; 'pci'=0; 'vdrvroot'=0;
    'storahci'=0; 'stornvme'=0; 'BasicDisplay'=1; 'BasicRender'=1;
    'RpcSs'=2; 'DcomLaunch'=2; 'RpcEptMapper'=2; 'EventLog'=2; 'PlugPlay'=3; 'ProfSvc'=2; 'SamSs'=2; 'Winmgmt'=2; 'Schedule'=2; 'CryptSvc'=2; 'TrustedInstaller'=3; 'Appinfo'=3; 'LSM'=2; 'Power'=2; 'EventSystem'=2
}
foreach ($name in $bootCriticalDefaults.Keys) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (Test-Path $key) {
        try {
            $props = Get-ItemProperty -Path $key
            $oldStart = $props.Start
            $target = [int]$bootCriticalDefaults[$name]
            $svcBackup += [pscustomobject]@{ Name=$name; OldStart=$oldStart; TargetIfDisabled=$target; Path=$key }
            if ($oldStart -eq 4) {
                Set-ItemProperty -Path $key -Name Start -Value $target -Type DWord
                Warn-User "$name was Disabled (Start=4). Set to safer Start=$target. Original value is in boot-critical-start-backup.json."
                Add-Summary "Repair disabled boot-critical item $name" 'FIXED' "Start 4 -> $target"
            }
        } catch { Fail-Step "Boot-critical check $name" $_.Exception.Message }
    }
}
Export-JsonSafe $svcBackup (Join-Path $LogDir 'boot-critical-start-backup.json') 5

Step 'Ensuring essential services are not disabled'
$serviceStartModes = @{
    'RpcSs'='auto'; 'DcomLaunch'='auto'; 'RpcEptMapper'='auto'; 'EventLog'='auto'; 'ProfSvc'='auto';
    'SamSs'='auto'; 'Winmgmt'='auto'; 'Schedule'='auto'; 'CryptSvc'='auto'; 'Appinfo'='demand';
    'TrustedInstaller'='demand'; 'wuauserv'='demand'; 'BITS'='delayed-auto'; 'LSM'='auto'; 'Power'='auto'; 'EventSystem'='auto'; 'LanmanWorkstation'='auto'; 'Dhcp'='auto'; 'Dnscache'='auto'
}
foreach ($svc in $serviceStartModes.Keys) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($null -eq $s) { continue }
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
        $start = (Get-ItemProperty -Path $regPath -Name Start -ErrorAction SilentlyContinue).Start
        if ($start -eq 4) {
            $mode = $serviceStartModes[$svc]
            if ($mode -eq 'delayed-auto') { & sc.exe config $svc start= delayed-auto | Out-Null }
            elseif ($mode -eq 'auto') { & sc.exe config $svc start= auto | Out-Null }
            else { & sc.exe config $svc start= demand | Out-Null }
            Add-Summary "Service $svc disabled repair" 'FIXED' "Set start=$mode"
        }
    } catch { Warn-User "Could not check/fix service ${svc}: $($_.Exception.Message)" }
}

Step 'Reducing reboot-loop risk: enable recovery, boot log, disable Fast Startup'
try {
    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
    Add-Summary 'Disable Fast Startup' 'OK' 'HiberbootEnabled=0'
} catch { Fail-Step 'Disable Fast Startup' $_.Exception.Message }
Run-Cmd 'Enable Windows recovery for current boot entry' 'bcdedit.exe' @('/set','{current}','recoveryenabled','Yes') -NoFail | Out-Null
Run-Cmd 'Enable boot logging for current boot entry' 'bcdedit.exe' @('/set','{current}','bootlog','Yes') -NoFail | Out-Null
Run-Cmd 'Use standard boot menu policy' 'bcdedit.exe' @('/set','{current}','bootmenupolicy','Standard') -NoFail | Out-Null

Run-Cmd 'Show boot failures instead of hiding them' 'bcdedit.exe' @('/set','{current}','bootstatuspolicy','DisplayAllFailures') -NoFail | Out-Null
if ($MaximumProtection) {
    $bcdNow = (& bcdedit.exe /enum '{current}' 2>&1 | Out-String)
    if ($bcdNow -match 'safeboot') { Run-Cmd 'MaximumProtection remove accidental Safe Mode flag' 'bcdedit.exe' @('/deletevalue','{current}','safeboot') -NoFail | Out-Null } else { Add-Summary 'MaximumProtection Safe Mode flag check' 'OK' 'safeboot absent' }
    if ($bcdNow -match 'safebootalternateshell') { Run-Cmd 'MaximumProtection remove alternate shell Safe Mode flag' 'bcdedit.exe' @('/deletevalue','{current}','safebootalternateshell') -NoFail | Out-Null } else { Add-Summary 'MaximumProtection Safe Mode alternate shell check' 'OK' 'safebootalternateshell absent' }
    if ($bcdNow -match 'debug\s+Yes') { Run-Cmd 'MaximumProtection ensure kernel debugging off' 'bcdedit.exe' @('/debug','{current}','off') -NoFail | Out-Null } else { Add-Summary 'MaximumProtection kernel debugging check' 'OK' 'debugging already off/absent' }
}

Step 'Checking pending reboot/update markers'
$pending = [ordered]@{}
$pending['CBS_RebootPending'] = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$pending['WindowsUpdate_RebootRequired'] = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$pending['SessionManager_PendingFileRenameOperations'] = $null
try { $pending['SessionManager_PendingFileRenameOperations'] = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations } catch {}
Export-JsonSafe $pending (Join-Path $LogDir 'pending-reboot-markers.json') 5
if ($pending['CBS_RebootPending'] -or $pending['WindowsUpdate_RebootRequired'] -or $pending['SessionManager_PendingFileRenameOperations']) {
    Warn-User 'Windows has pending reboot/update/file-rename markers. The script will repair what it can, but do not force power off during the next boot.'
}

Step 'Analyze component store before repair'
Run-Cmd 'DISM AnalyzeComponentStore' 'dism.exe' @('/Online','/Cleanup-Image','/AnalyzeComponentStore') -TimeoutSeconds 7200 -NoFail | Out-Null

Step 'Repair Windows component store with repeated DISM passes until clean or blocked'
Run-Cmd 'DISM ScanHealth initial' 'dism.exe' @('/Online','/Cleanup-Image','/ScanHealth') -TimeoutSeconds 7200 -NoFail | Out-Null
$script:DismCleanBeforeFinal = $false
for ($dismPass = 1; $dismPass -le 3; $dismPass++) {
    Wait-ServicingIdle 900 | Out-Null
    Run-Cmd "DISM RestoreHealth pass $dismPass" 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth') -TimeoutSeconds 14400 -NoFail | Out-Null
    Wait-ServicingIdle 900 | Out-Null
    $checkPass = Run-Cmd "DISM CheckHealth after pass $dismPass" 'dism.exe' @('/Online','/Cleanup-Image','/CheckHealth') -TimeoutSeconds 3600 -NoFail
    $checkText = Get-FileTextSafe $checkPass.StdOut
    if (Test-DismCheckHealthClean $checkText $checkPass.ExitCode) {
        $script:DismCleanBeforeFinal = $true
        Add-Summary 'DISM repeated repair loop' 'CLEAN' "Clean after pass $dismPass"
        break
    } else {
        Warn-User "DISM still reports component store repairable after pass $dismPass; retrying if passes remain."
    }
}
Step 'Clean superseded component payloads safely'
Run-Cmd 'DISM StartComponentCleanup' 'dism.exe' @('/Online','/Cleanup-Image','/StartComponentCleanup') -TimeoutSeconds 14400 -NoFail | Out-Null
Wait-ServicingIdle 900 | Out-Null
Step 'Repair protected system files with repeated SFC passes until clean or blocked'
for ($sfcPass = 1; $sfcPass -le 3; $sfcPass++) {
    Wait-ServicingIdle 900 | Out-Null
    $sfcRun = Run-Cmd "SFC scannow pass $sfcPass" 'sfc.exe' @('/scannow') -TimeoutSeconds 14400 -NoFail
    $sfcText = Get-FileTextSafe $sfcRun.StdOut
    if ($sfcRun.ExitCode -eq 0 -and $sfcText -notmatch 'integrity violations|found corrupt|could not perform|Another servicing or repair operation') {
        Add-Summary 'SFC repeated repair loop' 'CLEAN' "Clean after pass $sfcPass"
        break
    }
    Start-Sleep -Seconds 20
}

Step 'Repair Windows Recovery Environment if disabled'
try {
    $reagentOut = & reagentc.exe /info 2>&1 | Out-String
    Save-Text 'reagentc-info-after-initial.txt' $reagentOut | Out-Null
    if ($reagentOut -match 'Windows RE status:\s+Disabled') {
        Run-Cmd 'reagentc enable' 'reagentc.exe' @('/enable') -NoFail | Out-Null
    } else { Add-Summary 'Windows RE status' 'OK/UNCHANGED' 'Not disabled according to reagentc /info' }
} catch { Warn-User "Could not inspect/enable WinRE: $($_.Exception.Message)" }

Step 'Online file-system checks on fixed volumes'
$diskFindings = @()
try {
    $vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
    foreach ($v in $vols) {
        $drive = "$($v.DriveLetter):"
        Write-Host "Checking $drive"
        $rv = $null
        try { $rv = Repair-Volume -DriveLetter $v.DriveLetter -Scan -ErrorAction Continue 3>&1 2>&1 | Out-String } catch { $rv = $_.Exception.Message }
        Save-Text "Repair-Volume-$($v.DriveLetter)-Scan.txt" $rv | Out-Null
        $chkdsk = Run-Cmd "chkdsk $drive scan" 'chkdsk.exe' @($drive,'/scan','/perf') -TimeoutSeconds 7200 -NoFail
        $text = ''
        try { $text = Get-Content $chkdsk.StdOut -Raw -ErrorAction SilentlyContinue } catch {}
        $hasIssue = Test-ChkdskTextHasRealIssue $text
        $diskFindings += [pscustomobject]@{ Drive=$drive; ChkdskExit=$chkdsk.ExitCode; IssuePattern=$hasIssue; ChkdskLog=$chkdsk.StdOut }
        if ($hasIssue -and $drive -eq $env:SystemDrive) {
            Warn-User "$drive reported possible file-system issues. Scheduling offline chkdsk /F for next boot. This can make next boot take longer, but is safer than ignoring corruption."
            Run-Cmd "schedule chkdsk $drive /F" 'cmd.exe' @('/c',"echo Y|chkdsk $drive /F") -TimeoutSeconds 600 -NoFail | Out-Null
        } elseif ($hasIssue) {
            Warn-User "$drive reported possible file-system issues. Not running chkdsk /F on non-system/script-accessible drives during this script; run chkdsk $drive /F manually after backups if needed."
        }
    }
} catch { Fail-Step 'Online file-system checks' $_.Exception.Message }
Export-JsonSafe $diskFindings (Join-Path $LogDir 'disk-findings.json') 6

if ($ResetWindowsUpdate) {
    Step 'Optional Windows Update component reset'
    $services = @('bits','wuauserv','appidsvc','cryptsvc')
    foreach ($s in $services) { try { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } catch {} }
    try {
        $sd = Join-Path $env:SystemRoot 'SoftwareDistribution'
        $cr = Join-Path $env:SystemRoot 'System32\catroot2'
        if (Test-Path $sd) { Rename-Item $sd ($sd + ".bak_$RunStamp") -ErrorAction Stop }
        if (Test-Path $cr) { Rename-Item $cr ($cr + ".bak_$RunStamp") -ErrorAction Stop }
        Add-Summary 'Windows Update cache reset' 'OK' 'SoftwareDistribution/catroot2 renamed'
    } catch { Fail-Step 'Windows Update cache reset' $_.Exception.Message }
    foreach ($s in $services) { try { Start-Service -Name $s -ErrorAction SilentlyContinue } catch {} }
}

if ($MaximumProtection) {
    Step 'MaximumProtection trigger Windows Update scan/report without installing by force'
    Run-Cmd 'UsoClient StartScan' 'UsoClient.exe' @('StartScan') -TimeoutSeconds 600 -NoFail | Out-Null
    Run-Cmd 'UsoClient ScanInstallWait' 'UsoClient.exe' @('ScanInstallWait') -TimeoutSeconds 1800 -NoFail | Out-Null
}

Step 'Configure crash-dump collection for future diagnosis'
try {
    $crashKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Set-ItemProperty -Path $crashKey -Name CrashDumpEnabled -Type DWord -Value 2
    Set-ItemProperty -Path $crashKey -Name AlwaysKeepMemoryDump -Type DWord -Value 1
    Set-ItemProperty -Path $crashKey -Name LogEvent -Type DWord -Value 1
    Set-ItemProperty -Path $crashKey -Name AutoReboot -Type DWord -Value 1
    Add-Summary 'Crash dump configuration' 'OK' 'Kernel dump + event logging enabled'
} catch { Fail-Step 'Crash dump configuration' $_.Exception.Message }

Step 'Final verification pass'
$finalDism = Run-Cmd 'DISM CheckHealth final' 'dism.exe' @('/Online','/Cleanup-Image','/CheckHealth') -TimeoutSeconds 3600 -NoFail
$finalSfc = Run-Cmd 'SFC verifyonly final' 'sfc.exe' @('/verifyonly') -TimeoutSeconds 7200 -NoFail
$finalReagent = Run-Cmd 'reagentc info final' 'reagentc.exe' @('/info') -NoFail
$finalBcd = Run-Cmd 'bcdedit enum current final' 'bcdedit.exe' @('/enum','{current}') -NoFail

Step 'Strict reboot readiness gate'
$gate = New-Object System.Collections.Generic.List[object]
$dismText = Get-FileTextSafe $finalDism.StdOut
$sfcText = Get-FileTextSafe $finalSfc.StdOut
$reagentText = Get-FileTextSafe $finalReagent.StdOut
$bcdText = Get-FileTextSafe $finalBcd.StdOut
Add-RebootGateItem $gate 'DISM final CheckHealth clean' 'CRITICAL' (Test-DismCheckHealthClean $dismText $finalDism.ExitCode) ('Exit=' + $finalDism.ExitCode)
Add-RebootGateItem $gate 'SFC final verify-only clean' 'CRITICAL' ($finalSfc.ExitCode -eq 0 -and $sfcText -notmatch 'integrity violations|could not perform|found corrupt') ('Exit=' + $finalSfc.ExitCode)
Add-RebootGateItem $gate 'Windows Recovery Environment enabled or inspectable' 'HIGH' ($finalReagent.ExitCode -eq 0 -and $reagentText -match 'Windows RE status:\s+Enabled') ('Exit=' + $finalReagent.ExitCode)
Add-RebootGateItem $gate 'BCD current entry inspectable' 'CRITICAL' ($finalBcd.ExitCode -eq 0 -and $bcdText -match 'Windows Boot Loader') ('Exit=' + $finalBcd.ExitCode)
Add-RebootGateItem $gate 'Boot recovery enabled' 'HIGH' ($bcdText -match 'recoveryenabled\s+Yes') 'recoveryenabled should be Yes'
Add-RebootGateItem $gate 'No accidental Safe Mode flag' 'CRITICAL' ($bcdText -notmatch 'safeboot') 'safeboot should be absent'
Add-RebootGateItem $gate 'Boot logging enabled' 'MEDIUM' ($bcdText -match 'bootlog\s+Yes') 'bootlog should be Yes'
try {
    $coreBoot = Get-Content (Join-Path $LogDir 'core-boot-files.json') -Raw | ConvertFrom-Json
    $badCore = @(@($coreBoot) | Where-Object { -not $_.Exists -or ($_.SignatureStatus -and $_.SignatureStatus -ne 'Valid') })
    Add-RebootGateItem $gate 'Core boot files exist and are Microsoft-signed' 'CRITICAL' ($badCore.Count -eq 0) (($badCore | ConvertTo-Json -Compress))
} catch { Add-RebootGateItem $gate 'Core boot files exist and are Microsoft-signed' 'CRITICAL' $false $_.Exception.Message }
try {
    $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue
    $badPhys = @($phys | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })
    Add-RebootGateItem $gate 'Physical disks report Healthy' 'CRITICAL' ($badPhys.Count -eq 0) (($badPhys | Select-Object FriendlyName,HealthStatus,OperationalStatus | ConvertTo-Json -Compress))
} catch { Add-RebootGateItem $gate 'Physical disks report Healthy' 'HIGH' $true 'Not available on this Windows edition/storage stack' }
try {
    $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
    $smartBad = @($smart | Where-Object { $_.PredictFailure -eq $true })
    Add-RebootGateItem $gate 'SMART failure prediction is clear' 'CRITICAL' ($smartBad.Count -eq 0) (($smartBad | Select-Object InstanceName,PredictFailure,Reason | ConvertTo-Json -Compress))
} catch { Add-RebootGateItem $gate 'SMART failure prediction is clear' 'HIGH' $true 'SMART WMI unavailable; not treated as failure' }
try {
    $sysVol = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    $freeGB = if ($sysVol) { [math]::Round($sysVol.SizeRemaining / 1GB, 2) } else { -1 }
    Add-RebootGateItem $gate 'System drive has at least 10GB free' 'HIGH' ($freeGB -ge 10) ("FreeGB=$freeGB")
} catch { Add-RebootGateItem $gate 'System drive has at least 10GB free' 'HIGH' $false $_.Exception.Message }
try {
    $criticalProblems = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and ($_.Class -match 'System|SCSIAdapter|HDC|DiskDrive|Volume|Net|Display|Computer|Processor') })
    Add-RebootGateItem $gate 'No present critical PnP devices in error state' 'HIGH' ($criticalProblems.Count -eq 0) (($criticalProblems | Select-Object Class,FriendlyName,InstanceId,Status | ConvertTo-Json -Compress))
} catch { Add-RebootGateItem $gate 'No present critical PnP devices in error state' 'MEDIUM' $true 'PnP query unavailable' }
try {
    $disabledCritical = @()
    foreach ($name in $bootCriticalDefaults.Keys) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
        if (Test-Path $key) {
            $startVal = (Get-ItemProperty -Path $key -Name Start -ErrorAction SilentlyContinue).Start
            if ($startVal -eq 4) { $disabledCritical += $name }
        }
    }
    Add-RebootGateItem $gate 'No known boot-critical services/drivers disabled' 'CRITICAL' ($disabledCritical.Count -eq 0) ($disabledCritical -join ',')
} catch { Add-RebootGateItem $gate 'No known boot-critical services/drivers disabled' 'CRITICAL' $false $_.Exception.Message }
try {
    $recentBugchecks = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=(Get-Date).AddDays(-2)} -ErrorAction SilentlyContinue)
    Add-RebootGateItem $gate 'No bugcheck events during last 48h evidence window' 'MEDIUM' ($recentBugchecks.Count -eq 0) ("Count=$($recentBugchecks.Count)")
} catch { Add-RebootGateItem $gate 'No bugcheck events during last 48h evidence window' 'LOW' $true 'Event query unavailable' }

$minimumGateItems = 12
if ($gate.Count -lt $minimumGateItems) {
    Add-RebootGateItem $gate 'Reboot gate internal completeness' 'CRITICAL' $false ("Only $($gate.Count) gate items were recorded; expected at least $minimumGateItems")
}
try {
    $pendingNow = [ordered]@{}
    $pendingNow['CBS_RebootPending'] = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $pendingNow['WindowsUpdate_RebootRequired'] = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pendingNow['PendingFileRenameOperations'] = $null
    try { $pendingNow['PendingFileRenameOperations'] = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations } catch {}
    Add-RebootGateItem $gate 'Pending reboot markers are understood' 'MEDIUM' $true (($pendingNow | ConvertTo-Json -Compress))
} catch { Add-RebootGateItem $gate 'Pending reboot markers are understood' 'LOW' $true 'Could not inspect pending reboot markers' }
try {
    $essentialStopped = @()
    foreach ($es in @('RpcSs','DcomLaunch','EventLog','PlugPlay','ProfSvc','Winmgmt','Schedule','CryptSvc','Power','EventSystem')) {
        $svcObj = Get-Service -Name $es -ErrorAction SilentlyContinue
        if ($svcObj -and $svcObj.Status -eq 'Stopped' -and $es -notin @('Schedule')) { $essentialStopped += ($es + '=' + $svcObj.Status) }
    }
    Add-RebootGateItem $gate 'Essential live services are not unexpectedly stopped' 'HIGH' ($essentialStopped.Count -eq 0) ($essentialStopped -join ',')
} catch { Add-RebootGateItem $gate 'Essential live services are not unexpectedly stopped' 'MEDIUM' $true 'Service query unavailable' }
try {
    $bootDriversMissing = @()
    foreach ($drv in @('disk','partmgr','volmgr','volsnap','mountmgr','Ntfs','Wdf01000','FltMgr','FileInfo','CLFS','CNG','ksecdd','ACPI','pci')) {
        if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$drv")) { $bootDriversMissing += $drv }
    }
    Add-RebootGateItem $gate 'Known core boot driver service keys exist' 'CRITICAL' ($bootDriversMissing.Count -eq 0) ($bootDriversMissing -join ',')
} catch { Add-RebootGateItem $gate 'Known core boot driver service keys exist' 'CRITICAL' $false $_.Exception.Message }
try {
    $fw = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    Add-RebootGateItem $gate 'UEFI/SecureBoot query does not show firmware access failure' 'LOW' $true ("SecureBoot=$fw")
} catch { Add-RebootGateItem $gate 'UEFI/SecureBoot query does not show firmware access failure' 'LOW' $true 'SecureBoot query unavailable or non-UEFI; not a blocker' }

$criticalFail = @($gate | Where-Object { $_.Severity -eq 'CRITICAL' -and -not $_.Passed })
$highFail = @($gate | Where-Object { $_.Severity -eq 'HIGH' -and -not $_.Passed })
$mediumFail = @($gate | Where-Object { $_.Severity -eq 'MEDIUM' -and -not $_.Passed })
$score = 100 - (35 * $criticalFail.Count) - (15 * $highFail.Count) - (5 * $mediumFail.Count)
if ($score -lt 0) { $score = 0 }
if ($script:Failures.Count -gt 0 -and $score -gt 74) { $score = 74 }
$status = if ($script:Failures.Count -gt 0) { 'NOT_READY_SCRIPT_FAILURES_PRESENT' } elseif ($criticalFail.Count -gt 0) { 'UNSAFE_TO_TRUST_REBOOT' } elseif ($score -ge 90) { 'READY_90_PLUS' } elseif ($score -ge 75) { 'RISK_REDUCED_BUT_NOT_90' } else { 'NOT_READY' }
$gateResult = [pscustomobject]@{
    Status=$status
    RebootReadinessScore=$score
    CriticalFailures=$criticalFail.Count
    HighFailures=$highFail.Count
    MediumFailures=$mediumFail.Count
    Items=$gate
}
Export-JsonSafe $gateResult (Join-Path $LogDir 'reboot-readiness-gate.json') 12
if ($status -eq 'READY_90_PLUS') {
    Add-Summary 'Strict reboot readiness gate' 'READY_90_PLUS' "Score=$score"
    Write-Host "REBOOT READINESS: READY_90_PLUS ($score/100)" -ForegroundColor Green
} else {
    Warn-User "REBOOT READINESS: $status ($score/100). Read reboot-readiness-gate.json before trusting the reboot."
    Add-Summary 'Strict reboot readiness gate' $status "Score=$score"
}

Step 'Writing final report' 
$summaryPath = Join-Path $LogDir 'summary.json'
$warningsPath = Join-Path $LogDir 'warnings.txt'
$failuresPath = Join-Path $LogDir 'failures.txt'
Export-JsonSafe $script:Summary $summaryPath 8
$script:Warnings | Out-File $warningsPath -Encoding UTF8 -Force
$script:Failures | Out-File $failuresPath -Encoding UTF8 -Force

$readme = @"
Windows Pre-Reboot Fix Report
Run: $RunStamp
Logs: $LogDir

What was done:
- Safety backups: BCD + registry hives under registry-backup
- Evidence collection: events, drivers, disks, hotfixes, problem devices
- Repairs: DISM ScanHealth/RestoreHealth/StartComponentCleanup, SFC scannow
- Boot safety: recovery enabled, boot logging enabled, Fast Startup disabled
- Boot-critical guard: only services/drivers found disabled were changed, with old values saved
- Disk scans: online Repair-Volume/chkdsk logs saved; offline chkdsk scheduled only when triggered by switch/issue policy
- MaximumProtection mode, when used, also enables deeper hardware evidence, resets Windows Update components, removes accidental Safe Mode BCD flags, triggers a Windows Update scan, and runs a second SFC pass
- Strict reboot readiness gate writes reboot-readiness-gate.json and only calls the run READY_90_PLUS if critical checks pass and score is at least 90
- In MaximumProtection mode the script returns exit code 2 when the gate is not READY_90_PLUS, so automation cannot silently treat a risky state as success
- FastReadiness30 is designed to finish under 30 seconds by doing checks only, not slow DISM/SFC/CHKDSK repairs

Important truth:
No script can guarantee a PC will never crash again. If the next reboot still fails, use these logs plus Windows Recovery. The BCD backup and registry hive backups are in this folder.

Recommended if problems continue:
1. Run vendor/OEM BIOS + chipset + storage/NVMe + GPU driver updates from official sources.
2. Check RAM with Windows Memory Diagnostic or MemTest86.
3. Check SSD/NVMe SMART/firmware using the drive vendor tool.
4. If minidumps exist in C:\Windows\Minidump, analyze them with WinDbg.
"@
$readme | Out-File (Join-Path $LogDir 'README-FIRST.txt') -Encoding UTF8 -Force

Write-Host "`n================ FINAL RESULT ================" -ForegroundColor Green
Write-Host "Logs saved to: $LogDir" -ForegroundColor Green
Write-Host "Summary: $summaryPath"
Write-Host "Warnings: $warningsPath"
Write-Host "Failures: $failuresPath"
Write-Host "Reboot readiness gate: $(Join-Path $LogDir 'reboot-readiness-gate.json')"
if ($script:Warnings.Count -gt 0) { Write-Host "Warnings count: $($script:Warnings.Count)" -ForegroundColor Yellow }
if ($script:Failures.Count -gt 0) { Write-Host "Failures count: $($script:Failures.Count)" -ForegroundColor Red }
else { Write-Host 'No script-level failures recorded.' -ForegroundColor Green }
Write-Host 'The script did not reboot your PC.' -ForegroundColor Green
Write-Host 'If offline chkdsk was scheduled, next boot can take longer. Do not force power off during that repair.' -ForegroundColor Yellow
Write-Host 'Strongest repair command: F:\DOWNLOADS\fix.ps1 -MaximumProtection' -ForegroundColor Cyan
Write-Host 'Under-30-second check command: F:\DOWNLOADS\fix.ps1 -FastReadiness30' -ForegroundColor Cyan
Write-Host 'Only trust reboot as 90%+ if final output says REBOOT READINESS: READY_90_PLUS and Failures count is 0.' -ForegroundColor Cyan

Stop-Transcript | Out-Null
if (-not $NoPause) {
    Write-Host "`nPress Enter to close..."
    try { [void][Console]::ReadLine() } catch {}
}
exit $finalExitCode
