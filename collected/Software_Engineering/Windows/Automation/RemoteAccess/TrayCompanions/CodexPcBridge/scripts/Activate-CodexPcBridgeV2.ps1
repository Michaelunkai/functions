param(
    [int]$ShadowPort = 18776,
    [int]$LivePort = 18767,
    [string]$ServiceName = "CodexPcBridgeV2",
    [string]$StateRoot = "$env:ProgramData\CodexPcBridge",
    [string]$ExpectedLegacyExecutablePath,
    [string]$AndroidHealthCommand,
    [switch]$SkipAndroidHealth,
    [switch]$SkipRelayRequirement
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this activation tool from an elevated PowerShell 5.1 session."
    }
}

function Get-BridgeHealth {
    param([int]$Port)

    return Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/v2/health" `
        -Method Get `
        -TimeoutSec 3
}

function Wait-BridgeHealth {
    param(
        [int]$Port,
        [bool]$ExpectedShadow,
        [int]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $health = Get-BridgeHealth -Port $Port
            $relayReady = $SkipRelayRequirement -or (
                $health.relayConfigured -and $health.relayReady)
            if ($health.ok -and
                $health.gatewayReady -and
                $health.agentConnected -and
                $health.shadowMode -eq $ExpectedShadow -and
                $relayReady) {
                return $health
            }
        } catch {
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Bridge health did not reach the required state on port $Port."
}

function Write-ServiceSettings {
    param(
        [string]$Path,
        [int]$Port,
        [bool]$ShadowMode,
        [object]$Previous
    )

    $settings = [ordered]@{
        Version = 2
        Port = $Port
        TailscaleEnabled = [bool]$Previous.TailscaleEnabled
        RelayEnabled = [bool]$Previous.RelayEnabled
        RelayUrl = $Previous.RelayUrl
        ShadowMode = $ShadowMode
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $settings | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Resolve-LegacyListener {
    $listener = Get-NetTCPConnection `
        -LocalPort $LivePort `
        -State Listen `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $listener) {
        return $null
    }
    if ($listener.OwningProcess -eq 4) {
        if (-not $ExpectedLegacyExecutablePath) {
            throw (
                "Port $LivePort is registered through HTTP.sys. Pass " +
                "-ExpectedLegacyExecutablePath so the retained bridge can be " +
                "identified without ever targeting PID 4.")
        }
        $expected = [IO.Path]::GetFullPath($ExpectedLegacyExecutablePath)
        $matches = @(Get-CimInstance Win32_Process |
            Where-Object {
                $_.ExecutablePath -and
                [IO.Path]::GetFullPath($_.ExecutablePath).Equals(
                    $expected,
                    [StringComparison]::OrdinalIgnoreCase)
            })
        if ($matches.Count -ne 1) {
            throw "The retained legacy bridge process could not be identified uniquely."
        }
        $process = $matches[0]
    } else {
        $process = Get-CimInstance Win32_Process `
            -Filter "ProcessId = $($listener.OwningProcess)"
    }
    if (-not $process -or -not $process.ExecutablePath) {
        throw "The current live-port owner could not be identified."
    }
    $resolved = [IO.Path]::GetFullPath($process.ExecutablePath)
    if ($ExpectedLegacyExecutablePath) {
        $expected = [IO.Path]::GetFullPath($ExpectedLegacyExecutablePath)
        if (-not $resolved.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Live port $LivePort is owned by an unexpected executable."
        }
    } elseif ([IO.Path]::GetFileName($resolved) -ne "CodexPcBridge.exe") {
        throw "Live port $LivePort is not owned by the expected legacy bridge."
    }
    return [pscustomobject]@{
        ProcessId = [int]$process.ProcessId
        ExecutablePath = $resolved
        WorkingDirectory = Split-Path -Parent $resolved
    }
}

function Wait-PortReleased {
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 10
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $connect = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            if (-not $connect.AsyncWaitHandle.WaitOne(250)) {
                return
            }
            try {
                $client.EndConnect($connect)
                $listening = $client.Connected
            } catch {
                $listening = $false
            }
            if (-not $listening) {
                return
            }
        } finally {
            $client.Dispose()
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Port $Port did not become available."
}

Assert-Administrator
$settingsPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) "service-settings.json"
if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "Service settings were not found at $settingsPath."
}
$service = Get-Service -Name $ServiceName -ErrorAction Stop
if ($service.Status -ne "Running") {
    Start-Service -Name $ServiceName
}
$shadowHealth = Wait-BridgeHealth -Port $ShadowPort -ExpectedShadow $true
if (-not $SkipAndroidHealth -and -not $AndroidHealthCommand) {
    throw "AndroidHealthCommand is required unless -SkipAndroidHealth is explicit."
}
if ($AndroidHealthCommand) {
    & $env:ComSpec /d /s /c $AndroidHealthCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Android health command failed before activation."
    }
}

$legacy = Resolve-LegacyListener
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$rollbackRoot = Join-Path ([IO.Path]::GetFullPath($StateRoot)) "rollback"
New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
$rollbackPath = Join-Path $rollbackRoot "pre-v2-activation.json"
$rollback = [ordered]@{
    createdAt = [DateTimeOffset]::UtcNow.ToString("O")
    settings = $settings
    legacy = $legacy
    shadowHealth = $shadowHealth
}
$rollback | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $rollbackPath -Encoding utf8

try {
    Stop-Service -Name $ServiceName -Force
    if ($legacy) {
        Stop-Process -Id $legacy.ProcessId -Force
        Wait-Process -Id $legacy.ProcessId -ErrorAction SilentlyContinue
        Wait-PortReleased -Port $LivePort
    }
    Write-ServiceSettings `
        -Path $settingsPath `
        -Port $LivePort `
        -ShadowMode $false `
        -Previous $settings
    Start-Service -Name $ServiceName
    $liveHealth = Wait-BridgeHealth -Port $LivePort -ExpectedShadow $false
    if ($AndroidHealthCommand) {
        & $env:ComSpec /d /s /c $AndroidHealthCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Android health command failed after activation."
        }
    }
    Write-Output (
        "CODEX_PC_BRIDGE_V2_ACTIVATED port=$LivePort rollback=$rollbackPath " +
        "relayReady=$($liveHealth.relayReady)")
} catch {
    $activationError = $_
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    try {
        Wait-PortReleased -Port $LivePort
    } catch {
    }
    Copy-Item -LiteralPath $settingsPath `
        -Destination "$settingsPath.failed-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))" `
        -Force `
        -ErrorAction SilentlyContinue
    Write-ServiceSettings `
        -Path $settingsPath `
        -Port $ShadowPort `
        -ShadowMode $true `
        -Previous $settings
    Start-Service -Name $ServiceName
    Wait-BridgeHealth -Port $ShadowPort -ExpectedShadow $true | Out-Null
    if ($legacy -and -not (Get-Process -Id $legacy.ProcessId -ErrorAction SilentlyContinue)) {
        Start-Process `
            -FilePath $legacy.ExecutablePath `
            -WorkingDirectory $legacy.WorkingDirectory `
            -WindowStyle Hidden
    }
    throw "V2 activation failed and shadow/legacy rollback was attempted: $($activationError.Exception.Message)"
}
