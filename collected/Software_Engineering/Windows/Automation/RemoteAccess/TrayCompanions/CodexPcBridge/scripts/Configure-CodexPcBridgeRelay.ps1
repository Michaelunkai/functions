param(
    [Parameter(Mandatory = $true)]
    [string]$RelayUrl,
    [string]$ServiceName = "CodexPcBridgeV2",
    [string]$StateRoot = "$env:ProgramData\CodexPcBridge",
    [int]$HealthTimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this relay configuration tool from an elevated PowerShell 5.1 session."
    }
}

function Resolve-RelayUrl {
    param([string]$Value)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.UserInfo -or
        $uri.Fragment) {
        throw "RelayUrl must be an absolute URL without credentials or a fragment."
    }
    $loopbackDevelopment = $uri.Scheme -eq "http" -and
        $uri.Host -in @("127.0.0.1", "localhost")
    if ($uri.Scheme -ne "https" -and -not $loopbackDevelopment) {
        throw "RelayUrl must use HTTPS, except for loopback development."
    }
    return $uri.AbsoluteUri.TrimEnd("/")
}

function Write-Settings {
    param(
        [string]$Path,
        [object]$Current,
        [string]$NormalizedRelay
    )

    $updated = [ordered]@{
        Version = 2
        Port = [int]$Current.Port
        TailscaleEnabled = [bool]$Current.TailscaleEnabled
        RelayEnabled = $true
        RelayUrl = $NormalizedRelay
        ShadowMode = [bool]$Current.ShadowMode
    }
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $updated | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

Assert-Administrator
$normalizedRelay = Resolve-RelayUrl -Value $RelayUrl
$settingsPath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) "service-settings.json"
if (-not (Test-Path -LiteralPath $settingsPath)) {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($service.Status -ne "Running") {
        Start-Service -Name $ServiceName
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $settingsPath) -and
        [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
}
if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "Service settings were not created at $settingsPath."
}
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
Stop-Service -Name $ServiceName -Force
Write-Settings `
    -Path $settingsPath `
    -Current $settings `
    -NormalizedRelay $normalizedRelay
Start-Service -Name $ServiceName

$deadline = [DateTime]::UtcNow.AddSeconds($HealthTimeoutSeconds)
do {
    try {
        $health = Invoke-RestMethod `
            -Uri "http://127.0.0.1:$([int]$settings.Port)/v2/health" `
            -Method Get `
            -TimeoutSec 3
        if ($health.ok -and
            $health.gatewayReady -and
            $health.relayConfigured) {
            Write-Output (
                "CODEX_PC_BRIDGE_RELAY_CONFIGURED relay=$normalizedRelay " +
                "port=$($settings.Port) shadow=$($settings.ShadowMode)")
            return
        }
    } catch {
    }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)

throw "Service did not return relay-configured health after restart."
