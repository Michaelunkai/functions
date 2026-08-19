param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$TaskId
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
. (Join-Path $PSScriptRoot 'CodexSessionVerification.ps1')

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class AgentControlForegroundWindow {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
}
'@

$title = [Environment]::GetEnvironmentVariable('AGENT_CONTROL_TASK_TITLE')
$description = [Environment]::GetEnvironmentVariable('AGENT_CONTROL_TASK_DESCRIPTION')
if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($description)) {
    throw 'Task title and description are required.'
}
$marker = 'AC-' + $TaskId.Substring(0, [Math]::Min(8, $TaskId.Length))
$prompt = @"
$title [$marker]

MANDATORY FIRST ACTION: obtain your current thread ID from the goal/thread context, then call
codex_app.set_thread_pinned with that thread ID and pinned=true. Verify the native pin succeeds
before doing any mission work.

Agent Control mission:
$description

Work autonomously. Keep this session's progress understandable, verify the result, and finish with a concise summary.
Finish the final response with exactly one standalone result line:
AGENT_CONTROL_RESULT: DONE - only after the requested result is implemented and verified
AGENT_CONTROL_RESULT: WAITING - when external input or access is still required
AGENT_CONTROL_RESULT: FAILED - when the mission could not be completed after supported recovery
"@
$pinStatePath = Join-Path $env:USERPROFILE '.codex\.codex-global-state.json'
$sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
$knownSessionIds = @{}
Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') {
        $knownSessionIds[$Matches[1]] = $true
    }
}

function ConvertTo-NormalizedWorkspacePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path)) {
        throw "Workspace UI value is not an absolute path: '$Path'."
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if (-not $fullPath.Equals($pathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fullPath = $fullPath.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))
    }
    return $fullPath
}

function Test-AutomationElementEqual {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

    try {
        $leftId = @($Left.GetRuntimeId())
        $rightId = @($Right.GetRuntimeId())
    } catch {
        return $false
    }
    if ($leftId.Count -ne $rightId.Count) { return $false }
    for ($index = 0; $index -lt $leftId.Count; $index++) {
        if ($leftId[$index] -ne $rightId[$index]) { return $false }
    }
    return $true
}

function Get-CodexWindowForWorkspace {
    param([Parameter(Mandatory = $true)][string]$ExpectedWorkspace)

    $expectedPath = ConvertTo-NormalizedWorkspacePath -Path $ExpectedWorkspace
    $expectedLeaf = [System.IO.Path]::GetFileName($expectedPath)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $ids = @(Get-Process ChatGPT -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $matchingWindows = @(
    foreach ($window in $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($ids -notcontains $window.Current.ProcessId -or $window.Current.ClassName -ne 'Chrome_WidgetWin_1') { continue }
        $workspaceProved = $false
        $leafMatches = 0
        foreach ($element in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
            $name = [string]$element.Current.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            try {
                $candidatePath = ConvertTo-NormalizedWorkspacePath -Path $name
            } catch {
                if ($name.Equals($expectedLeaf, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $leafMatches++
                }
                continue
            }
            if ($candidatePath.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $workspaceProved = $true
                break
            }
        }
        if (-not $workspaceProved -and $leafMatches -gt 0) {
            $workspaceProved = $true
        }
        if ($workspaceProved) { $window }
    }
    )
    if ($matchingWindows.Count -gt 1) {
        $foregroundHandle = [AgentControlForegroundWindow]::GetForegroundWindow().ToInt64()
        $foregroundMatches = @(
            $matchingWindows | Where-Object {
                [int64]$_.Current.NativeWindowHandle -eq $foregroundHandle
            }
        )
        if ($foregroundMatches.Count -eq 1) {
            return $foregroundMatches[0]
        }
        throw "More than one Codex Desktop window proved the exact workspace '$expectedPath', and the foreground window was not uniquely identifiable; refusing synthetic input."
    }
    if ($matchingWindows.Count -eq 1) { return $matchingWindows[0] }
    return $null
}

function Assert-CodexInputTarget {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$ExpectedWorkspace,
        [Parameter(Mandatory = $true)]$Target
    )

    try {
        $liveWindow = [System.Windows.Automation.AutomationElement]::FromHandle(
            [IntPtr]$Window.Current.NativeWindowHandle
        )
    } catch {
        $liveWindow = $null
    }
    if ($null -eq $liveWindow -or
        $liveWindow.Current.ProcessId -le 0 -or
        $liveWindow.Current.ClassName -ne 'Chrome_WidgetWin_1') {
        throw "Codex Desktop no longer proves the original workspace window '$ExpectedWorkspace'; refusing synthetic input."
    }

    $current = $Target
    $belongsToWindow = $false
    while ($null -ne $current) {
        if (Test-AutomationElementEqual -Left $current -Right $Window) {
            $belongsToWindow = $true
            break
        }
        try {
            $current = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($current)
        } catch {
            $current = $null
        }
    }
    if (-not $belongsToWindow) {
        throw "The focused Codex control is not inside the uniquely verified workspace window '$ExpectedWorkspace'."
    }

    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    if ($null -eq $focused -or -not (Test-AutomationElementEqual -Left $Target -Right $focused)) {
        throw "The intended Codex control is not focused for workspace '$ExpectedWorkspace'."
    }
    return $liveWindow
}

function Wait-Until([scriptblock]$Action, [int]$Seconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $result = & $Action
        if ($null -ne $result) { return $result }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Confirm-SessionWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$SessionPath,
        [Parameter(Mandatory = $true)][string]$ExpectedWorkspace
    )

    $firstRecord = Get-Content -LiteralPath $SessionPath -TotalCount 1 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $actualWorkspace = [string]$firstRecord.payload.cwd
    if ([string]::IsNullOrWhiteSpace($actualWorkspace)) {
        throw "Codex session did not record its workspace for task $TaskId."
    }
    $expectedFullPath = ConvertTo-NormalizedWorkspacePath -Path $ExpectedWorkspace
    $actualFullPath = ConvertTo-NormalizedWorkspacePath -Path $actualWorkspace
    if (-not $actualFullPath.Equals($expectedFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Codex session workspace did not match the requested task workspace: expected '$expectedFullPath', recorded '$actualFullPath'."
    }
    return $actualFullPath
}

function Find-CodexButton {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $nameCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $Name
    )
    $matches = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCondition)
    foreach ($candidate in $matches) {
        if ($candidate.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
            return $candidate
        }
    }
    return $null
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Test-ByteArrayEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Left,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function New-ConfigRestoreJournal {
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$OriginalBytes
    )

    if (Test-Path -LiteralPath $JournalPath) {
        throw "A config restore journal still exists after recovery: $JournalPath"
    }
    $journal = [pscustomobject]@{
        version = 1
        configPath = [System.IO.Path]::GetFullPath($ConfigPath)
        sha256 = Get-ByteArraySha256 -Bytes $OriginalBytes
        originalBytes = [Convert]::ToBase64String($OriginalBytes)
    }
    $journalTempPath = "$JournalPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($journalTempPath, ($journal | ConvertTo-Json -Compress), $utf8WithoutBom)
        $journalStream = [System.IO.File]::Open(
            $journalTempPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $journalStream.Flush($true)
        } finally {
            $journalStream.Dispose()
        }
        [System.IO.File]::Move($journalTempPath, $JournalPath)
    } finally {
        if (Test-Path -LiteralPath $journalTempPath) {
            Remove-Item -LiteralPath $journalTempPath -Force
        }
    }
}

function Restore-ConfigFromJournal {
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $JournalPath)) { return $false }
    $journal = Get-Content -LiteralPath $JournalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$journal.version -ne 1) {
        throw "Unsupported config restore journal version in '$JournalPath'."
    }
    $expectedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
    $journalConfigPath = [System.IO.Path]::GetFullPath([string]$journal.configPath)
    if (-not $journalConfigPath.Equals($expectedConfigPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Config restore journal targeted '$journalConfigPath', not '$expectedConfigPath'."
    }
    try {
        $originalBytes = [Convert]::FromBase64String([string]$journal.originalBytes)
    } catch {
        throw "Config restore journal '$JournalPath' did not contain valid original bytes."
    }
    $actualHash = Get-ByteArraySha256 -Bytes $originalBytes
    if (-not $actualHash.Equals([string]$journal.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Config restore journal '$JournalPath' failed its original-byte hash check."
    }

    $restoreTempPath = "$ConfigPath.agent-control.$PID.$([Guid]::NewGuid().ToString('N')).restore"
    $replaceBackupPath = "$ConfigPath.agent-control.restore.backup"
    try {
        [System.IO.File]::WriteAllBytes($restoreTempPath, $originalBytes)
        $restoreStream = [System.IO.File]::Open(
            $restoreTempPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $restoreStream.Flush($true)
        } finally {
            $restoreStream.Dispose()
        }
        if (Test-Path -LiteralPath $ConfigPath) {
            if (Test-Path -LiteralPath $replaceBackupPath) {
                Remove-Item -LiteralPath $replaceBackupPath -Force
            }
            [System.IO.File]::Replace($restoreTempPath, $ConfigPath, $replaceBackupPath, $true)
        } else {
            [System.IO.File]::Move($restoreTempPath, $ConfigPath)
        }
        $restoredBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
        if (-not (Test-ByteArrayEqual -Left $originalBytes -Right $restoredBytes)) {
            throw "Config restoration verification failed for '$ConfigPath'; journal retained at '$JournalPath'."
        }
        if (Test-Path -LiteralPath $replaceBackupPath) {
            Remove-Item -LiteralPath $replaceBackupPath -Force
        }
        Remove-Item -LiteralPath $JournalPath -Force
        return $true
    } finally {
        if (Test-Path -LiteralPath $restoreTempPath) {
            Remove-Item -LiteralPath $restoreTempPath -Force
        }
    }
}

function Get-StreamBytes {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

    if (-not $Stream.CanRead -or -not $Stream.CanSeek) {
        throw 'Clipboard stream cannot be read and rewound for verification.'
    }
    $originalPosition = $Stream.Position
    $memory = New-Object System.IO.MemoryStream
    try {
        $Stream.Position = 0
        $Stream.CopyTo($memory)
        return $memory.ToArray()
    } finally {
        $Stream.Position = $originalPosition
        $memory.Dispose()
    }
}

function Get-ImageBytes {
    param([Parameter(Mandatory = $true)][System.Drawing.Image]$Image)

    $memory = New-Object System.IO.MemoryStream
    try {
        $Image.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
        return $memory.ToArray()
    } finally {
        $memory.Dispose()
    }
}

function Test-ClipboardValueEqual {
    param($Left, $Right)

    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [System.Array] -or $Right -is [System.Array]) {
        if ($Left -isnot [System.Array] -or $Right -isnot [System.Array]) { return $false }
        if ($Left.Length -ne $Right.Length) { return $false }
        for ($index = 0; $index -lt $Left.Length; $index++) {
            if (-not (Test-ClipboardValueEqual -Left $Left.GetValue($index) -Right $Right.GetValue($index))) {
                return $false
            }
        }
        return $true
    }
    if ($Left -is [System.IO.Stream] -or $Right -is [System.IO.Stream]) {
        if ($Left -isnot [System.IO.Stream] -or $Right -isnot [System.IO.Stream]) { return $false }
        $leftBytes = @(Get-StreamBytes -Stream $Left)
        $rightBytes = @(Get-StreamBytes -Stream $Right)
        return Test-ByteArrayEqual -Left $leftBytes -Right $rightBytes
    }
    if ($Left -is [System.Drawing.Image] -or $Right -is [System.Drawing.Image]) {
        if ($Left -isnot [System.Drawing.Image] -or $Right -isnot [System.Drawing.Image]) { return $false }
        $leftBytes = @(Get-ImageBytes -Image $Left)
        $rightBytes = @(Get-ImageBytes -Image $Right)
        return Test-ByteArrayEqual -Left $leftBytes -Right $rightBytes
    }
    if ($Left.GetType() -ne $Right.GetType()) { return $false }
    return $Left.Equals($Right)
}

function New-ClipboardSnapshot {
    $source = [System.Windows.Forms.Clipboard]::GetDataObject()
    $dataObject = [System.Windows.Forms.DataObject]::new()
    $values = @{}
    $formats = @()
    if ($null -ne $source) {
        $formats = @($source.GetFormats($true) | Sort-Object -Unique)
        foreach ($format in $formats) {
            try {
                if (-not $source.GetDataPresent($format, $true)) {
                    throw 'The source reported the format but could not render it.'
                }
                $value = $source.GetData($format, $true)
                if ($null -eq $value) {
                    throw 'The source rendered a null value.'
                }
                $dataObject.SetData($format, $false, $value)
                if (-not $dataObject.GetDataPresent($format, $false)) {
                    throw 'The materialized DataObject did not retain the format.'
                }
                $materializedValue = $dataObject.GetData($format, $false)
                if ($null -eq $materializedValue) {
                    throw 'The materialized DataObject retained a null value.'
                }
                if (-not (Test-ClipboardValueEqual -Left $value -Right $materializedValue)) {
                    throw 'The materialized DataObject changed the format value.'
                }
                $values[$format] = $materializedValue
            } catch {
                throw "Clipboard format '$format' could not be materialized: $($_.Exception.Message)"
            }
        }
    }
    return [pscustomobject]@{
        DataObject = $dataObject
        Formats = [string[]]$formats
        Values = $values
    }
}

function Assert-ClipboardSnapshotRestored {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $restored = [System.Windows.Forms.Clipboard]::GetDataObject()
    $actualFormats = if ($null -eq $restored) { @() } else { @($restored.GetFormats($true) | Sort-Object -Unique) }
    $expectedFormats = @($Snapshot.Formats)
    if ($actualFormats.Count -ne $expectedFormats.Count) {
        throw "Clipboard restoration verification failed: expected $($expectedFormats.Count) formats, found $($actualFormats.Count)."
    }
    foreach ($format in $expectedFormats) {
        $formatFound = $false
        foreach ($actualFormat in $actualFormats) {
            if ([string]::Equals($format, $actualFormat, [System.StringComparison]::Ordinal)) {
                $formatFound = $true
                break
            }
        }
        if (-not $formatFound -or $null -eq $restored -or -not $restored.GetDataPresent($format, $true)) {
            throw "Clipboard restoration verification failed: format '$format' is missing."
        }
        try {
            $actualValue = $restored.GetData($format, $true)
            $expectedValue = $Snapshot.Values[$format]
            if (-not (Test-ClipboardValueEqual -Left $expectedValue -Right $actualValue)) {
                throw 'The restored value differs from the captured value.'
            }
        } catch {
            throw "Clipboard restoration verification failed for format '$format': $($_.Exception.Message)"
        }
    }
    return $true
}

function Restore-ClipboardSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (@($Snapshot.Formats).Count -eq 0) {
        [System.Windows.Forms.Clipboard]::Clear()
    } else {
        [System.Windows.Forms.Clipboard]::SetDataObject($Snapshot.DataObject, $true)
    }
    Start-Sleep -Milliseconds 100
    Assert-ClipboardSnapshotRestored -Snapshot $Snapshot | Out-Null
}

$workspacePath = ConvertTo-NormalizedWorkspacePath -Path $Workspace
$codexCommand = (Get-Command codex.cmd -ErrorAction Stop).Source
$configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
$configRestoreJournalPath = "$configPath.agent-control.restore.json"
$launchMutex = [System.Threading.Mutex]::new($false, 'Local\AgentControlCodexLaunchSettings')
$mutexHeld = $false
$newSessionId = $null
try {
    try {
        $mutexHeld = $launchMutex.WaitOne([TimeSpan]::FromSeconds(90))
    } catch [System.Threading.AbandonedMutexException] {
        $mutexHeld = $true
    }
    if (-not $mutexHeld) { throw 'Timed out waiting for the Agent Control exact-settings launch lock.' }

    Restore-ConfigFromJournal -JournalPath $configRestoreJournalPath -ConfigPath $configPath | Out-Null
    $originalConfigBytes = [System.IO.File]::ReadAllBytes($configPath)
    $selectedModel = [Environment]::GetEnvironmentVariable('AGENT_CONTROL_TASK_MODEL')
    $selectedEffort = [Environment]::GetEnvironmentVariable('AGENT_CONTROL_TASK_EFFORT')
    $requestedModel = Resolve-RequestedSessionSetting -Selection $selectedModel -ConfigName 'model'
    $requestedEffort = Resolve-RequestedSessionSetting -Selection $selectedEffort -ConfigName 'model_reasoning_effort'

    # Codex Desktop can already be running, in which case `codex app -c ...`
    # opens the workspace but the existing process may read root config for the
    # new task. Hold a cross-process lock and pin both surfaces to the same
    # exact pair until the new JSONL proves what the native session recorded.
    New-ConfigRestoreJournal -JournalPath $configRestoreJournalPath -ConfigPath $configPath -OriginalBytes $originalConfigBytes
    Set-CodexTopLevelSetting -ConfigPath $configPath -Name 'model' -Value $requestedModel
    Set-CodexTopLevelSetting -ConfigPath $configPath -Name 'model_reasoning_effort' -Value $requestedEffort
    $launchArguments = @('app')
    $launchArguments += @('-c', "model=`"$requestedModel`"")
    $launchArguments += @('-c', "model_reasoning_effort=`"$requestedEffort`"")
    $launchArguments += $workspacePath
    Start-Process -FilePath $codexCommand -ArgumentList $launchArguments -WindowStyle Hidden
    $window = Wait-Until { Get-CodexWindowForWorkspace -ExpectedWorkspace $workspacePath } 30
    if ($null -eq $window) { throw "Codex Desktop did not open the required workspace: $workspacePath" }

    $newTask = Wait-Until { Find-CodexButton -Window $window -Name 'New task' } 10
    if ($null -eq $newTask) { throw 'Codex Desktop New task control was not available.' }
    $newTask.SetFocus()
    Assert-CodexInputTarget -Window $window -ExpectedWorkspace $workspacePath -Target $newTask | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

    $composer = Wait-Until {
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $focused -and $focused.Current.ClassName -like 'ProseMirror*') { $focused } else { $null }
    } 10
    if ($null -eq $composer) { throw 'Codex Desktop composer did not receive focus.' }

    $clipboardSnapshot = New-ClipboardSnapshot
    try {
        $composer.SetFocus()
        Assert-CodexInputTarget -Window $window -ExpectedWorkspace $workspacePath -Target $composer | Out-Null
        [System.Windows.Forms.Clipboard]::SetText($prompt)
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 350
        Assert-CodexInputTarget -Window $window -ExpectedWorkspace $workspacePath -Target $composer | Out-Null
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    } finally {
        Start-Sleep -Milliseconds 500
        Restore-ClipboardSnapshot -Snapshot $clipboardSnapshot
    }

    $newSession = Wait-Until {
        $candidates = Get-ChildItem -LiteralPath $sessionsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$' -and
                -not $knownSessionIds.ContainsKey($Matches[1])
            }
        foreach ($candidate in $candidates) {
            if (Select-String -LiteralPath $candidate.FullName -Pattern $marker -SimpleMatch -Quiet) {
                $firstRecord = Get-Content -LiteralPath $candidate.FullName -TotalCount 1 | ConvertFrom-Json
                if ($firstRecord.type -eq 'session_meta' -and $firstRecord.payload.id) {
                    return [pscustomobject]@{
                        Id = [string]$firstRecord.payload.id
                        Path = $candidate.FullName
                    }
                }
            }
        }
        return $null
    } 30
    if ($null -eq $newSession -or [string]::IsNullOrWhiteSpace([string]$newSession.Id)) {
        throw "Codex submitted the prompt but its new persistent session could not be identified ($marker)."
    }
    $newSessionId = [string]$newSession.Id
    $sessionPath = [string]$newSession.Path
    Confirm-SessionWorkspace -SessionPath $sessionPath -ExpectedWorkspace $workspacePath | Out-Null

    $pinPersisted = Wait-Until {
        $saved = Get-Content -LiteralPath $pinStatePath -Raw | ConvertFrom-Json
        if (@($saved.'pinned-thread-ids') -contains $newSessionId) { return $true }
        return $null
    } 30
    if ($pinPersisted -ne $true) { throw "The new Codex session did not complete its native pin action ($newSessionId)." }
    Start-Sleep -Seconds 3
    $confirmedState = Get-Content -LiteralPath $pinStatePath -Raw | ConvertFrom-Json
    if (@($confirmedState.'pinned-thread-ids') -notcontains $newSessionId) {
        throw "Codex did not retain native pin state for session $newSessionId."
    }

    $verifiedSettings = Wait-Until {
        Confirm-RequestedSessionSettings -SessionPath $sessionPath -ExpectedModel $requestedModel -ExpectedEffort $requestedEffort
    } 30
    if ($null -eq $verifiedSettings) {
        throw "Codex session '$newSessionId' did not record its model/effort settings within 30 seconds."
    }

    [pscustomobject]@{
        accepted = $true
        marker = $marker
        sessionId = $newSessionId
        title = $title
        pinned = $true
        selectedModel = $selectedModel.Trim().ToLowerInvariant()
        selectedEffort = $selectedEffort.Trim().ToLowerInvariant()
        expectedModel = $requestedModel
        expectedEffort = $requestedEffort
        model = $verifiedSettings.model
        effort = $verifiedSettings.effort
    } | ConvertTo-Json -Compress
} catch {
    if (-not [string]::IsNullOrWhiteSpace([string]$newSessionId)) {
        [pscustomobject]@{
            accepted = $false
            sessionOpened = $true
            sessionId = $newSessionId
            error = $_.Exception.Message
        } | ConvertTo-Json -Compress
    }
    throw
} finally {
    try {
        if ($mutexHeld) {
            Restore-ConfigFromJournal -JournalPath $configRestoreJournalPath -ConfigPath $configPath | Out-Null
        }
    } finally {
        if ($mutexHeld) {
            $launchMutex.ReleaseMutex()
        }
        $launchMutex.Dispose()
    }
}
