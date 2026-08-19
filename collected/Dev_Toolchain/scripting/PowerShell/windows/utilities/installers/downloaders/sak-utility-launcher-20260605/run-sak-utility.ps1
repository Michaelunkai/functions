$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $repo = 'RandyNorthrup/S.A.K.-Utility'
    $release = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -eq 'SAK-Utility-Windows-x64.zip' } | Select-Object -First 1
    $sumAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1

    if (-not $asset) {
        throw 'No SAK-Utility-Windows-x64.zip asset found in latest GitHub release.'
    }

    $baseDir = Join-Path $env:LOCALAPPDATA 'SAK-Utility'
    $installDir = Join-Path $baseDir $release.tag_name
    $workDir = Join-Path $env:TEMP ('SAK-Utility-' + [guid]::NewGuid().ToString('N'))
    $extractDir = Join-Path $workDir 'extract'
    $zipPath = Join-Path $workDir $asset.name

    $existingExe = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'sak_utility.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingExe) {
        $process = Start-Process -FilePath $existingExe.FullName -PassThru
        Start-Sleep -Seconds 3
        $running = [bool](Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
        Write-Host "SAK launched from existing install: $($existingExe.FullName)"
        Write-Host "ProcessId: $($process.Id); RunningAfter3s: $running"
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $workDir, $extractDir, $installDir | Out-Null

    Write-Host "Downloading S.A.K. Utility $($release.tag_name)..."
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath

    if ($sumAsset) {
        $sums = (Invoke-WebRequest -UseBasicParsing -Uri $sumAsset.browser_download_url).Content
        $expectedHash = ([regex]::Match($sums, '(?im)^([a-f0-9]{64})\s+\*?SAK-Utility-Windows-x64\.zip\s*$')).Groups[1].Value
        if ($expectedHash) {
            $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash.ToUpperInvariant()) {
                throw "SAK ZIP SHA256 mismatch. Expected $expectedHash actual $actualHash"
            }
            Write-Host "SHA256 verified: $actualHash"
        }
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $extractedExe = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter 'sak_utility.exe' | Select-Object -First 1
    if (-not $extractedExe) {
        throw 'sak_utility.exe was not found after extraction.'
    }

    Get-ChildItem -LiteralPath $extractDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $installDir -Recurse -Force
    }
    $finalExe = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'sak_utility.exe' | Select-Object -First 1
    if (-not $finalExe) {
        throw 'sak_utility.exe was not found in the final install directory.'
    }

    $process = Start-Process -FilePath $finalExe.FullName -PassThru
    Start-Sleep -Seconds 3
    $running = [bool](Get-Process -Id $process.Id -ErrorAction SilentlyContinue)

    Write-Host "SAK launched: $($finalExe.FullName)"
    Write-Host "ProcessId: $($process.Id); RunningAfter3s: $running"

    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
