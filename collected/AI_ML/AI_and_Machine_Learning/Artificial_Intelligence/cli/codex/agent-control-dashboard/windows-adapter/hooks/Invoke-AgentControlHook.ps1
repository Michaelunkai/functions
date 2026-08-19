param(
    [string]$CredentialRoot = (Join-Path $env:LOCALAPPDATA 'AgentControl')
)

$ErrorActionPreference = "Stop"

# Lifecycle telemetry is non-blocking. Keep concurrent hook bursts from
# competing with Codex Desktop's interactive renderer and app-server.
try {
    $currentProcess = Get-Process -Id $PID -ErrorAction Stop
    if ($currentProcess.PriorityClass -ne "Idle") {
        $currentProcess.PriorityClass = "Idle"
    }
    $processorCount = [Environment]::ProcessorCount
    if ($processorCount -ge 2 -and $processorCount -le 62) {
        $currentProcess.ProcessorAffinity = [IntPtr]([Int64]1 -shl ($processorCount - 1))
    }
} catch {
    # Continue normally when process-priority adjustment is unavailable.
}

function Remove-RedundantAgentControlSessionEndHook {
    $hooksPath = Join-Path $env:USERPROFILE '.codex\hooks.json'
    if (-not (Test-Path -LiteralPath $hooksPath)) {
        return
    }
    try {
        $document = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
        $sessionEnd = @($document.hooks.SessionEnd)
        $filtered = @($sessionEnd | Where-Object {
            $commands = @($_.hooks | ForEach-Object { $_.commandWindows; $_.command_windows; $_.command })
            -not ($commands -match [regex]::Escape('Invoke-AgentControlHook.ps1'))
        })
        if ($filtered.Count -eq $sessionEnd.Count) {
            return
        }
        $document.hooks | Add-Member -NotePropertyName SessionEnd -NotePropertyValue $filtered -Force
        $temporary = "$hooksPath.$PID.tmp"
        [System.IO.File]::WriteAllText(
            $temporary,
            "$($document | ConvertTo-Json -Depth 20)$([Environment]::NewLine)",
            (New-Object System.Text.UTF8Encoding($false))
        )
        Move-Item -LiteralPath $temporary -Destination $hooksPath -Force
    } catch {
        # Dashboard delivery must remain non-blocking if configuration is busy.
    }
}

Remove-RedundantAgentControlSessionEndHook

$credentialScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\AgentControlCredential.ps1'
if (Test-Path -LiteralPath $credentialScript) {
    . $credentialScript
}
$endpointOverride = [Environment]::GetEnvironmentVariable('AgentControl__HookEndpoint')
$fallbackOverride = [Environment]::GetEnvironmentVariable('AgentControl__HookFallbackPath')
$endpoint = "http://127.0.0.1:17867/hooks"
if (-not [string]::IsNullOrWhiteSpace($endpointOverride)) {
    $candidateEndpoint = $null
    if (
        [Uri]::TryCreate($endpointOverride, [UriKind]::Absolute, [ref]$candidateEndpoint) -and
        $candidateEndpoint.Scheme -eq 'http' -and
        @('127.0.0.1', 'localhost') -contains $candidateEndpoint.Host -and
        $candidateEndpoint.AbsolutePath -eq '/hooks' -and
        [string]::IsNullOrEmpty($candidateEndpoint.Query) -and
        [string]::IsNullOrEmpty($candidateEndpoint.Fragment)
    ) {
        $endpoint = $candidateEndpoint.AbsoluteUri
    }
}
$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$fallbackRoot = [System.IO.Path]::GetFullPath((Join-Path $localAppData "AgentControl"))
$fallback = Join-Path $fallbackRoot "hook-fallback.jsonl"
if (-not [string]::IsNullOrWhiteSpace($fallbackOverride)) {
    $candidateFallback = [System.IO.Path]::GetFullPath($fallbackOverride)
    $fallbackPrefix = $fallbackRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    if ($candidateFallback.StartsWith($fallbackPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $fallback = $candidateFallback
    }
}

function Protect-AgentControlText {
    param(
        [AllowEmptyString()][string]$Text,
        [string[]]$SensitiveValues
    )
    $redacted = $Text
    foreach ($sensitiveValue in $SensitiveValues) {
        if (-not [string]::IsNullOrEmpty($sensitiveValue)) {
            $redacted = $redacted.Replace($sensitiveValue, "[REDACTED]")
        }
    }
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)\bAuthorization\s*:\s*Bearer\s+\S+',
        'Authorization: Bearer [REDACTED]'
    )
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+',
        'Bearer [REDACTED]'
    )
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)(\b(?:[A-Za-z0-9]+[_-]?)*?(?:owner[_-]?token|api[_-]?key|access[_-]?(?:token|key)|secret[_-]?access[_-]?key|private[_-]?key|database[_-]?url|connection[_-]?string|credentials?|token|password|passwd|secret)\b["'']?\s*[:=]\s*)(?:(["''])([^\r\n]*?)\2|([^\s"'',;}]+))',
        { param($match) $match.Groups[1].Value + $(if ($match.Groups[2].Success) { $match.Groups[2].Value }) + "[REDACTED]" + $(if ($match.Groups[2].Success) { $match.Groups[2].Value }) }
    )
    $redacted = [regex]::Replace($redacted, '\bsk-(?:proj-)?[A-Za-z0-9_-]{12,}\b', '[REDACTED]')
    if ($redacted.Length -gt 20000) {
        return $redacted.Substring(0, 20000)
    }
    return $redacted
}

function Protect-AgentControlValue {
    param(
        [AllowNull()]$Value,
        [AllowEmptyString()][string]$KeyName,
        [AllowEmptyString()][string]$EventName,
        [string[]]$SensitiveValues
    )
    if ($KeyName -match '^(?i:authorization|(?:[a-z0-9]+[_-]?)*?(?:owner[_-]?token|api[_-]?key|access[_-]?(?:token|key)|secret[_-]?access[_-]?key|private[_-]?key|database[_-]?url|connection[_-]?string|credentials?|token|password|passwd|secret))$') {
        return "[REDACTED]"
    }
    if (
        $EventName -eq 'PostToolUse' -and
        $KeyName -match '^(?i:tool_output|tool_result|output|stdout|stderr)$'
    ) {
        return "Tool completed; detailed output retained only in the native Codex session."
    }
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        if ($KeyName -eq 'cwd') {
            $trimmedPath = $Value.Trim().TrimEnd([char[]]"\/")
            $leaf = ($trimmedPath -split '[\\/]')[-1]
            return $leaf
        }
        return Protect-AgentControlText -Text $Value -SensitiveValues $SensitiveValues
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($entry in $Value.GetEnumerator()) {
            $childKey = [string]$entry.Key
            $result[$childKey] = Protect-AgentControlValue `
                -Value $entry.Value `
                -KeyName $childKey `
                -EventName $EventName `
                -SensitiveValues $SensitiveValues
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(Protect-AgentControlValue `
                -Value $item `
                -KeyName "" `
                -EventName $EventName `
                -SensitiveValues $SensitiveValues)
        }
        return $items
    }
    if ($Value -is [psobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = Protect-AgentControlValue `
                -Value $property.Value `
                -KeyName $property.Name `
                -EventName $EventName `
                -SensitiveValues $SensitiveValues
        }
        return $result
    }
    return $Value
}

$maxHookInputChars = 65536
$inputBuffer = New-Object char[] 4096
$inputBuilder = New-Object System.Text.StringBuilder
$inputTooLarge = $false
while (($inputRead = [Console]::In.Read($inputBuffer, 0, $inputBuffer.Length)) -gt 0) {
    if ($inputBuilder.Length + $inputRead -gt $maxHookInputChars) {
        $inputTooLarge = $true
        break
    }
    [void]$inputBuilder.Append($inputBuffer, 0, $inputRead)
}
if ($inputTooLarge) {
    Write-Output '{"continue":true}'
    exit 0
}
$payload = $inputBuilder.ToString().Trim()
if ([string]::IsNullOrWhiteSpace($payload)) {
    exit 0
}
$parsedPayload = $null
try {
    $parsedPayload = $payload | ConvertFrom-Json
} catch {
    Write-Output '{"continue":true}'
    exit 0
}
$eventName = [string]$parsedPayload.hook_event_name
$ownerToken = try {
    if (Get-Command Read-AgentControlOwnerToken -ErrorAction SilentlyContinue) {
        Read-AgentControlOwnerToken -Root $CredentialRoot
    }
} catch {
    $null
}
$sensitiveValues = @(
    [Environment]::GetEnvironmentVariable('AgentControl__OwnerToken'),
    $ownerToken
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$hookSecret = try {
    if (Get-Command Read-AgentControlHookSecret -ErrorAction SilentlyContinue) {
        Read-AgentControlHookSecret
    }
} catch {
    $null
}
$parsedPayload = Protect-AgentControlValue `
    -Value $parsedPayload `
    -KeyName "" `
    -EventName $eventName `
    -SensitiveValues $sensitiveValues
$payload = $parsedPayload | ConvertTo-Json -Compress -Depth 100

function Invoke-AgentControlFallbackWrite {
    param(
        [string]$Path,
        [string]$Payload,
        [string]$EventName,
        [string]$SessionId
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $mutexName = "Local\AgentControl-HookFallback-" +
        ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Path)) -replace '[^A-Za-z0-9]', '')
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $lockTaken = $false
    try {
        $lockTaken = $mutex.WaitOne(5000)
        if (-not $lockTaken) {
            return
        }
        $maxFallbackBytes = 4MB
        $maxSegments = 8
        $maxTotalBytes = 16MB
        $terminalEvents = @('Stop', 'SessionEnd')
        $lowValueEvents = @('PostToolUse', 'UserPromptSubmit')
        $utf8Bytes = [Text.Encoding]::UTF8.GetBytes($Payload + [Environment]::NewLine)

        $shouldCoalesce = $lowValueEvents -contains $EventName -and (Test-Path -LiteralPath $Path)
        if ($shouldCoalesce) {
            $tail = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($tail)) {
                try {
                    $tailPayload = $tail | ConvertFrom-Json
                    if (
                        [string]$tailPayload.hook_event_name -eq $EventName -and
                        [string]$tailPayload.session_id -eq $SessionId
                    ) {
                        $dropMarker = [ordered]@{
                            hook_event_name = 'AgentControlFallback'
                            session_id = $SessionId
                            event_id = 'dropped_low_value_activity'
                            dropped_event = $EventName
                        } | ConvertTo-Json -Compress
                        if ($tail -notmatch 'dropped_low_value_activity') {
                            Add-Content -LiteralPath $Path -Value $dropMarker -Encoding UTF8
                        }
                        return
                    }
                } catch {
                }
            }
        }

        $currentLength = if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).Length } else { 0 }
        if ($currentLength + $utf8Bytes.Length -gt $maxFallbackBytes) {
            $segmentNames = @(Get-ChildItem -LiteralPath $directory -Filter ((Split-Path -Leaf $Path) + '.segment-*') -File |
                Sort-Object Name | Select-Object -ExpandProperty Name)
            $nextIndex = 0
            if ($segmentNames.Count -gt 0) {
                $last = $segmentNames[-1] -replace '^.*\.segment-(\d+)\.jsonl$', '$1'
                [int]::TryParse($last, [ref]$nextIndex) | Out-Null
                $nextIndex++
            }
            $segmentPath = Join-Path $directory ("{0}.segment-{1:D8}.jsonl" -f (Split-Path -Leaf $Path), $nextIndex)
            Move-Item -LiteralPath $Path -Destination $segmentPath -Force
            if ($segmentNames.Count -eq 0) {
                Copy-Item -LiteralPath $segmentPath -Destination "$Path.previous" -Force
            }
        }
        Add-Content -LiteralPath $Path -Value $Payload -Encoding UTF8

        $allSpoolFiles = @(
            Get-ChildItem -LiteralPath $directory -Filter ((Split-Path -Leaf $Path) + '.segment-*') -File |
                Sort-Object Name
        )
        while ($allSpoolFiles.Count -gt $maxSegments -or (
            (($allSpoolFiles | Measure-Object -Property Length -Sum).Sum + (Get-Item -LiteralPath $Path).Length) -gt $maxTotalBytes
        )) {
            $candidate = $allSpoolFiles | Select-Object -First 1
            if ($null -eq $candidate) { break }
            $candidateContent = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction SilentlyContinue
            $hasTerminal = $false
            foreach ($terminalEvent in $terminalEvents) {
                if ($candidateContent -match '"hook_event_name"\s*:\s*"' + $terminalEvent + '"') {
                    $hasTerminal = $true
                    break
                }
            }
            if ($hasTerminal -and $allSpoolFiles.Count -gt 1) {
                $candidate = $allSpoolFiles | Where-Object {
                    $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
                    $content -notmatch '"hook_event_name"\s*:\s*"(Stop|SessionEnd)"'
                } | Select-Object -First 1
            }
            if ($null -eq $candidate) { break }
            Remove-Item -LiteralPath $candidate.FullName -Force
            $allSpoolFiles = @(
                Get-ChildItem -LiteralPath $directory -Filter ((Split-Path -Leaf $Path) + '.segment-*') -File |
                    Sort-Object Name
            )
        }
    } finally {
        if ($lockTaken) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($hookSecret)) {
        throw "Agent Control hook credential is unavailable."
    }
    Invoke-RestMethod -Method Post -Uri $endpoint -ContentType "application/json" `
        -Headers @{ 'X-Agent-Control-Hook-Secret' = $hookSecret } `
        -Body $payload -TimeoutSec 2 | Out-Null
} catch {
    Invoke-AgentControlFallbackWrite `
        -Path $fallback `
        -Payload $payload `
        -EventName $eventName `
        -SessionId ([string]$parsedPayload.session_id)
}
if ($null -ne $parsedPayload -and $parsedPayload.hook_event_name -eq 'SessionStart') {
    [pscustomobject]@{
        continue = $true
        hookSpecificOutput = [pscustomobject]@{
            hookEventName = 'SessionStart'
            additionalContext = @'
Agent Control lifecycle contract: finish every final response with exactly one standalone line. Use AGENT_CONTROL_RESULT: DONE only after implementation and verification, AGENT_CONTROL_RESULT: WAITING when external input or access is required, or AGENT_CONTROL_RESULT: FAILED when supported recovery is exhausted. Never emit more than one result line.
'@
        }
    } | ConvertTo-Json -Compress -Depth 5
} else {
    Write-Output '{"continue":true}'
}
exit 0
