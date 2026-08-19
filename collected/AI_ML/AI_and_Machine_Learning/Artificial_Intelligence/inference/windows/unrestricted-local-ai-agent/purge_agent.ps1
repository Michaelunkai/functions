[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$StateDirectory = '',
    [switch]$PlanOnly,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-SafePurgeTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = Get-NormalizedPath -Path $Path
    $protectedRoots = @(
        [IO.Path]::GetPathRoot($normalized),
        $env:USERPROFILE,
        $env:ProgramData,
        $env:WINDIR
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Get-NormalizedPath -Path $_ }
    if ($protectedRoots -contains $normalized) {
        throw "Refusing to purge a protected root: $normalized"
    }

    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($normalized)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to purge a reparse point: $current"
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to purge because a reparse point exists: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Get-StateDirectory {
    if (-not [string]::IsNullOrWhiteSpace($StateDirectory)) {
        return Get-NormalizedPath -Path $StateDirectory
    }
    $programData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::CommonApplicationData
    )
    return Join-Path $programData 'UnrestrictedLocalAI'
}

function Get-BindingPath {
    param(
        [Parameter(Mandatory = $true)][string]$DeploymentRoot,
        [Parameter(Mandatory = $true)][string]$DeploymentStateDirectory
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes(
        (Get-NormalizedPath -Path $DeploymentRoot).ToUpperInvariant()
    )
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $key = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $hash.Dispose()
    }
    return Join-Path (Join-Path $DeploymentStateDirectory 'roots') ($key + '.json')
}

function Get-RecordedRoot {
    param([Parameter(Mandatory = $true)][string]$DeploymentStateDirectory)

    $pointerPath = Join-Path $DeploymentStateDirectory 'deployment-root.txt'
    if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
        $recorded = [IO.File]::ReadAllText($pointerPath).Trim()
        if (-not [string]::IsNullOrWhiteSpace($recorded)) {
            return Get-NormalizedPath -Path $recorded
        }
    }
    return Get-NormalizedPath -Path (Join-Path $env:USERPROFILE 'UnrestrictedAgent')
}

function Test-OwnedDeploymentRoot {
    param(
        [Parameter(Mandatory = $true)][string]$DeploymentRoot,
        [Parameter(Mandatory = $true)][string]$DeploymentStateDirectory
    )

    $normalizedRoot = Get-NormalizedPath -Path $DeploymentRoot
    $markerPath = Join-Path $normalizedRoot '.portable-agent-root.json'
    $bindingPath = Get-BindingPath -DeploymentRoot $normalizedRoot `
        -DeploymentStateDirectory $DeploymentStateDirectory
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $bindingPath -PathType Leaf)) {
        return $false
    }
    try {
        $marker = [IO.File]::ReadAllText($markerPath) | ConvertFrom-Json
        $binding = [IO.File]::ReadAllText($bindingPath) | ConvertFrom-Json
        return (
            ([int]$marker.schema -eq 2) -and
            ([string]$marker.purpose -eq 'portable-local-agent') -and
            ((Get-NormalizedPath -Path ([string]$marker.root)) -eq $normalizedRoot) -and
            (-not [string]::IsNullOrWhiteSpace([string]$marker.installationId)) -and
            ([int]$binding.schema -eq 1) -and
            ((Get-NormalizedPath -Path ([string]$binding.root)) -eq $normalizedRoot) -and
            ([string]$binding.installationId -eq [string]$marker.installationId)
        )
    }
    catch {
        return $false
    }
}

function Stop-DeploymentProcesses {
    param([Parameter(Mandatory = $true)][string]$DeploymentRoot)

    $prefix = (Get-NormalizedPath -Path $DeploymentRoot) + '\'
    $processes = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
                ([string]$_.ExecutablePath).StartsWith(
                    $prefix,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    foreach ($process in $processes) {
        Write-Output ("Stopping deployment process {0}: {1}" -f `
            $process.ProcessId, $process.Name)
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }
    if ($processes.Count -gt 0) {
        Start-Sleep -Seconds 2
    }
    return $processes.Count
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [Int64]0
    }
    Assert-SafePurgeTree -Path $Path
    $total = [Int64]0
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push((Get-NormalizedPath -Path $Path))
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
            else {
                $total += [Int64]$child.Length
            }
        }
    }
    return $total
}

function Remove-EmptyStateDirectories {
    param([Parameter(Mandatory = $true)][string]$DeploymentStateDirectory)

    $rootsDirectory = Join-Path $DeploymentStateDirectory 'roots'
    if ((Test-Path -LiteralPath $rootsDirectory -PathType Container) -and
        @((Get-ChildItem -LiteralPath $rootsDirectory -Force)).Count -eq 0) {
        Remove-Item -LiteralPath $rootsDirectory -Force
    }
    if ((Test-Path -LiteralPath $DeploymentStateDirectory -PathType Container) -and
        @((Get-ChildItem -LiteralPath $DeploymentStateDirectory -Force)).Count -eq 0) {
        Remove-Item -LiteralPath $DeploymentStateDirectory -Force
    }
}

function Invoke-DeploymentPurge {
    param(
        [Parameter(Mandatory = $true)][string]$DeploymentRoot,
        [Parameter(Mandatory = $true)][string]$DeploymentStateDirectory,
        [switch]$DryRun
    )

    $normalizedRoot = Get-NormalizedPath -Path $DeploymentRoot
    $normalizedState = Get-NormalizedPath -Path $DeploymentStateDirectory
    if (-not (Test-OwnedDeploymentRoot -DeploymentRoot $normalizedRoot `
        -DeploymentStateDirectory $normalizedState)) {
        throw "Refusing to purge an unverified deployment root: $normalizedRoot"
    }

    $bindingPath = Get-BindingPath -DeploymentRoot $normalizedRoot `
        -DeploymentStateDirectory $normalizedState
    $pointerPath = Join-Path $normalizedState 'deployment-root.txt'
    $bytes = Get-DirectoryBytes -Path $normalizedRoot
    if ($DryRun) {
        Write-Output 'PURGE_PLAN: PASS'
        Write-Output ("ROOT: {0}" -f $normalizedRoot)
        Write-Output ("BYTES_TO_FREE: {0}" -f $bytes)
        return
    }

    $stopped = Stop-DeploymentProcesses -DeploymentRoot $normalizedRoot
    Assert-SafePurgeTree -Path $normalizedRoot
    Remove-Item -LiteralPath $normalizedRoot -Recurse -Force
    if (Test-Path -LiteralPath $bindingPath -PathType Leaf) {
        Remove-Item -LiteralPath $bindingPath -Force
    }
    if (Test-Path -LiteralPath $pointerPath -PathType Leaf) {
        $recorded = [IO.File]::ReadAllText($pointerPath).Trim()
        if ((Get-NormalizedPath -Path $recorded) -eq $normalizedRoot) {
            Remove-Item -LiteralPath $pointerPath -Force
        }
    }
    Remove-EmptyStateDirectories -DeploymentStateDirectory $normalizedState
    Write-Output 'PURGE_RESULT: PASS'
    Write-Output ("ROOT_REMOVED: {0}" -f $normalizedRoot)
    Write-Output ("BYTES_FREED: {0}" -f $bytes)
    Write-Output ("PROCESSES_STOPPED: {0}" -f $stopped)
}

function Invoke-PurgeSelfTest {
    $testBase = Join-Path ([IO.Path]::GetTempPath()) (
        'unrestricted-agent-purge-' + [Guid]::NewGuid().ToString('N')
    )
    $testRoot = Join-Path $testBase 'agent'
    $testState = Join-Path $testBase 'program-data\UnrestrictedLocalAI'
    try {
        [void](New-Item -ItemType Directory -Path $testRoot,(Join-Path $testState 'roots') -Force)
        $installationId = [Guid]::NewGuid().ToString('N')
        $marker = [ordered]@{
            schema = 2
            root = Get-NormalizedPath -Path $testRoot
            installationId = $installationId
            purpose = 'portable-local-agent'
        } | ConvertTo-Json
        [IO.File]::WriteAllText(
            (Join-Path $testRoot '.portable-agent-root.json'),
            $marker,
            (New-Object Text.UTF8Encoding($false))
        )
        [IO.File]::WriteAllText(
            (Join-Path $testRoot 'payload.bin'),
            ('x' * 8192),
            (New-Object Text.UTF8Encoding($false))
        )
        $bindingPath = Get-BindingPath -DeploymentRoot $testRoot `
            -DeploymentStateDirectory $testState
        $binding = [ordered]@{
            schema = 1
            root = Get-NormalizedPath -Path $testRoot
            installationId = $installationId
        } | ConvertTo-Json
        [IO.File]::WriteAllText($bindingPath, $binding, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText(
            (Join-Path $testState 'deployment-root.txt'),
            (Get-NormalizedPath -Path $testRoot),
            (New-Object Text.UTF8Encoding($false))
        )

        Invoke-DeploymentPurge -DeploymentRoot $testRoot `
            -DeploymentStateDirectory $testState
        if ((Test-Path -LiteralPath $testRoot) -or
            (Test-Path -LiteralPath $bindingPath) -or
            (Test-Path -LiteralPath (Join-Path $testState 'deployment-root.txt'))) {
            throw 'Purge self-test left verified deployment state behind.'
        }
        Write-Output 'PURGE_SELF_TEST: PASS'
    }
    finally {
        if (Test-Path -LiteralPath $testBase) {
            Remove-Item -LiteralPath $testBase -Recurse -Force
        }
    }
}

if ($SelfTest) {
    Invoke-PurgeSelfTest
    exit 0
}

$deploymentState = Get-StateDirectory
$deploymentRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
    Get-RecordedRoot -DeploymentStateDirectory $deploymentState
}
else {
    Get-NormalizedPath -Path $Root
}
Invoke-DeploymentPurge -DeploymentRoot $deploymentRoot `
    -DeploymentStateDirectory $deploymentState -DryRun:$PlanOnly
