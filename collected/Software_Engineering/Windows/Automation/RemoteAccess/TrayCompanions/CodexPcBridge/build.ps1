param(
    [ValidateSet("win-x64", "win-arm64", "all")]
    [string]$RuntimeIdentifier = "win-x64",
    [string]$Version = "2.0.0",
    [string]$CertificateThumbprint,
    [switch]$RequireSigning,
    [switch]$SkipMsi
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotnet = if ($env:CODEX_DOTNET) { $env:CODEX_DOTNET } else { "dotnet" }
$signTool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
$releaseRoot = Join-Path $root "release\windows"

function Invoke-Checked {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Sign {
    param([string]$Path)
    if (-not $CertificateThumbprint) {
        if ($RequireSigning) {
            throw "A trusted code-signing certificate thumbprint is required."
        }
        return
    }
    if ([IO.Path]::GetExtension($Path) -ieq ".ps1") {
        $certificate = Get-CodeSigningCertificate
        $signature = Set-AuthenticodeSignature `
            -LiteralPath $Path `
            -Certificate $certificate `
            -HashAlgorithm SHA256 `
            -TimestampServer "http://timestamp.digicert.com"
        if ($signature.Status -ne "Valid") {
            throw "PowerShell signing failed for ${Path}: $($signature.Status)."
        }
    } else {
        if (-not (Test-Path -LiteralPath $signTool)) {
            throw "signtool.exe was not found at $signTool."
        }
        & $signTool sign /sha1 $CertificateThumbprint /fd SHA256 /td SHA256 `
            /tr http://timestamp.digicert.com /v $Path
        if ($LASTEXITCODE -ne 0) {
            throw "Signing failed for $Path."
        }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne "Valid") {
        throw "Signature validation failed for ${Path}: $($signature.Status)."
    }
}

function Get-CodeSigningCertificate {
    foreach ($root in @("Cert:\CurrentUser\My", "Cert:\LocalMachine\My")) {
        $certificate = Get-ChildItem -LiteralPath $root |
            Where-Object {
                $_.Thumbprint -eq $CertificateThumbprint -and
                $_.HasPrivateKey
            } |
            Select-Object -First 1
        if ($certificate) {
            return $certificate
        }
    }
    throw "Code-signing certificate was not found in CurrentUser or LocalMachine stores."
}

function Invoke-DetachedSign {
    param([string]$Path)

    if (-not $CertificateThumbprint) {
        if ($RequireSigning) {
            throw "A trusted code-signing certificate thumbprint is required."
        }
        return
    }
    Add-Type -AssemblyName System.Security.Cryptography.Pkcs
    $certificate = Get-CodeSigningCertificate
    $content = [Security.Cryptography.Pkcs.ContentInfo]::new(
        [IO.File]::ReadAllBytes($Path))
    $cms = [Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
    $signer = [Security.Cryptography.Pkcs.CmsSigner]::new($certificate)
    $signer.IncludeOption =
        [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $cms.ComputeSignature($signer)
    $signaturePath = "$Path.p7s"
    [IO.File]::WriteAllBytes($signaturePath, $cms.Encode())

    $verification = [Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
    $verification.Decode([IO.File]::ReadAllBytes($signaturePath))
    $verification.CheckSignature($true)
}

function Get-StringSha256 {
    param([string]$Value)
    $sha256 = New-Object Security.Cryptography.SHA256Managed
    try {
        return (($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) |
            ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha256.Dispose()
    }
}

function Write-ReleaseMetadata {
    param(
        [string]$ArchitectureRoot,
        [string]$Runtime
    )
    $files = Get-ChildItem -LiteralPath $ArchitectureRoot -File -Recurse |
        Where-Object { $_.Name -notin @("SHA256SUMS.txt", "update-manifest.json", "sbom.spdx.json") } |
        Sort-Object FullName
    $checksums = foreach ($file in $files) {
        $relative = $file.FullName.Substring($ArchitectureRoot.Length).TrimStart("\") -replace "\\", "/"
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    Set-Content -LiteralPath (Join-Path $ArchitectureRoot "SHA256SUMS.txt") `
        -Value $checksums -Encoding ascii

    $manifestFiles = foreach ($file in $files) {
        $relative = $file.FullName.Substring($ArchitectureRoot.Length).TrimStart("\") -replace "\\", "/"
        [ordered]@{
            path = $relative
            size = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            signed = (Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -eq "Valid"
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        product = "CodexPcBridge"
        version = $Version
        runtime = $Runtime
        generatedAt = [DateTimeOffset]::UtcNow.ToString("O")
        minimumRollbackVersion = "1.0.0"
        legacyGatewayRetention = @("18765", "v1-hmac")
        files = $manifestFiles
    }
    $manifest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $ArchitectureRoot "update-manifest.json") -Encoding utf8

    $sbomPackages = foreach ($file in $files) {
        $relative = $file.FullName.Substring($ArchitectureRoot.Length).TrimStart("\") -replace "\\", "/"
        [ordered]@{
            SPDXID = "SPDXRef-File-" + (Get-StringSha256 $relative).Substring(0, 16)
            fileName = $relative
            checksums = @(
                [ordered]@{
                    algorithm = "SHA256"
                    checksumValue = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            )
        }
    }
    $sbom = [ordered]@{
        spdxVersion = "SPDX-2.3"
        dataLicense = "CC0-1.0"
        SPDXID = "SPDXRef-DOCUMENT"
        name = "CodexPcBridge-$Version-$Runtime"
        documentNamespace = "urn:codex-pc-bridge:$Version`:$Runtime`:$([guid]::NewGuid())"
        creationInfo = [ordered]@{
            created = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            creators = @("Tool: CodexPcBridge-build.ps1")
        }
        files = $sbomPackages
    }
    $sbom | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $ArchitectureRoot "sbom.spdx.json") -Encoding utf8
}

function Build-Runtime {
    param([string]$Runtime)

    $platform = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }
    $upgradeCode = if ($Runtime -eq "win-arm64") {
        "CCAB0D10-2E08-4C12-8C5A-C58F49B86042"
    } else {
        "FD24EFAC-B728-4F7A-BEE7-64F8E4B15F4B"
    }
    $architectureRoot = Join-Path $releaseRoot $Runtime
    $trayOutput = Join-Path $architectureRoot "tray"
    $toolsOutput = Join-Path $architectureRoot "tools"
    New-Item -ItemType Directory -Path $trayOutput -Force | Out-Null
    New-Item -ItemType Directory -Path $toolsOutput -Force | Out-Null
    Copy-Item -Path (Join-Path $root "scripts\*.ps1") `
        -Destination $toolsOutput -Force

    & $dotnet publish (Join-Path $root "CodexPcBridge\CodexPcBridge.csproj") `
        -c Release -r $Runtime --self-contained true -o $trayOutput `
        /p:PublishSingleFile=true `
        /p:IncludeNativeLibrariesForSelfExtract=true `
        /p:DebugType=None `
        /p:DebugSymbols=false `
        /p:Version=$Version
    if ($LASTEXITCODE -ne 0) { throw "Tray publish failed for $Runtime." }

    Invoke-Sign (Join-Path $trayOutput "CodexPcBridge.exe")
    Get-ChildItem -LiteralPath $toolsOutput -Filter "*.ps1" -File |
        ForEach-Object { Invoke-Sign $_.FullName }

    if (-not $SkipMsi) {
        $msiOutput = Join-Path $architectureRoot "installer"
        New-Item -ItemType Directory -Path $msiOutput -Force | Out-Null
        & $dotnet build (Join-Path $root "installer\CodexPcBridge.Installer.wixproj") `
            -c Release `
            /p:PublishRoot=$architectureRoot `
            /p:PlatformName=$platform `
            /p:InstallerVersion=$Version `
            /p:InstallerUpgradeCode=$upgradeCode `
            /p:OutputPath=$msiOutput
        if ($LASTEXITCODE -ne 0) { throw "MSI build failed for $Runtime." }
        $msi = Get-ChildItem -LiteralPath $msiOutput -Filter "*.msi" -File |
            Select-Object -First 1
        if (-not $msi) { throw "MSI output was not produced for $Runtime." }
        Invoke-Sign $msi.FullName
    }

    Write-ReleaseMetadata $architectureRoot $Runtime
    Invoke-DetachedSign (Join-Path $architectureRoot "SHA256SUMS.txt")
    Invoke-DetachedSign (Join-Path $architectureRoot "update-manifest.json")
    Invoke-DetachedSign (Join-Path $architectureRoot "sbom.spdx.json")
    Write-Output "CODEX_PC_BRIDGE_RELEASE=$architectureRoot"
}

if ($RuntimeIdentifier -eq "all") {
    Build-Runtime "win-x64"
    Build-Runtime "win-arm64"
} else {
    Build-Runtime $RuntimeIdentifier
}
