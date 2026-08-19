$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'setup_agent.ps1'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

Assert-True -Condition (Test-Path -LiteralPath $scriptPath -PathType Leaf) `
    -Message 'setup_agent.ps1 must exist at the repository root.'

if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
    $content = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )

    Assert-True -Condition ($parseErrors.Count -eq 0) `
        -Message ('PowerShell parser errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))

    foreach ($required in @(
        'param(',
        '[switch]$SelfTest',
        '[switch]$PlanOnly',
        'function Get-HardwareProfile',
        'function Select-AgentModel',
        'function Install-PortablePython',
        'function Install-PortableOllama',
        'function Test-OllamaToolCalling',
        'function Install-PortableMinGit',
        'function Invoke-VerifiedDownload',
        'function Get-Sha256',
        'function Get-DeploymentStateDirectory',
        'function Protect-DeploymentStateDirectory',
        'function Get-DeploymentRootPointerPath',
        'function Get-DeploymentBindingPath',
        'function Write-DeploymentBinding',
        'function Write-DeploymentRootPointer',
        'function Stop-DeploymentProcesses',
        'deployment-root.txt',
        'ProgramData',
        'function Get-TcpListenerProcessId',
        '.agent-packages-ready',
        '.portable-agent-root.json',
        '--require-hashes',
        'sync_playwright',
        'import lxml',
        'import PIL',
        'import tenacity',
        'import typer',
        '$installedSetupPath',
        'OLLAMA_MODELS',
        'PLAYWRIGHT_BROWSERS_PATH',
        'def _action_key(',
        'REPEATED_IDENTICAL_ACTION',
        'repeated_action_blocked',
        'PREMATURE_ACTION_INTENT_PATTERNS',
        'def _is_incomplete_action_intent(',
        'incomplete_action_corrections',
        'def start_process(',
        'def stop_process(',
        'def install_windows_package(',
        'def download_and_install(',
        'def _normalize_process_arguments(',
        'class ProgressReporter:',
        'PROGRESS_HEARTBEAT_SECONDS = 10',
        'MAX_CONSECUTIVE_MODEL_FAILURES = 12',
        'MAX_CONSECUTIVE_NO_PROGRESS_CYCLES = 12',
        'NO_PROGRESS_FINALIZATION_LIMIT',
        'TASK_STATUS: NO_VERIFIED_ACTION_AFTER_RETRIES',
        'preserving task state and continuing automatically',
        '{FREE_TCP_PORT}',
        '"process_lifecycle": True',
        'def _decode_forwarded_arguments(',
        '--arguments-base64',
        'if (`$null -eq `$Arguments)',
        '[object[]]`$normalizedArguments = @()',
        '[object[]]`$normalizedArguments = @(`$Arguments)',
        'function Get-RecoverySetupArguments',
        'RECOVERY_SETTINGS_TEST: PASS',
        'browserRequired = $BrowserRequired',
        "`$argumentJson = '[]'",
        'qwen3.6:27b',
        'qwen3.5:9b',
        'qwen2.5-coder:7b',
        'HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:IQ2_M'
    )) {
        Assert-True -Condition ($content.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -ge 0) `
            -Message ("Missing required implementation marker: {0}" -f $required)
    }

    foreach ($forbidden in @(
        'winget ',
        'choco ',
        'Install-Package',
        'Start-BitsTransfer'
    )) {
        Assert-True -Condition ($content.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
            -Message ("Forbidden installer or global package mechanism found: {0}" -f $forbidden)
    }

    $selfTestOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $scriptPath -SelfTest 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) `
        -Message ('Self-test failed: ' + ($selfTestOutput -join [Environment]::NewLine))
    Assert-True -Condition (($selfTestOutput -join "`n") -match 'SELF_TEST: PASS') `
        -Message 'Self-test did not emit SELF_TEST: PASS.'
    Assert-True -Condition (($selfTestOutput -join "`n") -match 'PORT_OWNERSHIP_TEST: PASS') `
        -Message 'Self-test did not verify TCP listener ownership detection.'
    Assert-True -Condition (($selfTestOutput -join "`n") -match 'OLLAMA_COLLISION_TEST: PASS') `
        -Message 'Self-test did not verify Ollama owned-reuse and collision decisions.'
    Assert-True -Condition (($selfTestOutput -join "`n") -match 'DEPLOYMENT_ROOT_POINTER_TEST: PASS') `
        -Message 'Self-test did not verify deployment root pointer persistence.'

    $planRoot = Join-Path $env:TEMP ('agent-plan-' + [Guid]::NewGuid().ToString('N'))
    try {
        $planOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File $scriptPath -Root $planRoot -PlanOnly 2>&1
        Assert-True -Condition ($LASTEXITCODE -eq 0) `
            -Message ('Plan-only execution failed: ' + ($planOutput -join [Environment]::NewLine))
        Assert-True -Condition (($planOutput -join "`n") -match 'PLAN_ONLY: PASS') `
            -Message 'Plan-only execution did not emit PLAN_ONLY: PASS.'
    }
    finally {
        if (Test-Path -LiteralPath $planRoot) {
            Remove-Item -LiteralPath $planRoot -Recurse -Force
        }
    }

    $foreignRoot = Join-Path $env:TEMP ('agent-foreign-' + [Guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $foreignRoot -Force)
        [IO.File]::WriteAllText((Join-Path $foreignRoot 'unrelated.txt'), 'preserve')
        $foreignOutPath = Join-Path $foreignRoot 'child.out.log'
        $foreignErrPath = Join-Path $foreignRoot 'child.err.log'
        $foreignProcess = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $scriptPath, '-Root', $foreignRoot, '-SkipModel', '-SkipBrowser'
            ) -RedirectStandardOutput $foreignOutPath -RedirectStandardError $foreignErrPath
        $foreignOutput = @()
        if (Test-Path -LiteralPath $foreignOutPath) {
            $foreignOutput += Get-Content -LiteralPath $foreignOutPath
        }
        if (Test-Path -LiteralPath $foreignErrPath) {
            $foreignOutput += Get-Content -LiteralPath $foreignErrPath
        }
        Assert-True -Condition ($foreignProcess.ExitCode -ne 0) `
            -Message 'Foreign-root ownership guard returned a successful exit code.'
        Assert-True -Condition (($foreignOutput -join "`n") -match 'Refusing to deploy into a non-empty unowned directory') `
            -Message 'Foreign-root ownership guard did not reject a non-empty unowned directory.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $foreignRoot 'unrelated.txt')) `
            -Message 'Foreign-root ownership guard did not preserve the unrelated file.'
    }
    finally {
        if (Test-Path -LiteralPath $foreignRoot) {
            Remove-Item -LiteralPath $foreignRoot -Recurse -Force
        }
    }

    $forgedRoot = Join-Path $env:TEMP ('agent-forged-' + [Guid]::NewGuid().ToString('N'))
    $forgedLock = $null
    try {
        [void](New-Item -ItemType Directory -Path $forgedRoot -Force)
        [IO.File]::WriteAllText(
            (Join-Path $forgedRoot 'deployment.json'),
            (@{ root = $forgedRoot } | ConvertTo-Json)
        )
        [IO.File]::WriteAllText(
            (Join-Path $forgedRoot '.portable-agent-root.json'),
            (@{
                schema = 2
                root = $forgedRoot
                installationId = 'forged-installation-id'
                purpose = 'portable-local-agent'
            } | ConvertTo-Json)
        )
        [IO.File]::WriteAllText((Join-Path $forgedRoot 'unrelated.txt'), 'preserve')
        $setupLockPath = Join-Path $forgedRoot 'setup.lock'
        $forgedLock = [IO.File]::Open(
            $setupLockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        $forgedOutPath = Join-Path $env:TEMP ('agent-forged-out-' + [Guid]::NewGuid().ToString('N') + '.log')
        $forgedErrPath = Join-Path $env:TEMP ('agent-forged-err-' + [Guid]::NewGuid().ToString('N') + '.log')
        $forgedProcess = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $scriptPath, '-Root', $forgedRoot, '-SkipModel', '-SkipBrowser'
            ) -RedirectStandardOutput $forgedOutPath -RedirectStandardError $forgedErrPath
        $forgedOutput = @()
        if (Test-Path -LiteralPath $forgedOutPath) {
            $forgedOutput += Get-Content -LiteralPath $forgedOutPath
        }
        if (Test-Path -LiteralPath $forgedErrPath) {
            $forgedOutput += Get-Content -LiteralPath $forgedErrPath
        }
        Assert-True -Condition ($forgedProcess.ExitCode -ne 0) `
            -Message 'Forged deployment manifest returned a successful exit code.'
        Assert-True -Condition (($forgedOutput -join "`n") -match 'Deployment ownership marker is invalid') `
            -Message 'A forged ownership marker bypassed the protected root binding.'
    }
    finally {
        if ($forgedLock) {
            $forgedLock.Dispose()
        }
        Remove-Item -LiteralPath $forgedOutPath,$forgedErrPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $forgedRoot) {
            Remove-Item -LiteralPath $forgedRoot -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'TEST_RESULT: FAIL'
    foreach ($failure in $failures) {
        Write-Host (' - ' + $failure)
    }
    exit 1
}

Write-Host 'TEST_RESULT: PASS'
exit 0
