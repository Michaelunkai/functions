param(
    [string]$DeployedRoot = (Join-Path $env:USERPROFILE 'UnrestrictedAgent')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $root 'setup_agent.ps1'
$agentPath = Join-Path $deployedRoot 'local_agent.py'
$launcherPath = Join-Path $deployedRoot 'run_agent.ps1'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

$setupContent = [IO.File]::ReadAllText($setupPath)
foreach ($required in @(
    '$agentPath',
    'local_agent.py',
    'AGENT_SYSTEM_PROMPT',
    'run_powershell',
    'read_file',
    'write_file',
    'list_directory',
    'web_fetch',
    'download_file',
    'install_python_package',
    'search_files',
    'run_python',
    'discover_capabilities',
    'read_binary_file',
    'write_binary_file',
    'browser_automation',
    'desktop_automation',
    'MODEL_RESPONSE_RETRY',
    'MANUAL_DEFLECTION_PATTERNS',
    'PYTHONIOENCODING',
    'Test-IsAdministrator',
    'LOCAL_AGENT_ADMIN',
    'successful_tool_used',
    'privileged_filesystem',
    'external_program',
    'action_loop_guard',
    'Unsupported browser action',
    'tool_calls',
    'AGENT_SELF_TEST: PASS',
    'function Get-RecoverySetupArguments',
    'function Invoke-AgentRecovery',
    'RECOVERY_SETTINGS_TEST: PASS',
    'RECOVERY_INVOCATION_TEST: PASS',
    'browserRequired = $BrowserRequired'
)) {
    Assert-True -Condition ($setupContent.IndexOf($required, [StringComparison]::Ordinal) -ge 0) `
        -Message ("Missing local-agent implementation marker: {0}" -f $required)
}

Assert-True -Condition (Test-Path -LiteralPath $agentPath -PathType Leaf) `
    -Message 'The deployed local_agent.py does not exist.'
Assert-True -Condition (Test-Path -LiteralPath $launcherPath -PathType Leaf) `
    -Message 'The deployed interactive launcher does not exist.'

if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $launcherTokens = $null
    $launcherErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $launcherPath,
        [ref]$launcherTokens,
        [ref]$launcherErrors
    ) | Out-Null
    Assert-True -Condition ($launcherErrors.Count -eq 0) `
        -Message ('The deployed launcher has PowerShell parse errors: ' + (
            ($launcherErrors | ForEach-Object { $_.Message }) -join '; '
        ))
    $launcherContent = [IO.File]::ReadAllText($launcherPath)
    foreach ($marker in @(
        'Test-IsAdministrator',
        'Invoke-ElevatedEncodedCommand',
        "Verb = 'RunAs'",
        'LOCAL_AGENT_ADMIN'
    )) {
        Assert-True -Condition ($launcherContent.IndexOf(
            $marker,
            [StringComparison]::Ordinal
        ) -ge 0) -Message ("Missing launcher elevation marker: {0}" -f $marker)
    }
    $elevationOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $launcherPath -ElevationSelfTest 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) `
        -Message ('Launcher elevation handoff self-test failed: ' + (
            $elevationOutput -join [Environment]::NewLine
        ))
    Assert-True -Condition (($elevationOutput -join "`n") -match 'ELEVATION_HANDOFF_TEST: PASS') `
        -Message 'Launcher elevation handoff did not emit its PASS marker.'

    $interactiveOutput = 'exit' | & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $launcherPath 2>&1
    $interactiveExitCode = $LASTEXITCODE
    Assert-True -Condition ($interactiveExitCode -eq 0) `
        -Message ('No-argument interactive launch failed: ' + (
            $interactiveOutput -join [Environment]::NewLine
        ))
    Assert-True -Condition (($interactiveOutput -join "`n") -match 'Local action agent ready:') `
        -Message 'No-argument interactive launch did not display its ready prompt.'

    $manifestPath = Join-Path $deployedRoot 'deployment.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $originalManifest = [IO.File]::ReadAllBytes($manifestPath)
        $recoveryStubPath = Join-Path $env:TEMP (
            'local-agent-recovery-stub-' + [Guid]::NewGuid().ToString('N') + '.ps1'
        )
        $recoveryProofPath = Join-Path $env:TEMP (
            'local-agent-recovery-proof-' + [Guid]::NewGuid().ToString('N') + '.txt'
        )
        $previousRecoverySetup = $env:UNRESTRICTED_AGENT_RECOVERY_SETUP_PATH
        $previousRecoveryProof = $env:UNRESTRICTED_AGENT_RECOVERY_PROOF
        try {
            $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
            $manifest | Add-Member -NotePropertyName browserRequired -NotePropertyValue $false -Force
            [IO.File]::WriteAllText(
                $manifestPath,
                ($manifest | ConvertTo-Json -Depth 8),
                (New-Object Text.UTF8Encoding($false))
            )
            $recoveryOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
                -File $launcherPath -RecoverySettingsSelfTest 2>&1
            Assert-True -Condition ($LASTEXITCODE -eq 0) `
                -Message ('Recovery settings self-test failed: ' + (
                    $recoveryOutput -join [Environment]::NewLine
                ))
            Assert-True -Condition (($recoveryOutput -join "`n") -match 'RECOVERY_SETTINGS_TEST: PASS') `
                -Message 'Recovery settings self-test did not emit its PASS marker.'
            $expectedRecovery = 'RECOVERY_ARGUMENTS: -Root\|' +
                [regex]::Escape($deployedRoot) + '\|-Model\|' +
                [regex]::Escape([string]$manifest.model) + '\|-ContextLength\|' +
                [regex]::Escape([string]$manifest.contextLength) + '\|-SkipBrowser'
            Assert-True -Condition (($recoveryOutput -join "`n") -match $expectedRecovery) `
                -Message ('Recovery settings did not preserve model, context, and browser state: ' + (
                    $recoveryOutput -join [Environment]::NewLine
                ))

            $recoveryStub = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
[IO.File]::WriteAllText(
    $env:UNRESTRICTED_AGENT_RECOVERY_PROOF,
    ($Rest -join '|'),
    (New-Object Text.UTF8Encoding($false))
)
'@
            [IO.File]::WriteAllText(
                $recoveryStubPath,
                $recoveryStub,
                (New-Object Text.UTF8Encoding($false))
            )
            $env:UNRESTRICTED_AGENT_RECOVERY_SETUP_PATH = $recoveryStubPath
            $env:UNRESTRICTED_AGENT_RECOVERY_PROOF = $recoveryProofPath
            $recoveryInvocationOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
                -File $launcherPath -RecoveryInvocationSelfTest 2>&1
            Assert-True -Condition ($LASTEXITCODE -eq 0) `
                -Message ('Recovery invocation self-test failed: ' + (
                    $recoveryInvocationOutput -join [Environment]::NewLine
                ))
            Assert-True -Condition (($recoveryInvocationOutput -join "`n") -match 'RECOVERY_INVOCATION_TEST: PASS') `
                -Message 'Recovery invocation self-test did not emit its PASS marker.'
            Assert-True -Condition (Test-Path -LiteralPath $recoveryProofPath -PathType Leaf) `
                -Message 'Recovery invocation did not execute the configured setup target.'
            if (Test-Path -LiteralPath $recoveryProofPath -PathType Leaf) {
                Assert-True -Condition ((Get-Content -LiteralPath $recoveryProofPath -Raw).Trim() -match (
                    '^-Root\|' + [regex]::Escape($deployedRoot) + '\|-Model\|' +
                    [regex]::Escape([string]$manifest.model) + '\|-ContextLength\|' +
                    [regex]::Escape([string]$manifest.contextLength) + '\|-SkipBrowser$'
                )) -Message 'Recovery invocation did not pass the preserved setup arguments.'
            }
        }
        finally {
            $env:UNRESTRICTED_AGENT_RECOVERY_SETUP_PATH = $previousRecoverySetup
            $env:UNRESTRICTED_AGENT_RECOVERY_PROOF = $previousRecoveryProof
            [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
            Remove-Item -LiteralPath $recoveryStubPath,$recoveryProofPath -Force -ErrorAction SilentlyContinue
        }
    }
}

if (Test-Path -LiteralPath $agentPath -PathType Leaf) {
    $pathProbeScript = Join-Path $env:TEMP (
        'local-agent-path-probe-' + [Guid]::NewGuid().ToString('N') + '.py'
    )
    $pathProbeCode = @'
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

agent_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("deployed_local_agent", agent_path)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Unable to load {agent_path}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = json.loads(module.run_powershell("(Get-Command whoami).Source"))
print(json.dumps(result))
expected = str(Path(r"C:\Windows\System32\whoami.exe"))
actual = result.get("stdout", "").strip()
if not result.get("ok") or actual.lower() != expected.lower():
    raise SystemExit(f"Expected {expected}, got {actual!r}: {result}")

original_module_path = os.environ.get("PSModulePath")
os.environ["PSModulePath"] = r"C:\Program Files\PowerShell\7\Modules"
try:
    module_result = json.loads(
        module.run_powershell("(Get-Command Get-FileHash -ErrorAction Stop).Source")
    )
    if not module_result.get("ok") or "Microsoft.PowerShell.Utility" not in module_result.get(
        "stdout", ""
    ):
        raise SystemExit(f"Get-FileHash module resolution failed: {module_result}")

    with tempfile.NamedTemporaryFile(delete=False) as handle:
        handle.write(b"local-agent-powershell-module-probe")
        hash_path = Path(handle.name)
    try:
        escaped_hash_path = str(hash_path).replace("'", "''")
        hash_result = json.loads(
            module.run_powershell(
                f"(Get-FileHash -LiteralPath '{escaped_hash_path}' -Algorithm SHA256).Hash"
            )
        )
        expected_hash = hashlib.sha256(hash_path.read_bytes()).hexdigest().upper()
        if (
            not hash_result.get("ok")
            or hash_result.get("stdout", "").strip().upper() != expected_hash
        ):
            raise SystemExit(f"Get-FileHash execution failed: {hash_result}")
    finally:
        hash_path.unlink(missing_ok=True)

    error_result = json.loads(
        module.run_powershell(
            "Write-Error 'EXPECTED_NONTERMINATING_FAILURE'; Write-Output 'continued'"
        )
    )
    if error_result.get("ok") or int(error_result.get("exit_code", 0)) == 0:
        raise SystemExit(
            "PowerShell non-terminating errors must produce a failed tool result: "
            f"{error_result}"
        )

    capabilities = json.loads(
        module.discover_capabilities("Get-FileHash ConvertTo-Json", 20)
    )
    discovered_names = {
        str(item.get("name", "")).casefold()
        for item in capabilities.get("powershell_commands", [])
    }
    if not {"get-filehash", "convertto-json"}.issubset(discovered_names):
        raise SystemExit(
            "PowerShell capability discovery did not find the requested cmdlets: "
            f"{capabilities}"
        )
finally:
    if original_module_path is None:
        os.environ.pop("PSModulePath", None)
    else:
        os.environ["PSModulePath"] = original_module_path
'@
    try {
        [IO.File]::WriteAllText(
            $pathProbeScript,
            $pathProbeCode,
            (New-Object System.Text.UTF8Encoding($false))
        )
        $savedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $pathProbeOutput = & (Join-Path $deployedRoot 'runtime\python\python.exe') `
                $pathProbeScript $agentPath 2>&1
            $pathProbeExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
        Assert-True -Condition ($pathProbeExitCode -eq 0) `
            -Message ('Windows command resolution regression: ' + (
                $pathProbeOutput -join [Environment]::NewLine
            ))
    }
    finally {
        if (Test-Path -LiteralPath $pathProbeScript) {
            Remove-Item -LiteralPath $pathProbeScript -Force
        }
    }

    $testRoot = Join-Path $env:TEMP ('local-agent-contract-' + [Guid]::NewGuid().ToString('N'))
    try {
        $output = & (Join-Path $deployedRoot 'runtime\python\python.exe') $agentPath `
            '--self-test' '--test-root' $testRoot 2>&1
        Assert-True -Condition ($LASTEXITCODE -eq 0) `
            -Message ('Local-agent self-test failed: ' + ($output -join [Environment]::NewLine))
        Assert-True -Condition (($output -join "`n") -match 'AGENT_SELF_TEST: PASS') `
            -Message 'Local-agent self-test did not emit AGENT_SELF_TEST: PASS.'
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'LOCAL_AGENT_TEST: FAIL'
    foreach ($failure in $failures) {
        Write-Host (' - ' + $failure)
    }
    exit 1
}

Write-Host 'LOCAL_AGENT_TEST: PASS'
exit 0
