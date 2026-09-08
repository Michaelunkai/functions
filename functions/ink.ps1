# ink.ps1 — Compatibility alias for the current verified NVIDIA rank-1 model.
# Usage: ink          (opens the rank-1 verified NVIDIA model)
#        ink -Check   (health-check first, then open)
#        ink <args>   (pass extra args to opencode)
#
# Inkling reached end-of-life. This alias delegates to the canonical ranked
# dispatcher so it cannot reintroduce the retired model or bypass identity
# checks.
# All proxy, config, health-check, and session-backup logic is inherited.

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
        throw "2sc-generated script requires the Codex profile module: $__2scProfileModule"
    }
    Import-Module -Name $__2scProfileModule -Force -DisableNameChecking -ErrorAction Stop
    Initialize-CodexProfileFunctions
}
function ink {
    [CmdletBinding()]
    param(
        [switch]$Check,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args
    )

    $rankedDispatcher = 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1'
    if (-not (Test-Path -LiteralPath $rankedDispatcher -PathType Leaf)) {
        throw "Ranked NVIDIA dispatcher not found at $rankedDispatcher"
    }

    $passthroughArgs = @('-Rank', '1')

    if ($Check) {
        $passthroughArgs += '-Check'
    }
    $passthroughArgs += $Args

    & $rankedDispatcher @passthroughArgs
}

if ($MyInvocation.InvocationName -ne '.') {
    $__checkSwitch = $false
    $__passArgs = @()
    foreach ($__a in $args) {
        if ($__a -eq '-Check' -or $__a -eq '-check') {
            $__checkSwitch = $true
        } else {
            $__passArgs += $__a
        }
    }
    if ($__checkSwitch) {
        & 'ink' -Check @__passArgs
    } else {
        & 'ink' @__passArgs
    }
}
