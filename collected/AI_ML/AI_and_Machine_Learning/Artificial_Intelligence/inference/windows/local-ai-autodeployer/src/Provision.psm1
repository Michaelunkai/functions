Set-StrictMode -Version 2.0

function Get-DownloadFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [int64]$ExpectedBytes = 0
    )
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path -LiteralPath $OutFile) {
        if ($ExpectedBytes -le 0 -or (Get-Item -LiteralPath $OutFile).Length -eq $ExpectedBytes) {
            return $OutFile
        }
        Remove-Item -LiteralPath $OutFile -Force
    }
    Write-Log "Downloading $Url"
    $tmp = "$OutFile.partial"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers.Add('User-Agent', 'local-ai-autodeployer/1.0 PowerShell5 Windows')
        $client.DownloadFile($Url, $tmp)
        if ($ExpectedBytes -gt 0) {
            $actual = (Get-Item -LiteralPath $tmp).Length
            if ($actual -ne $ExpectedBytes) {
                throw "Downloaded byte count mismatch for $Url. Expected $ExpectedBytes bytes, got $actual bytes."
            }
        }
        Move-Item -LiteralPath $tmp -Destination $OutFile -Force
    } finally {
        $client.Dispose()
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    return $OutFile
}

function Expand-BackendArchive {
    param(
        [Parameter(Mandatory=$true)][string]$Archive,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Force -Path $Destination | Out-Null }
    if ($Archive -match '\.zip$') {
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    } elseif ($Archive -match '\.7z$') {
        $seven = Get-Command 7z.exe -ErrorAction SilentlyContinue
        if (-not $seven) { throw 'A 7z backend archive was selected, but 7z.exe is not available. Rerun discovery or install a zip-capable backend release.' }
        & $seven.Source x "-o$Destination" -y $Archive | Out-Null
    } else {
        throw "Unsupported backend archive type: $Archive"
    }
    $exe = Get-ChildItem -LiteralPath $Destination -Recurse -File -Filter 'llama-server.exe' | Select-Object -First 1
    if (-not $exe) {
        $exe = Get-ChildItem -LiteralPath $Destination -Recurse -File -Filter 'server.exe' | Select-Object -First 1
    }
    if (-not $exe) { throw 'Extracted backend did not contain llama-server.exe or server.exe.' }
    return $exe.FullName
}

function Install-Backend {
    param([Parameter(Mandatory=$true)]$ReleaseAsset)
    $root = Get-ProjectRoot
    $safe = ConvertTo-SafeFileName -Text $ReleaseAsset.AssetName
    $archive = Join-Path $root ("downloads\{0}" -f $safe)
    Get-DownloadFile -Url $ReleaseAsset.DownloadUrl -OutFile $archive -ExpectedBytes ([int64]$ReleaseAsset.Size) | Out-Null
    $dest = Join-Path $root ('runtime\llama-cpp-' + (ConvertTo-SafeFileName -Text $ReleaseAsset.ReleaseTag))
    $exe = Expand-BackendArchive -Archive $archive -Destination $dest
    return [pscustomobject]@{
        BackendExe = $exe
        Archive = $archive
        Sha256 = Get-FileSha256 -Path $archive
        Release = $ReleaseAsset
    }
}

function Install-Model {
    param([Parameter(Mandatory=$true)]$ModelSelection)
    $root = Get-ProjectRoot
    $name = ConvertTo-SafeFileName -Text ((Split-Path -Leaf $ModelSelection.FilePath))
    $folder = Join-Path $root ('models\' + (ConvertTo-SafeFileName -Text $ModelSelection.ModelId))
    $out = Join-Path $folder $name
    Get-DownloadFile -Url $ModelSelection.DownloadUrl -OutFile $out -ExpectedBytes ([int64]$ModelSelection.Size) | Out-Null
    return [pscustomobject]@{
        ModelPath = $out
        Sha256 = Get-FileSha256 -Path $out
        Selection = $ModelSelection
    }
}

Export-ModuleMember -Function *
