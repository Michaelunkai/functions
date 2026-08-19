$script = @'
$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $repo = 'RandyNorthrup/S.A.K.-Utility'
    $rel = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -eq 'SAK-Utility-Windows-x64.zip' } | Select-Object -First 1
    $sumAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
    if (-not $asset) { throw 'No SAK-Utility-Windows-x64.zip asset found in latest release.' }

    $base = Join-Path $env:LOCALAPPDATA 'SAK-Utility'
    $versionDir = Join-Path $base $rel.tag_name
    $downloadDir = Join-Path $env:TEMP ('SAK-Utility-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $downloadDir, $versionDir | Out-Null
    $zip = Join-Path $downloadDir $asset.name

    Write-Host "Downloading $($rel.tag_name): $($asset.browser_download_url)"
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zip

    if ($sumAsset) {
        $sums = (Invoke-WebRequest -UseBasicParsing -Uri $sumAsset.browser_download_url).Content
        $expected = ([regex]::Match($sums, '(?im)^([a-f0-9]{64})\s+\*?SAK-Utility-Windows-x64\.zip\s*$')).Groups[1].Value
        if ($expected) {
            $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
            if ($actual -ne $expected.ToUpperInvariant()) { throw "SHA256 mismatch. Expected $expected actual $actual" }
            Write-Host "SHA256 verified: $actual"
        } else {
            Write-Host 'SHA256SUMS.txt did not contain a matching SAK ZIP line; continuing after GitHub HTTPS download.'
        }
    }

    $extract = Join-Path $downloadDir 'extract'
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'sak_utility.exe' | Select-Object -First 1
    if (-not $exe) { throw 'sak_utility.exe not found after extraction.' }

    Copy-Item -LiteralPath (Join-Path $extract '*') -Destination $versionDir -Recurse -Force
    $finalExe = Get-ChildItem -LiteralPath $versionDir -Recurse -Filter 'sak_utility.exe' | Select-Object -First 1
    if (-not $finalExe) { throw 'sak_utility.exe not found in final install directory.' }

    $proc = Start-Process -FilePath $finalExe.FullName -PassThru
    Start-Sleep -Seconds 3
    $stillRunning = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
    Write-Host "SAK launched: $($finalExe.FullName)"
    Write-Host "ProcessId: $($proc.Id); RunningAfter3s: $stillRunning"
    Remove-Item -LiteralPath $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
'@

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
$one = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'sak-encoded-working-oneliner.txt') -Value $one -Encoding ASCII
Write-Host "onelinerLength=$($one.Length)"
