Set-StrictMode -Version 2.0

function Get-ProjectRoot {
    $root = Split-Path -Parent $PSScriptRoot
    return (Resolve-Path -LiteralPath $root).Path
}

function New-ProjectLayout {
    param([string]$Root = (Get-ProjectRoot))
    foreach ($name in @('state','runtime','models','logs','downloads','reports')) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = 'INFO'
    )
    $root = Get-ProjectRoot
    New-ProjectLayout -Root $root
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('s'), $Level.ToUpperInvariant(), $Message
    Add-Content -LiteralPath (Join-Path $root 'logs\local-ai-autodeployer.log') -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-Json {
    param(
        [Parameter(Mandatory=$true)]$InputObject,
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Depth = 12
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Invoke-WebJson {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [int]$TimeoutSec = 45
    )
    Write-Log "GET $Uri"
    $headers = @{
        'User-Agent' = 'local-ai-autodeployer/1.0 PowerShell5 Windows'
        'Accept' = 'application/json'
    }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec
}

function Get-FileSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory=$true)][string]$Text)
    $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
    $regex = '[{0}]' -f [Regex]::Escape($invalid)
    return ([Regex]::Replace($Text, $regex, '_')).Trim()
}

Export-ModuleMember -Function *
