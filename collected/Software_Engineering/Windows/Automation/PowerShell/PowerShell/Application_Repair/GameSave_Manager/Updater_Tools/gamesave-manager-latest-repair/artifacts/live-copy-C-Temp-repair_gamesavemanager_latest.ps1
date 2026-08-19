#requires -version 3
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$InstallDir = 'F:\backup\windowsapps\installed\gamesavemanager'
$ExeName = 'gs_mngr_3.exe'
$GsmHome = 'https://www.gamesave-manager.com/'
$MaxAttempts = 5
$ProbeSeconds = 18
$Work = 'C:\Temp\gsm_latest_repair'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Log = Join-Path $Work 'last_run.log'
function Log([string]$m){ $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m); Write-Host $line; Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 }
function Get-TextFromUrl([string]$url){
  $wc = New-Object Net.WebClient
  $wc.Headers['User-Agent'] = 'Mozilla/5.0 Hermes-GSM-Repair'
  return $wc.DownloadString($url)
}
function Download-FileStrict([string]$url,[string]$out){
  $wc = New-Object Net.WebClient
  $wc.Headers['User-Agent'] = 'Mozilla/5.0 Hermes-GSM-Repair'
  $wc.DownloadFile($url,$out)
}
function HashOf([string]$path,[string]$alg){ (Get-FileHash -LiteralPath $path -Algorithm $alg).Hash.ToLowerInvariant() }
function Stop-GSM(){
  Get-Process -Name 'gs_mngr_3' -ErrorAction SilentlyContinue | ForEach-Object {
    Log ('Stopping old GameSave Manager pid={0}' -f $_.Id)
    try { $_.CloseMainWindow() | Out-Null } catch {}
  }
  Start-Sleep -Milliseconds 800
  Get-Process -Name 'gs_mngr_3' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
function Ensure-ZipAssembly(){ Add-Type -AssemblyName System.IO.Compression.FileSystem }
function Backup-Settings(){
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $backup = Join-Path $Work ('settings_backup_' + $stamp)
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  foreach($name in @('settings','bin\config.ini','bin\config.ini.bk')){
    $src = Join-Path $InstallDir $name
    if(Test-Path -LiteralPath $src){ Copy-Item -LiteralPath $src -Destination (Join-Path $backup ($name -replace '[\\/:*?"<>|]','_')) -Recurse -Force }
  }
  return $backup
}
function Install-Latest(){
  if(!(Test-Path -LiteralPath $InstallDir)){ New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }
  $html = Get-TextFromUrl $GsmHome
  $m = [regex]::Match($html, 'Download GameSave Manager v([0-9.]+)')
  if(!$m.Success){ throw 'Could not read latest GameSave Manager version from homepage.' }
  $latest = $m.Groups[1].Value
  $d = [regex]::Match($html, '/download/[0-9a-fA-F-]+/')
  if(!$d.Success){ throw 'Could not find homepage download link.' }
  $downloadPageUrl = (New-Object Uri((New-Object Uri($GsmHome)), $d.Value)).AbsoluteUri
  $page = Get-TextFromUrl $downloadPageUrl
  $file = [regex]::Match($page, 'https://www\.gamesave-manager\.com/file/[^''" ]+/')
  if(!$file.Success){ throw 'Could not find real ZIP download URL.' }
  $md5m = [regex]::Match($page, '<td align="right">md5</td>\s*<td>([a-fA-F0-9]+)</td>')
  $sha1m = [regex]::Match($page, '<td align="right">sha1</td>\s*<td>([a-fA-F0-9]+)</td>')
  $zip = Join-Path $Work ('GameSaveManager_' + $latest + '.zip')
  Log ('Latest GameSave Manager online version: ' + $latest)
  Log ('Downloading: ' + $file.Value)
  Download-FileStrict $file.Value $zip
  if($md5m.Success){ $md5 = HashOf $zip 'MD5'; if($md5 -ne $md5m.Groups[1].Value.ToLowerInvariant()){ throw ('MD5 mismatch: ' + $md5) }; Log ('MD5 verified: ' + $md5) }
  if($sha1m.Success){ $sha1 = HashOf $zip 'SHA1'; if($sha1 -ne $sha1m.Groups[1].Value.ToLowerInvariant()){ throw ('SHA1 mismatch: ' + $sha1) }; Log ('SHA1 verified: ' + $sha1) }
  $backup = Backup-Settings
  Log ('Settings backup: ' + $backup)
  Stop-GSM
  Ensure-ZipAssembly
  $extract = Join-Path $Work 'extract'
  if(Test-Path -LiteralPath $extract){ Remove-Item -LiteralPath $extract -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $extract | Out-Null
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
  Get-ChildItem -LiteralPath $extract -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $InstallDir -Recurse -Force }
  $exe = Join-Path $InstallDir $ExeName
  if(!(Test-Path -LiteralPath $exe)){ throw ('Missing executable after extract: ' + $exe) }
  $ver = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
  Log ('Installed ProductVersion: ' + $ver)
  if($ver -ne $latest){ throw ('Installed version ' + $ver + ' is not latest ' + $latest) }
  return $latest
}
function Get-UiErrorsForProcess([int]$TargetPid){
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  $bad = New-Object System.Collections.Generic.List[string]
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  foreach($w in $all){
    try{
      $wpid = $w.Current.ProcessId
      $title = '' + $w.Current.Name
      if(($wpid -eq $TargetPid) -or ($title -match 'GameSave|File not found|Error')){
        $texts = New-Object System.Collections.Generic.List[string]
        if($title){ $texts.Add($title) }
        $kids = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach($k in $kids){ $n = '' + $k.Current.Name; if($n){ $texts.Add($n) } }
        $joined = ($texts | Select-Object -Unique) -join ' | '
        if($joined -match 'File not found|Unhandled|Exception|Error|missing|not found') { $bad.Add($joined) }
      }
    } catch {}
  }
  return @($bad.ToArray())
}
function Probe-Launch(){
  $exe = Join-Path $InstallDir $ExeName
  Stop-GSM
  $p = Start-Process -FilePath $exe -WorkingDirectory $InstallDir -PassThru
  Log ('Launched GameSave Manager pid=' + $p.Id)
  $deadline = (Get-Date).AddSeconds($ProbeSeconds)
  $errors = @()
  while((Get-Date) -lt $deadline){
    Start-Sleep -Seconds 2
    if($p.HasExited){ throw ('GameSave Manager exited during probe with code ' + $p.ExitCode) }
    $errors = @(Get-UiErrorsForProcess $p.Id)
    if($errors.Count -gt 0){ break }
  }
  if($errors.Count -gt 0){ throw ('Visible UI error detected: ' + ($errors -join ' || ')) }
  $ver = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
  Log ('Probe clean: no File-not-found/Error dialogs detected for ' + $ProbeSeconds + 's. Version=' + $ver)
  return $true
}
if(Test-Path -LiteralPath $Log){ Remove-Item -LiteralPath $Log -Force }
$lastErr = $null
for($attempt=1; $attempt -le $MaxAttempts; $attempt++){
  try{
    Log ('=== Attempt ' + $attempt + ' of ' + $MaxAttempts + ' ===')
    $latest = Install-Latest
    Probe-Launch | Out-Null
    Log ('SUCCESS latest working version=' + $latest)
    exit 0
  } catch {
    $lastErr = $_.Exception.Message
    Log ('Attempt failed: ' + $lastErr)
    Stop-GSM
    Start-Sleep -Seconds 2
  }
}
throw ('Repair failed after ' + $MaxAttempts + ' attempts. Last error: ' + $lastErr)
