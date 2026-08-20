# seek.ps1 — Launch OpenCode with DeepSeek V4 Flash (best DeepSeek model)
# Usage: seek         (opens DeepSeek V4 Flash — 284B MoE, 1M ctx)
#        seek -Check  (health-check first, then open)
#
# DeepSeek V4 Flash: fastest coding model, 1M context window.
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
        throw "seek requires the Codex profile module: $__2scProfileModule"
    }
    Import-Module -Name $__2scProfileModule -Force -DisableNameChecking -ErrorAction Stop
    Initialize-CodexProfileFunctions
}

function seek {
    [CmdletBinding()]
    param(
        [switch]$Check,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args
    )

    $nviocScript = 'F:\study\Platforms\windows\functions\nvioc.ps1'
    if (-not (Test-Path -LiteralPath $nviocScript -PathType Leaf)) {
        throw "seek requires nvioc.ps1: $nviocScript"
    }

    # Force DeepSeek V4 Flash model. Pass -Check if requested, plus any extra args.
    $invArgs = @('-m', 'nvidia-nim/deepseek-ai/deepseek-v4-flash-0731')
    if ($Check) { $invArgs += '-Check' }
    foreach ($a in $Args) { $invArgs += $a }
    & $nviocScript @invArgs
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
        & 'seek' -Check @__passArgs
    } else {
        & 'seek' @__passArgs
    }
}
