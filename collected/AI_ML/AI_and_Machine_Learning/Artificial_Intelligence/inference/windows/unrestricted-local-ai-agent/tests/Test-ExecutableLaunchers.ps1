[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $sourceRoot 'Build-Executables.ps1'
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "Build script not found: $buildScript"
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('unrestricted-launchers-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $testRoot 'package'
$agentRoot = Join-Path $testRoot 'agent'
$programDataRoot = Join-Path $testRoot 'program-data'
New-Item -ItemType Directory -Path $packageRoot, $agentRoot -Force | Out-Null

try {
    $installer = Join-Path $packageRoot 'Install-UnrestrictedLocalAI.exe'
    $talk = Join-Path $packageRoot 'Talk-To-UnrestrictedLocalAI.exe'
    $purge = Join-Path $packageRoot 'Purge-UnrestrictedLocalAI.exe'
    $buildOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $buildScript -OutputDirectory $packageRoot 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Executable build failed: $($buildOutput -join [Environment]::NewLine)"
    }
    if (($buildOutput -join "`n") -notmatch 'EXECUTABLE_BUILD: PASS') {
        throw "Build script did not emit its PASS marker: $($buildOutput -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "Installer executable was not created: $installer"
    }
    if (-not (Test-Path -LiteralPath $talk -PathType Leaf)) {
        throw "Interactive executable was not created: $talk"
    }
    if (-not (Test-Path -LiteralPath $purge -PathType Leaf)) {
        throw "Purge executable was not created: $purge"
    }

    $shippedBuildOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $buildScript 2>&1
    if ($LASTEXITCODE -ne 0 -or ($shippedBuildOutput -join "`n") -notmatch 'EXECUTABLE_BUILD: PASS') {
        throw "Shipped executable build failed: $($shippedBuildOutput -join [Environment]::NewLine)"
    }
    foreach ($name in 'Install-UnrestrictedLocalAI.exe','Talk-To-UnrestrictedLocalAI.exe','Purge-UnrestrictedLocalAI.exe') {
        $shipped = Join-Path $sourceRoot $name
        if (-not (Test-Path -LiteralPath $shipped -PathType Leaf)) {
            throw "Shipped executable is missing after build: $shipped"
        }
        Copy-Item -LiteralPath $shipped -Destination (Join-Path $packageRoot $name) -Force
    }

    $defaultPackage = Join-Path $packageRoot 'default-build'
    $defaultLaunchers = Join-Path $defaultPackage 'launchers'
    New-Item -ItemType Directory -Path $defaultLaunchers -Force | Out-Null
    Copy-Item -LiteralPath $buildScript -Destination $defaultPackage
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'launchers\Install-UnrestrictedLocalAI.cs') `
        -Destination $defaultLaunchers
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'launchers\Talk-To-UnrestrictedLocalAI.cs') `
        -Destination $defaultLaunchers
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'launchers\Purge-UnrestrictedLocalAI.cs') `
        -Destination $defaultLaunchers
    $defaultBuildOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $defaultPackage 'Build-Executables.ps1') 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Default executable build failed: $($defaultBuildOutput -join [Environment]::NewLine)"
    }
    if (($defaultBuildOutput -join "`n") -notmatch 'EXECUTABLE_BUILD: PASS') {
        throw 'Default executable build did not emit its PASS marker.'
    }
    foreach ($name in 'Install-UnrestrictedLocalAI.exe','Talk-To-UnrestrictedLocalAI.exe','Purge-UnrestrictedLocalAI.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $defaultPackage $name) -PathType Leaf)) {
            throw "Default executable build did not create: $name"
        }
    }

    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
for ($index = 0; $index -lt $Rest.Count; $index++) {
    if ($Rest[$index] -eq '-Root' -and ($index + 1) -lt $Rest.Count) {
        $pointerDirectory = Join-Path $env:ProgramData 'UnrestrictedLocalAI'
        New-Item -ItemType Directory -Path $pointerDirectory -Force | Out-Null
        [IO.File]::WriteAllText(
            (Join-Path $pointerDirectory 'deployment-root.txt'),
            $Rest[$index + 1],
            [Text.UTF8Encoding]::new($false)
        )
        break
    }
}
"setup:$($Rest -join '|')" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-proof.txt') -Encoding UTF8
Write-Output 'STUB_SETUP_STREAM_OK'
'@ | Set-Content -LiteralPath (Join-Path $packageRoot 'setup_agent.ps1') -Encoding UTF8

    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
"talk:$($Rest -join '|')" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'talk-proof.txt') -Encoding UTF8
Write-Output 'STUB_TALK_STREAM_OK'
'@ | Set-Content -LiteralPath (Join-Path $agentRoot 'run_agent.ps1') -Encoding UTF8

    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
"purge:$($Rest -join '|')" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'purge-proof.txt') -Encoding UTF8
Write-Output 'STUB_PURGE_STREAM_OK'
'@ | Set-Content -LiteralPath (Join-Path $packageRoot 'purge_agent.ps1') -Encoding UTF8

    $previousRoot = $env:UNRESTRICTED_AGENT_ROOT
    $previousProgramData = $env:ProgramData
    try {
        $env:ProgramData = $programDataRoot
        Remove-Item Env:UNRESTRICTED_AGENT_ROOT -ErrorAction SilentlyContinue

        $installerOutput = & $installer '-Root' $agentRoot '-PlanOnly' 'C:\one two\three' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Installer launcher returned $LASTEXITCODE"
        }
        if (($installerOutput -join "`n") -notmatch 'STUB_SETUP_STREAM_OK') {
            throw 'Installer did not inherit and stream child output'
        }
        $setupProof = Get-Content -LiteralPath (Join-Path $packageRoot 'setup-proof.txt') -Raw
        if ($setupProof.Trim() -ne "setup:-Root|$agentRoot|-PlanOnly|C:\one two\three") {
            throw "Installer did not forward arguments: $setupProof"
        }

        $rootPointer = Join-Path $programDataRoot 'UnrestrictedLocalAI\deployment-root.txt'
        if (-not (Test-Path -LiteralPath $rootPointer -PathType Leaf)) {
            throw "Installer test did not persist the deployment root: $rootPointer"
        }
        $persistedRoot = (Get-Content -LiteralPath $rootPointer -Raw).Trim()
        if ($persistedRoot -ne $agentRoot) {
            throw "Persisted root mismatch. Expected '$agentRoot', got '$persistedRoot'."
        }

        $talkOutput = & $talk 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw (
                "No-argument interactive launcher returned {0}: {1}" -f
                $LASTEXITCODE, ($talkOutput -join [Environment]::NewLine)
            )
        }
        if (($talkOutput -join "`n") -notmatch 'STUB_TALK_STREAM_OK') {
            throw 'No-argument interactive launcher did not inherit and stream child output'
        }
        $noArgumentProof = Get-Content -LiteralPath (Join-Path $agentRoot 'talk-proof.txt') -Raw
        if ($noArgumentProof.Trim() -ne 'talk:') {
            throw "Interactive launcher no-argument forwarding failed: $noArgumentProof"
        }

        $talkOutput = & $talk '--prompt' 'launcher test' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Interactive launcher returned $LASTEXITCODE"
        }

        $purgeOutput = & $purge '-Root' $agentRoot '-PlanOnly' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Purge launcher returned $LASTEXITCODE"
        }
        if (($purgeOutput -join "`n") -notmatch 'STUB_PURGE_STREAM_OK') {
            throw 'Purge launcher did not inherit and stream child output'
        }
        $purgeProof = Get-Content -LiteralPath (Join-Path $packageRoot 'purge-proof.txt') -Raw
        if ($purgeProof.Trim() -ne "purge:-Root|$agentRoot|-PlanOnly") {
            throw "Purge launcher did not forward arguments: $purgeProof"
        }

        [IO.File]::WriteAllText(
            $rootPointer,
            (Join-Path $testRoot 'missing-agent-root'),
            [Text.UTF8Encoding]::new($false)
        )
        $stalePointerOutPath = Join-Path $testRoot 'stale-pointer-out.log'
        $stalePointerErrPath = Join-Path $testRoot 'stale-pointer-err.log'
        $stalePointerProcess = Start-Process -FilePath $talk -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @('--prompt', 'must not fall back') `
            -RedirectStandardOutput $stalePointerOutPath -RedirectStandardError $stalePointerErrPath
        $stalePointerOutput = @()
        if (Test-Path -LiteralPath $stalePointerOutPath) {
            $stalePointerOutput += Get-Content -LiteralPath $stalePointerOutPath
        }
        if (Test-Path -LiteralPath $stalePointerErrPath) {
            $stalePointerOutput += Get-Content -LiteralPath $stalePointerErrPath
        }
        Remove-Item -LiteralPath $stalePointerOutPath,$stalePointerErrPath -Force -ErrorAction SilentlyContinue
        if ($stalePointerProcess.ExitCode -eq 0 -or
            ($stalePointerOutput -join "`n") -notmatch 'recorded local AI deployment is incomplete') {
            throw 'Interactive launcher did not fail clearly for a stale persisted deployment root.'
        }
    } finally {
        $env:UNRESTRICTED_AGENT_ROOT = $previousRoot
        $env:ProgramData = $previousProgramData
    }
    if (($talkOutput -join "`n") -notmatch 'STUB_TALK_STREAM_OK') {
        throw 'Interactive launcher did not inherit and stream child output'
    }
    $talkProof = Get-Content -LiteralPath (Join-Path $agentRoot 'talk-proof.txt') -Raw
    if ($talkProof -notmatch 'talk:--prompt\|launcher test') {
        throw "Interactive launcher did not forward arguments: $talkProof"
    }

    Write-Output 'EXECUTABLE_LAUNCHER_TEST: PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
