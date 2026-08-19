param(
    [Parameter(Mandatory = $true)][ValidatePattern('^https://')][string]$ApiUrl
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") {
    $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
        throw "Windows PowerShell 5.1 is required to register the Agent Control scheduled task."
    }
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ApiUrl $ApiUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Windows PowerShell installer handoff failed with exit code $LASTEXITCODE."
    }
    exit 0
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$node = (Get-Command node.exe -ErrorAction Stop).Source
$npm = (Get-Command npm.cmd -ErrorAction Stop).Source
$hook = Join-Path $root "hooks\Invoke-AgentControlHook.ps1"
$server = Join-Path $root "dist\server.js"
$hooksPath = Join-Path $env:USERPROFILE ".codex\hooks.json"
$hooksDirectory = Split-Path -Parent $hooksPath
$taskName = "AgentControlWindowsAdapter"
$windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$hiddenLauncher = Join-Path $root "Start-AgentControlAdapterHidden.vbs"
. (Join-Path $root "scripts\AgentControlCredential.ps1")
$hookSecret = Initialize-AgentControlHookSecret
$ownerToken = Read-AgentControlOwnerToken
if ([string]::IsNullOrWhiteSpace($ownerToken)) {
    $secureOwnerToken = Read-Host -Prompt 'Agent Control owner token' -AsSecureString
    $ownerTokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureOwnerToken)
    try {
        $ownerToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ownerTokenPointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ownerTokenPointer)
    }
}
if ([string]::IsNullOrWhiteSpace($ownerToken)) {
    throw "Agent Control owner token is unavailable."
}

function Get-AgentControlAdapterProcess {
    @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
            $_.CommandLine.IndexOf($server, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
}

$currentHealth = try {
    Invoke-RestMethod -Uri "http://127.0.0.1:17867/health/details" `
        -Headers @{ 'X-Agent-Control-Hook-Secret' = $hookSecret } -TimeoutSec 2
} catch {
    $null
}
if ($null -eq $currentHealth) {
    $listenerHealth = try {
        Invoke-RestMethod -Uri "http://127.0.0.1:17867/health" -TimeoutSec 2
    } catch {
        $null
    }
    if ($null -ne $listenerHealth -and $listenerHealth.status -eq "ok") {
        # A legacy idle adapter predates authenticated health/details. Permit
        # only its exact process when it explicitly reports no managed task.
        $legacyManagedTask = $listenerHealth.PSObject.Properties["managedTaskId"]
        $legacyIdleAdapter = $null -ne $legacyManagedTask -and
            [string]::IsNullOrWhiteSpace([string]$legacyManagedTask.Value) -and
            @(Get-AgentControlAdapterProcess).Count -eq 1
        if (-not $legacyIdleAdapter) {
            throw "Refusing to restart Agent Control because authenticated /health/details inspection failed."
        }
    }
}
if ($null -ne $currentHealth -and -not [string]::IsNullOrWhiteSpace([string]$currentHealth.managedTaskId)) {
    throw "Refusing to restart Agent Control while a managed task is active: $($currentHealth.managedTaskId)"
}

Push-Location $root
try {
    & $npm run build
    if ($LASTEXITCODE -ne 0) { throw "Adapter build failed." }
} finally {
    Pop-Location
}
New-Item -ItemType Directory -Path $hooksDirectory -Force | Out-Null

$document = if (Test-Path -LiteralPath $hooksPath) {
    Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{ hooks = [pscustomobject]@{} }
}
if (-not $document.hooks) {
    $document | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
}

$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hook`""
foreach ($eventName in @("SessionStart", "UserPromptSubmit", "Stop")) {
    $current = @($document.hooks.$eventName)
    $filtered = @($current | Where-Object {
        $commands = @($_.hooks | ForEach-Object { $_.commandWindows; $_.command_windows; $_.command })
        -not ($commands -match [regex]::Escape("Invoke-AgentControlHook.ps1"))
    })
    $hookDefinition = [ordered]@{
        type = "command"
        command = $command
        statusMessage = "Updating Agent Control"
    }
    $hookDefinition.timeout = 5
    $entry = [pscustomobject]@{
        hooks = @([pscustomobject]$hookDefinition)
    }
    $document.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @($filtered + $entry) -Force
}
$postToolUse = @($document.hooks.PostToolUse)
$filteredPostToolUse = @($postToolUse | Where-Object {
    $commands = @($_.hooks | ForEach-Object { $_.commandWindows; $_.command_windows; $_.command })
    -not ($commands -match [regex]::Escape("Invoke-AgentControlHook.ps1"))
})
$document.hooks | Add-Member -NotePropertyName PostToolUse -NotePropertyValue $filteredPostToolUse -Force
$sessionEnd = @($document.hooks.SessionEnd)
$filteredSessionEnd = @($sessionEnd | Where-Object {
    $commands = @($_.hooks | ForEach-Object { $_.commandWindows; $_.command_windows; $_.command })
    -not ($commands -match [regex]::Escape("Invoke-AgentControlHook.ps1"))
})
$document.hooks | Add-Member -NotePropertyName SessionEnd -NotePropertyValue $filteredSessionEnd -Force

$temporary = "$hooksPath.tmp"
$hooksJson = $document | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText(
    $temporary,
    "$hooksJson$([Environment]::NewLine)",
    (New-Object System.Text.UTF8Encoding($false))
)
Move-Item -LiteralPath $temporary -Destination $hooksPath -Force

[Environment]::SetEnvironmentVariable("AgentControl__ApiUrl", $ApiUrl.TrimEnd('/'), "User")
Write-AgentControlOwnerToken -Token $ownerToken
$ownerToken = $null
[Environment]::SetEnvironmentVariable("AgentControl__OwnerToken", $null, "User")

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
foreach ($process in @(Get-AgentControlAdapterProcess)) {
    Stop-Process -Id $process.ProcessId -Force
}
$stopDeadline = (Get-Date).AddSeconds(15)
while (@(Get-AgentControlAdapterProcess).Count -gt 0 -and (Get-Date) -lt $stopDeadline) {
    Start-Sleep -Milliseconds 200
}
if (@(Get-AgentControlAdapterProcess).Count -gt 0) {
    throw "The existing Agent Control adapter process did not stop."
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
$escapedLauncher = $hiddenLauncher.Replace('"', '""')
$action = New-ScheduledTaskAction -Execute $wscript -Argument "//B //Nologo `"$escapedLauncher`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $windowsIdentity
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Durable local Codex lifecycle adapter for Agent Control" -Force -ErrorAction Stop | Out-Null
Start-ScheduledTask -TaskName $taskName

$healthy = $false
$healthDeadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $healthDeadline) {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:17867/health" -TimeoutSec 2
        if ($health.status -eq "ok") {
            $healthy = $true
            break
        }
    } catch {
        Start-Sleep -Milliseconds 250
    }
}
if (-not $healthy) {
    throw "Agent Control adapter health did not recover after installation."
}

[pscustomobject]@{
    TaskName = $taskName
    HooksPath = $hooksPath
    Server = $server
    TrustReviewRequired = $true
}
