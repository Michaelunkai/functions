<#
.SYNOPSIS
  Max-safe C: space recovery audit with clipboard delete one-liner generation.
.DESCRIPTION
  ALLOW_DESTRUCTIVE: this file contains deletion code only for the explicit -ForceDeleteListed
  path and the manifest one-liner requested by the user. Normal audit mode never deletes.

  Purpose: free as much possible space from C: safely, without missing high-confidence
  disposable files and without deleting installed programs, Windows servicing stores,
  user data, credentials, databases, virtual disks, source-control packs, or live state
  that may be needed later.

  Finds high-confidence disposable files on C: using a same-folder Everything CLI
  when available or a built-in filesystem scan otherwise, validates each candidate
  through strict allow/deny rules, includes locked-but-safe rebuildable/cache files by
  default so large opportunities are not hidden, saves an exact delete manifest, and
  copies a manifest-driven one-liner to the clipboard only after manifest integrity
  checks pass. No required project dependency is loaded from C:.
#>
[CmdletBinding()]
param(
  [string]$Root = 'C:\',
  [string]$OutputRoot = 'F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\reports\CDriveMaxSafeDeleteAudit',
  [string]$EfuPath = 'F:\downloads\A.efu',
  [int]$EfuScanLimit = 1000000,
  [switch]$RefreshCache,
  [int]$EverythingLimit = 25000,
  [int]$MaxCandidates = 0,
  [string]$DeleteManifest = '',
  [switch]$ForceDeleteListed,
  [switch]$IncludeLocked,
  [switch]$OnlyImmediatelyDeletable,
  [switch]$ScheduleFailedForReboot,
  [switch]$NoClipboard,
  [switch]$OpenReportFolder,
  [switch]$SelfTest,
  [string]$ClassifyPath = '',
  [string]$ClassifyList = '',
  [int]$ReviewLimit = 1000,
  [int64]$ReviewMinimumBytes = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptPath = $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptPath
$EsPath = Join-Path $ProjectRoot 'bin\es.exe'
$EverythingExe = 'F:\backup\windowsapps\installed\Everything\Everything.exe'
$script:RequireFullRefreshAfterCacheDrift = $false

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
  $runId = ('{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), ([guid]::NewGuid().ToString('N').Substring(0,8)))
  $directory = Join-Path $OutputRoot $runId
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  [pscustomobject]@{
    RunId = $runId
    Directory = $directory
    CsvPath = Join-Path $directory 'max-safe-delete-candidates.csv'
    JsonPath = Join-Path $directory 'max-safe-delete-candidates.json'
    ReportPath = Join-Path $directory 'max-safe-delete-candidates.txt'
    DeleteOneLinerPath = Join-Path $directory 'max-safe-delete-one-liner.txt'
    ReviewCsvPath = Join-Path $directory 'max-safe-delete-review-only-blocked.csv'
    ReviewJsonPath = Join-Path $directory 'max-safe-delete-review-only-blocked.json'
    ReviewReportPath = Join-Path $directory 'max-safe-delete-review-only-blocked.txt'
    SystemCleanupJsonPath = Join-Path $directory 'max-safe-delete-system-cleanup-opportunities.json'
    SystemCleanupReportPath = Join-Path $directory 'max-safe-delete-system-cleanup-opportunities.txt'
  }
}

function Get-CacheContext {
  $cacheDirectory = Join-Path $OutputRoot '_cache'
  [pscustomobject]@{
    Directory = $cacheDirectory
    CsvPath = Join-Path $cacheDirectory 'latest-max-safe-delete-candidates.csv'
    JsonPath = Join-Path $cacheDirectory 'latest-max-safe-delete-candidates.json'
    SummaryPath = Join-Path $cacheDirectory 'latest-max-safe-delete-summary.txt'
    ReviewCsvPath = Join-Path $cacheDirectory 'latest-max-safe-delete-review-only-blocked.csv'
    ReviewJsonPath = Join-Path $cacheDirectory 'latest-max-safe-delete-review-only-blocked.json'
    ReviewReportPath = Join-Path $cacheDirectory 'latest-max-safe-delete-review-only-blocked.txt'
    SystemCleanupJsonPath = Join-Path $cacheDirectory 'latest-max-safe-delete-system-cleanup-opportunities.json'
    SystemCleanupReportPath = Join-Path $cacheDirectory 'latest-max-safe-delete-system-cleanup-opportunities.txt'
  }
}

function Test-RootedOnC([string]$Path) {
  return ($Path -match '^(?i)C:\\')
}

function Test-ValidCandidatePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  if (-not (Test-RootedOnC $Path)) { return $false }
  foreach ($ch in $Path.ToCharArray()) {
    if ([int][char]$ch -lt 32) { return $false }
  }
  if ($Path.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) { return $false }
  return $true
}

function Test-UserGeneratedDisposablePath([string]$Path) {
  if (-not (Test-ValidCandidatePath $Path)) { return $false }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\.*\\logs\\.*\.(pml|csv|etl|dmp|mdmp|hdmp|wer|log|trace|tmp|temp|bak|old)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\(WindowsPowerShell|PowerShell)\\.*\.corrupt-\d{8}-\d{6}\.bak$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\\.codex\\db-backups\\[^\\]+\\.*\.corrupt_\d{8}_\d{6}\.bak$') { return $true }
  return $false
}

function Test-ExcludedTechnologyPath([string]$Path) {
  if ($Path -match '(?i)(docker|docker desktop|dockerdesktop|moby|containerd)') { return $true }
  if ($Path -match '(?i)(python|pyenv|conda|anaconda|miniconda|venv|site-packages|uv\\python|pseverythingpy)') { return $true }
  return $false
}

function Test-HardNeverDeletePath([string]$Path) {
  if (-not (Test-ValidCandidatePath $Path)) { return $true }
  if (-not (Test-RootedOnC $Path)) { return $true }
  if ($Path -match '(?i)(docker|docker desktop|dockerdesktop|moby|containerd|Windows\\Containers)') { return $true }
  if ($Path -match '(?i)(\\|^)(ext4|docker_data|wsl|wsl2)[^\\]*\.vhdx$') { return $true }
  if ($Path -match '(?i)\.(vhd|vhdx|avhd|avhdx|vdi|vmdk)$') { return $true }
  if ($Path -match '(?i)\\(\.git|\.hg|\.svn)\\') { return $true }
  if ($Path -match '(?i)\\(Hermes|\.hermes)\\') { return $true }
  if ($Path -match '(?i)\\(IndexedDB|Local Storage|Session Storage|databases?)\\') { return $true }
  if ($Path -match '(?i)\\(Cookies|History|Login Data|Preferences|Secure Preferences|Sessions|Extensions)(\\|$)') { return $true }
  if ($Path -match '(?i)\\(Site Characteristics Database|Extension State|Sync Data)\\') { return $true }
  if ($Path -match '(?i)\\Mozilla\\Firefox\\Profiles\\[^\\]+\\storage\\') { return $true }
  if ($Path -match '(?i)\\AppData\\Roaming\\Codex\\web\\') { return $true }
  return $false
}

function Test-DisposablePatternPath([string]$Path) {
  if ($Path -match '(?i)\\(cache|caches|temp|tmp|logs?|crashdumps?|reportqueue|reportarchive|download|downloads|downloader|installer|installers|setup|update|updates|redist|commonredist|shadercache|dxcache|glcache|gpucache|dawncache|grshadercache|component_crx_cache|deliveryoptimization\\cache|softwaredistribution\\download)\\') { return $true }
  if ($Path -match '(?i)\.(etl|log|tmp|temp|old|bak|dmp|mdmp|hdmp|wer|crdownload|part|partial|download|nupkg|outdated|ushaderprecache|pml)$') { return $true }
  if ($Path -match '(?i)\\(thumbcache|iconcache)[^\\]*\.db$') { return $true }
  return $false
}

function Test-UserFolderDisposablePath([string]$Path) {
  if (Test-UserGeneratedDisposablePath $Path) { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Videos|Music|OneDrive|CrossDevice)\\.*\\(cache|caches|temp|tmp|logs?|crashdumps?)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Downloads\\.*\.(tmp|temp|crdownload|part|partial|download|nupkg|outdated|dmp|mdmp|hdmp|wer|etl|log)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Downloads\\.*(setup|installer|update|driver|redist).*\.(exe|msi|msu|cab|zip|7z|rar)$') { return $true }
  return $false
}

function Test-ExplicitDisposablePath([string]$Path) {
  if ($Path -notmatch '(?i)^C:\\') { return $false }

  if ($Path -match '(?i)^C:\\Windows\\Logs\\CBS\\.*\.log$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\Logs\\WindowsUpdate\\.*\.(etl|log)$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\Panther\\.*\.(etl|log|tmp|bak|old)$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\INF\\.*\.log$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\debug\\.*\.(log|etl|dmp|tmp)$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\System32\\WDI\\LogFiles\\.*\.(etl|log)$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\System32\\LogFiles\\WMI\\.*\.(etl|log)$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\System32\\config\\systemprofile\\AppData\\Local\\Temp\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\SysWOW64\\config\\systemprofile\\AppData\\Local\\Temp\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Roaming\\PSEverythingPy\\.*\.(tmp|temp)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.codex\\workspace\\[^\\]+\\chrome-profile[^\\]*\\[^\\]+\\(Cache|Code Cache|GPUCache|GrShaderCache|DawnCache|GPUPersistentCache)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\(work|logs|reports)\\.*\.(csv|json|jsonl|log|etl|pml|dmp|mdmp|hdmp|wer|tmp|temp)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\stability-reports\\nvidia-driver-backup\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows Defender\\Quarantine\\ResourceData\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows Defender\\Scans\\mpcache-[^\\]+$') { return $true }

  if ($Path -match '(?i)^C:\\ProgramData\\Package Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\Installer\\\$patchcache\$\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\CbsTemp\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\LiveKernelReports\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\Minidump\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\Memory\.dmp$') { return $true }
  if ($Path -match '(?i)^C:\\CrashDumps\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\CrashDumps\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\Explorer\\(thumbcache|iconcache)[^\\]*\.db$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\PeerDistRepub\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\WER\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\CloudStore\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Packages\\[^\\]+\\TempState\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\USOShared\\Logs\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\WER\\(ReportQueue|ReportArchive)\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Diagnosis\\(ETLLogs|DownloadedSettings)\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\DeviceMetadataCache\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\Power Efficiency Diagnostics\\.*\.(etl|log|xml)$') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\(Temp|Package Cache|USOPrivate\\UpdateStore)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\pip\\cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\npm-cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Yarn\\Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\pnpm-store\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NuGet\\v3-cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\pipx\\Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\uv\\Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.gradle\\caches\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.m2\\repository\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.cargo\\registry\\cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.nuget\\packages\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.cache\\(pip|uv|node-gyp|electron|ms-playwright)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.npm\\(_cacache|_logs)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\(SquirrelTemp|Downloaded Installations|Package Cache|Crashpad\\reports|CrashReportClient\\Saved\\Crashes)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Roaming\\Code\\(Cache|CachedData|CachedExtensionVSIXs)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\VisualStudio\\[^\\]+\\(ComponentModelCache|MEIX)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NVIDIA\\NVIDIA App\\DxcCache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\D3DSCache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\DirectX Shader Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NVIDIA Corporation\\NV_Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\LocalLow\\NVIDIA\\PerDriverVersion\\[^\\]+\\DXCache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\AMD\\(DxCache|GLCache)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\(Local|LocalLow|Roaming)\\[^\\]+\\(Cache|Code Cache|GPUCache|DawnCache|GrShaderCache|ShaderCache)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\BraveSoftware\\Brave-Browser\\User Data\\[^\\]+\\(Cache|Code Cache|GPUCache|Service Worker\\ScriptCache|Service Worker\\CacheStorage|BudgetDatabase|CouponDatabase|GrShaderCache|DawnCache|GPUPersistentCache)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Vivaldi\\User Data\\[^\\]+\\(Cache|Code Cache|GPUCache|Service Worker\\ScriptCache|Service Worker\\CacheStorage|BudgetDatabase|CouponDatabase|GrShaderCache|DawnCache|GPUPersistentCache)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Mozilla\\Firefox\\Profiles\\[^\\]+\\(cache2|thumbnails)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Edge\\User Data\\[^\\]+\\(Cache|Code Cache|GPUCache|Service Worker\\ScriptCache|Service Worker\\CacheStorage|BudgetDatabase|CouponDatabase)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Google\\Chrome\\User Data\\[^\\]+\\(Service Worker\\ScriptCache|Service Worker\\CacheStorage|BudgetDatabase|CouponDatabase)\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\INetCache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\Caches\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\ServiceProfiles\\(NetworkService|LocalService)\\AppData\\Local\\Temp\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\DeliveryOptimization\\Cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\SoftwareDistribution\\Download\\') { return $true }

  if (Test-ExcludedTechnologyPath $Path) { return $false }

  if ($Path -match '(?i)^C:\\Program Files\\GIGABYTE\\Control Center\\Lib\\Download\\.*\.(exe|zip|7z|msix|cab|bin|rom|fa[0-9a-z]+)$') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\NVID\\(downloads|work)\\.*\.(exe|zip|7z|cab|dll|sys|bin|so|msi)$') { return $true }
  if ($Path -match '(?i)^C:\\Program Files \(x86\)\\Microsoft\\EdgeUpdate\\Download\\.*\.(exe|cab|msi|msu)$') { return $true }
  if ($Path -match '(?i)^C:\\Program Files \(x86\)\\Google\\GoogleUpdater\\crx_cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Google\\Chrome\\User\\extensions_crx_cache\\') { return $true }

  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\[^\\]+\\packages\\.*\.(nupkg|msi|exe)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\[^\\]+-updater\\installer\.exe$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\fitgirl-repacks-manager-updater\\installer\.exe$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.claude\\downloads\\.*\.(exe|msi|zip|nupkg)$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.pkg-cache\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.bun\\bin\\.*\.outdated$') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Wand\\app-[^\\]+\\resources\\.*\.backup$') { return $true }

  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Roaming\\hydralauncher\\CommonRedist\\.*\.(exe|zip|cab)$') { return $true }

  if ($Path -match '(?i)^C:\\Windows\\SoftwareDistribution\.bak[^\\]*\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\System32\\catroot2\.(bak|old|codexbak)[^\\]*\\') { return $true }

  if ($Path -match '(?i)^C:\\ProgramData\\HermesAMD_RyzenMasterFix\\.*\.(exe|msi|zip)$') { return $true }
  return $false
}

function Test-ForbiddenPath([string]$Path) {
  if (-not (Test-ValidCandidatePath $Path)) { return $true }
  if (-not (Test-RootedOnC $Path)) { return $true }
  if (Test-HardNeverDeletePath $Path) { return $true }
  if (Test-ExplicitDisposablePath $Path) { return $false }
  if (Test-ExcludedTechnologyPath $Path) { return $true }
  if ($Path -match '(?i)^C:\\(pagefile|hiberfil|swapfile)\.sys$') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\(WinSxS|servicing|Installer|assembly|Microsoft\.NET|Fonts|System32\\config|System32\\DriverStore|System32\\catroot2)\\') { return $true }
  if ($Path -match '(?i)^C:\\Windows\\SoftwareDistribution(?!\.bak_)\\') { return $true }
  if (($Path -match '(?i)^C:\\Windows\\(SystemApps|Logs|SoftwareDistribution(?!\.bak_)|System32\\LogFiles|SysWOW64|System32)\\') -and (-not (Test-DisposablePatternPath $Path))) { return $true }
  if ($Path -match '(?i)^C:\\Windows\\SystemTemp\\.*\.(exe|dll|sys|drv|ocx|vdm|manifest|cat|mum)$') { return $true }
  if (($Path -match '(?i)^C:\\Program Files( \(x86\))?\\') -and (-not (Test-DisposablePatternPath $Path))) { return $true }
  if (($Path -match '(?i)^C:\\ProgramData\\Microsoft\\(Windows Defender|Network\\Downloader)\\') -and (-not (Test-DisposablePatternPath $Path))) { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\(Microsoft\\Windows\\Containers|Package Cache|Docker|NVIDIA Corporation\\DockerDesktop)\\') { return $true }
  if (($Path -match '(?i)^C:\\ProgramData\\USOShared\\Logs\\') -and (-not (Test-DisposablePatternPath $Path))) { return $true }
  if ($Path -match '(?i)\\(Docker|Docker Desktop|dockerdesktop|containerd|moby|Windows\\Containers)\\') { return $true }
  if ($Path -match '(?i)(\\|^)(ext4|docker_data|wsl|wsl2)[^\\]*\.vhdx$') { return $true }
  if ($Path -match '(?i)\\(python|pyenv|conda|anaconda|miniconda|venv|site-packages|uv\\python|pseverythingpy)\\') { return $true }
  if ($Path -match '(?i)\\(Hermes|\.hermes|\.codex|Phone Link|Packages\\Microsoft\.YourPhone|Packages\\Microsoft\.YourPhone_|Packages\\OpenAI\.Codex_)') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\Codex\\') { return $true }
  if ($Path -match '(?i)^C:\\ProgramData\\CodexCrashHardening\\') { return $true }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.local\\share\\opencode\\log\\') { return $true }
  if ($Path -match '(?i)\\AppData\\Roaming\\[^\\]+\\(Local Storage|IndexedDB)\\') { return $true }
  if (($Path -match '(?i)^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Videos|Music|OneDrive|Downloads|CrossDevice)\\') -and (-not (Test-UserFolderDisposablePath $Path))) { return $true }
  if ($Path -match '(?i)\\(IndexedDB|Local Storage|Session Storage|databases?)\\') { return $true }
  if (($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\') -and ($Path -match '(?i)\\[^\\]*(Database|State|Settings|System|bin)[^\\]*\\')) { return $true }
  if ($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\.*\\(Database|bin|System|Settings|State)\\') { return $true }
  if ($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\.*\.(db|sqlite|sqlite3|edb|ldb|log|wal|shm|dll|exe)$') { return $true }
  if ($Path -match '(?i)\\(Chrome|Edge|Firefox)\\User Data\\.*\\(Cookies|History|Login Data|Preferences|Secure Preferences|Local Storage|IndexedDB|Sessions|Extensions)') { return $true }
  if (($Path -match '(?i)\\(Google\\Chrome|Microsoft\\Edge|Mozilla\\Firefox|Chrome|Edge|Firefox)\\') -and ($Path -match '(?i)\\User( Data)?\\|\\Profiles?\\') -and ($Path -notmatch '(?i)\\(Cache|Code Cache|GPUCache|GrShaderCache|DawnCache|GPUPersistentCache|component_crx_cache)\\')) { return $true }
  return $false
}

function Test-ImmediatelyDeletable([string]$Path) {
  if (-not (Test-ValidCandidatePath $Path)) { return $false }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) { return $false }
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    return $true
  } catch {
    return $false
  } finally {
    if ($stream) { $stream.Close(); $stream.Dispose() }
  }
}

function Test-ActiveVolatileDiagnosticFile($Info) {
  if (-not $Info -or $Info.PSIsContainer) { return $false }
  $path = [string]$Info.FullName
  if ($path -notmatch '(?i)\.(log|etl|pml|trace|csv|wer)$') { return $false }
  return ($Info.LastWriteTime -gt (Get-Date).AddMinutes(-5))
}

function Test-PendingDeleteOnReboot([string]$Path) {
  if (-not (Test-ValidCandidatePath $Path)) { return $false }
  $nativePath = '\??\' + $Path
  try {
    $pending = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($null -eq $pending) { return $false }
    foreach ($entry in @($pending)) {
      if ([string]::Equals([string]$entry, $nativePath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
  } catch {}
  return $false
}

function Get-DeleteReadiness([string]$Path) {
  if (Test-PendingDeleteOnReboot $Path) { return 'Scheduled for deletion on reboot' }
  if ($OnlyImmediatelyDeletable) { return 'Openable now' }
  return 'Manifest candidate; may be locked until related apps/services close'
}

function Add-PendingDeleteRegistryEntry([string]$Path) {
  $nativePath = '\??\' + $Path
  $propertyName = 'PendingFileRenameOperations'
  $key = $null
  try {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $true)
    if ($null -eq $key) { throw 'Session Manager registry key not found.' }
    $existingValue = $key.GetValue($propertyName, @(), [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $existing = @()
    if ($null -ne $existingValue) { $existing = @($existingValue) }
    for ($i = 0; $i -lt $existing.Count; $i += 2) {
      if ([string]::Equals([string]$existing[$i], $nativePath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $updated = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $existing) { $updated.Add([string]$entry) | Out-Null }
    $updated.Add($nativePath) | Out-Null
    $updated.Add('') | Out-Null
    $key.SetValue($propertyName, [string[]]$updated.ToArray(), [Microsoft.Win32.RegistryValueKind]::MultiString)
    return (Test-PendingDeleteOnReboot $Path)
  } finally {
    if ($key) { $key.Dispose() }
  }
}

function Get-CleanupClassification([string]$Path) {
  if (Test-ForbiddenPath $Path) { return $null }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\stability-reports\\nvidia-driver-backup\\') { return 'Generated Codex stability-report driver backup artifact' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\(work|logs|reports)\\') { return 'Generated Codex workspace work/log/report artifact' }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows Defender\\Quarantine\\ResourceData\\') { return 'Microsoft Defender quarantine payload' }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows Defender\\Scans\\mpcache-[^\\]+$') { return 'Microsoft Defender rebuildable scan cache' }
  if ($Path -match '(?i)\\Temp\\|\\Windows\\Temp\\|\\SystemTemp\\|\.(tmp|temp)$') { return 'Temporary file / temp folder residue' }
  if ($Path -match '(?i)\.etl$|\\WDI\\LogFiles\\|\\System32\\LogFiles\\WMI\\|\\DiagOutputDir\\') { return 'Diagnostic trace (.etl) / diagnostics output' }
  if ($Path -match '(?i)\.(log|wer|pml|trace|csv)$|\\Windows\\Logs\\|\\CrashDumps\\|\\WER\\') { return 'Log / crash / Windows Error Reporting residue' }
  if ($Path -match '(?i)\\(Cache|LocalCache|Code Cache|GPUCache|DawnCache|GrShaderCache|ShaderCache|ComputeCache|DXCache|GLCache|INetCache|crx_cache)\\|\.ushaderprecache$') { return 'Rebuildable application/browser/GPU cache' }
  if ($Path -match '(?i)\\(npm-cache|Yarn\\Cache|pnpm-store|NuGet\\v3-cache)\\') { return 'Package-manager download cache' }
  if ($Path -match '(?i)\\SoftwareDistribution\\Download\\|\\DeliveryOptimization\\Cache\\') { return 'Windows Update / Delivery Optimization download cache' }
  if ($Path -match '(?i)\.(old|bak)$') { return 'Old backup/previous-version residue' }
  if ($Path -match '(?i)\.(dmp|mdmp|hdmp)$') { return 'Memory dump / crash dump' }
  if ($Path -match '(?i)^C:\\ProgramData\\Package Cache\\') { return 'Re-downloadable Windows Installer package cache' }
  if ($Path -match '(?i)^C:\\Windows\\Installer\\\$patchcache\$\\') { return 'Windows Installer orphaned patch cache' }
  if ($Path -match '(?i)^C:\\Windows\\CbsTemp\\') { return 'Windows CBS servicing temp files' }
  if ($Path -match '(?i)^C:\\Windows\\LiveKernelReports\\') { return 'Windows live kernel crash reports' }
  if ($Path -match '(?i)^C:\\Windows\\Minidump\\') { return 'Windows minidump crash reports' }
  if ($Path -match '(?i)^C:\\Windows\\Memory\.dmp$') { return 'Full Windows memory dump' }
  if ($Path -match '(?i)^C:\\CrashDumps\\') { return 'Application crash dump' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\CrashDumps\\') { return 'User application crash dump' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\Explorer\\(thumbcache|iconcache)') { return 'Windows Explorer thumbnail/icon cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\PeerDistRepub\\') { return 'Branch Cache peer distribution cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\WER\\') { return 'Windows Error Reporting temp data' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\CloudStore\\') { return 'Windows CloudStore sync cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Packages\\[^\\]+\\TempState\\') { return 'UWP app temporary state' }
  if ($Path -match '(?i)^C:\\ProgramData\\USOShared\\Logs\\') { return 'Windows Update shared orchestrator logs' }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\WER\\(ReportQueue|ReportArchive)\\') { return 'Windows Error Reporting archived reports' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\pip\\cache\\') { return 'Python pip download cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\npm-cache\\') { return 'Node.js npm download cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Yarn\\Cache\\') { return 'Yarn package cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\pnpm-store\\') { return 'pnpm content-addressable store' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NuGet\\v3-cache\\') { return 'NuGet v3 download cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.gradle\\caches\\') { return 'Gradle build cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.m2\\repository\\') { return 'Maven local repository cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.cargo\\registry\\cache\\') { return 'Rust Cargo registry download cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\.nuget\\packages\\') { return 'NuGet restored packages cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Roaming\\Code\\(Cache|CachedData|CachedExtensionVSIXs)\\') { return 'VS Code application cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\VisualStudio\\[^\\]+\\(ComponentModelCache|MEIX)\\') { return 'Visual Studio component model / MEF cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NVIDIA\\NVIDIA App\\DxcCache\\') { return 'NVIDIA DX shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\D3DSCache\\') { return 'Direct3D shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\DirectX Shader Cache\\') { return 'DirectX shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\NVIDIA Corporation\\NV_Cache\\') { return 'NVIDIA driver shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\LocalLow\\NVIDIA\\PerDriverVersion\\[^\\]+\\DXCache\\') { return 'NVIDIA per-driver DirectX shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\AMD\\(DxCache|GLCache)\\') { return 'AMD GPU shader cache (rebuildable)' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\(Local|LocalLow|Roaming)\\[^\\]+\\(Cache|Code Cache|GPUCache|DawnCache|GrShaderCache|ShaderCache)\\') { return 'Application cache subtree' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\(BraveSoftware\\Brave-Browser|Vivaldi)\\User Data\\[^\\]+\\(Cache|Code Cache|GPUCache|Service Worker|BudgetDatabase|CouponDatabase|GrShaderCache|DawnCache|GPUPersistentCache)\\') { return 'Alternative browser cache data' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Mozilla\\Firefox\\Profiles\\[^\\]+\\(cache2|thumbnails)\\') { return 'Firefox cache / thumbnail data' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Edge\\User Data\\[^\\]+\\(Service Worker|BudgetDatabase|CouponDatabase)\\') { return 'Edge Service Worker / budget cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Google\\Chrome\\User Data\\[^\\]+\\(Service Worker|BudgetDatabase|CouponDatabase)\\') { return 'Chrome Service Worker / budget cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\INetCache\\') { return 'Windows INet / IE download cache' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows\\Caches\\') { return 'Windows per-user cache subtree' }
  if ($Path -match '(?i)^C:\\Windows\\ServiceProfiles\\(NetworkService|LocalService)\\AppData\\Local\\Temp\\') { return 'Windows service-profile temporary file' }
  if ($Path -match '(?i)^C:\\Windows\\ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Cache\\') { return 'Delivery Optimization service cache' }
  if ($Path -match '(?i)^C:\\ProgramData\\Microsoft\\Windows\\DeliveryOptimization\\Cache\\') { return 'Delivery Optimization program data cache' }
  if (Test-ExplicitDisposablePath $Path) { return 'High-confidence downloaded installer/update cache or obsolete package payload' }
  return $null
}

function Get-SafetyNote([string]$Path, [string]$Class) {
  if ($Class -match 'Codex stability-report') { return 'Generated diagnostic driver backup under a dated Codex work folder; installed DriverStore/NVIDIA live state remains excluded.' }
  if ($Class -match 'Codex workspace') { return 'Generated work/log/report artifact under a dated Codex work folder; active Codex state and databases remain excluded.' }
  if ($Class -match 'Defender') { return 'Defender quarantine/cache payload; active Defender platform, definitions, and settings remain excluded.' }
  if ($Class -match 'browser') { return 'Cache class only; identity, cookies, history, passwords, sessions, and extensions are excluded.' }
  if ($Class -match 'GPU') { return 'GPU shader/cache class; may be regenerated and may be locked while graphics apps run.' }
  if ($Class -match 'Windows Update') { return 'Downloaded update payload only; servicing stores are excluded.' }
  if ($Class -match 'installer') { return 'Downloaded installer/update payload; installed application folders are excluded unless path is a known cache/download subtree.' }
  if ($Class -match 'Package Cache') { return 'Re-downloadable Windows Installer cached payload; can be re-fetched from Windows Update or original installer.' }
  if ($Class -match 'patch cache') { return 'Windows Installer patch cache; rebuildable on next patch application.' }
  if ($Class -match 'CBS') { return 'CBS servicing temp files; recreated as needed by Windows servicing stack.' }
  if ($Class -match 'kernel') { return 'Live kernel crash reports; diagnostic only, safe to remove.' }
  if ($Class -match 'minidump') { return 'Minidump crash reports; diagnostic only, safe to remove.' }
  if ($Class -match 'memory dump') { return 'Full memory dump; diagnostic only, safe to remove.' }
  if ($Class -match 'crash dump') { return 'Application crash dump; diagnostic only, safe to remove.' }
  if ($Class -match 'thumbnail|icon cache') { return 'Explorer thumbnail/icon cache; rebuilds automatically on next folder browse.' }
  if ($Class -match 'Branch Cache') { return 'Branch Cache peer distribution data; transparently re-fetched from content server.' }
  if ($Class -match 'WER') { return 'Windows Error Reporting data; diagnostic only, safe to remove.' }
  if ($Class -match 'CloudStore') { return 'Windows CloudStore sync cache; re-syncs from cloud on next login.' }
  if ($Class -match 'TempState') { return 'UWP app temporary state; recreated on next app launch.' }
  if ($Class -match 'USOShared') { return 'Windows Update orchestrator logs; safe to remove.' }
  if ($Class -match 'pip') { return 'Python pip download cache; re-downloads on next pip install.' }
  if ($Class -match 'npm') { return 'Node.js npm download cache; re-downloads on next npm install.' }
  if ($Class -match 'Yarn') { return 'Yarn package cache; re-downloads on next yarn install.' }
  if ($Class -match 'pnpm') { return 'pnpm content-addressable store; re-downloads on next pnpm install.' }
  if ($Class -match 'NuGet') { return 'NuGet package cache; re-downloads on next dotnet restore.' }
  if ($Class -match 'Gradle') { return 'Gradle build cache; re-downloads on next gradle build.' }
  if ($Class -match 'Maven') { return 'Maven local repository cache; re-downloads on next mvn build.' }
  if ($Class -match 'Cargo') { return 'Rust Cargo registry download cache; re-downloads on next cargo build.' }
  if ($Class -match 'VS Code') { return 'VS Code application cache; rebuilds automatically.' }
  if ($Class -match 'Visual Studio') { return 'Visual Studio component model / MEF cache; rebuilds on next VS launch.' }
  if ($Class -match 'NVIDIA DX|AMD') { return 'GPU shader cache; rebuilds automatically when apps regenerate shaders.' }
  if ($Class -match 'Direct3D|DirectX|NVIDIA driver|per-driver|Application cache|Windows per-user cache') { return 'Rebuildable cache subtree; identity, settings, databases, and extension/session state remain excluded.' }
  if ($Class -match 'service-profile temporary') { return 'Windows service-profile temp residue; services recreate needed temp files.' }
  if ($Class -match 'Delivery Optimization') { return 'Downloaded delivery cache only; Windows re-downloads required update payloads.' }
  if ($Class -match 'alternative browser') { return 'Alternative browser cache/profile data; identity data excluded.' }
  if ($Class -match 'Firefox') { return 'Firefox cache / thumbnail data; identity data excluded.' }
  if ($Class -match 'Edge Service Worker') { return 'Edge Service Worker / budget cache; rebuilds automatically.' }
  if ($Class -match 'Chrome Service Worker') { return 'Chrome Service Worker / budget cache; rebuilds automatically.' }
  if ($Class -match 'INetCache') { return 'Windows INet / IE download cache; transparent re-fetch.' }
  return 'Matched a high-confidence disposable or rebuildable file class after protected-path exclusions.'
}

function Get-PathSafetyAudit([string]$Path) {
  $valid = Test-ValidCandidatePath $Path
  $class = $null
  $eligible = $false
  $note = ''
  if ($valid) {
    $class = Get-CleanupClassification $Path
    if ($class) {
      $eligible = $true
      $note = Get-SafetyNote -Path $Path -Class $class
    } else {
      $note = 'Protected, unknown, installed, stateful, user-owned, system-owned, or not a high-confidence disposable class.'
    }
  } else {
    $note = 'Invalid candidate path or not rooted on C:.'
  }
  [pscustomobject]@{
    Eligible = $eligible
    Class = if ($class) { $class } else { '' }
    ValidCPath = $valid
    Path = $Path
    Note = $note
  }
}

function Invoke-ClassifyList([string]$ListPath) {
  if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf -ErrorAction SilentlyContinue)) {
    throw "Classify list not found: $ListPath"
  }
  Get-Content -LiteralPath $ListPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
    $p = $_.Trim().Trim('"')
    Get-PathSafetyAudit -Path $p
  }
}

function Invoke-EsLines([string[]]$Arguments) {
  $result = @(& $EsPath @Arguments)
  if ($LASTEXITCODE -ne 0) { throw "ES exit $LASTEXITCODE for arguments: $($Arguments -join ' ')" }
  @($result | ForEach-Object { [string]$_ })
}

function Test-EverythingClientAvailable {
  if (-not (Test-Path -LiteralPath $EsPath -PathType Leaf -ErrorAction SilentlyContinue)) { return $false }
  try {
    [void](Invoke-EsLines -Arguments @('-n','1','C:\'))
    return $true
  } catch {
    return $false
  }
}

function Get-ExternalHelperStatusLines {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add(('Everything CLI bundled: {0}' -f (Test-Path -LiteralPath $EsPath -PathType Leaf -ErrorAction SilentlyContinue))) | Out-Null
  $lines.Add(('Everything index service/app path: {0}' -f (Test-Path -LiteralPath $EverythingExe -PathType Leaf -ErrorAction SilentlyContinue))) | Out-Null
  $lines.Add(('ripgrep available for EFU filtering: {0}' -f [bool](Get-Command rg -ErrorAction SilentlyContinue))) | Out-Null
  $lines.Add(('Windows cleanmgr available for manual OS cleanup: {0}' -f [bool](Get-Command cleanmgr -ErrorAction SilentlyContinue))) | Out-Null
  $lines.Add(('Windows DISM available for component-store analysis: {0}' -f [bool](Get-Command dism.exe -ErrorAction SilentlyContinue))) | Out-Null
  foreach ($optional in @('wiztree','WizTree64','BleachBit','winget')) {
    $cmd = Get-Command $optional -ErrorAction SilentlyContinue
    if ($cmd) {
      $lines.Add(('{0} optional helper: {1}' -f $optional, $cmd.Source)) | Out-Null
    } else {
      $lines.Add(('{0} optional helper: not installed or not on PATH' -f $optional)) | Out-Null
    }
  }
  @($lines)
}

function Get-DirectorySizeBytes([string]$Path, [int]$MaxFiles = 200000) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue)) { return 0L }
  $total = 0L
  $seen = 0
  $pending = New-Object System.Collections.Generic.Queue[string]
  $pending.Enqueue($Path)
  while (($pending.Count -gt 0) -and ($seen -lt $MaxFiles)) {
    $directory = $pending.Dequeue()
    try {
      $dirInfo = New-Object System.IO.DirectoryInfo($directory)
      if (($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    } catch { continue }
    try {
      foreach ($subdir in [System.IO.Directory]::EnumerateDirectories($directory)) {
        try {
          $subdirInfo = New-Object System.IO.DirectoryInfo($subdir)
          if (($subdirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { $pending.Enqueue($subdir) }
        } catch {}
      }
    } catch {}
    try {
      foreach ($file in [System.IO.Directory]::EnumerateFiles($directory)) {
        try {
          $info = New-Object System.IO.FileInfo($file)
          if (($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            $total += [int64]$info.Length
            $seen++
            if ($seen -ge $MaxFiles) { break }
          }
        } catch {}
      }
    } catch {}
  }
  $total
}

function Add-SystemCleanupOpportunity($Rows, [string]$Name, [int64]$Bytes, [string]$Action, [string]$Safety, [string]$Evidence) {
  [void]$Rows.Add([pscustomobject]@{
    Name = $Name
    Bytes = $Bytes
    Size = Format-BytesHuman $Bytes
    Action = $Action
    Safety = $Safety
    Evidence = $Evidence
  })
}

function Get-DismAnalyzeText {
  $dism = Get-Command dism.exe -ErrorAction SilentlyContinue
  if (-not $dism) { return @() }
  try {
    @(& $dism.Source /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | ForEach-Object { [string]$_ })
  } catch {
    @("DISM_ANALYZE_FAILED: $($_.Exception.Message)")
  }
}

function Get-CleanMgrVolumeCacheHandlers {
  $handlers = New-Object System.Collections.ArrayList
  $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
  if (-not (Test-Path -LiteralPath $base -ErrorAction SilentlyContinue)) { return @() }
  try {
    foreach ($key in Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue) {
      $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
      [void]$handlers.Add([pscustomobject]@{
        Handler = $key.PSChildName
        Description = [string]$props.Description
        Display = [string]$props.Display
      })
    }
  } catch {}
  @($handlers | Sort-Object Handler)
}

function Get-SystemCleanupOpportunities {
  $rows = New-Object System.Collections.ArrayList

  Add-SystemCleanupOpportunity -Rows $rows -Name 'Windows Storage settings cleanup recommendations' -Bytes 0 -Action 'Open ms-settings:storagesense and Windows Cleanup recommendations for Microsoft-supported cleanup that can include prior Windows installs, delivery optimization, thumbnails, DirectX shader cache, and temporary files.' -Safety 'REPORT_ONLY: this is a user-mediated Windows Settings surface; 100ccc does not invoke deletion or toggle Storage Sense automatically.' -Evidence 'ms-settings:storagesense; ms-settings:storagepolicies'

  $dismText = @(Get-DismAnalyzeText)
  if ($dismText.Count -gt 0) {
    $recommended = ($dismText | Where-Object { $_ -match '(?i)Component Store Cleanup Recommended\s*:\s*Yes' } | Select-Object -First 1)
    $evidence = ($dismText | Where-Object { $_ -match '(?i)(Component Store Cleanup Recommended|Backups and Disabled Features|Cache and Temporary Data|Date of Last Cleanup)' }) -join ' | '
    Add-SystemCleanupOpportunity -Rows $rows -Name 'Windows component store analysis (DISM)' -Bytes 0 -Action 'Review DISM output; if cleanup is recommended, use the Microsoft-supported StartComponentCleanup task or DISM StartComponentCleanup from an elevated shell.' -Safety 'REPORT_ONLY: component store is protected Windows servicing state and is never included in the file delete manifest.' -Evidence $evidence
  }

  $handlers = @(Get-CleanMgrVolumeCacheHandlers)
  if ($handlers.Count -gt 0) {
    Add-SystemCleanupOpportunity -Rows $rows -Name 'Disk Cleanup cleanmgr handler inventory' -Bytes 0 -Action 'Use cleanmgr /sageset and /sagerun for Microsoft-supported cleanup classes after selecting only safe handlers.' -Safety 'REPORT_ONLY: cleanmgr is not invoked destructively by 100ccc; this records available OS cleanup categories.' -Evidence (($handlers | Select-Object -ExpandProperty Handler) -join ', ')
  }

  foreach ($path in @('C:\$Recycle.Bin','C:\Windows.old','C:\$WINDOWS.~BT','C:\$WINDOWS.~WS','C:\ESD','C:\RecoveryImage','C:\ProgramData\Microsoft\Windows\Caches','C:\ProgramData\Microsoft\Windows\WER\Temp','C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache')) {
    if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
      $bytes = Get-DirectorySizeBytes -Path $path -MaxFiles 200000
      $name = switch -Exact ($path) {
        'C:\$Recycle.Bin' { 'Recycle Bin contents'; break }
        'C:\ProgramData\Microsoft\Windows\Caches' { 'ProgramData Windows cache inventory'; break }
        'C:\ProgramData\Microsoft\Windows\WER\Temp' { 'Windows Error Reporting temporary inventory'; break }
        'C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache' { 'Delivery Optimization cache inventory'; break }
        default { "Windows upgrade/recovery residue: $path" }
      }
      $safety = switch -Exact ($path) {
        'C:\$Recycle.Bin' { 'REVIEW_ONLY: Recycle Bin can contain user-restorable files, so 100ccc never puts it in the automatic delete manifest.'; break }
        'C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache' { 'REVIEW_ONLY: Delivery Optimization is a Windows-managed cache; use Windows Settings/Disk Cleanup instead of raw deletion while services may be active.'; break }
        'C:\ProgramData\Microsoft\Windows\WER\Temp' { 'REVIEW_ONLY: WER temporary files are Windows-managed; raw deletion is avoided to prevent racing active reporting processes.'; break }
        'C:\ProgramData\Microsoft\Windows\Caches' { 'REVIEW_ONLY: shared Windows cache state can be process-owned; 100ccc reports size only and leaves cleanup to supported Windows surfaces.'; break }
        default { 'REVIEW_ONLY: upgrade/rollback/recovery folders may be needed for rollback or recovery; use Windows Disk Cleanup/Storage Sense after user review.' }
      }
      Add-SystemCleanupOpportunity -Rows $rows -Name $name -Bytes $bytes -Action 'Review with Windows-supported cleanup UI/cleanmgr/Storage Sense instead of raw deletion.' -Safety $safety -Evidence $path
    }
  }

  @($rows | Sort-Object Bytes -Descending)
}

function Save-SystemCleanupOpportunityFiles($Context) {
  $rows = @(Get-SystemCleanupOpportunities)
  if ($rows.Count -gt 0) {
    $rows | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $Context.SystemCleanupJsonPath
  } else {
    '[]' | Set-Content -Encoding UTF8 -Path $Context.SystemCleanupJsonPath
  }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('C: Max Safe Delete Audit - SYSTEM CLEANUP OPPORTUNITIES') | Out-Null
  $lines.Add('These are report-only opportunities discovered through supported Windows or external-tool surfaces. They are never included in the generated delete command.') | Out-Null
  $lines.Add(('Rows: {0}' -f $rows.Count)) | Out-Null
  $lines.Add('') | Out-Null
  foreach ($row in $rows) {
    $lines.Add(('{0,12} | {1}' -f $row.Size, $row.Name)) | Out-Null
    $lines.Add(('        Action: {0}' -f $row.Action)) | Out-Null
    $lines.Add(('        Safety: {0}' -f $row.Safety)) | Out-Null
    $lines.Add(('        Evidence: {0}' -f $row.Evidence)) | Out-Null
  }
  $lines | Set-Content -Encoding UTF8 -Path $Context.SystemCleanupReportPath
  [pscustomobject]@{ Count=$rows.Count; JsonPath=$Context.SystemCleanupJsonPath; ReportPath=$Context.SystemCleanupReportPath }
}

function Ensure-EverythingClientAvailable {
  if (Test-EverythingClientAvailable) { return $true }
  if (Test-Path -LiteralPath $EverythingExe -PathType Leaf -ErrorAction SilentlyContinue) {
    Start-Process -FilePath $EverythingExe -ArgumentList '-startup' -WindowStyle Minimized | Out-Null
    $deadline = (Get-Date).AddSeconds(8)
    do {
      Start-Sleep -Milliseconds 400
      if (Test-EverythingClientAvailable) { return $true }
    } while ((Get-Date) -lt $deadline)
  }
  return $false
}

function Parse-EsCsvLine([string]$Line) {
  if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
  $m = [regex]::Match($Line, '^(\d+),([^,]*),"(.*)"$')
  if (-not $m.Success) { return $null }
  $bytes = 0L
  if (-not [int64]::TryParse($m.Groups[1].Value, [ref]$bytes)) { return $null }
  if ($bytes -lt 0) { return $null }
  $path = $m.Groups[3].Value.Replace('""','"')
  if (-not (Test-ValidCandidatePath $path)) { return $null }
  [pscustomobject]@{ Bytes=$bytes; LastWriteTime=$m.Groups[2].Value; Path=$path }
}

function Convert-FileTimeTextToLocalText([string]$Value) {
  $ticks = 0L
  if ([int64]::TryParse($Value, [ref]$ticks) -and ($ticks -gt 0)) {
    try { return ([DateTime]::FromFileTime($ticks).ToString('yyyy-MM-dd HH:mm:ss')) } catch {}
  }
  return $Value
}

function Parse-EfuCsvLine([string]$Line) {
  if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
  if ($Line -match '^(?i)Filename,Size,Date Modified,') { return $null }
  $m = [regex]::Match($Line, '^"((?:[^"]|"")*)",(-?\d+),([^,]*),[^,]*,(-?\d+)\s*$')
  if (-not $m.Success) { return $null }
  $path = $m.Groups[1].Value.Replace('""','"')
  if (-not (Test-ValidCandidatePath $path)) { return $null }
  $bytes = 0L
  if (-not [int64]::TryParse($m.Groups[2].Value, [ref]$bytes)) { return $null }
  if ($bytes -lt 0) { return $null }
  $attributes = 0
  if ([int]::TryParse($m.Groups[4].Value, [ref]$attributes) -and (($attributes -band 16) -ne 0)) { return $null }
  [pscustomobject]@{
    Bytes = $bytes
    LastWriteTime = Convert-FileTimeTextToLocalText $m.Groups[3].Value
    Path = $path
  }
}

function Get-EfuCleanupPattern {
  return '(?i)(cache|caches|temp|tmp|logs?|crashdumps?|reportqueue|reportarchive|download|downloads|downloader|installer|installers|setup|update|updates|redist|commonredist|shadercache|dxcache|glcache|gpucache|dawncache|grshadercache|component_crx_cache|deliveryoptimization\\cache|softwaredistribution\\download|stability-reports\\nvidia-driver-backup|\\Documents\\Codex\\\d{4}-\d{2}-\d{2}\\[^\\]+\\(work|logs|reports)\\|Windows Defender\\Quarantine\\ResourceData|Windows Defender\\Scans\\mpcache|procmon|sandbox-procmon|sandbox-server-procmon|\.etl|\.log|\.tmp|\.temp|\.part|\.crdownload|\.download|\.partial|\.old|\.bak|\.backup|\.outdated|\.corrupt-|\.dmp|\.mdmp|\.hdmp|\.wer|\.pml|\.nupkg|thumbcache|iconcache|\.ushaderprecache|Package.Cache|\\\$patchcache\$|CbsTemp|LiveKernelReports|Minidump|Memory\.dmp|PeerDistRepub|CloudStore|TempState|USOShared|Windows\\\\WER|WindowsUpdate|Panther|DeviceMetadataCache|Power.Efficiency.Diagnostics|Diagnosis\\\\(ETLLogs|DownloadedSettings)|npm-cache|Yarn\\\\Cache|pnpm-store|NuGet\\\\v3-cache|pipx\\\\Cache|uv\\\\Cache|\.cache\\\\(pip|uv|node-gyp|electron|ms-playwright)|\.npm\\\\(_cacache|_logs)|\.gradle\\\\caches|\.m2\\\\repository|\.cargo\\\\registry\\\\cache|\.nuget\\\\packages|SquirrelTemp|Downloaded.Installations|Crashpad\\\\reports|CrashReportClient\\\\Saved\\\\Crashes|Code\\\\(Cache|CachedData|CachedExtensionVSIXs)|VisualStudio.*\\\\(ComponentModelCache|MEIX)|NVIDIA.App\\\\DxcCache|AMD\\\\(DxCache|GLCache)|BraveSoftware|Vivaldi|Firefox.*\\\\(cache2|thumbnails)|Service.Worker|BudgetDatabase|CouponDatabase|INetCache)'
}

function Get-EfuCandidateLines {
  if ([string]::IsNullOrWhiteSpace($EfuPath)) { return @() }
  if (-not (Test-Path -LiteralPath $EfuPath -PathType Leaf -ErrorAction SilentlyContinue)) { return @() }
  $pattern = Get-EfuCleanupPattern
  $rg = Get-Command rg -ErrorAction SilentlyContinue
  if ($rg) {
    $args = @('-i')
    if ($EfuScanLimit -gt 0) { $args += @('-m', [string]$EfuScanLimit) }
    $args += @($pattern, $EfuPath)
    return @(& $rg.Source @args | ForEach-Object { [string]$_ })
  }
  $lines = New-Object System.Collections.ArrayList
  $reader = $null
  try {
    $reader = New-Object System.IO.StreamReader($EfuPath, [Text.Encoding]::UTF8, $true)
    $lineCount = 0
    while (-not $reader.EndOfStream) {
      $lineCount++
      $line = [string]$reader.ReadLine()
      if ($line -match $pattern) { [void]$lines.Add($line) }
      if (($EfuScanLimit -gt 0) -and ($lineCount -ge $EfuScanLimit)) { break }
    }
  } finally {
    if ($reader) { $reader.Close(); $reader.Dispose() }
  }
  @($lines)
}

function Get-CleanupQueries {
  @(
    'C:\',
    'cache|temp|download|downloads|installer|setup|update|package|packages|redist|driver|*.etl|*.log|*.tmp|*.temp|*.old|*.bak|*.dmp|*.mdmp|*.hdmp|*.wer|*.crdownload|*.part|*.nupkg|*.outdated|thumbcache|iconcache|*.ushaderprecache',
    'DXCache|GLCache|GPUCache|DawnCache|GrShaderCache|ShaderCache|ComputeCache|D3DSCache|NV_Cache|NVIDIA|AMD|*.nvph|*.ushaderprecache|DxcCache',
    'download|downloads|downloader|installer|installers|setup|update|updates|package|packages|redist|commonredist|driver|*.exe|*.msi|*.msu|*.cab|*.zip|*.7z|*.rar|*.nupkg|*.appx|*.appxbundle|*.msix|*.msixbundle',
    'cache|caches|tmp|temp|crashdump|crashdumps|wer|reportqueue|reportarchive|livekernelreports|INetCache|HttpCache|blob_storage|CacheStorage|SoftwareDistribution\Download|DeliveryOptimization\Cache|Windows\Temp|Windows\SystemTemp|AppData\Local\Temp|CbsTemp|Minidump|Memory.dmp|PeerDistRepub|CloudStore|TempState|USOShared',
    'procmon|sandbox-procmon|sandbox-server-procmon|*.pml|*.dmp|*.mdmp|*.hdmp|*.wer|*.etl|*.tmp|*.temp|*.part|*.crdownload|*.download|*.partial|*.old|*.bak|*.backup|*.outdated|*.corrupt-*.bak|*.corrupt_*.bak|thumbcache|iconcache',
    'npm-cache|Yarn Cache|pnpm-store|NuGet v3-cache|.gradle caches|.m2 repository|.cargo registry cache|.nuget packages|Code Cache|Code CachedData|VisualStudio ComponentModelCache|pip cache',
    'BraveSoftware|Vivaldi|Firefox cache2|Firefox thumbnails|Service Worker ScriptCache|Service Worker CacheStorage|BudgetDatabase|CouponDatabase|INetCache',
    'Package Cache|$patchcache$|CrashDumps'
    'Panther|WindowsUpdate|DeviceMetadataCache|Power Efficiency Diagnostics|Diagnosis ETLLogs|DownloadedSettings|SquirrelTemp|Crashpad reports|CrashReportClient Saved Crashes|Downloaded Installations'
    '.cache pip|.cache uv|.cache node-gyp|.cache electron|.cache ms-playwright|.npm _cacache|pipx Cache|uv Cache'
  )
}

function Add-ExistingDirectoryRoot($Roots, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-RootedOnC $Path)) { return }
  if (Test-ExcludedTechnologyPath $Path) { return }
  if (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue) {
    [void]$Roots.Add($Path)
  }
}

function Add-ExistingDirectoryChildren($Roots, [string]$Path, [string[]]$Names) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue)) { return }
  try {
    foreach ($child in Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue) {
      foreach ($name in $Names) {
        Add-ExistingDirectoryRoot -Roots $Roots -Path (Join-Path $child.FullName $name)
      }
    }
  } catch {}
}

function Get-TargetedFilesystemRoots {
  $roots = New-Object System.Collections.ArrayList
  foreach ($path in @(
    'C:\Windows\Temp',
    'C:\Windows\SystemTemp',
    'C:\Windows\SoftwareDistribution\Download',
    'C:\Windows\CbsTemp',
    'C:\Windows\LiveKernelReports',
    'C:\Windows\Minidump',
    'C:\Windows\Logs\DISM',
    'C:\Windows\Logs\MoSetup',
    'C:\Windows\Logs\WindowsUpdate',
    'C:\Windows\Panther',
    'C:\Windows\debug',
    'C:\Windows\System32\config\systemprofile\AppData\Local\Temp',
    'C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Temp',
    'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp',
    'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp',
    'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache',
    'C:\ProgramData\Temp',
    'C:\ProgramData\Package Cache',
    'C:\Windows\Installer\$PatchCache$',
    'C:\ProgramData\Microsoft\Diagnosis\ETLLogs',
    'C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings',
    'C:\ProgramData\Microsoft\Windows\DeviceMetadataCache',
    'C:\ProgramData\Microsoft\Windows\Power Efficiency Diagnostics',
    'C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache',
    'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
    'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
    'C:\ProgramData\USOShared\Logs',
    'C:\ProgramData\Microsoft\Windows Defender\Quarantine\ResourceData'
  )) {
    Add-ExistingDirectoryRoot -Roots $roots -Path $path
  }

  if (Test-Path -LiteralPath 'C:\Users' -PathType Container -ErrorAction SilentlyContinue) {
    foreach ($user in Get-ChildItem -LiteralPath 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue) {
      foreach ($relative in @(
        'AppData\Local\Temp',
        'AppData\Local\CrashDumps',
        'AppData\Local\Microsoft\Windows\WER',
        'AppData\Local\Microsoft\Windows\Explorer',
        'AppData\Local\Microsoft\Windows\INetCache',
        'AppData\Local\pip\cache',
        'AppData\Local\npm-cache',
        'AppData\Local\Yarn\Cache',
        'AppData\Local\pnpm-store',
        'AppData\Local\NuGet\v3-cache',
        'AppData\Local\pipx\Cache',
        'AppData\Local\uv\Cache',
        'AppData\Local\SquirrelTemp',
        'AppData\Local\Downloaded Installations',
        'AppData\Local\Package Cache',
        'AppData\Local\Crashpad\reports',
        'AppData\Local\CrashReportClient\Saved\Crashes',
        '.cache\pip',
        '.cache\uv',
        '.cache\node-gyp',
        '.cache\electron',
        '.cache\ms-playwright',
        '.npm\_cacache',
        '.npm\_logs',
        '.gradle\caches',
        '.m2\repository',
        '.cargo\registry\cache',
        '.nuget\packages',
        'AppData\Roaming\Code\Cache',
        'AppData\Roaming\Code\CachedData',
        'AppData\Roaming\Code\CachedExtensionVSIXs',
        'AppData\Local\D3DSCache',
        'AppData\Local\Microsoft\DirectX Shader Cache',
        'AppData\Local\Microsoft\Windows\Caches',
        'AppData\Local\NVIDIA\DXCache',
        'AppData\Local\NVIDIA\GLCache',
        'AppData\Local\NVIDIA\ComputeCache',
        'AppData\Local\NVIDIA\NVIDIA App\DxcCache',
        'AppData\Local\NVIDIA Corporation\NV_Cache',
        'AppData\Local\AMD\DxCache',
        'AppData\Local\AMD\GLCache'
      )) {
        Add-ExistingDirectoryRoot -Roots $roots -Path (Join-Path $user.FullName $relative)
      }

      foreach ($appDataRoot in @('AppData\Local','AppData\LocalLow','AppData\Roaming')) {
        Add-ExistingDirectoryChildren -Roots $roots -Path (Join-Path $user.FullName $appDataRoot) -Names @(
          'Cache',
          'Code Cache',
          'GPUCache',
          'DawnCache',
          'GrShaderCache',
          'ShaderCache'
        )
      }
      Add-ExistingDirectoryChildren -Roots $roots -Path (Join-Path $user.FullName 'AppData\LocalLow\NVIDIA\PerDriverVersion') -Names @('DXCache')
      Add-ExistingDirectoryChildren -Roots $roots -Path (Join-Path $user.FullName 'AppData\Local\Microsoft\VisualStudio') -Names @('ComponentModelCache','MEIX')
      foreach ($browserRoot in @(
        'AppData\Local\Google\Chrome\User Data',
        'AppData\Local\Microsoft\Edge\User Data',
        'AppData\Local\BraveSoftware\Brave-Browser\User Data',
        'AppData\Local\Vivaldi\User Data'
      )) {
        Add-ExistingDirectoryChildren -Roots $roots -Path (Join-Path $user.FullName $browserRoot) -Names @(
          'Cache',
          'Code Cache',
          'GPUCache',
          'Service Worker\ScriptCache',
          'Service Worker\CacheStorage',
          'BudgetDatabase',
          'CouponDatabase',
          'GrShaderCache',
          'DawnCache',
          'GPUPersistentCache',
          'component_crx_cache'
        )
      }
      Add-ExistingDirectoryChildren -Roots $roots -Path (Join-Path $user.FullName 'AppData\Local\Mozilla\Firefox\Profiles') -Names @('cache2','thumbnails')
    }
  }

  @($roots | Select-Object -Unique)
}

function Get-CandidatesFromEfu {
  if ([string]::IsNullOrWhiteSpace($EfuPath)) { return @() }
  if (-not (Test-Path -LiteralPath $EfuPath -PathType Leaf -ErrorAction SilentlyContinue)) { return @() }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList
  foreach ($line in @(Get-EfuCandidateLines)) {
    $parsed = Parse-EfuCsvLine ([string]$line)
    if (-not $parsed) { continue }
    Add-CandidateRow -Rows $rows -Seen $seen -Path $parsed.Path -Bytes $parsed.Bytes -LastWriteTime $parsed.LastWriteTime
    if (($MaxCandidates -gt 0) -and ($rows.Count -ge ($MaxCandidates * 4))) { break }
  }
  @($rows | Sort-Object Bytes -Descending)
}

function Get-CandidatesFromTargetedFilesystem {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList
  foreach ($rootPath in @(Get-TargetedFilesystemRoots)) {
    $addedFromRoot = 0
    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue($rootPath)
    while (($pending.Count -gt 0) -and ($addedFromRoot -lt 50000)) {
      $directory = $pending.Dequeue()
      try {
        $dirInfo = New-Object System.IO.DirectoryInfo($directory)
        if (($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
      } catch { continue }
      try {
        foreach ($subdir in [System.IO.Directory]::EnumerateDirectories($directory)) {
          try {
            $subdirInfo = New-Object System.IO.DirectoryInfo($subdir)
            if (($subdirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
              $pending.Enqueue($subdir)
            }
          } catch {}
        }
      } catch {}
      try {
        foreach ($file in [System.IO.Directory]::EnumerateFiles($directory)) {
        try {
          $info = New-Object System.IO.FileInfo($file)
          if (($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
          Add-CandidateRow -Rows $rows -Seen $seen -Path $info.FullName -Bytes ([int64]$info.Length) -LastWriteTime $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
          $addedFromRoot++
          if ($addedFromRoot -ge 50000) { break }
        } catch {}
      }
      } catch {}
    }
  }
  @($rows | Sort-Object Bytes -Descending)
}

function Get-CandidatesFromEverything {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList

  foreach ($query in Get-CleanupQueries) {
    $take = $EverythingLimit
    if (($MaxCandidates -gt 0) -and ($take -gt ($MaxCandidates * 80))) { $take = [Math]::Max(1000, $MaxCandidates * 80) }
    $args = @('-p','/a-d','-csv','-no-header','-size','-size-format','1','-dm','-date-format','1','-full-path-and-name','-sort','size','-sort-descending','-n',[string]$take,$query)
    foreach ($line in @(Invoke-EsLines -Arguments $args)) {
      $parsed = Parse-EsCsvLine ([string]$line)
      if (-not $parsed) { continue }
      Add-CandidateRow -Rows $rows -Seen $seen -Path $parsed.Path -Bytes $parsed.Bytes -LastWriteTime $parsed.LastWriteTime
      if (($MaxCandidates -gt 0) -and ($rows.Count -ge $MaxCandidates)) { break }
    }
    if (($MaxCandidates -gt 0) -and ($rows.Count -ge $MaxCandidates)) { break }
  }

  @($rows | Sort-Object Bytes -Descending)
}

function Add-CandidateRow($Rows, $Seen, [string]$Path, [int64]$Bytes, [string]$LastWriteTime) {
  if (-not (Test-ValidCandidatePath $Path)) { return }
  if (-not $Seen.Add($Path)) { return }
  $info = $null
  try {
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
  } catch {
    return
  }
  if (-not $info -or $info.PSIsContainer) { return }
  if (Test-ActiveVolatileDiagnosticFile $info) { return }
  $class = Get-CleanupClassification $Path
  if (-not $class) { return }
  $liveBytes = [int64]$info.Length
  $liveLastWriteTime = $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  $confirmInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $confirmInfo -or $confirmInfo.PSIsContainer) { return }
  if ([int64]$confirmInfo.Length -ne $liveBytes) { return }
  if ($confirmInfo.LastWriteTime -ne $info.LastWriteTime) { return }
  [void]$Rows.Add([pscustomobject]@{
    Rank = 0
    Bytes = $liveBytes
    Size = Format-BytesHuman $liveBytes
    LastWriteTime = $liveLastWriteTime
    Reason = $class
    SafetyNote = Get-SafetyNote -Path $Path -Class $class
    DeleteReadiness = Get-DeleteReadiness $Path
    Path = $Path
  })
}

function Get-CandidatesFromFilesystem {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList
  $pending = New-Object System.Collections.Generic.Queue[string]
  $pending.Enqueue($Root)
  while ($pending.Count -gt 0) {
    $directory = $pending.Dequeue()
    try {
      foreach ($subdir in [System.IO.Directory]::EnumerateDirectories($directory)) {
        $pending.Enqueue($subdir)
      }
    } catch {}
    try {
      foreach ($file in [System.IO.Directory]::EnumerateFiles($directory)) {
        try {
          $info = New-Object System.IO.FileInfo($file)
          Add-CandidateRow -Rows $rows -Seen $seen -Path $info.FullName -Bytes ([int64]$info.Length) -LastWriteTime $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
          if (($MaxCandidates -gt 0) -and ($rows.Count -ge $MaxCandidates)) { return @($rows | Sort-Object Bytes -Descending) }
        } catch {}
      }
    } catch {}
  }
  @($rows | Sort-Object Bytes -Descending)
}

function Get-Candidates {
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList
  $sources = @()
  $sources += @(Get-CandidatesFromEfu)
  $sources += @(Get-CandidatesFromTargetedFilesystem)
  if (Ensure-EverythingClientAvailable) {
    $sources += @(Get-CandidatesFromEverything)
  } else {
    $sources += @(Get-CandidatesFromFilesystem)
  }
  foreach ($candidate in @($sources | Sort-Object Bytes -Descending)) {
    if (-not $seen.Add($candidate.Path)) { continue }
    [void]$rows.Add($candidate)
    if (($MaxCandidates -gt 0) -and ($rows.Count -ge $MaxCandidates)) { break }
  }
  @($rows | Sort-Object Bytes -Descending)
}

function Get-BlockedReviewReason([string]$Path) {
  if (Test-HardNeverDeletePath $Path) { return 'Hard protected: virtual disk, container/WSL/Docker, source-control, database/storage, or identity/session state' }
  if (Test-ExcludedTechnologyPath $Path) { return 'Protected technology/runtime path' }
  if ($Path -match '(?i)^C:\\Windows\\(WinSxS|servicing|Installer|assembly|Microsoft\.NET|Fonts|System32\\config|System32\\DriverStore|System32\\catroot2)\\') { return 'Windows servicing, installer, driver, or system store' }
  if ($Path -match '(?i)^C:\\Program Files( \(x86\))?\\') { return 'Installed application tree; cleanup-looking name is not enough' }
  if ($Path -match '(?i)^C:\\Users\\[^\\]+\\(Documents|Desktop|Pictures|Videos|Music|OneDrive|Downloads|CrossDevice)\\') { return 'User-owned folder; not high-confidence disposable' }
  if ($Path -match '(?i)\\AppData\\Local\\Packages\\[^\\]+\\(LocalState|LocalCache)\\') { return 'Packaged-app state/cache area; not safe without a narrower allow rule' }
  if ($Path -match '(?i)\\AppData\\Roaming\\') { return 'Roaming application state; not safe unless a known cache subtree is matched' }
  return 'Cleanup-looking but not high-confidence safe for automatic deletion'
}

function Add-ReviewOnlyRow($Rows, $Seen, $SafeSeen, [string]$Path, [int64]$Bytes, [string]$LastWriteTime) {
  if (-not (Test-ValidCandidatePath $Path)) { return }
  if (-not $Seen.Add($Path)) { return }
  if ($SafeSeen.Contains($Path)) { return }
  if (Get-CleanupClassification $Path) { return }
  if (($Path -notmatch (Get-EfuCleanupPattern)) -and (-not (Test-DisposablePatternPath $Path))) { return }
  $info = $null
  try {
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
  } catch {
    return
  }
  if (-not $info -or $info.PSIsContainer) { return }
  $liveBytes = [int64]$info.Length
  if ($liveBytes -lt $ReviewMinimumBytes) { return }
  [void]$Rows.Add([pscustomobject]@{
    Rank = 0
    Bytes = $liveBytes
    Size = Format-BytesHuman $liveBytes
    LastWriteTime = $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    ReviewReason = Get-BlockedReviewReason $Path
    DeleteCommandAction = 'NOT_INCLUDED_IN_DELETE_COMMAND'
    Path = $Path
  })
}

function Get-ReviewOnlyBlockedRows($SafeCandidates) {
  $safeSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($candidate in @($SafeCandidates)) {
    if ($candidate.Path) { [void]$safeSeen.Add([string]$candidate.Path) }
  }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $rows = New-Object System.Collections.ArrayList
  foreach ($line in @(Get-EfuCandidateLines)) {
    $parsed = Parse-EfuCsvLine ([string]$line)
    if (-not $parsed) { continue }
    Add-ReviewOnlyRow -Rows $rows -Seen $seen -SafeSeen $safeSeen -Path $parsed.Path -Bytes $parsed.Bytes -LastWriteTime $parsed.LastWriteTime
    if (($ReviewLimit -gt 0) -and ($rows.Count -ge ($ReviewLimit * 3))) { break }
  }
  $rank = 1
  $reviewRows = @($rows | Sort-Object Bytes -Descending | Select-Object -First $ReviewLimit)
  foreach ($row in $reviewRows) { $row.Rank = $rank; $rank++ }
  @($reviewRows)
}

function Save-ReviewOnlyFiles($Context, $SafeCandidates) {
  $reviewRows = @(Get-ReviewOnlyBlockedRows $SafeCandidates)
  $totalBytes = 0L
  foreach ($row in $reviewRows) { $totalBytes += [int64]$row.Bytes }
  if ($reviewRows.Count -gt 0) {
    $reviewRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Context.ReviewCsvPath
    $reviewRows | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $Context.ReviewJsonPath
  } else {
    '"Rank","Bytes","Size","LastWriteTime","ReviewReason","DeleteCommandAction","Path"' | Set-Content -Encoding UTF8 -Path $Context.ReviewCsvPath
    '[]' | Set-Content -Encoding UTF8 -Path $Context.ReviewJsonPath
  }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('C: Max Safe Delete Audit - REVIEW ONLY BLOCKED PATHS') | Out-Null
  $lines.Add('These cleanup-looking paths were deliberately NOT included in the delete command because they are protected, stateful, user-owned, installed-app-owned, or not high-confidence safe.') | Out-Null
  $lines.Add(('Rows: {0}' -f $reviewRows.Count)) | Out-Null
  $lines.Add(('Bytes represented: {0:N0}' -f $totalBytes)) | Out-Null
  $lines.Add(('Human: {0}' -f (Format-BytesHuman $totalBytes))) | Out-Null
  $lines.Add('Delete command action: NONE. This file is visibility only.') | Out-Null
  $lines.Add('') | Out-Null
  foreach ($row in $reviewRows) {
    $lines.Add(('{0,6}. {1,12} | {2} | {3}' -f $row.Rank, $row.Size, $row.ReviewReason, $row.Path)) | Out-Null
    $lines.Add(('        Modified: {0}' -f $row.LastWriteTime)) | Out-Null
  }
  $lines | Set-Content -Encoding UTF8 -Path $Context.ReviewReportPath
  [pscustomobject]@{ Count=$reviewRows.Count; TotalBytes=$totalBytes; CsvPath=$Context.ReviewCsvPath; ReportPath=$Context.ReviewReportPath }
}

function Copy-ReviewFilesToCache($Context, $Cache) {
  foreach ($pair in @(
    @{ Source=$Context.ReviewCsvPath; Target=$Cache.ReviewCsvPath },
    @{ Source=$Context.ReviewJsonPath; Target=$Cache.ReviewJsonPath },
    @{ Source=$Context.ReviewReportPath; Target=$Cache.ReviewReportPath },
    @{ Source=$Context.SystemCleanupJsonPath; Target=$Cache.SystemCleanupJsonPath },
    @{ Source=$Context.SystemCleanupReportPath; Target=$Cache.SystemCleanupReportPath }
  )) {
    if (Test-Path -LiteralPath $pair.Source -PathType Leaf -ErrorAction SilentlyContinue) {
      Copy-Item -LiteralPath $pair.Source -Destination $pair.Target -Force
    }
  }
}

function Assert-NoNulBytes([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  foreach ($b in $bytes) {
    if ($b -eq 0) { throw "Output file contains NUL bytes and will not be used: $Path" }
  }
}

function Assert-CsvManifestValid([string]$Path, [int]$ExpectedCount) {
  Assert-NoNulBytes $Path
  $rows = @(Import-Csv -LiteralPath $Path)
  if ($rows.Count -ne $ExpectedCount) {
    throw "CSV manifest round-trip mismatch: expected $ExpectedCount rows, imported $($rows.Count) rows from $Path"
  }
  foreach ($row in $rows) {
    if (-not (Test-ValidCandidatePath $row.Path)) { throw "CSV manifest contains invalid path: $($row.Path)" }
    $item = Get-Item -LiteralPath $row.Path -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { throw "CSV manifest contains missing or non-file path: $($row.Path)" }
    $manifestBytes = 0L
    if (-not [int64]::TryParse([string]$row.Bytes, [ref]$manifestBytes)) { throw "CSV manifest contains invalid byte count: $($row.Path)" }
    if ($manifestBytes -ne [int64]$item.Length) {
      throw "CSV manifest byte count is stale for $($row.Path): manifest=$manifestBytes live=$($item.Length)"
    }
  }
}

function Get-LiveExactCandidateRows($Candidates) {
  $rows = New-Object System.Collections.ArrayList
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($candidate in @($Candidates)) {
    if (-not $candidate.Path) { continue }
    if (-not $seen.Add([string]$candidate.Path)) { continue }
    $row = Add-CandidateRow -Rows $rows -Seen (New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)) -Path ([string]$candidate.Path) -Bytes 0 -LastWriteTime ''
    if ($null -ne $row) {
      $row.Reason = [string]$candidate.Reason
      $row.SafetyNote = [string]$candidate.SafetyNote
      $row.DeleteReadiness = 'Openable now; live byte count verified'
    }
  }
  @($rows | Sort-Object Bytes -Descending)
}

function Write-StableCandidateFiles($Candidates, [string]$CsvPath, [string]$JsonPath) {
  $current = @($Candidates)
  for ($attempt = 1; $attempt -le 50; $attempt++) {
    $live = @(Get-LiveExactCandidateRows $current)
    $rank = 1
    foreach ($candidate in $live) { $candidate.Rank = $rank; $rank++ }
    $live | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath
    if ($live.Count -gt 0) {
      $live | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $JsonPath
    } else {
      '[]' | Set-Content -Encoding UTF8 -Path $JsonPath
    }
    try {
      Assert-CsvManifestValid -Path $CsvPath -ExpectedCount $live.Count
      Assert-NoNulBytes -Path $JsonPath
      return @($live)
    } catch {
      if ($attempt -ge 50) { throw }
      $message = [string]$_.Exception.Message
      $badPath = ''
      if ($message -match 'CSV manifest byte count is stale for (.*): manifest=') {
        $badPath = $Matches[1]
      } elseif ($message -match 'CSV manifest contains missing or non-file path: (.*)$') {
        $badPath = $Matches[1]
      }
      if (-not [string]::IsNullOrWhiteSpace($badPath)) {
        $current = @($live | Where-Object { -not [string]::Equals([string]$_.Path, $badPath, [StringComparison]::OrdinalIgnoreCase) })
      } else {
        $current = $live
      }
      Start-Sleep -Milliseconds 250
    }
  }
  return @()
}

function Set-ClipboardVerified([string]$Value) {
  Set-Clipboard -Value $Value
  Start-Sleep -Milliseconds 200
  $actual = Get-Clipboard -Raw
  if (($null -eq $actual) -or ($actual.TrimEnd("`r","`n") -cne $Value.TrimEnd("`r","`n"))) {
    throw 'Clipboard verification failed; refusing to claim the cleanup one-liner was copied.'
  }
}

function Register-DeleteOnReboot([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Success=$false; ErrorCode=2; ErrorMessage='Path no longer exists' }
  }
  $class = Get-CleanupClassification $Path
  if (-not $class) {
    return [pscustomobject]@{ Success=$false; ErrorCode=0; ErrorMessage='Path is not a current cleanup candidate' }
  }
  if (-not ('Win32MoveFileEx' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win32MoveFileEx {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
}
'@
  }
  $MOVEFILE_DELAY_UNTIL_REBOOT = 0x4
  $ok = [Win32MoveFileEx]::MoveFileEx($Path, [NullString]::Value, $MOVEFILE_DELAY_UNTIL_REBOOT)
  if ($ok -and (Test-PendingDeleteOnReboot $Path)) {
    return [pscustomobject]@{ Success=$true; ErrorCode=0; ErrorMessage='' }
  }
  $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  $moveFileMessage = if ($ok) { 'MoveFileEx returned success but pending delete was not readable' } else { ([ComponentModel.Win32Exception]$code).Message }
  try {
    if (Add-PendingDeleteRegistryEntry $Path) {
      return [pscustomobject]@{ Success=$true; ErrorCode=0; ErrorMessage='Registry pending-delete fallback' }
    }
    return [pscustomobject]@{ Success=$false; ErrorCode=$code; ErrorMessage=('{0}; registry fallback did not read back pending delete' -f $moveFileMessage) }
  } catch {
    return [pscustomobject]@{ Success=$false; ErrorCode=$code; ErrorMessage=('{0}; registry fallback failed: {1}' -f $moveFileMessage, $_.Exception.Message) }
  }
}

function New-DeleteOneLiner([string]$ManifestPath) {
  # ALLOW_DESTRUCTIVE: generated only after audit; targets the exact manifest requested by the user.
  $script = $PSCommandPath
  $payload = @"
`$ErrorActionPreference='Stop'; `$script='$script'; `$m='$ManifestPath'; if(-not (Test-Path -LiteralPath `$script -PathType Leaf)){ throw "Cleanup script not found: `$script" }; if(-not (Test-Path -LiteralPath `$m -PathType Leaf)){ throw "Manifest not found: `$m" }; & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File `$script -ForceDeleteListed -DeleteManifest `$m -ScheduleFailedForReboot; exit `$LASTEXITCODE
"@
  'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + (ConvertTo-Base64Utf16 $payload)
}

function Save-Reports($Context, $Candidates, [datetime]$StartedAt, [datetime]$FinishedAt) {
  $Candidates = @(Write-StableCandidateFiles -Candidates $Candidates -CsvPath $Context.CsvPath -JsonPath $Context.JsonPath)
  $reviewData = Save-ReviewOnlyFiles -Context $Context -SafeCandidates $Candidates
  $systemCleanupData = Save-SystemCleanupOpportunityFiles -Context $Context
  $totalBytes = 0
  if ($Candidates.Count -gt 0) {
    foreach ($candidate in $Candidates) { $totalBytes += [int64]$candidate.Bytes }
  }
  foreach ($candidate in $Candidates) {
    if (-not (Test-ValidCandidatePath $candidate.Path)) { throw "Refusing to write manifest with invalid candidate path: $($candidate.Path)" }
  }
  $oneLiner = if ($Candidates.Count -gt 0) { New-DeleteOneLiner $Context.CsvPath } else { 'NO_DELETE_LINER_NO_CANDIDATES' }
  Set-Content -Encoding ASCII -Path $Context.DeleteOneLinerPath -Value $oneLiner
  if (($Candidates.Count -gt 0) -and (-not $NoClipboard)) { Set-ClipboardVerified -Value $oneLiner }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('C: Max Safe Delete Audit - READ ONLY') | Out-Null
  $lines.Add('Purpose: maximize safely recoverable C: free space without deleting installed apps, Windows servicing stores, user data, credentials, databases, virtual disks, source-control packs, or live state that may be needed.') | Out-Null
  $lines.Add(('Run: {0}' -f $Context.RunId)) | Out-Null
  $lines.Add(('Started: {0}' -f $StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))) | Out-Null
  $lines.Add(('Finished: {0}' -f $FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))) | Out-Null
  $lines.Add(('Duration: {0:N2}s' -f (($FinishedAt - $StartedAt).TotalSeconds))) | Out-Null
  $lines.Add(('Candidates: {0}' -f $Candidates.Count)) | Out-Null
  $lines.Add(('Potential bytes: {0:N0}' -f $totalBytes)) | Out-Null
  $lines.Add(('Potential human: {0}' -f (Format-BytesHuman $totalBytes))) | Out-Null
  $lines.Add(('Review-only blocked cleanup-looking paths: {0}' -f $reviewData.Count)) | Out-Null
  $lines.Add(('Review-only represented bytes: {0:N0} ({1})' -f $reviewData.TotalBytes, (Format-BytesHuman $reviewData.TotalBytes))) | Out-Null
  $lines.Add(('Review-only CSV: {0}' -f $reviewData.CsvPath)) | Out-Null
  $lines.Add(('System cleanup opportunity rows: {0}' -f $systemCleanupData.Count)) | Out-Null
  $lines.Add(('System cleanup opportunity report: {0}' -f $systemCleanupData.ReportPath)) | Out-Null
  $lines.Add('Deletion performed: NO. The clipboard one-liner deletes only the exact CSV manifest from this run.') | Out-Null
  $lines.Add('Review-only rows are never included in the generated delete command; they exist to show cleanup-looking paths that were intentionally preserved.') | Out-Null
  $lines.Add('Delete readiness: every listed file existed and matched its live byte count immediately before this report was written. Some safe cache/temp candidates may be locked by live apps; the generated force-delete command aborts before deleting anything if the manifest is stale, and can schedule failed deletes for reboot.') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('External helper status:') | Out-Null
  foreach ($helperLine in @(Get-ExternalHelperStatusLines)) {
    $lines.Add(('  - {0}' -f $helperLine)) | Out-Null
  }
  $lines.Add('') | Out-Null
  foreach ($candidate in $Candidates) {
    $lines.Add(('{0,6}. {1,12} | {2} | {3}' -f $candidate.Rank, $candidate.Size, $candidate.Reason, $candidate.Path)) | Out-Null
    $lines.Add(('        Modified: {0} | {1} | {2}' -f $candidate.LastWriteTime, $candidate.DeleteReadiness, $candidate.SafetyNote)) | Out-Null
  }
  $lines.Add('') | Out-Null
  $lines.Add('ONE-LINER COPIED TO CLIPBOARD:') | Out-Null
  $lines.Add($oneLiner) | Out-Null
  $lines | Set-Content -Encoding UTF8 -Path $Context.ReportPath
  [pscustomobject]@{ TotalBytes=$totalBytes; OneLiner=$oneLiner; ReviewCount=$reviewData.Count; ReviewBytes=$reviewData.TotalBytes; ReviewCsvPath=$reviewData.CsvPath; ReviewReportPath=$reviewData.ReportPath; SystemCleanupCount=$systemCleanupData.Count; SystemCleanupReportPath=$systemCleanupData.ReportPath }
}

function Save-CandidateCache($Candidates, [datetime]$StartedAt, [datetime]$FinishedAt) {
  $cache = Get-CacheContext
  New-Item -ItemType Directory -Force -Path $cache.Directory | Out-Null
  $Candidates = @(Write-StableCandidateFiles -Candidates $Candidates -CsvPath $cache.CsvPath -JsonPath $cache.JsonPath)
  $totalBytes = 0L
  foreach ($candidate in $Candidates) { $totalBytes += [int64]$candidate.Bytes }
  @(
    'C: Max Safe Delete Audit Cache'
    ('Generated: {0}' -f $FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))
    ('Duration: {0:N2}s' -f (($FinishedAt - $StartedAt).TotalSeconds))
    ('Candidates: {0}' -f $Candidates.Count)
    ('Potential bytes: {0:N0}' -f $totalBytes)
    ('Potential human: {0}' -f (Format-BytesHuman $totalBytes))
    ('Source EFU: {0}' -f $EfuPath)
  ) | Set-Content -Encoding UTF8 -Path $cache.SummaryPath
  return $cache
}

function Get-CandidatesFromCache {
  $cache = Get-CacheContext
  if (-not (Test-Path -LiteralPath $cache.CsvPath -PathType Leaf -ErrorAction SilentlyContinue)) { return @() }
  $rows = @(Import-Csv -LiteralPath $cache.CsvPath)
  $candidates = New-Object System.Collections.ArrayList
  foreach ($row in $rows) {
    $class = Get-CleanupClassification $row.Path
    if (-not $class) { continue }
    $bytes = 0L
    [void][int64]::TryParse([string]$row.Bytes, [ref]$bytes)
    [void]$candidates.Add([pscustomobject]@{
      Rank = 0
      Bytes = $bytes
      Size = Format-BytesHuman $bytes
      LastWriteTime = [string]$row.LastWriteTime
      Reason = $class
      SafetyNote = Get-SafetyNote -Path $row.Path -Class $class
      DeleteReadiness = Get-DeleteReadiness $row.Path
      Path = [string]$row.Path
    })
  }
  @($candidates | Sort-Object Bytes -Descending)
}

function Invoke-FastCacheOneLiner {
  $cache = Get-CacheContext
  if (-not (Test-Path -LiteralPath $cache.CsvPath -PathType Leaf -ErrorAction SilentlyContinue)) { return $false }
  $cacheRows = @(Import-Csv -LiteralPath $cache.CsvPath)
  $liveRows = @(Get-LiveExactCandidateRows $cacheRows)
  $cacheNeedsRepair = ($liveRows.Count -ne $cacheRows.Count)
  if (-not $cacheNeedsRepair) {
    for ($i = 0; $i -lt $cacheRows.Count; $i++) {
      if (([string]$liveRows[$i].Path -ne [string]$cacheRows[$i].Path) -or ([int64]$liveRows[$i].Bytes -ne [int64]$cacheRows[$i].Bytes)) {
        $cacheNeedsRepair = $true
        break
      }
    }
  }
  if ($cacheNeedsRepair) {
    $script:RequireFullRefreshAfterCacheDrift = $true
    Write-Host 'Cached manifest has drifted; running a full refresh instead of shrinking the cache.' -ForegroundColor Yellow
    return $false
  }
  Assert-CsvManifestValid -Path $cache.CsvPath -ExpectedCount $cacheRows.Count
  $oneLiner = New-DeleteOneLiner $cache.CsvPath
  $oneLinerPath = Join-Path $cache.Directory 'latest-max-safe-delete-one-liner.txt'
  Set-Content -Encoding ASCII -Path $oneLinerPath -Value $oneLiner
  Set-ClipboardVerified -Value $oneLiner
  $summary = @()
  if (Test-Path -LiteralPath $cache.SummaryPath -PathType Leaf -ErrorAction SilentlyContinue) {
    $summary = @(Get-Content -LiteralPath $cache.SummaryPath)
  }
  $candidateLine = ($summary | Where-Object { $_ -match '^Candidates:' } | Select-Object -First 1)
  $potentialLine = ($summary | Where-Object { $_ -match '^Potential human:' } | Select-Object -First 1)
  $candidateText = if ($candidateLine) { $candidateLine.Replace('Candidates:','').Trim() } else { 'cached' }
  $potentialText = if ($potentialLine) { $potentialLine.Replace('Potential human:','').Trim() } else { 'cached' }
  Write-Host ('C: max safe delete audit ready from cache. Candidates={0} Potential={1}' -f $candidateText,$potentialText) -ForegroundColor Green
  Write-Host ('CSV manifest: {0}' -f $cache.CsvPath) -ForegroundColor Green
  if (Test-Path -LiteralPath $cache.ReviewCsvPath -PathType Leaf -ErrorAction SilentlyContinue) {
    Write-Host ('Review-only blocked manifest: {0}' -f $cache.ReviewCsvPath) -ForegroundColor Yellow
  }
  if (Test-Path -LiteralPath $cache.SystemCleanupReportPath -PathType Leaf -ErrorAction SilentlyContinue) {
    Write-Host ('System cleanup opportunities: {0}' -f $cache.SystemCleanupReportPath) -ForegroundColor Yellow
  }
  Write-Host ('One-liner file: {0}' -f $oneLinerPath) -ForegroundColor Green
  Write-Host 'The manifest-driven cleanup one-liner was copied to the clipboard.' -ForegroundColor Yellow
  return $true
}

function Invoke-DeleteManifest([string]$ManifestPath) {
  # ALLOW_DESTRUCTIVE: explicit -ForceDeleteListed path only; normal audit mode never reaches this function.
  if (-not (Test-Path -LiteralPath $ManifestPath -ErrorAction SilentlyContinue)) { throw "Manifest not found: $ManifestPath" }
  $rows = @(Import-Csv -LiteralPath $ManifestPath)
  Assert-CsvManifestValid -Path $ManifestPath -ExpectedCount $rows.Count
  $expectedBytes = 0L
  $preflightFailures = New-Object System.Collections.ArrayList
  foreach ($r in $rows) {
    $p = [string]$r.Path
    $manifestBytes = 0L
    if (-not [int64]::TryParse([string]$r.Bytes, [ref]$manifestBytes)) {
      [void]$preflightFailures.Add("INVALID_BYTES: $p")
      continue
    }
    if (-not (Get-CleanupClassification $p)) {
      [void]$preflightFailures.Add("UNSAFE_NOW: $p")
      continue
    }
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (($null -eq $item) -or $item.PSIsContainer) {
      [void]$preflightFailures.Add("MISSING_NOW: $p")
      continue
    }
    if ([int64]$item.Length -ne $manifestBytes) {
      [void]$preflightFailures.Add(("SIZE_CHANGED: {0} manifest={1} live={2}" -f $p,$manifestBytes,$item.Length))
      continue
    }
    $expectedBytes += $manifestBytes
  }
  if ($preflightFailures.Count -gt 0) {
    foreach ($failure in $preflightFailures) { Write-Host $failure -ForegroundColor Red }
    throw "Delete manifest is stale or unsafe; deleted nothing. Refresh with: 100ccc -RefreshCache"
  }
  $ok = 0; $missing = 0; $fail = 0; $scheduled = 0; $unsafe = 0; $deletedBytes = 0L
  foreach ($r in $rows) {
    $p = $r.Path
    try {
      if (-not (Get-CleanupClassification $p)) {
        $unsafe++
        Write-Host ('SKIPPED_UNSAFE: {0}' -f $p) -ForegroundColor Yellow
        continue
      }
      $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      if ($null -eq $item) {
        $missing++
        continue
      }
      $manifestBytes = [int64]$r.Bytes
      Remove-Item -LiteralPath $p -Force -ErrorAction Stop
      $ok++
      $deletedBytes += $manifestBytes
    } catch {
      if ($ScheduleFailedForReboot) {
        $pending = Register-DeleteOnReboot $p
        if ($pending.Success) {
          $scheduled++
          Write-Host ('SCHEDULED_REBOOT_DELETE: {0}' -f $p) -ForegroundColor Yellow
        } else {
          $fail++
          Write-Host ('FAILED: {0} :: {1} | reboot-schedule failed: [{2}] {3}' -f $p, $_.Exception.Message, $pending.ErrorCode, $pending.ErrorMessage) -ForegroundColor Red
        }
      } else {
        $fail++
        Write-Host ('FAILED: {0} :: {1}' -f $p, $_.Exception.Message) -ForegroundColor Red
      }
    }
  }
  Write-Host ('C-drive cleanup finished. Deleted={0} DeletedBytes={1:N0} ExpectedBytes={2:N0} Missing={3} ScheduledRebootDelete={4} SkippedUnsafe={5} Failed={6} Manifest={7}' -f $ok,$deletedBytes,$expectedBytes,$missing,$scheduled,$unsafe,$fail,$ManifestPath) -ForegroundColor Green
}

function Invoke-SelfTest {
  $cases = @(
    @{ Path='C:\Users\micha\AppData\Local\Temp\a.tmp'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\important.tmp'; Expect=$false },
    @{ Path='C:\Windows\System32\DriverStore\FileRepository\a.tmp'; Expect=$false },
    @{ Path='C:\Windows\System32\LogFiles\WMI\trace.etl'; Expect=$true },
    @{ Path='C:\Program Files\SomeApp\Cache\old.tmp'; Expect=$true },
    @{ Path='C:\Program Files\SomeApp\app.exe'; Expect=$false },
    @{ Path='C:\Users\micha\Downloads\setup.tmp'; Expect=$true },
    @{ Path='C:\Users\micha\Downloads\resume.pdf'; Expect=$false },
    @{ Path='C:\Windows\Logs\CBS\CBS.log'; Expect=$true },
    @{ Path='C:\Windows\Logs\WindowsUpdate\WindowsUpdate.20260707.001.etl'; Expect=$true },
    @{ Path='C:\Windows\Panther\setupact.log'; Expect=$true },
    @{ Path='C:\Windows\INF\setupapi.dev.log'; Expect=$true },
    @{ Path='C:\Windows\debug\NetSetup.log'; Expect=$true },
    @{ Path='C:\Windows\System32\WDI\LogFiles\BootPerfDiagLogger.etl'; Expect=$true },
    @{ Path='C:\Windows\System32\LogFiles\WMI\RtBackup\EtwRTDiagLog.etl'; Expect=$true },
    @{ Path='C:\Windows\System32\config\systemprofile\AppData\Local\Temp\svc.tmp'; Expect=$true },
    @{ Path='C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Temp\svc.tmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\Cache\data_1'; Expect=$true },
    @{ Path='C:\$WINDOWS.~BT\NewOS\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\Cortana.UI\cache\SVLocal\Desktop\12.js'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA\DXCache\e000a91c4d51283f.nvph'; Expect=$true },
    @{ Path='C:\ProgramData\NVIDIA Corporation\Downloader\latest\nvidia-driver.exe'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\Login Data'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA Corporation\NVIDIA App\CefCache\Default\IndexedDB\https_nvfile_0.indexeddb.leveldb\000003.log'; Expect=$false },
    @{ Path='C:\Windows\SoftwareDistribution\Download\abc.cab'; Expect=$true },
    @{ Path='C:\ProgramData\Package Cache\abc.msi'; Expect=$true },
    @{ Path='C:\Users\micha\.docker\config.json.corrupt-before-codex-dkill-repair-20260606-0359.bak'; Expect=$false },
    @{ Path='C:\Users\micha\.codex\logs\old.log'; Expect=$false },
    @{ Path='C:\Users\micha\.codex\workspace\linkedin-auto-apply\chrome-profile2-rd\Profile 2\Cache\Cache_Data\data_3'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\PSEverythingPy\index.jsonl.tmp'; Expect=$true },
    @{ Path='C:\Windows\UUS\Packages\Preview\amd64\MoUsoCoreWorker.exe'; Expect=$false },
    @{ Path='C:\Windows\SystemTemp\87E8A338-AD30-4CD1-848E-542E3561DE51\en-US\MpAsDesc.dll.mui'; Expect=$true },
    @{ Path='C:\ProgramData\USOPrivate\UpdateStore\store.bak'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\WebCache\V01.log'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Temp\D2EF1A23-FD9E-4EFE-99E8-C09AFC7EF5D4\swap.vhdx'; Expect=$false },
    @{ Path='C:\Users\micha\Documents\Codex\2026-06-28\sandbox-is-broken-and-not-launching\sandbox-repair-project\logs\sandbox-procmon-20260628-133635.pml'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\Codex\2026-06-28\sandbox-is-broken-and-not-launching\sandbox-repair-project\logs\sandbox-server-procmon-20260628-134145.csv'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.full.ps1.corrupt-20260625-191611.bak'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.full.definitions.ps1.corrupt-20260625-191611.bak'; Expect=$true },
    @{ Path='C:\Users\micha\.codex\db-backups\sqlite-1782168608-0\logs_2.sqlite.corrupt_20260628_140346.bak'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Docker\wsl\data\ext4.vhdx'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx'; Expect=$false },
    @{ Path='C:\Users\micha\Documents\Codex\2026-06-05\browser-task\repo\.git\objects\pack\pack-1111111111111111111111111111111111111111.pack'; Expect=$false },
    @{ Path='C:\Users\micha\.codex\logs_2.sqlite'; Expect=$false },
    @{ Path='C:\Users\micha\Documents\Codex\2026-06-30\f-study-dev-toolchain-programming-python\work\wiztree-c-admin-639183935886945422.csv'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\Codex\2026-06-13\e-games-avatarfrontiersofpandora-this-game-crashed\stability-reports\nvidia-driver-backup\NVIDIA-610.52-current\nvdxdlkernels.dll'; Expect=$true },
    @{ Path='C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_6f3cfb7117944855\nvdxdlkernels.dll'; Expect=$false },
    @{ Path='C:\ProgramData\Microsoft\Windows Defender\Quarantine\ResourceData\E6\E6C551E65C27575A7FEAE5B760D63729F8AF7A8C'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows Defender\Definition Updates\Backup\mpasbase.vdm'; Expect=$false },
    @{ Path='C:\ProgramData\Microsoft\Windows Defender\Scans\mpcache-3626D24E93D2B0560EA4D61636C41B0B6667BD6B.bin.7E'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'; Expect=$false },
    @{ Path='C:\CrashDumps\Games\CrossDeviceService.exe.3040.dmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\CrashDumps\myapp.exe.1234.dmp'; Expect=$true },
    @{ Path='C:\Windows\CbsTemp\some-temp-file.tmp'; Expect=$true },
    @{ Path='C:\Windows\LiveKernelReports\livekernel.dmp'; Expect=$true },
    @{ Path='C:\Windows\Minidump\063026-12345-01.dmp'; Expect=$true },
    @{ Path='C:\Windows\Memory.dmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\Explorer\thumbcache_32.db'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\Explorer\iconcache_32.db'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\PeerDistRepub\repub-cache.dat'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\WER\Temp\report.wer'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\CloudStore\cache.dat'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Packages\SomeApp\TempState\cache.tmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\LocalState\EBWebView\Default\Site Characteristics Database\LOG.old'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\LocalState\EBWebView\Default\Extension State\LOG.old'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\LocalState\EBWebView\Default\BudgetDatabase\LOG.old'; Expect=$false },
    @{ Path='C:\ProgramData\USOShared\Logs\update.log'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Diagnosis\ETLLogs\AutoLogger\diag.etl'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings\settings.json'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows\DeviceMetadataCache\dmrccache\payload.tmp'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows\Power Efficiency Diagnostics\energy-report.xml'; Expect=$true },
    @{ Path='C:\ProgramData\Temp\vendor.tmp'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows\WER\ReportQueue\report.txt'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows\WER\ReportArchive\report.txt'; Expect=$true },
    @{ Path='C:\ProgramData\Package Cache\abc.msi'; Expect=$true },
    @{ Path='C:\Windows\Installer\$PatchCache$\patched.msi'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\pip\cache\http-v2\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\npm-cache\_cacache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Yarn\Cache\abc.zip'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\pnpm-store\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\NuGet\v3-cache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\pipx\Cache\abc.whl'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\uv\Cache\archive-v0\abc\package.whl'; Expect=$true },
    @{ Path='C:\Users\micha\.cache\pip\http\abc'; Expect=$true },
    @{ Path='C:\Users\micha\.cache\uv\archive-v0\abc'; Expect=$true },
    @{ Path='C:\Users\micha\.cache\node-gyp\20.0.0\headers.tar.gz'; Expect=$true },
    @{ Path='C:\Users\micha\.cache\electron\electron-v1.zip'; Expect=$true },
    @{ Path='C:\Users\micha\.cache\ms-playwright\chromium-1000\chrome-win\chrome.exe'; Expect=$true },
    @{ Path='C:\Users\micha\.npm\_cacache\content-v2\sha512\aa\bb'; Expect=$true },
    @{ Path='C:\Users\micha\.npm\_logs\2026-07-07-debug.log'; Expect=$true },
    @{ Path='C:\Users\micha\.gradle\caches\modules-2\abc.jar'; Expect=$true },
    @{ Path='C:\Users\micha\.m2\repository\com\abc.jar'; Expect=$true },
    @{ Path='C:\Users\micha\.cargo\registry\cache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\.nuget\packages\abc\1.0\abc.nupkg'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\Code\Cache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\Code\CachedData\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\Code\CachedExtensionVSIXs\abc.vsix'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\VisualStudio\17.0\ComponentModelCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\VisualStudio\17.0\MEIX\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA\NVIDIA App\DxcCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\D3DSCache\abc.bin'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\DirectX Shader Cache\abc.bin'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA Corporation\NV_Cache\abc.bin'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\LocalLow\NVIDIA\PerDriverVersion\551.86\DXCache\abc.bin'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\AMD\DxCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\AMD\GLCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\SquirrelTemp\setup.log'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Downloaded Installations\installer.msi'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Package Cache\pkg.nupkg'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Crashpad\reports\crash.dmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\CrashReportClient\Saved\Crashes\crash.dmp'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\discord\Cache\data_1'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\discord\Code Cache\js\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Roaming\discord\Local Storage\leveldb\000003.log'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Roaming\Hermes\GPUCache\data_1'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA Corporation\NVIDIA App\CefCache\Default\Site Characteristics Database\LOG.old'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\NVIDIA Corporation\NVIDIA App\CefCache\Default\Sync Data\LevelDB\LOG.old'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Roaming\Codex\web\Codex\Default\Extension State\LOG.old'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Roaming\Mozilla\Firefox\Profiles\default.default-release\storage\default\https+++www.youtube.com\cache\caches.sqlite'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache\data_1'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Login Data'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Vivaldi\User Data\Default\Cache\data_1'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Vivaldi\User Data\Default\Cookies'; Expect=$false },
    @{ Path='C:\Users\micha\AppData\Local\Mozilla\Firefox\Profiles\abc\cache2\entries\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Mozilla\Firefox\Profiles\abc\thumbnails\abc.jpg'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\ScriptCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Edge\User Data\Default\BudgetDatabase\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Edge\User Data\Default\CouponDatabase\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\Service Worker\ScriptCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\Service Worker\CacheStorage\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\BudgetDatabase\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Google\Chrome\User Data\Default\CouponDatabase\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\INetCache\abc'; Expect=$true },
    @{ Path='C:\Users\micha\AppData\Local\Microsoft\Windows\Caches\abc.cache'; Expect=$true },
    @{ Path='C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp\net.tmp'; Expect=$true },
    @{ Path='C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\payload.bin'; Expect=$true },
    @{ Path='C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache\payload.bin'; Expect=$true },
    @{ Path='C:\Users\micha\Documents\Codex\2026-07-06\repo\.git\objects\pack\pack-2222222222222222222222222222222222222222.pack'; Expect=$false },
    @{ Path=("C:\Users\micha\AppData\Local\Temp\a" + [char]0 + ".tmp"); Expect=$false }
  )
  $efuParsed = Parse-EfuCsvLine '"C:\Users\micha\AppData\Local\Temp\a.tmp",1024,134272978415718128,,0'
  if (($null -eq $efuParsed) -or ($efuParsed.Path -ne 'C:\Users\micha\AppData\Local\Temp\a.tmp') -or ($efuParsed.Bytes -ne 1024)) {
    throw 'SelfTest failed: EFU CSV parser did not parse a quoted C: file row.'
  }
  $efuDirectory = Parse-EfuCsvLine '"C:\Users\micha\AppData\Local\Temp",2048,134272978415718128,,16'
  if ($null -ne $efuDirectory) {
    throw 'SelfTest failed: EFU CSV parser accepted a directory aggregate row.'
  }
  $efuBlocked = Parse-EfuCsvLine '"F:\downloads\not-c.txt",1024,134272978415718128,,0'
  if ($null -ne $efuBlocked) {
    throw 'SelfTest failed: EFU CSV parser accepted a non-C: row.'
  }
  $deleteLine = New-DeleteOneLiner 'F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\reports\CDriveMaxSafeDeleteAudit\_cache\latest-max-safe-delete-candidates.csv'
  if ($deleteLine -notmatch '^C:\\Windows\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand [A-Za-z0-9+/=]+$') {
    throw "SelfTest failed: cleanup one-liner is not a directly pasteable PS5 command: $deleteLine"
  }
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($deleteLine, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) {
    throw "SelfTest failed: cleanup one-liner does not parse in PowerShell: $($parseErrors[0].Message)"
  }
  $failed = 0
  foreach ($case in $cases) {
    $actual = [bool](Get-CleanupClassification $case.Path)
    if ($actual -ne $case.Expect) {
      $failed++
      Write-Host ('SELFTEST FAILED: {0} expected={1} actual={2}' -f $case.Path,$case.Expect,$actual) -ForegroundColor Red
    }
  }
  if ($failed -gt 0) { throw "SelfTest failed: $failed" }
  Write-Host 'SELFTEST_OK' -ForegroundColor Green
}

if ($SelfTest) {
  Invoke-SelfTest
  exit 0
}

if (-not [string]::IsNullOrWhiteSpace($ClassifyPath)) {
  Get-PathSafetyAudit -Path $ClassifyPath
  exit 0
}

if (-not [string]::IsNullOrWhiteSpace($ClassifyList)) {
  Invoke-ClassifyList -ListPath $ClassifyList
  exit 0
}

if ($ForceDeleteListed) {
  Invoke-DeleteManifest -ManifestPath $DeleteManifest
  exit 0
}

$startedAt = Get-Date
$context = New-RunContext
if (-not $RefreshCache) {
  if ((-not $NoClipboard) -and (-not $OpenReportFolder) -and (-not $OnlyImmediatelyDeletable) -and ($MaxCandidates -le 0)) {
    if (Invoke-FastCacheOneLiner) { exit 0 }
  }
  $cachedCandidates = if ($script:RequireFullRefreshAfterCacheDrift) { @() } else { @(Get-CandidatesFromCache) }
  if ($cachedCandidates.Count -gt 0) {
    $finishedAt = Get-Date
    $reportData = Save-Reports -Context $context -Candidates $cachedCandidates -StartedAt $startedAt -FinishedAt $finishedAt
    Write-Host ('C: max safe delete audit complete from cache. Candidates={0} Potential={1} Report={2}' -f $cachedCandidates.Count, (Format-BytesHuman $reportData.TotalBytes), $context.ReportPath) -ForegroundColor Green
    Write-Host ('CSV manifest: {0}' -f $context.CsvPath) -ForegroundColor Green
    Write-Host ('Review-only blocked manifest: {0}' -f $reportData.ReviewCsvPath) -ForegroundColor Yellow
    Write-Host ('System cleanup opportunities: {0}' -f $reportData.SystemCleanupReportPath) -ForegroundColor Yellow
    Write-Host ('One-liner file: {0}' -f $context.DeleteOneLinerPath) -ForegroundColor Green
    if (($cachedCandidates.Count -gt 0) -and (-not $NoClipboard)) {
      Write-Host 'The manifest-driven cleanup one-liner was copied to the clipboard.' -ForegroundColor Yellow
    }
    if ($OpenReportFolder) { Start-Process explorer.exe -ArgumentList @($context.Directory) | Out-Null }
    exit 0
  }
}
$candidates = @(Get-Candidates)
$finishedAt = Get-Date
$cache = Save-CandidateCache -Candidates $candidates -StartedAt $startedAt -FinishedAt $finishedAt
$reportData = Save-Reports -Context $context -Candidates $candidates -StartedAt $startedAt -FinishedAt $finishedAt
Copy-ReviewFilesToCache -Context $context -Cache $cache

Write-Host ('C: max safe delete audit complete. Candidates={0} Potential={1} Report={2}' -f $candidates.Count, (Format-BytesHuman $reportData.TotalBytes), $context.ReportPath) -ForegroundColor Green
Write-Host ('CSV manifest: {0}' -f $context.CsvPath) -ForegroundColor Green
Write-Host ('Review-only blocked manifest: {0}' -f $reportData.ReviewCsvPath) -ForegroundColor Yellow
Write-Host ('System cleanup opportunities: {0}' -f $reportData.SystemCleanupReportPath) -ForegroundColor Yellow
Write-Host ('Cache manifest: {0}' -f $cache.CsvPath) -ForegroundColor Green
Write-Host ('One-liner file: {0}' -f $context.DeleteOneLinerPath) -ForegroundColor Green
if (($candidates.Count -gt 0) -and (-not $NoClipboard)) {
  Write-Host 'The manifest-driven cleanup one-liner was copied to the clipboard.' -ForegroundColor Yellow
}
if ($OpenReportFolder) { Start-Process explorer.exe -ArgumentList @($context.Directory) | Out-Null }
if ($candidates.Count -eq 0) { exit 2 }
exit 0
