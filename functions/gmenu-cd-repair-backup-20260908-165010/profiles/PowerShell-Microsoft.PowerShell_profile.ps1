# BEGIN GMENU EARLY BOOTSTRAP
# Load GMenu before the fast-profile return so PS5/PS7 and fresh shells all
# resolve the same durable entry point. The local fallback remains usable when
# the F: drive is not mounted yet.
$gmenuFunctionCandidates=@(
    'F:\study\Platforms\windows\functions\GMenuFunctions.ps1',
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\GMenuFallback\GMenuFunctions.ps1')
)
$gmenuFunctionSource=$gmenuFunctionCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
if($gmenuFunctionSource){. $gmenuFunctionSource}
if(-not (Get-Command gmenu -CommandType Function -ErrorAction SilentlyContinue)) {
    $gmenuFallback=Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\GMenuFallback\gmenu.ps1'
    if(Test-Path -LiteralPath $gmenuFallback -PathType Leaf) {
        Set-Item -LiteralPath 'Function:\global:gmenu' -Value ([scriptblock]::Create("& '"+$gmenuFallback.Replace("'","''")+"' @args")) -Force
    }
}
# GMenu state is created lazily by a publish/restore operation.  Profile import
# must not recreate state that an explicit `uni gmenu` cleanup just removed.
# END GMENU EARLY BOOTSTRAP
# BEGIN CODEX FAST PROFILE ROUTE
# Normal PS5 launches and explicit profile reloads use the same verified cache
# as Windows Terminal. The marker prevents recursion when the generated entry
# executes this profile prefix or when the canonical fallback is required.
if ($PSVersionTable.PSEdition -eq 'Desktop' -and
    $env:CODEX_FAST_PROFILE_BOOTSTRAP_ACTIVE -ne '1') {
    $codexFastProfileStart = 'C:\Users\micha\AppData\Local\Codex\PowerShellFastStartup\Start-FastProfile.ps1'
    if (Test-Path -LiteralPath $codexFastProfileStart -PathType Leaf) {
        $codexFastProfileInteractive = $Host.Name -eq 'ConsoleHost' -and
            [Environment]::CommandLine -notmatch '(?i)(?:^|\s)-(?:c|command|e|enc|encodedcommand|f|file|noninteractive)(?:\s|$)'
        . $codexFastProfileStart -Interactive:$codexFastProfileInteractive
        return
    }
}
# END CODEX FAST PROFILE ROUTE

# BEGIN JOB APPLICATION SENDER PATH
$jobApplicationSenderDirectory = 'F:\study\projects\career\job_search\outreach\email\gmail\windows\job-application-email-sender'
if (Test-Path -LiteralPath $jobApplicationSenderDirectory -PathType Container) {
    $jobApplicationSenderPathEntry = $jobApplicationSenderDirectory.TrimEnd('\')
    $jobApplicationSenderOnPath = @(
        $env:Path -split ';' |
            ForEach-Object { $_.Trim().TrimEnd('\') } |
            Where-Object { $_.Equals($jobApplicationSenderPathEntry, [StringComparison]::OrdinalIgnoreCase) }
    ).Count -gt 0
    if (-not $jobApplicationSenderOnPath) {
        $env:Path = "$jobApplicationSenderPathEntry;$env:Path"
    }
}
# END JOB APPLICATION SENDER PATH

# BEGIN WILLOW-FORCE PSREADLINE HISTORY
function global:Enable-WillowForceVirtualTerminal {
    try {
        $consoleKey = 'HKCU:\Console'
        if (-not (Test-Path -LiteralPath $consoleKey)) {
            New-Item -Path $consoleKey -Force | Out-Null
        }
        New-ItemProperty -Path $consoleKey -Name 'VirtualTerminalLevel' -Value 1 -PropertyType DWord -Force | Out-Null
    } catch { }

    try {
        if (-not ('WillowForce.Console.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @"
namespace WillowForce.Console {
    using System;
    using System.Runtime.InteropServices;
    public static class NativeMethods {
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
    }
}
"@
        }
        foreach ($stdHandle in @(-11, -12)) {
            $handle = [WillowForce.Console.NativeMethods]::GetStdHandle($stdHandle)
            if ($handle -eq [IntPtr]::Zero -or $handle.ToInt64() -eq -1) { continue }
            $mode = 0
            if ([WillowForce.Console.NativeMethods]::GetConsoleMode($handle, [ref]$mode)) {
                [void][WillowForce.Console.NativeMethods]::SetConsoleMode($handle, ($mode -bor 4))
            }
        }
    } catch { }
}

function global:Initialize-FastProfilePsReadLineHistory {
    try {
        Enable-WillowForceVirtualTerminal

        $root = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
        $sessionsDir = Join-Path $root 'sessions'
        $historyPath = Join-Path $root 'ConsoleHost_forever_history.txt'
        $archivePath = Join-Path $root 'ConsoleHost_forever_archive.txt'

        $preferredPsReadLine = 'C:\Program Files\WindowsPowerShell\Modules\PSReadLine\2.4.5\Microsoft.PowerShell.PSReadLine.dll'
        if (Test-Path -LiteralPath $preferredPsReadLine -PathType Leaf) {
            try { Remove-Module PSReadLine,Microsoft.PowerShell.PSReadLine -Force -ErrorAction SilentlyContinue } catch { }
            try { Import-Module $preferredPsReadLine -Global -Force -ErrorAction SilentlyContinue } catch { }
        }
        $setPsReadLineOption = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
        $needsPsReadLineImport = (-not $setPsReadLineOption) -or (-not $setPsReadLineOption.Parameters.ContainsKey('PredictionSource'))
        if ($needsPsReadLineImport) {
            $moduleCandidates = @(
                $preferredPsReadLine,
                'C:\Program Files\WindowsPowerShell\Modules\PSReadLine\PSReadLine.psd1'
            )
            foreach ($modulePath in $moduleCandidates) {
                if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
                    try { Remove-Module PSReadLine,Microsoft.PowerShell.PSReadLine -Force -ErrorAction SilentlyContinue } catch { }
                    Import-Module $modulePath -Global -Force -ErrorAction SilentlyContinue
                    $setPsReadLineOption = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
                    if ($setPsReadLineOption -and $setPsReadLineOption.Parameters.ContainsKey('PredictionSource')) { break }
                }
            }
        }

        foreach ($dir in @($root, $sessionsDir)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        foreach ($file in @($historyPath, $archivePath)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                New-Item -ItemType File -Path $file -Force | Out-Null
            }
        }

        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            try { Set-PSReadLineOption -HistorySavePath $historyPath -HistorySaveStyle SaveIncrementally -MaximumHistoryCount 2147483647 -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]0x1b)[38;5;244m" } -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -HistoryNoDuplicates:$false -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction SilentlyContinue } catch { }
        }
    } catch {
        if ($env:WILLOW_FORCE_HISTORY_DEBUG -eq '1') {
            Write-Error $_
        }
    }
}
# END WILLOW-FORCE PSREADLINE HISTORY

# Record host output from the first profile action so session copies are not bounded by terminal scrollback.
# Every interactive session gets a full transcript; `clip` copies the entire session output into notepad.
$terminalLogPath = [Environment]::GetEnvironmentVariable(
    'CODEX_FULL_TERMINAL_LOG',
    [System.EnvironmentVariableTarget]::Process
)
$isInteractiveConsoleHost = $Host.Name -eq 'ConsoleHost' -and
    [string]::IsNullOrWhiteSpace($terminalLogPath) -and
    [Environment]::CommandLine -notmatch '(?i)(?:^|\s)-(?:c|command|e|enc|encodedcommand|f|file|noninteractive)(?:\s|$)'
if ($isInteractiveConsoleHost) {
    try {
        $recDir = Join-Path $env:TEMP 'PowerShellSessionRecordings'
        [void][System.IO.Directory]::CreateDirectory($recDir)
        $transcriptPath = $null
        $existingState = Get-Variable -Name CopyCurrentPowerShellSessionTranscriptState -Scope Global -ErrorAction SilentlyContinue
        if ($existingState -and $existingState.Value -and $existingState.Value.Path -and (Test-Path -LiteralPath $existingState.Value.Path -PathType Leaf)) {
            $transcriptPath = [string]$existingState.Value.Path
        }
        if (-not $transcriptPath) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            $candidate = Join-Path $recDir ("PowerShell-session-{0}-pid{1}.txt" -f $stamp, $PID)
            try {
                Start-Transcript -Path $candidate -Force -ErrorAction Stop | Out-Null
                $transcriptPath = $candidate
            } catch {
                $transcriptPath = $null
            }
        }
        if ($transcriptPath) {
            $state = [pscustomobject]@{ Path = $transcriptPath; TranscriptPath = $transcriptPath; Pid = $PID; Started = (Get-Date).ToString('o') }
            Set-Variable -Name CopyCurrentPowerShellSessionTranscriptState -Scope Global -Value $state -Force
            try {
                $manifest = Join-Path $recDir ("PowerShell-session-manifest-pid{0}.json" -f $PID)
                [System.IO.File]::WriteAllText($manifest, ($state | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
            } catch { }
        }
    } catch { }
}

# Codex PS5 command bootstrap.
$profileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
if (-not (Test-Path -LiteralPath $profileModule -PathType Leaf)) {
    throw "Codex profile module is missing: $profileModule"
}
# A profile reload (for example `be`) must replace a module that came from an
# older fast-start cache generation.  Without -Force, PowerShell keeps that
# deleted generation's private session state and its lazy resolver eventually
# calls helpers that no longer exist.
Import-Module -Name $profileModule -DisableNameChecking -Global -Force -ErrorAction Stop
Initialize-CodexProfileFunctions

# DUSH numbered navigation.  PowerShell's built-in `cd` is an AllScope alias,
# so replace that alias with a small compatible dispatcher after the profile
# module has installed Resolve-DushNumberedItems.
function global:Invoke-DushCd {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    $values = @()
    if ($null -ne $Path) {
        $values = @($Path)
    }
    if ($values.Count -eq 1 -and $values[0] -match '^\d+$' -and
        -not (Test-Path -LiteralPath $values[0])) {
        $selected = @(Resolve-DushNumberedItems -Selection $values[0] -DirectoriesOnly)
        if ($selected.Count -ne 1) { throw "cd number '$($values[0])' did not resolve to exactly one directory." }
        Microsoft.PowerShell.Management\Set-Location -LiteralPath $selected[0].Path
        Write-Host ("[cd] DUSH #{0} -> {1}" -f $selected[0].Index, $selected[0].Path) -ForegroundColor Cyan
        return
    }

    if ($values.Count -eq 0) {
        Microsoft.PowerShell.Management\Set-Location
    } elseif ($values.Count -eq 1) {
        Microsoft.PowerShell.Management\Set-Location -Path $values[0]
    } else {
        throw 'cd accepts one path or one DUSH number.'
    }
}
# The built-in `cd` alias is AllScope.  Replace its target in place while
# preserving that option so ordinary `cd`, `cd ..`, and child scopes keep
# working after profile startup.
Set-Alias -Name cd -Value Invoke-DushCd -Scope Global -Option AllScope -Force

# BEGIN GMENU FUNCTIONS
. 'F:\study\Platforms\windows\functions\GMenuFunctions.ps1'
# END GMENU FUNCTIONS



# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}
# >>> Jarvis - voice bridge to Freebuff >>>
# Hands-free: speak -> local Whisper STT -> Freebuff desktop app -> edge-tts reply.
# Usage: type `jarvis` (or `jarvis -Help`). Requires the Freebuff app + mic.
$jarvisVoiceScript = 'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\jarvis.ps1'
if (Test-Path -LiteralPath $jarvisVoiceScript -PathType Leaf) {
    try {
        . $jarvisVoiceScript
    } catch {
        Write-Warning "jarvis could not be loaded: $_"
    }
}
# <<< Jarvis voice bridge <<<
# >>> dklll - complete Docker wipe + fresh daemon (alias for dkill) >>>
function dklll {
    & 'F:\study\Platforms\windows\functions\dkill.ps1' @args
}
# <<< dklll <<<

# BEGIN AFTERFORMAT BACKUP/RESTORE
$AfterFormatDir = 'F:\backup\windowsapps\AfterFormat\executables'
function myback {
& 'F:\backup\windowsapps\AfterFormat\executables\AfterFormat-Backup-Sink.exe' @args
}
function myres {
& 'F:\backup\windowsapps\AfterFormat\executables\AfterFormat-Restore-Windows11.exe' @args
}
# END AFTERFORMAT BACKUP/RESTORE
# >>> aadb Android ADB bridge >>>
function aadb {
    & 'C:\Users\micha\bin\aadb.ps1' @args
}
function aad {
    & 'C:\Users\micha\bin\aad.ps1' @args
}
# <<< aadb Android ADB bridge <<<

# Keep ranked model launchers direct after profile-module initialization.
function global:nvi { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 1 @args }
function global:nvi2 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 2 @args }
function global:nvi3 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 3 @args }
function global:nvi4 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 4 @args }
function global:nvi5 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 5 @args }
function global:nvi6 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 6 @args }
function global:nvi7 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 7 @args }
function global:nvi8 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 8 @args }
function global:nvi9 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 9 @args }
function global:nvi10 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 10 @args }
function global:nvi11 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 11 @args }
function global:nvi12 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 12 @args }
function global:nvi13 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 13 @args }
function global:nvi14 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 14 @args }
function global:nvi15 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 15 @args }
function global:nvi16 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 16 @args }
function global:nvi17 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 17 @args }
function global:nvi18 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 18 @args }
function global:nvi19 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 19 @args }
function global:nvi20 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 20 @args }
function global:nvi21 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 21 @args }
function global:nvi22 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 22 @args }
function global:nvi23 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 23 @args }
function global:nvi24 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 24 @args }
function global:nvi25 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 25 @args }
function global:nvi26 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 26 @args }
function global:nvi27 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 27 @args }
function global:nvi28 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 28 @args }
function global:nvi29 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 29 @args }
function global:nvi30 { & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaRankedModel.ps1' -Rank 30 @args }

function global:nvall {
    & 'C:\Users\micha\Documents\WindowsPowerShell\Invoke-NvidiaAllPanes.ps1' @args
}

# Keep descriptive compatibility aliases.
function global:ink { & 'F:\study\Platforms\windows\functions\ink.ps1' @args }
function global:seek { & 'F:\study\Platforms\windows\functions\seek.ps1' @args }
function global:glm { & 'F:\study\Platforms\windows\functions\glm.ps1' @args }
function global:nemo2 { & 'F:\study\Platforms\windows\functions\nemo2.ps1' @args }
function global:nemo3 { & 'F:\study\Platforms\windows\functions\nemo3.ps1' @args }
function global:llama { & 'F:\study\Platforms\windows\functions\lla.ps1' @args }
function global:oss { & 'F:\study\Platforms\windows\functions\oss.ps1' @args }

. 'F:\study\Platforms\windows\functions\InstalledAppRestoreFunctions.ps1'

# BEGIN INSTALLED APP DOCKER FUNCTIONS
function gCodexMonitor {
    & 'F:\study\Platforms\windows\functions\gCodexMonitor.ps1' @args
}
function gWhisperKeyLocal {
    & 'F:\study\Platforms\windows\functions\gWhisperKeyLocal.ps1' @args
}


function greflect {
    & 'F:\study\Platforms\windows\functions\greflect.ps1' @args
}


function gtelegram {
    & 'F:\study\Platforms\windows\functions\gtelegram.ps1' @args
}

function gcloudflare {
    & 'F:\study\Platforms\windows\functions\gcloudflare.ps1' @args
}

function gkvrt {
    & 'F:\study\Platforms\windows\functions\gkvrt.ps1' @args
}
function gscoop {
    & 'F:\study\Platforms\windows\functions\gscoop.ps1' @args
}
function gBleachBitAutoClean {
    & 'F:\study\Platforms\windows\functions\gBleachBitAutoClean.ps1' @args
}

function gProcessLasso {
    & 'F:\study\Platforms\windows\functions\gProcessLasso.ps1' @args
}
function gOpenSpeedy {
    & 'F:\study\Platforms\windows\functions\gOpenSpeedy.ps1' @args
}
function ggamesavemanager {
    & 'F:\study\Platforms\windows\functions\ggamesavemanager.ps1' @args
}
function gadw {
    & 'F:\study\Platforms\windows\functions\gadw.ps1' @args
}
function gEverything {
    & 'F:\study\Platforms\windows\functions\gEverything.ps1' @args
}
function gqBittorrentSearchPluginsWiki {
    & 'F:\study\Platforms\windows\functions\gqBittorrentSearchPluginsWiki.ps1' @args
}
function gqBittorrentSearchPlugins {
    & 'F:\study\Platforms\windows\functions\gqBittorrentSearchPlugins.ps1' @args
}
function gapp {
    & 'F:\study\Platforms\windows\functions\gapp.ps1' @args
}
# END INSTALLED APP DOCKER FUNCTIONS

# BEGIN GAPP FUNCTION gqBittorrentSearchPluginsWiki
function gqBittorrentSearchPluginsWiki {
    & 'F:\study\Platforms\windows\functions\gqBittorrentSearchPluginsWiki.ps1' @args
}
# END GAPP FUNCTION gqBittorrentSearchPluginsWiki

# BEGIN GAPP FUNCTION gGappExactPathProof
function gGappExactPathProof {
    & 'F:\study\Platforms\windows\functions\gGappExactPathProof.ps1' @args
}
# END GAPP FUNCTION gGappExactPathProof

# BEGIN GMENU SAVED gtailscale
function gtailscale {
    Invoke-GMenuSavedCommand -Name 'gtailscale' -Arguments $args
}
# END GMENU SAVED gtailscale

# BEGIN GMENU SAVED gObsidian
function gObsidian {
    Invoke-GMenuSavedCommand -Name 'gObsidian' -Arguments $args
}
# END GMENU SAVED gObsidian

# BEGIN GMENU SAVED gtv
function gtv {
    Invoke-GMenuSavedCommand -Name 'gtv' -Arguments $args
}
# END GMENU SAVED gtv

# BEGIN GMENU SAVED gFlareSolverr
function gFlareSolverr {
    Invoke-GMenuSavedCommand -Name 'gFlareSolverr' -Arguments $args
}
# END GMENU SAVED gFlareSolverr

# BEGIN GMENU SAVED gProwlarr
function gProwlarr {
    Invoke-GMenuSavedCommand -Name 'gProwlarr' -Arguments $args
}
# END GMENU SAVED gProwlarr

# BEGIN GMENU SAVED gJackett
function gJackett {
    Invoke-GMenuSavedCommand -Name 'gJackett' -Arguments $args
}
# END GMENU SAVED gJackett

# BEGIN GMENU SAVED gWhisper
function gWhisper {
    Invoke-GMenuSavedCommand -Name 'gWhisper' -Arguments $args
}
# END GMENU SAVED gWhisper

# BEGIN GMENU SAVED gPortableGit
function gPortableGit {
    Invoke-GMenuSavedCommand -Name 'gPortableGit' -Arguments $args
}
# END GMENU SAVED gPortableGit

# BEGIN GMENU SAVED gBuzz
function gBuzz {
    Invoke-GMenuSavedCommand -Name 'gBuzz' -Arguments $args
}
# END GMENU SAVED gBuzz

# BEGIN GMENU SAVED gdeepseekharness
function gdeepseekharness {
    Invoke-GMenuSavedCommand -Name 'gdeepseekharness' -Arguments $args
}
# END GMENU SAVED gdeepseekharness

# BEGIN GMENU SAVED gOmniroute
function gOmniroute {
    Invoke-GMenuSavedCommand -Name 'gOmniroute' -Arguments $args
}
# END GMENU SAVED gOmniroute

# BEGIN GMENU SAVED gLatencyMon
function gLatencyMon {
    Invoke-GMenuSavedCommand -Name 'gLatencyMon' -Arguments $args
}
# END GMENU SAVED gLatencyMon

# BEGIN GMENU SAVED gHereticAI
function gHereticAI {
    Invoke-GMenuSavedCommand -Name 'gHereticAI' -Arguments $args
}
# END GMENU SAVED gHereticAI
