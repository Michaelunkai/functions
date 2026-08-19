Set-StrictMode -Version 2.0

function Get-QuantRank {
    param([string]$Name)
    $order = @('Q8','Q6_K','Q5_K_M','Q5_K_S','Q4_K_M','Q4_K_S','Q3_K_M','Q3_K_S','Q2_K')
    for ($i = 0; $i -lt $order.Count; $i++) {
        if ($Name -match [Regex]::Escape($order[$i])) { return (100 - $i) }
    }
    if ($Name -match 'F16|BF16') { return 10 }
    return 40
}

function Select-BestModelFile {
    param(
        [Parameter(Mandatory=$true)]$Candidates,
        [Parameter(Mandatory=$true)]$HardwareProfile
    )
    $budgetBytes = [int64]$HardwareProfile.VramBudgetMiB * 1MB
    if ($HardwareProfile.NvidiaGpu -and $HardwareProfile.NvidiaGpu.TotalVramMiB) {
        $totalBudget = [int64]([double]$HardwareProfile.NvidiaGpu.TotalVramMiB * 1MB * 0.70)
        $freeBudget = if ($HardwareProfile.NvidiaGpu.FreeVramMiB) { [int64]([double]$HardwareProfile.NvidiaGpu.FreeVramMiB * 1MB * 0.72) } else { $totalBudget }
        $budgetBytes = [math]::Min($budgetBytes, [math]::Min($totalBudget, $freeBudget))
    }
    if ($budgetBytes -le 0) {
        $budgetBytes = [int64]([double]$HardwareProfile.SystemRamMiB * 1MB * 0.50)
    }
    foreach ($candidate in $Candidates) {
        $files = @(Find-HuggingFaceGgufFiles -ModelId $candidate.ModelId)
        $fit = $files | Where-Object {
            $_.size -and
            ([int64]$_.size -lt $budgetBytes) -and
            (([string]$_.path + ' ' + [string]$candidate.ModelId) -notmatch '(?i)\bmtp\b|vision|multimodal|\bvl\b|image-text|1m-context|1m_context|embedding|embed')
        } | ForEach-Object {
            $quantScore = Get-QuantRank -Name $_.path
            [pscustomobject]@{
                ModelId = $candidate.ModelId
                ModelScore = $candidate.Score
                FilePath = $_.path
                Size = [int64]$_.size
                QuantScore = $quantScore
                CombinedScore = [double]$candidate.Score + ($quantScore * 1000000) + ([double]$_.size / 1MB)
                DownloadUrl = Get-HuggingFaceResolveUrl -ModelId $candidate.ModelId -Path $_.path
            }
        } | Sort-Object CombinedScore -Descending
        if ($fit) { return $fit[0] }
    }
    throw 'No discovered GGUF file fits the calculated memory budget.'
}

function New-RuntimeConfig {
    param(
        [Parameter(Mandatory=$true)]$HardwareProfile,
        [Parameter(Mandatory=$true)][string]$BackendExe,
        [Parameter(Mandatory=$true)][string]$ModelPath,
        [int]$Port = 8080
    )
    $threads = [int]$HardwareProfile.RecommendedThreads
    $hasGpu = $HardwareProfile.NvidiaGpu -ne $null
    $args = @(
        '--host', '0.0.0.0',
        '--port', [string]$Port,
        '--model', $ModelPath,
        '--threads', [string]$threads,
        '--ctx-size', '4096',
        '--batch-size', '512',
        '--ubatch-size', '128'
    )
    if ($hasGpu) {
        $args += @('--n-gpu-layers', '999', '--flash-attn', 'auto')
    }
    return [pscustomobject]@{
        BackendExe = $BackendExe
        ModelPath = $ModelPath
        Port = $Port
        Args = $args
        CreatedAt = (Get-Date).ToString('o')
        HardwareFingerprint = ('{0}|{1}|{2}' -f $HardwareProfile.CpuName, $HardwareProfile.SystemRamMiB, ($HardwareProfile.NvidiaGpu | ConvertTo-Json -Compress))
    }
}

Export-ModuleMember -Function *
