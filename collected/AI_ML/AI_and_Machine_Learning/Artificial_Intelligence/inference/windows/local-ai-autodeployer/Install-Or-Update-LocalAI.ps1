[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$SelfTest,
    [switch]$DiscoveryOnly,
    [switch]$SkipMutation,
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Import-Module (Join-Path $root 'src\Common.psm1') -Force
Import-Module (Join-Path $root 'src\Hardware.psm1') -Force
Import-Module (Join-Path $root 'src\Discovery.psm1') -Force
Import-Module (Join-Path $root 'src\ModelFit.psm1') -Force
Import-Module (Join-Path $root 'src\Provision.psm1') -Force
Import-Module (Join-Path $root 'src\Network.psm1') -Force
Import-Module (Join-Path $root 'src\Tune.psm1') -Force
Import-Module (Join-Path $root 'src\Validation.psm1') -Force

function Write-FinalManifest {
    Clear-Host
    Write-Host (Join-Path $root 'Install-Or-Update-LocalAI.ps1')
    Write-Host (Join-Path $root 'Open-LocalAIInteractive.ps1')
}

try {
    New-ProjectLayout -Root $root
    $admin = Test-IsAdmin
    if (-not $admin -and -not ($SelfTest -or $DiscoveryOnly -or $SkipMutation)) {
        throw 'Run from an elevated Windows PowerShell 5.1 session. Zero-prompt operation cannot self-elevate without UAC.'
    }

    $hardware = Get-LocalAIHardwareProfile
    Save-Json -InputObject $hardware -Path (Join-Path $root 'state\hardware-profile.json')

    if ($SelfTest) {
        $backend = Join-Path $root 'runtime\selftest\llama-server.exe'
        $model = Join-Path $root 'models\selftest\model.gguf'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backend),(Split-Path -Parent $model) | Out-Null
        if (-not (Test-Path -LiteralPath $backend)) { New-Item -ItemType File -Path $backend | Out-Null }
        if (-not (Test-Path -LiteralPath $model)) { New-Item -ItemType File -Path $model | Out-Null }
        $config = New-RuntimeConfig -HardwareProfile $hardware -BackendExe $backend -ModelPath $model -Port $Port
        $config = Invoke-LocalAITune -RuntimeConfig $config -HardwareProfile $hardware -Fast
        Save-Json -InputObject ([pscustomobject]@{ SelfTest = $true; Hardware = $hardware; Config = $config }) -Path (Join-Path $root 'reports\selftest-latest.json')
        Write-FinalManifest
        exit 0
    }

    Enable-LocalAIPerformanceMode -SkipMutation:$SkipMutation | Out-Null
    Assert-PortAvailable -Port $Port -SkipMutation:$SkipMutation | Out-Null
    Enable-LocalAIFirewallRule -Port $Port -SkipMutation:$SkipMutation | Out-Null

    $backendRelease = Find-LlamaCppReleaseAsset -PreferCuda:($hardware.NvidiaGpu -ne $null)
    $candidates = Find-HuggingFaceGgufCandidates -Limit 100
    Save-Json -InputObject ([pscustomobject]@{ Backend = $backendRelease; Candidates = $candidates }) -Path (Join-Path $root 'state\discovery-latest.json')

    if ($DiscoveryOnly) {
        Write-FinalManifest
        exit 0
    }

    $backendInstall = Install-Backend -ReleaseAsset $backendRelease
    $failures = @()
    $validation = $null
    foreach ($candidate in $candidates) {
        $modelInstall = $null
        $modelSelection = $null
        try {
            $modelSelection = Select-BestModelFile -Candidates @($candidate) -HardwareProfile $hardware
        } catch {
            Write-Log -Level 'INFO' -Message ("Skipping model candidate before download: {0}: {1}" -f $candidate.ModelId, $_.Exception.Message)
            continue
        }
        try {
            Save-Json -InputObject $modelSelection -Path (Join-Path $root 'state\model-selection.json')
            $modelInstall = Install-Model -ModelSelection $modelSelection
            Save-Json -InputObject ([pscustomobject]@{ Backend = $backendInstall; Model = $modelInstall }) -Path (Join-Path $root 'state\install-manifest.json')

            $config = New-RuntimeConfig -HardwareProfile $hardware -BackendExe $backendInstall.BackendExe -ModelPath $modelInstall.ModelPath -Port $Port
            $config = Invoke-LocalAITune -RuntimeConfig $config -HardwareProfile $hardware
            $validation = Invoke-LocalAIValidation -RuntimeConfig $config
            Save-Json -InputObject $validation -Path (Join-Path $root 'reports\validation-latest.json')
            break
        } catch {
            $failure = [pscustomobject]@{
                ModelId = $candidate.ModelId
                Error = $_.Exception.Message
                Timestamp = (Get-Date).ToString('o')
            }
            $failures += $failure
            Save-Json -InputObject $failures -Path (Join-Path $root 'state\model-validation-failures.json')
            Write-Log -Level 'WARN' -Message ("Model candidate failed validation: {0}: {1}" -f $candidate.ModelId, $_.Exception.Message)
            if ($modelInstall -and $modelInstall.ModelPath -and (Test-Path -LiteralPath $modelInstall.ModelPath)) {
                $modelDir = Split-Path -Parent $modelInstall.ModelPath
                if ($modelDir.StartsWith((Join-Path $root 'models'), [StringComparison]::OrdinalIgnoreCase)) {
                    Remove-Item -LiteralPath $modelDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    if (-not $validation) {
        throw ("No live-discovered GGUF model validated successfully. Failures: {0}" -f (($failures | ForEach-Object { $_.ModelId + '=' + $_.Error }) -join '; '))
    }

    Write-FinalManifest
} catch {
    Write-Log -Level 'ERROR' -Message $_.Exception.Message
    throw
}
