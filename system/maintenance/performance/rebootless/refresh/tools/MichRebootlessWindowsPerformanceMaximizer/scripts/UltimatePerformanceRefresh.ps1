param(
  [switch]$NoPause,
  [switch]$VerifyOnly,
  [ValidateRange(5, 15)]
  [int]$MaxRuntimeSeconds = 15
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Root = Split-Path -Path $PSCommandPath -Parent
$script:Log = Join-Path $script:Root 'last-run.log'
$script:Started = Get-Date
$script:HardDeadline = $script:Started.AddMilliseconds(($MaxRuntimeSeconds * 1000) - 350)

function Log([string]$Message) {
  Add-Content -LiteralPath $script:Log -Value ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message) -Encoding UTF8
}
function Step([string]$Name) { Log ('STEP ' + $Name) }
function Done([string]$Name) { Log ('DONE ' + $Name + ' elapsed-ms=' + [int]((Get-Date) - $script:Started).TotalMilliseconds) }
function Get-TimeLeftMs { [Math]::Max(0, [int]($script:HardDeadline - (Get-Date)).TotalMilliseconds) }
function Has-TimeLeft([int]$MinimumMs = 250) { (Get-TimeLeftMs) -gt $MinimumMs }
function Invoke-Safe([string]$Name, [scriptblock]$Block) {
  if (-not (Has-TimeLeft 300)) { Log ('SKIP budget ' + $Name); return }
  Step $Name
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { & $Block; Log ('DONE ' + $Name + ' step-ms=' + $sw.ElapsedMilliseconds) }
  catch { Log ('ERR ' + $Name + ' ' + $_.Exception.Message) }
}
function RunNative([string]$File, [string[]]$Argv, [int]$TimeoutMs) {
  try {
    if (-not (Test-Path -LiteralPath $File)) { Log ('SKIP missing ' + $File); return }
    $effectiveTimeout = [Math]::Min($TimeoutMs, [Math]::Max(0, (Get-TimeLeftMs) - 150))
    if ($effectiveTimeout -lt 250) { Log ('SKIP budget native ' + $File); return }
    $argText = ''
    if ($Argv) { $argText = ($Argv | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ' }
    $p = Start-Process -FilePath $File -ArgumentList $Argv -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
    if ($p) {
      if (-not $p.WaitForExit($effectiveTimeout)) { try { $p.Kill() } catch {}; Log ('TIMEOUT ' + $File + ' ' + $argText + ' timeout-ms=' + $effectiveTimeout) }
      elseif ($p.ExitCode -eq 0) { Log ('OK ' + $File + ' ' + $p.ExitCode + ' ' + $argText) }
      else { Log ('EXIT ' + $File + ' ' + $p.ExitCode + ' ' + $argText) }
    } else { Log ('SKIP could-not-start ' + $File + ' ' + $argText) }
  } catch { Log ('ERR ' + $File + ' ' + $_.Exception.Message) }
}
function Get-DirStatsBounded([string]$Path, [int]$MaxItems) {
  $bytes = 0L; $items = 0
  if ($Path -and (Test-Path -LiteralPath $Path)) {
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First $MaxItems | ForEach-Object {
      $items++
      try { if (-not $_.PSIsContainer) { $bytes += $_.Length } } catch {}
    }
  }
  [pscustomobject]@{ Bytes = $bytes; Items = $items }
}
function Get-MetricsLine([string]$Prefix) {
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $free = [math]::Round($os.FreePhysicalMemory / 1024, 1)
    $total = [math]::Round($os.TotalVisibleMemorySize / 1024, 1)
    $load = if ($total -gt 0) { [math]::Round((1 - ($free / $total)) * 100, 1) } else { 0 }
    $proc = @(Get-Process -ErrorAction SilentlyContinue).Count
    $svcRun = @(Get-Service -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running').Count
    $tempStats = Get-DirStatsBounded $env:TEMP 9000
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $cFree = if ($drive) { [math]::Round($drive.FreeSpace / 1MB, 1) } else { 0 }
    Log ("$Prefix memory-free-mb=$free memory-total-mb=$total memory-load-pct=$load processes=$proc running-services=$svcRun temp-items=$($tempStats.Items) temp-mb=$([math]::Round($tempStats.Bytes/1MB,1)) c-free-mb=$cFree uptime-hours=$([math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,1))")
  } catch { Log ("$Prefix metrics-error=$($_.Exception.Message)") }
}
function Remove-UnlockedBounded([string[]]$Roots, [datetime]$Cutoff, [int]$MaxItems, [int]$MaxSeconds, [string]$Label, [switch]$Recurse) {
  $localDeadline = (Get-Date).AddSeconds($MaxSeconds)
  $deleted = 0; $skipped = 0; $bytes = 0L; $seen = 0
  foreach ($root in ($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
    if ((Get-Date) -gt $localDeadline -or -not (Has-TimeLeft 300)) { break }
    $items = if ($Recurse) { Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue } else { Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue }
    $items | Where-Object { $_.LastWriteTime -lt $Cutoff } | Select-Object -First $MaxItems | ForEach-Object {
      if ((Get-Date) -gt $localDeadline -or -not (Has-TimeLeft 250)) { return }
      $seen++
      try {
        if ($_.PSIsContainer) {
          Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue | Select-Object -First 250 | ForEach-Object { try { $bytes += $_.Length } catch {} }
        } else { $bytes += $_.Length }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        $deleted++
      } catch { $skipped++ }
    }
  }
  Log "$Label-seen=$seen $Label-deleted=$deleted $Label-skipped=$skipped $Label-bytes=$bytes"
}
function Invoke-IfTimeLeft([string]$Name, [int]$BudgetSeconds, [scriptblock]$Block) {
  if (((Get-Date) - $script:Started).TotalSeconds -lt $BudgetSeconds) { Invoke-Safe $Name $Block }
  else { Log ('SKIP budget ' + $Name) }
}
function Get-ProfileCacheDirs([string[]]$ProfileRoots, [string[]]$Names, [int]$MaxProfiles) {
  $dirs = @()
  foreach ($root in ($ProfileRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
    if (-not (Has-TimeLeft 300)) { break }
    $profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First $MaxProfiles)
    $profiles += Get-Item -LiteralPath $root -ErrorAction SilentlyContinue
    foreach ($profile in $profiles) {
      foreach ($name in $Names) {
        $candidate = Join-Path $profile.FullName $name
        if (Test-Path -LiteralPath $candidate) { $dirs += $candidate }
      }
    }
  }
  $dirs | Select-Object -Unique
}

Set-Content -LiteralPath $script:Log -Value ('START {0:yyyy-MM-dd HH:mm:ss.fff}' -f (Get-Date)) -Encoding UTF8
Log 'CONTRACT no-reboot=true no-intentional-app-close=true locked-files=skip bounded-runtime=true'
Log ('BUDGET max-runtime-seconds=' + $MaxRuntimeSeconds + ' hard-deadline=' + $script:HardDeadline.ToString('o'))
Get-MetricsLine 'BEFORE'
if ($VerifyOnly) { Log 'VERIFYONLY complete'; Log ('END {0:yyyy-MM-dd HH:mm:ss.fff}' -f (Get-Date)); return }

Invoke-Safe 'native memory trim standby purge file-cache trim pressure flush' {
$code = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class RefreshNativeUltra2 {
 [StructLayout(LayoutKind.Sequential)] public class MEMORYSTATUSEX { public uint dwLength; public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual; public MEMORYSTATUSEX(){ dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); } }
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx([In,Out] MEMORYSTATUSEX lpBuffer);
 [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(UInt32 access, bool inherit, UInt32 pid);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetProcessWorkingSetSize(IntPtr h, IntPtr min, IntPtr max);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool EmptyWorkingSet(IntPtr h);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int cls, ref int info, int len);
 [DllImport("ntdll.dll")] static extern int RtlAdjustPrivilege(int priv, bool enable, bool currentThread, out bool enabled);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetSystemFileCacheSize(IntPtr minFileCacheSize, IntPtr maxFileCacheSize, int flags);
 const UInt32 PROCESS_SET_QUOTA = 0x0100; const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
 public static string TrimWorkingSets(){ int ok=0, empty=0, fail=0; foreach(Process p in Process.GetProcesses()){ try{ IntPtr h=OpenProcess(PROCESS_SET_QUOTA|PROCESS_QUERY_LIMITED_INFORMATION,false,(UInt32)p.Id); if(h!=IntPtr.Zero){ if(SetProcessWorkingSetSize(h,new IntPtr(-1),new IntPtr(-1))) ok++; if(EmptyWorkingSet(h)) empty++; CloseHandle(h); } else fail++; } catch { fail++; } } return "working-set-trim-ok="+ok+" empty-ok="+empty+" fail="+fail; }
 public static string PurgeList(int v){ try{ bool en; RtlAdjustPrivilege(13,true,false,out en); int x=v; int s=NtSetSystemInformation(80, ref x, 4); return "memory-list-"+v+"-status="+s; } catch(Exception e){ return "memory-list-"+v+"-error="+e.GetType().Name; } }
 public static string TrimFileCache(){ try{ bool en; RtlAdjustPrivilege(5,true,false,out en); bool ok=SetSystemFileCacheSize(new IntPtr(-1), new IntPtr(-1), 0); return "file-cache-trim="+ok; } catch(Exception e){ return "file-cache-error="+e.GetType().Name; } }
 public static string PressureFlush(int maxMb){ try{ MEMORYSTATUSEX m=new MEMORYSTATUSEX(); GlobalMemoryStatusEx(m); ulong avail=m.ullAvailPhys; long target=(long)Math.Min((ulong)maxMb*1024UL*1024UL, avail/4); if(target < 128L*1024L*1024L) return "pressure-skip-low-available target="+target; byte[][] chunks=new byte[Math.Max(1,target/(64L*1024L*1024L))][]; for(int i=0;i<chunks.Length;i++){ chunks[i]=new byte[64*1024*1024]; chunks[i][0]=1; chunks[i][chunks[i].Length-1]=2; } chunks=null; GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect(); return "pressure-flush-target-mb="+(target/1024/1024); } catch(Exception e){ return "pressure-error="+e.GetType().Name; } }
}
"@
  Add-Type -TypeDefinition $code -ErrorAction Stop | Out-Null
  Log ([RefreshNativeUltra2]::TrimWorkingSets())
  foreach ($i in @(5)) { if (-not (Has-TimeLeft 500)) { break }; Log ([RefreshNativeUltra2]::PurgeList($i)) }
  Log ([RefreshNativeUltra2]::TrimFileCache())
  Log 'SKIP pressure-flush fast-contract'
  if (Has-TimeLeft 2500) { Log ([RefreshNativeUltra2]::TrimWorkingSets()) } else { Log 'SKIP second-working-set-trim budget' }
}

Invoke-Safe 'managed runtime GC sweep' { [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect() }
Invoke-Safe 'DNS resolver client NetBIOS ARP destination cache refresh' {
  RunNative "$env:SystemRoot\System32\ipconfig.exe" @('/flushdns') 1000
  Log 'SKIP Clear-DnsClientCache cmdlet fast-contract'
  Log 'SKIP ipconfig /registerdns fast-contract'
  RunNative "$env:SystemRoot\System32\nbtstat.exe" @('-R') 800
  RunNative "$env:SystemRoot\System32\nbtstat.exe" @('-RR') 800
  RunNative "$env:SystemRoot\System32\arp.exe" @('-d','*') 900
  RunNative "$env:SystemRoot\System32\netsh.exe" @('interface','ip','delete','destinationcache') 1000
  RunNative "$env:SystemRoot\System32\netsh.exe" @('interface','ipv6','delete','destinationcache') 1000
}
Invoke-Safe 'network stack state touch without reset' {
  RunNative "$env:SystemRoot\System32\netsh.exe" @('winhttp','show','proxy') 800
  RunNative "$env:SystemRoot\System32\netsh.exe" @('interface','tcp','show','global') 800
  Log 'OK dns-display-suppressed-for-speed'
}
Invoke-Safe 'environment policy shell app-model broadcast refresh' {
$code2 = @"
using System;
using System.Runtime.InteropServices;
public static class ShellRefreshUltra2 {
 [DllImport("user32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg,UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr r);
 [DllImport("shell32.dll")] static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
 public static void DoIt(){ UIntPtr r; SendMessageTimeout(new IntPtr(0xffff),0x1A,UIntPtr.Zero,"Environment",2,800,out r); SendMessageTimeout(new IntPtr(0xffff),0x001A,UIntPtr.Zero,"Policy",2,800,out r); SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero); SHChangeNotify(0x00002000,0,IntPtr.Zero,IntPtr.Zero); }
}
"@
  Add-Type -TypeDefinition $code2 -ErrorAction Stop | Out-Null
  [ShellRefreshUltra2]::DoIt()
  RunNative "$env:SystemRoot\System32\rundll32.exe" @('user32.dll,UpdatePerUserSystemParameters') 1200
  RunNative "$env:SystemRoot\System32\ie4uinit.exe" @('-show') 1200
  try { (New-Object -ComObject Shell.Application).NameSpace(0) | Out-Null; Log 'OK shell-com-touch' } catch {}
}
Invoke-Safe 'graphics compositor nudge' { try { $sh=New-Object -ComObject WScript.Shell; $sh.SendKeys('^+#{B}'); Start-Sleep -Milliseconds 250; Log 'OK sent Win+Ctrl+Shift+B' } catch { Log ('ERR display-key ' + $_.Exception.Message) } }

Invoke-Safe 'Explorer icon thumbnail jump-list font cache cleanup unlocked only' {
  $patterns = @(
    "$env:LOCALAPPDATA\IconCache.db",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
    "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*.automaticDestinations-ms",
    "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*.customDestinations-ms",
    "$env:LOCALAPPDATA\Microsoft\Windows\Caches\*",
    "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*"
  )
  $deleted=0; $skipped=0; $bytes=0L
  foreach ($pat in $patterns) {
    if (-not (Has-TimeLeft 250)) { break }
    Get-ChildItem -Path $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try { if (-not $_.PSIsContainer) { $bytes += $_.Length }; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $deleted++ } catch { $skipped++ }
    }
  }
  Log "shell-font-cache-deleted=$deleted shell-font-cache-skipped=$skipped shell-font-cache-bytes=$bytes"
}
Invoke-Safe 'Windows WER update delivery DirectX shader stale queue cleanup' {
  $dirs = @(
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
    "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache",
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Service"
  )
  Remove-UnlockedBounded $dirs (Get-Date).AddHours(-4) 600 2 'system-cache'
}
Invoke-Safe 'GPU vendor shader caches cleanup unlocked only' {
  $dirs = @(
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:ProgramData\NVIDIA Corporation\NV_Cache",
    "$env:LOCALAPPDATA\AMD\DxCache",
    "$env:LOCALAPPDATA\AMD\GLCache",
    "$env:LOCALAPPDATA\Intel\ShaderCache"
  )
  Remove-UnlockedBounded $dirs (Get-Date).AddHours(-2) 500 2 'gpu-cache'
}
Invoke-Safe 'browser GPU shader code media caches cleanup without closing browsers' {
  $profileRoots = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
    "$env:LOCALAPPDATA\Vivaldi\User Data",
    "$env:APPDATA\Opera Software",
    "$env:APPDATA\Mozilla\Firefox\Profiles"
  ) | Where-Object { Test-Path -LiteralPath $_ }
  $names = @('GPUCache','ShaderCache','DawnCache','GrShaderCache','Code Cache','Cache','Service Worker','Media Cache','blob_storage')
  $cacheDirs = Get-ProfileCacheDirs $profileRoots $names 12
  Remove-UnlockedBounded $cacheDirs (Get-Date).AddHours(-1) 700 2 'browser-cache'
}
Invoke-Safe 'app runtime communication cache cleanup unlocked only' {
  $dirs = @(
    "$env:APPDATA\Microsoft\Teams\Service Worker\CacheStorage",
    "$env:APPDATA\Microsoft\Teams\GPUCache",
    "$env:APPDATA\Microsoft\Teams\Code Cache",
    "$env:APPDATA\Slack\Service Worker\CacheStorage",
    "$env:APPDATA\Slack\GPUCache",
    "$env:APPDATA\discord\Cache",
    "$env:APPDATA\discord\Code Cache",
    "$env:APPDATA\discord\GPUCache",
    "$env:APPDATA\Telegram Desktop\tdata\user_data\cache",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
  )
  Remove-UnlockedBounded $dirs (Get-Date).AddHours(-1) 650 2 'app-runtime-cache'
}
Invoke-Safe 'Windows app model package cache cleanup unlocked only' {
  $packageRoot = "$env:LOCALAPPDATA\Packages"
  $dirs = @()
  if (Test-Path -LiteralPath $packageRoot) {
    Get-ChildItem -LiteralPath $packageRoot -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 80 | ForEach-Object {
      foreach ($rel in @('AC\Temp','AC\INetCache','LocalCache','TempState')) {
        $candidate = Join-Path $_.FullName $rel
        if (Test-Path -LiteralPath $candidate) { $dirs += $candidate }
      }
    }
  }
  Remove-UnlockedBounded $dirs (Get-Date).AddHours(-6) 700 2 'appmodel-cache'
}
Invoke-Safe 'recent files jump shell telemetry cleanup unlocked only' {
  $dirs = @(
    "$env:APPDATA\Microsoft\Windows\Recent",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
    "$env:LOCALAPPDATA\Microsoft\Windows\History",
    "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
    "$env:LOCALAPPDATA\ConnectedDevicesPlatform"
  )
  Remove-UnlockedBounded $dirs (Get-Date).AddDays(-2) 550 2 'recent-telemetry-cache'
}
Invoke-Safe 'developer runtime build caches bounded cleanup' {
  $dirs = @(
    "$env:LOCALAPPDATA\pip\Cache",
    "$env:LOCALAPPDATA\NuGet\Cache",
    "$env:LOCALAPPDATA\Microsoft\MSBuild\NodeReuse",
    "$env:APPDATA\npm-cache",
    "$env:LOCALAPPDATA\Yarn\Cache",
    "$env:LOCALAPPDATA\pnpm\store",
    "$env:USERPROFILE\.gradle\caches\modules-2\files-2.1"
  )
  Remove-UnlockedBounded $dirs (Get-Date).AddDays(-7) 450 2 'dev-cache'
}
Invoke-Safe 'temp cleanup bounded unlocked stale top-level trees' {
  $dirs = @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
  Remove-UnlockedBounded $dirs (Get-Date).AddMinutes(-20) 450 2 'temp'
}
Invoke-Safe 'extra shell session system-parameter broadcasts' {
$code3 = @"
using System;
using System.Runtime.InteropServices;
public static class ExtraSessionBroadcasts {
 [DllImport("user32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg,UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr r);
 public static void DoIt(){ UIntPtr r; IntPtr all=new IntPtr(0xffff); SendMessageTimeout(all,0x1A,UIntPtr.Zero,"intl",2,500,out r); SendMessageTimeout(all,0x1A,UIntPtr.Zero,"windows",2,500,out r); SendMessageTimeout(all,0x7E,UIntPtr.Zero,"",2,500,out r); }
}
"@
  Add-Type -TypeDefinition $code3 -ErrorAction Stop | Out-Null
  [ExtraSessionBroadcasts]::DoIt()
  Log 'OK extra-session-broadcasts'
}
Invoke-Safe 'service control manager and WMI repository touch' {
  try { Get-Service -Name EventLog,Schedule,Winmgmt,Dnscache -ErrorAction SilentlyContinue | ForEach-Object { Log ('service-touch name=' + $_.Name + ' status=' + $_.Status) } } catch {}
  try { Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1 | Out-Null; Log 'OK wmi-os-touch' } catch {}
  try { Get-CimInstance Win32_PerfFormattedData_PerfOS_System -ErrorAction SilentlyContinue | Select-Object -First 1 | Out-Null; Log 'OK perf-counter-touch' } catch {}
}
Invoke-Safe 'storage state touch without slow retrim' {
  try {
    Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Select-Object -First 6 | ForEach-Object { Log ('fixed-volume drive=' + $_.DriveLetter + ' health=' + $_.HealthStatus + ' size-remaining=' + $_.SizeRemaining) }
    RunNative "$env:SystemRoot\System32\fsutil.exe" @('behavior','query','DisableDeleteNotify') 1200
  } catch { Log ('storage-touch-err ' + $_.Exception.Message) }
}
Invoke-Safe 'Ultimate Performance power scheme and latency settings' {
  $pc = "$env:SystemRoot\System32\powercfg.exe"
  $existing = (& $pc /list 2>&1 | Out-String)
  $guid = ([regex]::Matches($existing, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[^\r\n]*Ultimate Performance') | Select-Object -First 1).Value
  $ultimateGuid = ([regex]::Match($guid, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')).Value
  if (-not $ultimateGuid) {
    $dup = & $pc /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
    $ultimateGuid = ([regex]::Match($dup, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')).Value
  }
  if ($ultimateGuid) { RunNative $pc @('/setactive', $ultimateGuid) 1200 } else { Log 'SKIP ultimate-guid-not-found' }
  $settings = @(
    @('sub_processor','PROCTHROTTLEMIN','100'), @('sub_processor','PROCTHROTTLEMAX','100'), @('sub_processor','PERFINCPOL','2'), @('sub_processor','PERFDECPOL','1'),
    @('sub_disk','DISKIDLE','0'), @('SUB_PCIEXPRESS','ASPM','0'), @('2a737441-1930-4402-8d77-b2bebba308a3','48e6b7a6-50f5-4782-a5d4-53bb8f07e226','0'), @('SUB_SLEEP','AWAYMODE','0')
  )
  foreach ($s in $settings) { if (-not (Has-TimeLeft 350)) { break }; RunNative $pc @('/setacvalueindex','scheme_current',$s[0],$s[1],$s[2]) 900 }
  RunNative $pc @('/setactive','scheme_current') 900
  RunNative $pc @('/getactivescheme') 900
}
Invoke-Safe 'final memory and file-cache trim after cleanup' {
  try { Log ([RefreshNativeUltra2]::TrimWorkingSets()); Log ([RefreshNativeUltra2]::TrimFileCache()); if (Has-TimeLeft 1200) { Log ([RefreshNativeUltra2]::PurgeList(5)) } } catch { Log ('final-trim-err ' + $_.Exception.Message) }
}
Get-MetricsLine 'AFTER'
Log ('END {0:yyyy-MM-dd HH:mm:ss.fff} total-ms={1}' -f (Get-Date), [int]((Get-Date) - $script:Started).TotalMilliseconds)
