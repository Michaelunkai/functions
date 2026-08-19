[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $sourceRoot
}
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $compiler) {
    throw 'The .NET Framework C# compiler was not found.'
}

[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path

function Build-Launcher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Launcher source is missing: $SourcePath"
    }

    Write-Output ("Compiling {0}" -f (Split-Path -Leaf $OutputPath))
    $temporaryOutput = $OutputPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp.exe'
    $compilerOutput = & $compiler /nologo /target:exe "/out:$temporaryOutput" $SourcePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("Compilation failed for {0}: {1}" -f $SourcePath, (
            $compilerOutput -join [Environment]::NewLine
        ))
    }
    if (-not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
        throw "Compiler did not create: $temporaryOutput"
    }

    $replacementError = $null
    try {
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Move-Item -LiteralPath $temporaryOutput -Destination $OutputPath -Force
                $replacementError = $null
                break
            }
            catch {
                $replacementError = $_
                if ($attempt -lt 5) {
                    Write-Output ("Waiting to replace locked launcher ({0}/5)." -f $attempt)
                    Start-Sleep -Seconds $attempt
                }
            }
        }
        if ($replacementError) {
            throw (
                "Could not replace launcher after 5 attempts: {0}" -f
                $replacementError.Exception.Message
            )
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryOutput -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryOutput -Force -ErrorAction SilentlyContinue
        }
    }

    $item = Get-Item -LiteralPath $OutputPath
    $hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    Write-Output ("Built: {0}" -f $item.FullName)
    Write-Output ("Bytes: {0}; SHA256: {1}" -f $item.Length, $hash)
}

$installerPath = Join-Path $outputRoot 'Install-UnrestrictedLocalAI.exe'
$interactivePath = Join-Path $outputRoot 'Talk-To-UnrestrictedLocalAI.exe'
$purgePath = Join-Path $outputRoot 'Purge-UnrestrictedLocalAI.exe'

Build-Launcher `
    -SourcePath (Join-Path $sourceRoot 'launchers\Install-UnrestrictedLocalAI.cs') `
    -OutputPath $installerPath
Build-Launcher `
    -SourcePath (Join-Path $sourceRoot 'launchers\Talk-To-UnrestrictedLocalAI.cs') `
    -OutputPath $interactivePath
Build-Launcher `
    -SourcePath (Join-Path $sourceRoot 'launchers\Purge-UnrestrictedLocalAI.cs') `
    -OutputPath $purgePath

Write-Output 'EXECUTABLE_BUILD: PASS'
Write-Output ("INSTALL_EXECUTABLE: {0}" -f $installerPath)
Write-Output ("INTERACTIVE_EXECUTABLE: {0}" -f $interactivePath)
Write-Output ("PURGE_EXECUTABLE: {0}" -f $purgePath)
