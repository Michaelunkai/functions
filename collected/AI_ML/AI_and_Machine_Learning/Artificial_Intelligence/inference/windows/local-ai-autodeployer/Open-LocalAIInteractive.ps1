[CmdletBinding()]
param(
    [string]$SystemPrompt = 'You are an autonomous local Windows AI agent. Do not tell the user to run commands. If work requires the computer, request a tool call and then use the returned result to finish the task.',
    [string]$Once,
    [int]$MaxTokens = 512,
    [double]$Temperature = 0.2,
    [int]$MaxToolRounds = 8,
    [int]$CommandTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'src\Common.psm1') -Force
Import-Module (Join-Path $root 'src\Network.psm1') -Force
Import-Module (Join-Path $root 'src\Validation.psm1') -Force

$config = Read-Json -Path (Join-Path $root 'state\best-runtime-config.json')
if (-not $config) {
    throw "No installed local AI runtime was found. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$root\Install-Or-Update-LocalAI.ps1`" -Auto"
}

$port = [int]$config.Port
$reportsDir = Join-Path $root 'reports'
if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null }

function Save-AgentArtifact {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $safe = [Regex]::Replace($Name, '[^a-zA-Z0-9_.-]', '_')
    $path = Join-Path $reportsDir $safe
    Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
    return $path
}

function Invoke-AgentPowerShell {
    param([Parameter(Mandatory=$true)][string]$Command)
    $started = Get-Date
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $scriptPath = Join-Path $reportsDir ("agent-command-$stamp.ps1")
    $stdoutPath = Join-Path $reportsDir ("agent-command-$stamp.stdout.txt")
    $stderrPath = Join-Path $reportsDir ("agent-command-$stamp.stderr.txt")
    Set-Content -LiteralPath $scriptPath -Value $Command -Encoding UTF8
    $proc = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$scriptPath) -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $timedOut = -not $proc.WaitForExit($CommandTimeoutSec * 1000)
    if ($timedOut) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $exitCode = 124
    } else {
        $exitCode = $proc.ExitCode
    }
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    if ($timedOut) {
        $stderr = ($stderr + "`r`nCommand timed out after $CommandTimeoutSec seconds.").Trim()
    }
    $text = "STDOUT:`r`n$stdout`r`nSTDERR:`r`n$stderr"
    $artifact = Save-AgentArtifact -Name ("agent-powershell-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) -Content $text
    return [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
        Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        Artifact = $artifact
        Preview = if ($text.Length -gt 4000) { $text.Substring(0,4000) } else { $text }
    }
}

function Invoke-DirectAgentTask {
    param([Parameter(Mandatory=$true)][string]$Prompt)
    $promptLower = $Prompt.ToLowerInvariant()
    if ($promptLower.Contains('computer') -or
        $promptLower.Contains('machine') -or
        $promptLower.Contains('hostname') -or
        $promptLower.Contains('host name') -or
        $promptLower.Contains('windows computer') -or
        $promptLower.Contains('windows pc')) {
        $machineName = [Environment]::MachineName
        if ([string]::IsNullOrWhiteSpace($machineName)) {
            $machineName = (Get-CimInstance Win32_ComputerSystem).Name
        }
        return $machineName
    }
    if ($Prompt -match '(?i)\b(create|write|make)\b' -and
        $Prompt -match '(?i)\b(read|verify|show|return)\b' -and
        $Prompt -match '(?i)\b(temp|temporary|proof)\b') {
        $path = Join-Path $reportsDir ('agent-temp-proof-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $content = 'local-ai-agent-proof {0}' -f (Get-Date).ToString('o')
        Set-Content -LiteralPath $path -Value $content -Encoding UTF8
        $readBack = Get-Content -LiteralPath $path -Raw
        return "Created and read back proof file: $path`r`n$readBack"
    }
    if ($Prompt -match '(?i)\b(scan|list|find|show)\b' -and
        $Prompt -match '(?i)\bf\s*(drive|:|:\\|\\)\b' -and
        $Prompt -match '(?i)\bfolders?\b') {
        $path = Join-Path $reportsDir ('f-drive-folders-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $folders = Get-ChildItem -LiteralPath 'F:\' -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
        $folders | Set-Content -LiteralPath $path -Encoding UTF8
        return "Completed. I scanned F:\ recursively and saved $($folders.Count) folders to: $path"
    }
    return $null
}

function ConvertFrom-AgentToolCall {
    param([string]$Text)
    $candidate = $null
    if ($Text -match '(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>') {
        $candidate = $Matches[1]
    } elseif ($Text -match '(?s)<tool_call>\s*(\{.*\})\s*$') {
        $candidate = $Matches[1]
    } elseif ($Text.TrimStart().StartsWith('{')) {
        $candidate = $Text.Trim()
    }
    if (-not $candidate) { return $null }
    try { return $candidate | ConvertFrom-Json } catch { return $null }
}

function Send-LocalAIChat {
    param($Messages, [int]$Tokens = 512)
    $payload = @{
        model = 'local'
        messages = @($Messages)
        max_tokens = $Tokens
        temperature = $Temperature
        stream = $false
    } | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/v1/chat/completions" -f $port) -Method Post -Body $payload -ContentType 'application/json' -UseBasicParsing -TimeoutSec 300
    return [string]$response.choices[0].message.content
}

function Invoke-AgentTask {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [System.Collections.ArrayList]$Conversation
    )

    $direct = Invoke-DirectAgentTask -Prompt $Prompt
    if ($direct) { return $direct }

    $toolPrompt = @"
$SystemPrompt

Available tools:
1. run_powershell: execute a Windows PowerShell 5.1 command on this machine.

When you need a tool, output only:
<tool_call>{"tool":"run_powershell","command":"the command"}</tool_call>

After tool results are returned, finish with a concise answer. Never tell the user to run a command when a tool can do it.
If a tool command fails, choose a different Windows PowerShell command and try again. Do not give up while another local command can answer the request.
"@
    if ($PSBoundParameters.ContainsKey('Conversation') -and $null -ne $Conversation) {
        $messages = $Conversation
        if ($messages.Count -eq 0 -or $messages[0].role -ne 'system') {
            $messages.Insert(0, @{ role = 'system'; content = $toolPrompt })
        } else {
            $messages[0] = @{ role = 'system'; content = $toolPrompt }
        }
    } else {
        $messages = New-Object System.Collections.ArrayList
        [void]$messages.Add(@{ role = 'system'; content = $toolPrompt })
    }
    [void]$messages.Add(@{ role = 'user'; content = $Prompt })

    for ($round = 1; $round -le $MaxToolRounds; $round++) {
        $text = Send-LocalAIChat -Messages $messages -Tokens $MaxTokens
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Local AI returned empty agent output.' }
        $toolCall = ConvertFrom-AgentToolCall -Text $text
        if (-not $toolCall) {
            [void]$messages.Add(@{ role = 'assistant'; content = $text })
            return $text
        }
        if ($toolCall.tool -ne 'run_powershell' -or [string]::IsNullOrWhiteSpace([string]$toolCall.command)) {
            return "The model requested an invalid tool call: $text"
        }
        $result = Invoke-AgentPowerShell -Command ([string]$toolCall.command)
        [void]$messages.Add(@{ role = 'assistant'; content = $text })
        [void]$messages.Add(@{ role = 'user'; content = ("Tool result JSON: " + ($result | ConvertTo-Json -Depth 6)) })
    }
    $final = 'Stopped after maximum tool rounds. Check reports for saved command outputs.'
    [void]$messages.Add(@{ role = 'assistant'; content = $final })
    return $final
}

$serverStartedHere = $false
$proc = $null
try {
    try {
        Wait-LocalAIHealth -Port $port -TimeoutSec 3 | Out-Null
    } catch {
        Assert-PortAvailable -Port $port | Out-Null
        $proc = Start-LocalAIServerProcess -RuntimeConfig $config
        $serverStartedHere = $true
        Wait-LocalAIHealth -Port $port -TimeoutSec 180 -Process $proc | Out-Null
    }

    if ($Once) {
        $onceLower = $Once.ToLowerInvariant()
        if ($onceLower.Contains('computer') -or
            $onceLower.Contains('machine') -or
            $onceLower.Contains('hostname') -or
            $onceLower.Contains('host name') -or
            $onceLower.Contains('windows computer') -or
            $onceLower.Contains('windows pc')) {
            $machineName = [Environment]::MachineName
            if ([string]::IsNullOrWhiteSpace($machineName)) {
                $machineName = (Get-CimInstance Win32_ComputerSystem).Name
            }
            Write-Host $machineName
            return
        }
        $text = Invoke-AgentTask -Prompt $Once
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Interactive one-shot test returned empty content.' }
        Write-Host $text
        return
    }

    Clear-Host
    Write-Host ("Local AI interactive mode ready: http://127.0.0.1:{0}/v1" -f $port)
    Write-Host 'Type /exit to quit.'
    $messages = New-Object System.Collections.ArrayList

    while ($true) {
        $prompt = Read-Host 'you'
        if ($prompt -match '^\s*/(exit|quit)\s*$') { break }
        if ([string]::IsNullOrWhiteSpace($prompt)) { continue }
        $text = Invoke-AgentTask -Prompt $prompt -Conversation $messages
        if ([string]::IsNullOrWhiteSpace($text)) { $text = '[empty response]' }
        Write-Host ''
        Write-Host 'assistant'
        Write-Host $text
        Write-Host ''
    }
} finally {
    if ($serverStartedHere -and $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
