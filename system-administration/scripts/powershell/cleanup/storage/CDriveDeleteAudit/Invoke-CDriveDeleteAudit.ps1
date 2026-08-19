<#
.SYNOPSIS
  Fast read-only C: drive delete-candidate audit with per-run delete command generation.
.DESCRIPTION
  Uses the Everything index through ES.exe for sub-10-second ranked results when available.
  Lists the top 100 heaviest files on C: that match the agreed conservative cleanup-candidate rules.
  Excludes Python, Docker, Program Files, ProgramData Package Cache repair MSIs, personal folders, browser auth/profile DBs, Hermes/Phone Link/app state, and ambiguous app state.
  Normal mode never deletes. It prints a separate force-delete one-liner for the exact listed CSV.
#>
[CmdletBinding()]
param(
  [string]$Root = 'C:\',
  [int]$Top = 100,
  [string]$OutputRoot = 'C:\Temp\CDriveDeleteAudit',
  [string]$DeleteManifest = '',
  [switch]$ForceDeleteListed,
  [switch]$NoColor,
  [switch]$OpenReportFolder
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$ScriptPath = $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptPath
$EsPath = Join-Path $ProjectRoot 'bin\es.exe'
$EverythingExe = 'F:\backup\windowsapps\installed\Everything\Everything.exe'

function Write-PrettyLine([string]$Text = '', [ConsoleColor]$Color = [ConsoleColor]::Gray) {
  if ($NoColor) { Write-Host $Text; return }
  Write-Host $Text -ForegroundColor $Color
}

function Format-BytesHuman([int64]$Bytes) {
  if ($Bytes -ge 1TB) { return ('{0:N2} TiB' -f ($Bytes / 1TB)) }
  if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N1} MiB' -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ('{0:N1} KiB' -f ($Bytes / 1KB)) }
  return ("$Bytes B")
}

function ConvertTo-Base64Utf16([string]$Text) {
  return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Text))
}

function New-RunContext {
  $runId = Get-Date -Format 'yyyyMMdd_HHmmss'
  $directory = Join-Path $OutputRoot $runId
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  return [pscustomobject]@{
    RunId = $runId
    Directory = $directory
    CsvPath = Join-Path $directory 'top-delete-candidates.csv'
    JsonPath = Join-Path $directory 'top-delete-candidates.json'
    ReportPath = Join-Path $directory 'top-delete-candidates.txt'
    DeleteOneLinerPath = Join-Path $directory 'force-delete-listed-files-one-liner.txt'
  }
}

function Test-ExcludedTechnologyPath([string]$Path) {
  return ($Path -match '(?i)(python|pyenv|pip|conda|anaconda|miniconda|venv|site-packages|uv\\cache|uv\\python|pseverythingpy|docker|docker desktop|dockerdesktop|moby|containerd)')
}

function Test-ExplicitDisposablePath([string]$Path) {
  if ($Path -notmatch '(?i)^C:\\') { return $false }
  if (Test-ExcludedTechnologyPath $Path) { return $false }

  # Vendor / updater / installer download caches: safe as downloaded payloads, not installed binaries.
  if ($Path -match '(?i)^C:\\Program Files\\GIGABYTE\\Control Center\\Lib\\Download\\.*\.(exe|zip|7z|msix|cab|bin|rom|fa[0-9a-z]+)$') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\NVID\\(downloads|work)\\.*\.(exe|zip|7z|cab|dll|sys|bin|so|msi)$') { return $true }
  if ($Path -match '(?i)^C:\\Program Files \(x86\)\\Microsoft\\EdgeUpdate\\Download\\.*\.(exe|cab|msi|msu)$') { return $true }
  if ($Path -match '(?i)^C:\\Program Files \(x86\)\\Google\\GoogleUpdater\\crx_cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Google\\Chrome\\User\\extensions_crx_cache\\') { return $true }

  # User-level app updater package caches / previous package payloads.
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\[^\\]+\\packages\\.*\.(nupkg|msi|exe)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\fitgirl-repacks-manager-updater\\installer\.exe$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.claude\\downloads\\.*\.(exe|msi|zip|nupkg)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.pkg-cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.bun\\bin\\.*\.outdated$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Wand\\app-[^\\]+\\resources\\.*\.backup$') { return $true }

  # Downloaded redist/cache payloads used by game/launcher tools, not save data.
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Roaming\\hydralauncher\\CommonRedist\\.*\.(exe|zip|cab)$') { return $true }

  # Explicit old Windows repair/update backup databases, not the live stores.
  if ($Path -match '(?i)^C:\\Windows\\SoftwareDistribution\.bak[^\\]*\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\System32\\catroot2\.(bak|old|codexbak)[^\\]*\\') { return $true }

  # Hermes-created one-off installer/fix payloads, not Hermes runtime/state.
  if ($Path -match '(?i)^C:\\ProgramData\\HermesAMD_RyzenMasterFix\\.*\.(exe|msi|zip)$') { return $true }
  return $false
}

function Test-ProtectedAmbiguousPath([string]$Path) {
  if ($Path -notmatch '^(?i)C:\\') { return $true }
  if (Test-ExplicitDisposablePath $Path) { return $false }

  # Hard exclusions: never raw-delete OS stores, installed applications, repair databases,
  # container/WSL/Docker layers, Python, Codex/Hermes state, or browser identity/state.
  if ($Path -match '(?i)^C:\\(pagefile|hiberfil|swapfile)\.sys$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\(WinSxS|SystemApps|servicing|Installer|assembly|Microsoft\.NET|Fonts|Logs|SoftwareDistribution(?!\.bak_)|System32\\config|System32\\DriverStore|System32\\catroot2|System32\\LogFiles|SysWOW64|System32)\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\SystemTemp\\.*\.(exe|dll|sys|drv|ocx|vdm|manifest|cat|mum)$') { return $true }
  if ($Path -match '(?i)^C:\\Program Files( \(x86\))?\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\(Microsoft\\(Windows\\Containers|Windows Defender|Network\\Downloader)|Package Cache|Docker|NVIDIA Corporation\\DockerDesktop|USOShared\\Logs)\\') { return $true }
  if ($Path -match '(?i)\\(Docker|Docker Desktop|dockerdesktop|containerd|moby|Windows\\Containers|ext4\.vhdx|docker_data\.vhdx)\\') { return $true }
  if ($Path -match '(?i)\\(python|pyenv|pip|conda|anaconda|miniconda|venv|site-packages|uv\\python|pseverythingpy)\\') { return $true }
  if ($Path -match '(?i)\\(Hermes|\.hermes|\.codex|Phone Link|Packages\\Microsoft\.YourPhone|Packages\\Microsoft\.YourPhone_|Packages\\OpenAI\.Codex_)') { return $true }
  if ($Path -match '(?i)\\AppData\\Roaming\\[^\\]+\\(Local Storage|IndexedDB)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Videos|Music|OneDrive|Downloads|CrossDevice)\\') { return $true }
  if ($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\.*\\(Database|bin|System|Settings|State)\\') { return $true }
  if ($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\.*\.(db|sqlite|sqlite3|edb|ldb|log|wal|shm|dll|exe)$') { return $true }
  if ($Path -match '(?i)\\(Chrome|Edge|Firefox)\\User Data\\.*\\(Cookies|History|Login Data|Preferences|Secure Preferences|Local Storage|IndexedDB|Sessions|Extensions)') { return $true }
  if (($Path -match '(?i)\\(Google\\Chrome|Microsoft\\Edge|Mozilla\\Firefox|Chrome|Edge|Firefox)\\') -and ($Path -match '(?i)\\User( Data)?\\|\\Profiles?\\') -and ($Path -notmatch '(?i)\\(Cache|Code Cache|GPUCache|GrShaderCache|DawnCache|GPUPersistentCache|component_crx_cache)\\')) { return $true }
  return $false
}

function Get-CleanupReason([string]$Path) {
  if (Test-ExplicitDisposablePath $Path) { return 'High-confidence downloaded installer/update cache or obsolete package payload' }
  if ($Path -match '(?i)\\Temp\\|\\Windows\\Temp\\|\\SystemTemp\\|\.(tmp|temp)$') { return 'Temporary file / temp folder residue' }
  if ($Path -match '(?i)\.etl$|\\WDI\\LogFiles\\|\\System32\\LogFiles\\WMI\\|\\DiagOutputDir\\') { return 'Diagnostic trace (.etl) / diagnostics output' }
  if ($Path -match '(?i)\.(log|wer)$|\\Windows\\Logs\\|\\CrashDumps\\|\\WER\\') { return 'Log / crash / Windows Error Reporting residue' }
  if ($Path -match '(?i)\\(Cache|LocalCache|Code Cache|GPUCache|DawnCache|GrShaderCache|ShaderCache|ComputeCache|DXCache|GLCache|INetCache|crx_cache)\\|\.ushaderprecache$') { return 'Rebuildable application/browser/GPU cache' }
  if ($Path -match '(?i)\\(npm-cache|Yarn\\Cache|pnpm-store|NuGet\\v3-cache)\\') { return 'Package-manager download cache' }
  if ($Path -match '(?i)\\SoftwareDistribution\\Download\\|\\DeliveryOptimization\\Cache\\') { return 'Windows Update / Delivery Optimization download cache' }
  if ($Path -match '(?i)\.(old|bak)$') { return 'Old backup/previous-version residue' }
  if ($Path -match '(?i)\.(dmp|mdmp|hdmp)$') { return 'Memory dump / crash dump' }
  return $null
}

function Get-SafetyNote([string]$Path) {
  if (Test-ExplicitDisposablePath $Path) { return 'Downloaded/update cache payload; installed app/system locations remain excluded.' }
  if ($Path -match '(?i)\\winevt\\Logs\\.*\.evtx$') { return 'Excluded by policy: live event logs are not raw-delete candidates.' }
  if ($Path -match '(?i)\\Windows\\Logs\\CBS\\') { return 'CBS log residue; current logs can be locked.' }
  if ($Path -match '(?i)\\(Chrome|Edge|Firefox)\\User Data\\.*\\(Cache|Code Cache|GPUCache)\\') { return 'Cache only; cookies/history/passwords/extensions are excluded.' }
  if ($Path -match '(?i)\\NVIDIA\\|\\AMD\\|\\DXCache\\|\\ComputeCache\\|\.ushaderprecache$') { return 'GPU shader/cache file; safe to rebuild, may be locked while apps run.' }
  return 'High-confidence disposable/rebuildable file class.'
}

function Test-CurrentlyForceDeletable([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Delete)
    return $true
  } catch {
    return $false
  } finally {
    if ($stream) { $stream.Close(); $stream.Dispose() }
  }
}

function Join-WindowsArgumentList([string[]]$Arguments) {
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($arg in $Arguments) {
    if ($arg -match '[\s|&<>^"'']') {
      $escaped = $arg.Replace('"','\"')
      $parts.Add('"' + $escaped + '"') | Out-Null
    } else {
      $parts.Add($arg) | Out-Null
    }
  }
  return ($parts -join ' ')
}

function Invoke-EsLines([string[]]$Arguments, [int]$TimeoutSeconds = 8) {
  $result = @(& $EsPath @Arguments)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "ES exit $exitCode" }
  return @($result | ForEach-Object { [string]$_ })
}

function Ensure-EverythingClient {
  if (-not (Test-Path -LiteralPath $EsPath)) { throw "Missing ES CLI: $EsPath" }
  try { [void](Invoke-EsLines -Arguments @('-n','1','C:\') -TimeoutSeconds 3); return } catch {}
  if (Test-Path -LiteralPath $EverythingExe) {
    Get-CimInstance Win32_Process -Filter "Name='Everything.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match ' -help' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Process -FilePath $EverythingExe -ArgumentList '-startup' -WindowStyle Minimized | Out-Null
  }
  $deadline = (Get-Date).AddSeconds(8)
  do {
    Start-Sleep -Milliseconds 500
    try { [void](Invoke-EsLines -Arguments @('-n','1','C:\') -TimeoutSeconds 2); return } catch {}
  } while ((Get-Date) -lt $deadline)
  throw 'Everything IPC unavailable or hanging; restart Everything, then rerun the audit.'
}

function Parse-EsCsvLine([string]$Line) {
  if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
  $m = [regex]::Match($Line, '^(\d+),([^,]*),"(.*)"$')
  if (-not $m.Success) { return $null }
  return [pscustomobject]@{ Bytes=[int64]$m.Groups[1].Value; LastWriteTime=$m.Groups[2].Value; Path=$m.Groups[3].Value.Replace('""','"') }
}

function Get-CandidatesFromEverything([int]$Take) {
  Ensure-EverythingClient
  $query = 'cache|temp|download|downloads|installer|setup|update|package|packages|redist|driver|*.etl|*.log|*.tmp|*.temp|*.old|*.bak|*.dmp|*.mdmp|*.hdmp|*.wer|*.crdownload|*.part|*.nupkg|*.outdated|thumbcache|iconcache|*.ushaderprecache'
  # Pull a large indexed candidate window so protected/ambiguous results cannot hide eligible cleanup files.
  # Everything returns this quickly from its index; validation enforces <10s on this machine.
  $rawLimit = [Math]::Max(5000, $Take * 50)
  $rows = New-Object System.Collections.ArrayList
  $args = @('-p','/a-d','-csv','-no-header','-size','-size-format','1','-dm','-date-format','1','-full-path-and-name','-sort','size','-sort-descending','-n', [string]$rawLimit, $query)
  $esRows = @(Invoke-EsLines -Arguments $args -TimeoutSeconds 10)
  if ($esRows.Count -eq 0) { throw 'Everything returned zero indexed rows for cleanup query.' }
  foreach ($line in $esRows) {
    $parsed = Parse-EsCsvLine ([string]$line)
    if (-not $parsed) { continue }
    $path = $parsed.Path
    if (Test-ExcludedTechnologyPath $path) { continue }
    if (Test-ProtectedAmbiguousPath $path) { continue }
    $reason = Get-CleanupReason $path
    if (-not $reason) { continue }
    # Do not pre-open every file here: it makes the audit slow. The generated force-delete
    # command handles missing/locked files and reports failures at delete time.
    [void]$rows.Add([pscustomobject]@{
      Rank = 0
      Bytes = $parsed.Bytes
      Size = Format-BytesHuman $parsed.Bytes
      LastWriteTime = $parsed.LastWriteTime
      Reason = $reason
      SafetyNote = Get-SafetyNote $path
      Path = $path
    })
    if ($rows.Count -ge $Take) { break }
  }
  return @($rows | Sort-Object Bytes -Descending | Select-Object -First $Take)
}

function New-DeleteOneLiner([string]$ManifestPath) {
  $payload = @"
`$ErrorActionPreference='Continue'; `$m='$ManifestPath'; if(-not (Test-Path -LiteralPath `$m)){ throw "Manifest not found: `$m" }; `$rows=Import-Csv -LiteralPath `$m; `$ok=0; `$fail=0; foreach(`$r in `$rows){ `$p=`$r.Path; try{ if(Test-Path -LiteralPath `$p){ Remove-Item -LiteralPath `$p -Force -ErrorAction Stop; `$ok++ } } catch { `$fail++; Write-Host ('FAILED: '+`$p+' :: '+`$_.Exception.Message) -ForegroundColor Red } }; Write-Host ('Force-delete finished. Deleted='+`$ok+' Failed='+`$fail+' Manifest='+`$m) -ForegroundColor Green
"@
  return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + (ConvertTo-Base64Utf16 $payload)
}

function Save-Reports($Context, $Candidates, [datetime]$StartedAt, [datetime]$FinishedAt) {
  $rank = 1
  foreach ($candidate in $Candidates) { $candidate.Rank = $rank; $rank++ }
  $totalBytes = [int64](($Candidates | Measure-Object Bytes -Sum).Sum)
  $Candidates | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Context.CsvPath
  $Candidates | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $Context.JsonPath
  $deleteOneLiner = ''
  if ($Candidates.Count -gt 0) {
    $deleteOneLiner = New-DeleteOneLiner $Context.CsvPath
    Set-Content -Encoding ASCII -Path $Context.DeleteOneLinerPath -Value $deleteOneLiner
  } else {
    Set-Content -Encoding ASCII -Path $Context.DeleteOneLinerPath -Value 'NO_DELETE_LINER_NO_CANDIDATES'
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('C: Drive Delete-Candidate Audit') | Out-Null
  $lines.Add(('Run: {0}' -f $Context.RunId)) | Out-Null
  $lines.Add(('Root scanned: {0}' -f $Root)) | Out-Null
  $lines.Add(('Started: {0}' -f $StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))) | Out-Null
  $lines.Add(('Finished: {0}' -f $FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))) | Out-Null
  $lines.Add(('Duration: {0:N2}s' -f (($FinishedAt - $StartedAt).TotalSeconds))) | Out-Null
  $lines.Add(('Candidates shown: {0}' -f $Candidates.Count)) | Out-Null
  $lines.Add(('Top candidates total: {0} ({1:N0} bytes)' -f (Format-BytesHuman $totalBytes), $totalBytes)) | Out-Null
  $lines.Add('Source: Everything index via ES.exe; includes hidden/system indexed files; read-only audit.') | Out-Null
  $lines.Add('Excluded: Python/Docker terms, ProgramData Package Cache, Program Files, personal folders, browser auth/profile DBs, Hermes/Phone Link/app state.') | Out-Null
  $lines.Add('Deletion performed: NO - normal audit mode only prints the delete one-liner.') | Out-Null
  $lines.Add('') | Out-Null
  foreach ($candidate in $Candidates) {
    $lines.Add(('{0,3}. {1,10} | {2} | {3}' -f $candidate.Rank, $candidate.Size, $candidate.Reason, $candidate.Path)) | Out-Null
    $lines.Add(('     Modified: {0} | {1}' -f $candidate.LastWriteTime, $candidate.SafetyNote)) | Out-Null
  }
  $lines.Add('') | Out-Null
  if ($Candidates.Count -gt 0) {
    $lines.Add('FORCE-DELETE ONE-LINER FOR THE EXACT FILES LISTED ABOVE:') | Out-Null
    $lines.Add($deleteOneLiner) | Out-Null
  } else {
    $lines.Add('NO DELETE ONE-LINER GENERATED: no candidates passed the strict filters.') | Out-Null
  }
  $lines | Set-Content -Encoding UTF8 -Path $Context.ReportPath
  return [pscustomobject]@{ TotalBytes=$totalBytes; DeleteOneLiner=$deleteOneLiner }
}

function Show-ConsoleReport($Context, $Candidates, $ReportData, [datetime]$StartedAt, [datetime]$FinishedAt) {
  $bar = '=' * 112
  Write-PrettyLine $bar Cyan
  Write-PrettyLine '  C: DRIVE DELETE-CANDIDATE AUDIT - READ ONLY' Cyan
  Write-PrettyLine $bar Cyan
  Write-PrettyLine (('  Duration: {0:N2}s   Ranked files: {1}   Potential: {2}' -f (($FinishedAt - $StartedAt).TotalSeconds), $Candidates.Count, (Format-BytesHuman $ReportData.TotalBytes))) Green
  Write-PrettyLine '  Source: Everything index via ES.exe. Hidden/system indexed files included. No deletion was performed.' Yellow
  Write-PrettyLine $bar Cyan
  foreach ($candidate in $Candidates) {
    Write-PrettyLine (('{0,3}. {1,10}  {2}' -f $candidate.Rank, $candidate.Size, $candidate.Path)) White
    Write-PrettyLine (('     {0} | Modified {1} | {2}' -f $candidate.Reason, $candidate.LastWriteTime, $candidate.SafetyNote)) DarkGray
  }
  Write-PrettyLine $bar Cyan
  Write-PrettyLine (('  Report: {0}' -f $Context.ReportPath)) Green
  Write-PrettyLine (('  CSV:    {0}' -f $Context.CsvPath)) Green
  Write-PrettyLine (('  JSON:   {0}' -f $Context.JsonPath)) Green
  Write-PrettyLine (('  Delete one-liner file: {0}' -f $Context.DeleteOneLinerPath)) Green
  Write-PrettyLine $bar Cyan
  if ($Candidates.Count -gt 0) {
    Write-PrettyLine 'FORCE-DELETE ONE-LINER FOR THE EXACT FILES LISTED ABOVE:' Yellow
    Write-Host $ReportData.DeleteOneLiner
  } else {
    Write-PrettyLine 'NO DELETE ONE-LINER GENERATED: no candidates passed the strict filters.' Yellow
  }
}

function Invoke-DeleteManifest([string]$ManifestPath) {
  if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
  $rows = Import-Csv -LiteralPath $ManifestPath
  $ok = 0; $fail = 0
  foreach ($r in $rows) {
    $p = $r.Path
    try {
      if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; $ok++ }
    } catch {
      $fail++
      Write-PrettyLine (('FAILED: {0} :: {1}' -f $p, $_.Exception.Message)) Red
    }
  }
  Write-PrettyLine (('Force-delete finished. Deleted={0} Failed={1} Manifest={2}' -f $ok,$fail,$ManifestPath)) Green
}

if ($ForceDeleteListed) {
  Invoke-DeleteManifest -ManifestPath $DeleteManifest
  exit 0
}

$startedAt = Get-Date
$context = New-RunContext
$candidates = @(Get-CandidatesFromEverything -Take $Top)
$finishedAt = Get-Date
$reportData = Save-Reports -Context $context -Candidates $candidates -StartedAt $startedAt -FinishedAt $finishedAt
Show-ConsoleReport -Context $context -Candidates $candidates -ReportData $reportData -StartedAt $startedAt -FinishedAt $finishedAt
if ($OpenReportFolder) { Start-Process explorer.exe -ArgumentList @($context.Directory) | Out-Null }
if ($candidates.Count -eq 0) { exit 2 }
exit 0
