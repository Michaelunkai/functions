Set-StrictMode -Version 2.0

function Invoke-LocalAITune {
    param(
        [Parameter(Mandatory=$true)]$RuntimeConfig,
        [Parameter(Mandatory=$true)]$HardwareProfile,
        [switch]$Fast
    )
    $threads = @([math]::Max(1, [int]($HardwareProfile.RecommendedThreads / 2)), [int]$HardwareProfile.RecommendedThreads) | Sort-Object -Unique
    $batches = if ($Fast) { @(256) } else { @(128,256,512) }
    $best = $null
    $results = @()
    foreach ($t in $threads) {
        foreach ($b in $batches) {
            $score = ($t * 1000) + $b
            if ($HardwareProfile.NvidiaGpu) { $score += 100000 }
            $args = @($RuntimeConfig.Args)
            for ($i = 0; $i -lt $args.Count; $i++) {
                if ($args[$i] -eq '--threads') { $args[$i + 1] = [string]$t }
                if ($args[$i] -eq '--batch-size') { $args[$i + 1] = [string]$b }
            }
            $row = [pscustomobject]@{
                Threads = $t
                BatchSize = $b
                EstimatedScore = $score
                Args = $args
            }
            $results += $row
            if (-not $best -or $row.EstimatedScore -gt $best.EstimatedScore) { $best = $row }
        }
    }
    $RuntimeConfig.Args = $best.Args
    $root = Get-ProjectRoot
    Save-Json -InputObject ([pscustomobject]@{ Results = $results; Best = $best; RuntimeConfig = $RuntimeConfig }) -Path (Join-Path $root 'state\tune-cache.json')
    Save-Json -InputObject $RuntimeConfig -Path (Join-Path $root 'state\best-runtime-config.json')
    return $RuntimeConfig
}

Export-ModuleMember -Function *
