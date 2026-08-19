Set-StrictMode -Version 2.0

function Find-LlamaCppReleaseAsset {
    param([switch]$PreferCuda)
    $release = Invoke-WebJson -Uri 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'
    $assets = @($release.assets)
    $ranked = $assets | Where-Object {
        $_.name -match '^llama-.+-bin-win-.+\.zip$'
    } | ForEach-Object {
        $score = 0
        if ($PreferCuda -and $_.name -match 'cuda|cu[0-9]+') { $score += 100 }
        if ($_.name -match 'avx2|x64') { $score += 20 }
        if ($_.name -match 'vulkan') { $score += 10 }
        if ($_.name -match 'cpu') { $score += 1 }
        [pscustomobject]@{ Score = $score; Asset = $_ }
    } | Sort-Object Score -Descending
    if (-not $ranked) { throw 'No Windows llama.cpp release asset was discovered from the live GitHub release API.' }
    return [pscustomobject]@{
        ReleaseTag = $release.tag_name
        PublishedAt = $release.published_at
        AssetName = $ranked[0].Asset.name
        DownloadUrl = $ranked[0].Asset.browser_download_url
        Size = $ranked[0].Asset.size
    }
}

function Find-HuggingFaceGgufCandidates {
    param([int]$Limit = 40)
    $uris = @(
        'https://huggingface.co/api/models?filter=gguf&sort=downloads&direction=-1&limit={0}&full=true' -f ([math]::Max($Limit, 100)),
        'https://huggingface.co/api/models?search={0}&sort=downloads&direction=-1&limit={1}&full=true' -f [uri]::EscapeDataString('gguf'), $Limit,
        'https://huggingface.co/api/models?search={0}&sort=downloads&direction=-1&limit={1}&full=true' -f [uri]::EscapeDataString('gguf text-generation'), $Limit,
        'https://huggingface.co/api/models?search={0}&sort=downloads&direction=-1&limit={1}&full=true' -f [uri]::EscapeDataString('gguf instruct'), $Limit,
        'https://huggingface.co/api/models?search={0}&sort=downloads&direction=-1&limit={1}&full=true' -f [uri]::EscapeDataString('gguf coding'), $Limit,
        'https://huggingface.co/api/models?search={0}&sort=downloads&direction=-1&limit={1}&full=true' -f [uri]::EscapeDataString('gguf reasoning'), $Limit
    )
    $seen = @{}
    $items = @()
    foreach ($uri in $uris) {
        try {
            $response = Invoke-WebJson -Uri $uri
            $models = @()
            if ($response -is [System.Array]) {
                $models = $response
            } elseif ($response.modelId -is [System.Array]) {
                for ($i = 0; $i -lt $response.modelId.Count; $i++) {
                    $models += [pscustomobject]@{
                        modelId = $response.modelId[$i]
                        tags = if ($response.tags -is [System.Array]) { $response.tags[$i] } else { @() }
                        pipeline_tag = if ($response.pipeline_tag -is [System.Array]) { $response.pipeline_tag[$i] } else { $response.pipeline_tag }
                        downloads = if ($response.downloads -is [System.Array]) { $response.downloads[$i] } else { $response.downloads }
                        likes = if ($response.likes -is [System.Array]) { $response.likes[$i] } else { $response.likes }
                        lastModified = if ($response.lastModified -is [System.Array]) { $response.lastModified[$i] } else { $response.lastModified }
                    }
                }
            } else {
                $models = @($response)
            }
            foreach ($m in $models) {
                try {
                    if (-not $m.modelId -or $seen.ContainsKey($m.modelId)) { continue }
                    $seen[$m.modelId] = $true
                    $tags = @($m.tags)
                    if ((($tags -join ' ') + ' ' + [string]$m.modelId) -notmatch 'gguf') { continue }
                    $pipeline = ''
                    if ($m.PSObject.Properties.Name -contains 'pipeline_tag') {
                        $pipeline = [string]$m.pipeline_tag
                    }
                    $tagText = ($tags -join ' ')
                    $identityText = (($tagText + ' ' + [string]$m.modelId + ' ' + $pipeline)).ToLowerInvariant()
                    if ($identityText -match 'embedding|embed|sentence-similarity|feature-extraction|rerank|classification|fill-mask|stable-diffusion|whisper|tts|image-to-text|text-to-image|image-text-to-text|vision|multimodal|\bvl\b|\bmtp\b|1m-context|1m_context|deepseek-v4|deepseek4') { continue }
                    if (($pipeline + ' ' + $tagText) -notmatch 'text-generation|text2text-generation|text-to-text') { continue }
                    $downloads = if ($m.PSObject.Properties.Name -contains 'downloads' -and $m.downloads) { [int64]$m.downloads } else { 0 }
                    $likes = if ($m.PSObject.Properties.Name -contains 'likes' -and $m.likes) { [int64]$m.likes } else { 0 }
                    $last = if ($m.PSObject.Properties.Name -contains 'lastModified' -and $m.lastModified) { [datetime]$m.lastModified } else { [datetime]'1970-01-01' }
                    $score = [double]$downloads + ([double]$likes * 1000)
                    if ($pipeline -match 'text-generation') { $score += 250000 }
                    if ($pipeline -match 'text-generation') { $score += 50000 }
                    if ($tagText -match 'instruct|instruction') { $score += 150000 }
                    if ($tagText -match 'reason|thinking') { $score += 150000 }
                    if ($tagText -match 'coding|code') { $score += 125000 }
                    if ($tagText -match 'function-calling|tool') { $score += 100000 }
                    if ($tagText -match 'conversational|chat') { $score += 75000 }
                    if ($tagText -match 'embedding') { $score -= 500000 }
                    $score += [math]::Max(0, 365 - ((Get-Date) - $last).TotalDays) * 100
                    $items += [pscustomobject]@{
                        ModelId = $m.modelId
                        LastModified = $last.ToString('o')
                        Downloads = $downloads
                        Likes = $likes
                        Tags = $tags
                        Pipeline = $pipeline
                        Score = [math]::Round($score, 2)
                    }
                } catch {
                    Write-Log -Level 'WARN' -Message ("Skipping malformed Hugging Face model metadata for {0}: {1}" -f $m.modelId, $_.Exception.Message)
                }
            }
        } catch {}
    }
    $ranked = $items | Sort-Object Score -Descending
    if (-not $ranked) { throw 'No GGUF Hugging Face model candidates were discovered from the live API.' }
    return @($ranked)
}

function Find-HuggingFaceGgufFiles {
    param([Parameter(Mandatory=$true)][string]$ModelId)
    $repoPath = (($ModelId -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $uri = 'https://huggingface.co/api/models/{0}/tree/main?recursive=true' -f $repoPath
    $response = Invoke-WebJson -Uri $uri
    $tree = @()
    if ($response -is [System.Array]) {
        $tree = $response
    } elseif ($response.path -is [System.Array]) {
        for ($i = 0; $i -lt $response.path.Count; $i++) {
            $tree += [pscustomobject]@{
                path = $response.path[$i]
                size = if ($response.size -is [System.Array]) { $response.size[$i] } else { $response.size }
            }
        }
    } else {
        $tree = @($response)
    }
    return @($tree | Where-Object { $_.path -match '\.gguf$' } | Select-Object path, size)
}

function Get-HuggingFaceResolveUrl {
    param(
        [Parameter(Mandatory=$true)][string]$ModelId,
        [Parameter(Mandatory=$true)][string]$Path
    )
    return 'https://huggingface.co/{0}/resolve/main/{1}' -f $ModelId, ($Path -replace '\\','/')
}

Export-ModuleMember -Function *
