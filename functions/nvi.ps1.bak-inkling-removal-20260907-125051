# nvi.ps1 - Compatibility entrypoint for the ranked NVIDIA launchers.
# Usage: nvi          (opens rank 1: Inkling)
#        nvi -Ultra   (opens rank 2: Nemotron 3 Ultra 550B)
#        nvi -Check   (full health check, then open)
#
# This file preserves old shells that still point directly at nvi.ps1.
# All proxy, config, health-check, and session-backup logic is inherited.
#
# NOTE: When the proxy is running (port 3456), ALL preflight probes are
# skipped — the proxy handles 429s transparently with key rotation + retry.
# This means: glm, nvi, seek ALL open instantly with zero wait.

$__2scProfileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
$__2scNeedBootstrap = -not (Get-Command -Name 'Initialize-CodexProfileFunctions' -CommandType Function -ErrorAction SilentlyContinue)
if (-not $__2scNeedBootstrap) {
    $__2scLoadedModule = Get-Module -Name 'CodexProfileFunctions' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($__2scLoadedModule) {
        $__2scLoadedFingerprint = $__2scLoadedModule.SessionState.PSVariable.GetValue('ProfileModuleFingerprint')
        $__2scModuleFile = Join-Path $__2scLoadedModule.ModuleBase 'CodexProfileFunctions.psm1'
        if ([System.IO.File]::Exists($__2scModuleFile)) {
            $__2scDiskInfo = Get-Item -LiteralPath $__2scModuleFile -ErrorAction SilentlyContinue
            if ($__2scDiskInfo) {
                $__2scDiskFingerprint = '{0}|{1}' -f $__2scDiskInfo.Length, $__2scDiskInfo.LastWriteTimeUtc.Ticks
                if ([string]$__2scLoadedFingerprint -and $__2scDiskFingerprint -ne [string]$__2scLoadedFingerprint) { $__2scNeedBootstrap = $true }
            }
        }
    }
}
if ($__2scNeedBootstrap) {
    if (-not (Test-Path -LiteralPath $__2scProfileModule -PathType Leaf)) {
        throw "nvi requires the Codex profile module: $__2scProfileModule"
    }
    Import-Module -Name $__2scProfileModule -Force -DisableNameChecking -ErrorAction Stop
    Initialize-CodexProfileFunctions
}

function nvi {
    [CmdletBinding()]
    param(
        [switch]$Check,
        [switch]$Ultra,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args
    )

    $rankedDispatcher = 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1'
    if (-not (Test-Path -LiteralPath $rankedDispatcher -PathType Leaf)) {
        throw "nvi requires the ranked dispatcher: $rankedDispatcher"
    }

    $rank = if ($Ultra) { 2 } else { 1 }
    $invArgs = @()
    if ($Check) { $invArgs += '-Check' }
    foreach ($a in $Args) { $invArgs += $a }
    & $rankedDispatcher -Rank $rank @invArgs
}

if ($MyInvocation.InvocationName -ne '.') {
    $__checkSwitch = $false
    $__ultraSwitch = $false
    $__passArgs = @()
    foreach ($__a in $args) {
        if ($__a -eq '-Check' -or $__a -eq '-check') {
            $__checkSwitch = $true
        } elseif ($__a -eq '-Ultra' -or $__a -eq '-ultra') {
            $__ultraSwitch = $true
        } else {
            $__passArgs += $__a
        }
    }
    if ($__checkSwitch -and $__ultraSwitch) {
        & 'nvi' -Check -Ultra @__passArgs
    } elseif ($__checkSwitch) {
        & 'nvi' -Check @__passArgs
    } elseif ($__ultraSwitch) {
        & 'nvi' -Ultra @__passArgs
    } else {
        & 'nvi' @__passArgs
    }
}
