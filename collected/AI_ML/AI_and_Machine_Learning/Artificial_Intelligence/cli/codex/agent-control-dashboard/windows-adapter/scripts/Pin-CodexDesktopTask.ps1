param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SessionId
)

$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
    throw 'Pin-CodexDesktopTask.ps1 requires Windows PowerShell 5.1 with -STA.'
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class AgentControlCodexWindow {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@

function Wait-For {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Condition,

        [Parameter(Mandatory = $true)]
        [int]$Milliseconds,

        [int]$IntervalMilliseconds = 100
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    do {
        $result = @(& $Condition)
        if ($result.Count -gt 0 -and [bool]$result[$result.Count - 1]) {
            return $true
        }
        Start-Sleep -Milliseconds $IntervalMilliseconds
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Get-ArgumentFreePackagedDesktopProcess {
    $matches = @(
        Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                $remaining = $commandLine -replace '^\s*"[^"]+"\s*', ''
                [string]::IsNullOrWhiteSpace($remaining) -and
                [string]$_.ExecutablePath -like '*\OpenAI.Codex_*\app\ChatGPT.exe'
            }
    )
    if ($matches.Count -gt 1) {
        throw "Expected at most one argument-free packaged Codex Desktop process; found $($matches.Count)."
    }
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function Start-CodexDesktopIfNeeded {
    $existing = Get-ArgumentFreePackagedDesktopProcess
    if ($null -ne $existing) {
        return [pscustomobject]@{ Process = $existing; Launched = $false }
    }

    $packages = @(
        Get-AppxPackage -Name 'OpenAI.Codex' |
            Where-Object { -not $_.IsFramework } |
            Sort-Object Version -Descending
    )
    if ($packages.Count -ne 1) {
        throw "Expected exactly one installed OpenAI.Codex package; found $($packages.Count)."
    }
    $executable = Join-Path ([string]$packages[0].InstallLocation) 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "The packaged Codex Desktop executable was not found at '$executable'."
    }

    Start-Process -FilePath $executable | Out-Null
    $state = [pscustomobject]@{ Process = $null }
    $started = Wait-For -Milliseconds 20000 -Condition {
        [void]($state.Process = Get-ArgumentFreePackagedDesktopProcess)
        return $null -ne $state.Process
    }
    if (-not $started) {
        throw 'Codex Desktop did not start as one argument-free packaged process.'
    }
    return [pscustomobject]@{ Process = $state.Process; Launched = $true }
}

function Get-VisibleTopLevelWindows {
    param(
        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId
    )

    $handles = [System.Collections.Generic.List[System.IntPtr]]::new()
    $callback = [AgentControlCodexWindow+EnumWindowsProc]{
        param([IntPtr]$windowHandle, [IntPtr]$unused)

        if (-not [AgentControlCodexWindow]::IsWindowVisible($windowHandle)) {
            return $true
        }
        [uint32]$processId = 0
        [void][AgentControlCodexWindow]::GetWindowThreadProcessId($windowHandle, [ref]$processId)
        if ($processId -eq $OwnerProcessId) {
            $handles.Add($windowHandle)
        }
        return $true
    }
    [void][AgentControlCodexWindow]::EnumWindows($callback, [IntPtr]::Zero)
    return @($handles)
}

function Get-AutomationRoot {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle
    )

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    if ($null -eq $root) {
        throw "UI Automation could not inspect window handle $([int64]$WindowHandle)."
    }
    return $root
}

function Test-RuntimeIdEqual {
    param([int[]]$Left, [int[]]$Right)

    if ($null -eq $Left -or $null -eq $Right -or $Left.Count -ne $Right.Count) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Test-AutomationElementWithinWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element,

        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$WindowRoot
    )

    try {
        $rootRuntimeId = @($WindowRoot.GetRuntimeId())
        $current = $Element
        while ($null -ne $current) {
            if (Test-RuntimeIdEqual -Left @($current.GetRuntimeId()) -Right $rootRuntimeId) {
                return $true
            }
            $current = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($current)
        }
    } catch {
        return $false
    }
    return $false
}

function Get-VisibleExactElementsByName {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$SearchRoot,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$WindowRoot,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId,

        [switch]$MenuItemOnly
    )

    $found = @()
    foreach ($element in $SearchRoot.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )) {
        try {
            $displayName = [string]$element.Current.Name
            $withShortcut = '^{0}\s+(?:Ctrl|Alt|Shift|Win)(?:\+(?:Ctrl|Alt|Shift|Win|[A-Z0-9]))+$' -f
                [regex]::Escape($Name)
            if (
                (-not $displayName.Equals($Name, [StringComparison]::OrdinalIgnoreCase) -and
                    $displayName -notmatch $withShortcut) -or
                $element.Current.IsOffscreen -or
                $element.Current.ProcessId -ne $OwnerProcessId -or
                ($MenuItemOnly -and
                    $element.Current.ControlType -ne [System.Windows.Automation.ControlType]::MenuItem) -or
                (-not (Test-AutomationElementWithinWindow -Element $element -WindowRoot $WindowRoot))
            ) {
                continue
            }
            $found += $element
        } catch {
            # Renderer nodes can disappear while a native menu is closing.
        }
    }
    return @($found)
}

function Get-UniqueVisibleExactElement {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$SearchRoot,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$WindowRoot,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId,

        [switch]$MenuItemOnly
    )

    $found = @(
        Get-VisibleExactElementsByName `
            -SearchRoot $SearchRoot `
            -Name $Name `
            -WindowRoot $WindowRoot `
            -OwnerProcessId $OwnerProcessId `
            -MenuItemOnly:$MenuItemOnly
    )
    if ($found.Count -eq 0) {
        return $null
    }

    $actionable = @()
    $runtimeIds = @{}
    foreach ($element in $found) {
        $candidate = $element
        for ($depth = 0; $depth -lt 5 -and $null -ne $candidate; $depth++) {
            try {
                $displayName = [string]$candidate.Current.Name
                $withShortcut = '^{0}\s+(?:Ctrl|Alt|Shift|Win)(?:\+(?:Ctrl|Alt|Shift|Win|[A-Z0-9]))+$' -f
                    [regex]::Escape($Name)
                $nameMatches = (
                    $displayName.Equals($Name, [StringComparison]::OrdinalIgnoreCase) -or
                    $displayName -match $withShortcut
                )
                $pattern = $null
                $hasAction = (
                    $candidate.TryGetCurrentPattern(
                        [System.Windows.Automation.InvokePattern]::Pattern,
                        [ref]$pattern
                    ) -or
                    $candidate.TryGetCurrentPattern(
                        [System.Windows.Automation.ExpandCollapsePattern]::Pattern,
                        [ref]$pattern
                    ) -or
                    $candidate.TryGetCurrentPattern(
                        [System.Windows.Automation.SelectionItemPattern]::Pattern,
                        [ref]$pattern
                    )
                )
                if (
                    $nameMatches -and
                    $hasAction -and
                    (
                        -not $MenuItemOnly -or
                        $candidate.Current.ControlType -eq
                            [System.Windows.Automation.ControlType]::MenuItem
                    ) -and
                    (Test-AutomationElementWithinWindow -Element $candidate -WindowRoot $WindowRoot)
                ) {
                    $runtimeKey = @($candidate.GetRuntimeId()) -join ','
                    if (-not $runtimeIds.ContainsKey($runtimeKey)) {
                        $runtimeIds[$runtimeKey] = $true
                        $actionable += $candidate
                    }
                    break
                }
                $candidate = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($candidate)
            } catch {
                break
            }
        }
    }

    if ($actionable.Count -eq 1) {
        return $actionable[0]
    }
    if ($MenuItemOnly) {
        throw "UI Automation found $($actionable.Count) actionable '$Name' menu items in one Desktop window."
    }
    if ($found.Count -ne 1) {
        throw "UI Automation found $($found.Count) visible '$Name' controls in one Desktop window."
    }
    return $found[0]
}

function Set-UiaFocusWithinWindow {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId
    )

    [void][AgentControlCodexWindow]::ShowWindowAsync($WindowHandle, 9)
    [void][AgentControlCodexWindow]::SetForegroundWindow($WindowHandle)
    $root = Get-AutomationRoot -WindowHandle $WindowHandle
    $candidate = $null
    foreach ($name in @('Task actions', 'What should we build?', 'New task')) {
        $candidate = Get-UniqueVisibleExactElement `
            -SearchRoot $root `
            -Name $name `
            -WindowRoot $root `
            -OwnerProcessId $OwnerProcessId
        if ($null -ne $candidate -and $candidate.Current.IsKeyboardFocusable) {
            break
        }
        $candidate = $null
    }
    if ($null -eq $candidate) {
        foreach ($element in $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )) {
            try {
                if (
                    -not $element.Current.IsOffscreen -and
                    $element.Current.IsEnabled -and
                    $element.Current.IsKeyboardFocusable -and
                    $element.Current.ProcessId -eq $OwnerProcessId -and
                    (Test-AutomationElementWithinWindow -Element $element -WindowRoot $root)
                ) {
                    $candidate = $element
                    break
                }
            } catch {
                # Ignore stale renderer nodes.
            }
        }
    }
    if ($null -eq $candidate) {
        throw "The Desktop renderer in window $([int64]$WindowHandle) exposed no unique focus target."
    }

    $candidate.SetFocus()
    $focused = Wait-For -Milliseconds 5000 -Condition {
        try {
            [void]($element = [System.Windows.Automation.AutomationElement]::FocusedElement)
            return (
                $null -ne $element -and
                $element.Current.ProcessId -eq $OwnerProcessId -and
                (Test-AutomationElementWithinWindow -Element $element -WindowRoot $root)
            )
        } catch {
            return $false
        }
    }
    if (-not $focused) {
        throw "UI Automation could not prove renderer focus in window $([int64]$WindowHandle)."
    }
}

function Invoke-AutomationElement {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element
    )

    $candidate = $Element
    for ($depth = 0; $depth -lt 4 -and $null -ne $candidate; $depth++) {
        $pattern = $null
        if ($candidate.TryGetCurrentPattern(
            [System.Windows.Automation.InvokePattern]::Pattern,
            [ref]$pattern
        )) {
            ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
            return
        }
        if ($candidate.TryGetCurrentPattern(
            [System.Windows.Automation.ExpandCollapsePattern]::Pattern,
            [ref]$pattern
        )) {
            ([System.Windows.Automation.ExpandCollapsePattern]$pattern).Expand()
            return
        }
        if ($candidate.TryGetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern,
            [ref]$pattern
        )) {
            ([System.Windows.Automation.SelectionItemPattern]$pattern).Select()
            return
        }
        $candidate = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($candidate)
    }
    throw "UI Automation element '$($Element.Current.Name)' has no invokable pattern."
}

function Close-ExpandedControl {
    param([System.Windows.Automation.AutomationElement]$Element)

    if ($null -eq $Element) {
        return
    }
    $pattern = $null
    if ($Element.TryGetCurrentPattern(
        [System.Windows.Automation.ExpandCollapsePattern]::Pattern,
        [ref]$pattern
    )) {
        $pattern = [System.Windows.Automation.ExpandCollapsePattern]$pattern
        if (
            $pattern.Current.ExpandCollapseState -eq
                [System.Windows.Automation.ExpandCollapseState]::Expanded -or
            $pattern.Current.ExpandCollapseState -eq
                [System.Windows.Automation.ExpandCollapseState]::PartiallyExpanded
        ) {
            [void]$pattern.Collapse()
        }
    }
}

function Open-ExactMenuItem {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [string]$ButtonName,

        [Parameter(Mandatory = $true)]
        [string]$ItemName,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId
    )

    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        Set-UiaFocusWithinWindow -WindowHandle $WindowHandle -OwnerProcessId $OwnerProcessId
        $root = Get-AutomationRoot -WindowHandle $WindowHandle
        $button = Get-UniqueVisibleExactElement `
            -SearchRoot $root `
            -Name $ButtonName `
            -WindowRoot $root `
            -OwnerProcessId $OwnerProcessId
        if ($null -eq $button) {
            Start-Sleep -Milliseconds 250
            continue
        }
        Close-ExpandedControl -Element $button
        Invoke-AutomationElement -Element $button

        $state = [pscustomobject]@{ Item = $null }
        $found = Wait-For -Milliseconds 3000 -Condition {
            [void]($state.Item = Get-UniqueVisibleExactElement `
                    -SearchRoot $root `
                    -Name $ItemName `
                    -WindowRoot $root `
                    -OwnerProcessId $OwnerProcessId `
                    -MenuItemOnly)
            return $null -ne $state.Item
        }
        if ($found) {
            return $state.Item
        }
        Close-ExpandedControl -Element $button
    }
    throw "The native '$ItemName' action did not appear under '$ButtonName'."
}

function Get-TaskAction {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [string]$ItemName,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId
    )

    if ($ItemName -ne 'Copy Session ID') {
        return Open-ExactMenuItem `
            -WindowHandle $WindowHandle `
            -ButtonName 'Task actions' `
            -ItemName $ItemName `
            -OwnerProcessId $OwnerProcessId
    }

    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        Set-UiaFocusWithinWindow -WindowHandle $WindowHandle -OwnerProcessId $OwnerProcessId
        $root = Get-AutomationRoot -WindowHandle $WindowHandle
        $taskActions = Get-UniqueVisibleExactElement `
            -SearchRoot $root `
            -Name 'Task actions' `
            -WindowRoot $root `
            -OwnerProcessId $OwnerProcessId
        if ($null -eq $taskActions) {
            return $null
        }
        Close-ExpandedControl -Element $taskActions
        Invoke-AutomationElement -Element $taskActions

        $copySessionId = Get-UniqueVisibleExactElement `
            -SearchRoot $root `
            -Name 'Copy Session ID' `
            -WindowRoot $root `
            -OwnerProcessId $OwnerProcessId `
            -MenuItemOnly
        if ($null -ne $copySessionId) {
            return $copySessionId
        }
        $copy = Get-UniqueVisibleExactElement `
            -SearchRoot $root `
            -Name 'Copy' `
            -WindowRoot $root `
            -OwnerProcessId $OwnerProcessId `
            -MenuItemOnly
        if ($null -ne $copy) {
            Invoke-AutomationElement -Element $copy
            $state = [pscustomobject]@{ Item = $null }
            $found = Wait-For -Milliseconds 3000 -Condition {
                [void]($state.Item = Get-UniqueVisibleExactElement `
                        -SearchRoot $root `
                        -Name 'Copy Session ID' `
                        -WindowRoot $root `
                        -OwnerProcessId $OwnerProcessId `
                        -MenuItemOnly)
                return $null -ne $state.Item
            }
            if ($found) {
                return $state.Item
            }
        }
        Close-ExpandedControl -Element $taskActions
    }
    throw "The native 'Copy Session ID' action did not appear."
}

function Get-ExactSessionIdFromWindow {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$WindowHandle,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId
    )

    $probe = "agent-control-route-probe-$([Guid]::NewGuid().ToString('N'))"
    [System.Windows.Forms.Clipboard]::SetText($probe)
    $copySessionId = Get-TaskAction `
        -WindowHandle $WindowHandle `
        -ItemName 'Copy Session ID' `
        -OwnerProcessId $OwnerProcessId
    if ($null -eq $copySessionId) {
        return $null
    }
    Invoke-AutomationElement -Element $copySessionId

    $state = [pscustomobject]@{ Value = $probe }
    $copied = Wait-For -Milliseconds 5000 -Condition {
        try {
            [void]($state.Value = [System.Windows.Forms.Clipboard]::GetText())
            return $state.Value -ne $probe
        } catch {
            return $false
        }
    }
    if (-not $copied -or $state.Value -notmatch '^[0-9a-fA-F-]{36}$') {
        throw "Window $([int64]$WindowHandle) did not expose an exact native session ID."
    }
    return [string]$state.Value
}

function New-IsolatedDesktopWindow {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$SourceHandle,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [IntPtr[]]$ExistingHandles,

        [Parameter(Mandatory = $true)]
        [int]$OwnerProcessId,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$candidateState
    )

    $newWindow = Open-ExactMenuItem `
        -WindowHandle $SourceHandle `
        -ButtonName 'File' `
        -ItemName 'New Window' `
        -OwnerProcessId $OwnerProcessId
    Invoke-AutomationElement -Element $newWindow

    $created = Wait-For -Milliseconds 15000 -IntervalMilliseconds 150 -Condition {
        $current = @(Get-VisibleTopLevelWindows -OwnerProcessId $OwnerProcessId)
        $newHandles = @($current | Where-Object { $ExistingHandles -notcontains $_ })
        $candidateState.ObservedNewHandles = @($newHandles)
        $candidateState.NewHandles = @($newHandles)
        if ($candidateState.NewHandles.Count -ne 1) {
            $candidateState.Handle = [IntPtr]::Zero
            $candidateState.StableSince = [DateTime]::MinValue
            return $false
        }

        $candidate = [IntPtr]$candidateState.NewHandles[0]
        if ($candidateState.Handle -ne $candidate) {
            $candidateState.Handle = $candidate
            $candidateState.StableSince = [DateTime]::UtcNow
            return $false
        }
        return ([DateTime]::UtcNow - $candidateState.StableSince).TotalMilliseconds -ge 500
    }
    if (-not $created) {
        throw "Desktop did not create exactly one isolated helper window; found $($candidateState.ObservedNewHandles.Count)."
    }
    return [IntPtr]$candidateState.Handle
}

function Copy-ClipboardValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.IO.Stream]) {
        $position = if ($Value.CanSeek) { $Value.Position } else { 0 }
        $copy = [System.IO.MemoryStream]::new()
        if ($Value.CanSeek) { $Value.Position = 0 }
        $Value.CopyTo($copy)
        if ($Value.CanSeek) { $Value.Position = $position }
        $copy.Position = 0
        return $copy
    }
    if ($Value -is [System.Drawing.Image]) {
        return $Value.Clone()
    }
    if ($Value -is [System.Collections.Specialized.StringCollection]) {
        $copy = [System.Collections.Specialized.StringCollection]::new()
        [void]$copy.AddRange([string[]]@($Value))
        return $copy
    }
    if ($Value -is [byte[]]) {
        return [byte[]]$Value.Clone()
    }
    return $Value
}

function Get-ClipboardValueFingerprint {
    param($Value)

    if ($null -eq $Value) {
        return 'null'
    }
    $typeName = $Value.GetType().AssemblyQualifiedName
    if ($Value -is [System.IO.Stream]) {
        $position = if ($Value.CanSeek) { $Value.Position } else { 0 }
        $memory = [System.IO.MemoryStream]::new()
        if ($Value.CanSeek) { $Value.Position = 0 }
        $Value.CopyTo($memory)
        if ($Value.CanSeek) { $Value.Position = $position }
        $bytes = $memory.ToArray()
        $memory.Dispose()
    } elseif ($Value -is [System.Drawing.Image]) {
        $memory = [System.IO.MemoryStream]::new()
        $Value.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $memory.ToArray()
        $memory.Dispose()
    } elseif ($Value -is [byte[]]) {
        $bytes = $Value
    } elseif ($Value -is [System.Collections.Specialized.StringCollection] -or $Value -is [string[]]) {
        $bytes = [Text.Encoding]::UTF8.GetBytes((@($Value) -join [char]0))
    } else {
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Value)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return "$typeName|$([Convert]::ToBase64String($sha.ComputeHash($bytes)))"
    } finally {
        $sha.Dispose()
    }
}

function Copy-ClipboardDataObject {
    $source = [System.Windows.Forms.Clipboard]::GetDataObject()
    $snapshot = [System.Windows.Forms.DataObject]::new()
    $formats = @()
    $fingerprints = @{}
    if ($null -ne $source) {
        $formats = @($source.GetFormats($true))
        foreach ($format in $formats) {
            try {
                $value = Copy-ClipboardValue -Value $source.GetData($format, $true)
                $snapshot.SetData($format, $value)
                $fingerprints[$format] = Get-ClipboardValueFingerprint -Value $value
            } catch {
                throw "Clipboard format '$format' could not be materialized: $($_.Exception.Message)"
            }
        }
    }
    return [pscustomobject]@{
        DataObject = $snapshot
        Formats = $formats
        Fingerprints = $fingerprints
    }
}

function Restore-ClipboardDataObject {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.DataObject]$DataObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Formats,

        [Parameter(Mandatory = $true)]
        [hashtable]$Fingerprints
    )

    [System.Windows.Forms.Clipboard]::SetDataObject($DataObject, $true)
    $restored = Wait-For -Milliseconds 5000 -Condition {
        try {
            [void]($current = [System.Windows.Forms.Clipboard]::GetDataObject())
            if ($null -eq $current) {
                return $Formats.Count -eq 0
            }
            [void]($currentFormats = @($current.GetFormats($true)))
            if ($currentFormats.Count -ne $Formats.Count) {
                return $false
            }
            foreach ($format in $Formats) {
                if (
                    $currentFormats -notcontains $format -or
                    (Get-ClipboardValueFingerprint -Value $current.GetData($format, $true)) -cne
                        [string]$Fingerprints[$format]
                ) {
                    return $false
                }
            }
            return $true
        } catch {
            return $false
        }
    }
    if (-not $restored) {
        throw 'The complete clipboard data object could not be restored and verified.'
    }
}

function Test-SessionPinnedEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ThreadId
    )

    $statePath = Join-Path $env:USERPROFILE '.codex\.codex-global-state.json'
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($state.'pinned-thread-ids') -contains $ThreadId) {
            return $true
        }
        return @($state.'electron-persisted-atom-state'.pinnedThreadIds) -contains $ThreadId
    } catch {
        return $false
    }
}

$desktopState = Start-CodexDesktopIfNeeded
$desktop = $desktopState.Process
$desktopProcessId = [int]$desktop.ProcessId
$windowState = [pscustomobject]@{ Handles = @() }
$windowsReady = Wait-For -Milliseconds 20000 -Condition {
    [void]($windowState.Handles = @(Get-VisibleTopLevelWindows -OwnerProcessId $desktopProcessId))
    return $windowState.Handles.Count -gt 0
}
if (-not $windowsReady) {
    throw 'Codex Desktop did not expose a visible native window.'
}

$existingHandles = @($windowState.Handles)
$clipboard = Copy-ClipboardDataObject
$helperHandle = [IntPtr]::Zero
$helperCreationState = [pscustomobject]@{
    Handle = [IntPtr]::Zero
    StableSince = [DateTime]::MinValue
    NewHandles = @()
    ObservedNewHandles = @()
}
$operationError = $null

try {
    if ($desktopState.Launched) {
        if ($existingHandles.Count -ne 1) {
            throw "Freshly started Desktop exposed $($existingHandles.Count) windows; expected exactly one helper window."
        }
        $helperHandle = [IntPtr]$existingHandles[0]
        $helperCreationState.Handle = $helperHandle
        $helperCreationState.ObservedNewHandles = @($helperHandle)
    } else {
        $helperHandle = New-IsolatedDesktopWindow `
            -SourceHandle ([IntPtr]$existingHandles[0]) `
            -ExistingHandles $existingHandles `
            -OwnerProcessId $desktopProcessId `
            -candidateState $helperCreationState
    }

    Set-UiaFocusWithinWindow -WindowHandle $helperHandle -OwnerProcessId $desktopProcessId
    Start-Process -FilePath "codex://threads/$SessionId" | Out-Null

    $routeState = [pscustomobject]@{ SessionId = $null }
    $routed = Wait-For -Milliseconds 30000 -IntervalMilliseconds 250 -Condition {
        try {
            [void]($routeState.SessionId = Get-ExactSessionIdFromWindow `
                    -WindowHandle $helperHandle `
                    -OwnerProcessId $desktopProcessId)
            return $routeState.SessionId -ceq $SessionId
        } catch {
            return $false
        }
    }
    if (-not $routed) {
        throw "Desktop did not route exact session '$SessionId' into the isolated helper window."
    }

    try {
        [void](Get-TaskAction `
                -WindowHandle $helperHandle `
                -ItemName 'Unpin task' `
                -OwnerProcessId $desktopProcessId)
    } catch {
        $pinAction = Get-TaskAction `
            -WindowHandle $helperHandle `
            -ItemName 'Pin task' `
            -OwnerProcessId $desktopProcessId
        Invoke-AutomationElement -Element $pinAction
    }

    $stateConfirmed = Wait-For -Milliseconds 10000 -Condition {
        Test-SessionPinnedEvidence -ThreadId $SessionId
    }
    if (-not $stateConfirmed) {
        throw 'Codex Desktop did not flush read-only evidence after the native pin action.'
    }
    [void](Get-TaskAction `
            -WindowHandle $helperHandle `
            -ItemName 'Unpin task' `
            -OwnerProcessId $desktopProcessId)

    [ordered]@{
        sessionId = $SessionId
        routeVerified = $true
        pinned = $true
    } | ConvertTo-Json -Compress
} catch {
    $operationError = $_
    throw
} finally {
    $cleanupError = $null
    try {
        Restore-ClipboardDataObject `
            -DataObject $clipboard.DataObject `
            -Formats @($clipboard.Formats) `
            -Fingerprints $clipboard.Fingerprints
    } catch {
        $cleanupError = $_
    }

    $cleanupHelperHandle = $helperHandle
    if (
        $cleanupHelperHandle -eq [IntPtr]::Zero -and
        $helperCreationState.ObservedNewHandles.Count -eq 1
    ) {
        $cleanupHelperHandle = [IntPtr]$helperCreationState.ObservedNewHandles[0]
    }
    if ($cleanupHelperHandle -ne [IntPtr]::Zero) {
        [void][AgentControlCodexWindow]::PostMessage(
            $cleanupHelperHandle,
            0x0010,
            [IntPtr]::Zero,
            [IntPtr]::Zero
        )
        $closed = Wait-For -Milliseconds 5000 -Condition {
            @(Get-VisibleTopLevelWindows -OwnerProcessId $desktopProcessId) -notcontains $cleanupHelperHandle
        }
        if (-not $closed -and $null -eq $cleanupError) {
            $cleanupError = [InvalidOperationException]::new('The isolated helper window did not close.')
        }
    }

    if ($null -ne $cleanupError -and $null -eq $operationError) {
        throw $cleanupError
    }
}
