[CmdletBinding()]
param(
    [int[]]$Ports = @(8080),
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyParentRoot = Split-Path -Parent $root
$rulePrefix = 'LocalAI AutoDeployer TCP'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-GuidFromText {
    param([string]$Text)
    if ($Text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return $Matches[1]
    }
    return $null
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "[cleanup] $Name"
    if ($WhatIf) { return }
    & $Action
}

if (-not (Test-IsAdmin)) {
    throw 'Run this cleanup script from an elevated Windows PowerShell session so firewall and power-plan changes can be reversed without prompts.'
}

$stateDir = Join-Path $root 'state'
$bestConfig = Read-JsonFile -Path (Join-Path $stateDir 'best-runtime-config.json')
$hardwareProfile = Read-JsonFile -Path (Join-Path $stateDir 'hardware-profile.json')
$powerRollback = Read-JsonFile -Path (Join-Path $stateDir 'power-rollback.json')
if ($bestConfig -and $bestConfig.Port) {
    $Ports = @($Ports + [int]$bestConfig.Port | Sort-Object -Unique)
}

Invoke-Step -Name 'Stop project-owned local AI server processes' -Action {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $path = [string]$_.ExecutablePath
        $cmd = [string]$_.CommandLine
        (($path -and $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) -or
         ($cmd -and $cmd.IndexOf($root, [StringComparison]::OrdinalIgnoreCase) -ge 0)) -and
        ($_.Name -match 'llama|server|main|local-ai')
    })
    foreach ($proc in $processes) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Step -Name 'Remove LocalAI AutoDeployer firewall rules' -Action {
    foreach ($port in $Ports) {
        $name = "$rulePrefix $port"
        try {
            $rules = @(Get-NetFirewallRule -DisplayName $name -ErrorAction Stop)
            foreach ($rule in $rules) {
                Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
            }
        } catch {
            & netsh advfirewall firewall delete rule name="$name" protocol=TCP localport=$port | Out-Null
        }
        & netsh advfirewall firewall delete rule name="$name" | Out-Null
    }
    & netsh advfirewall firewall delete rule name="LocalAI AutoDeployer TCP 8080" | Out-Null
}

Invoke-Step -Name 'Restore pre-install active power scheme when rollback evidence exists' -Action {
    $guid = $null
    if ($powerRollback -and $powerRollback.ActiveSchemeBefore) {
        $guid = Get-GuidFromText -Text ([string]$powerRollback.ActiveSchemeBefore)
    }
    if (-not $guid -and $hardwareProfile -and $hardwareProfile.PowerPlanBefore) {
        $guid = Get-GuidFromText -Text ([string]$hardwareProfile.PowerPlanBefore)
    }
    if ($guid) {
        & powercfg /setactive $guid | Out-Null
    }
}

Invoke-Step -Name 'Delete all generated project state, downloads, runtime, models, logs, and reports' -Action {
    $generatedNames = @('state','runtime','models','downloads','reports','logs')
    $targets = @()
    $targets += $generatedNames | ForEach-Object { Join-Path $root $_ }
    $targets += $generatedNames | ForEach-Object { Join-Path $legacyParentRoot $_ }
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        }
    }
    Get-ChildItem -LiteralPath $root,$legacyParentRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.partial' -or $_.Name -like '*.tmp' -or $_.Name -like '*.download' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

Invoke-Step -Name 'Verify cleanup left no generated payload folders' -Action {
    $generatedNames = @('state','runtime','models','downloads','reports','logs')
    $leftovers = @()
    $leftovers += $generatedNames | ForEach-Object { Join-Path $root $_ }
    $leftovers += $generatedNames | ForEach-Object { Join-Path $legacyParentRoot $_ }
    $leftovers = $leftovers |
        Where-Object { Test-Path -LiteralPath $_ }
    if ($leftovers) {
        throw ("Cleanup leftovers remain: {0}" -f ($leftovers -join ', '))
    }
}

Write-Host 'LocalAI AutoDeployer cleanup script completed.'
