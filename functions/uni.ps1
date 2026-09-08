# First executable statement: no profile imports, WMI queries or compilation first.
if($MyInvocation.InvocationName -ne '.') { Write-Host ('[START] Uni C: cleanup: '+(@($args) -join ' ')) }
# Uni ownership-checked cleanup. Active profile entry point is this script.
# The embedded C# filesystem/registry collectors compile lazily on each fresh host.
# Exact app identities and exclusive C: paths authorize mutations. Shared and
# ambiguous discoveries are preserved and reported. Verified processes stop first.
# Exit 0: requested checked operations finished within the stated scan coverage.
# Exit 2: unremoved artifacts, scan errors, or unverified coverage; fatal errors
# also return a nonzero code. Neither code certifies universal zero leftovers.
# --dry-run previews identity/root selection without running uninstallers/cleanup.

$script:UniNeverKill = @('smss', 'csrss', 'wininit', 'winlogon', 'lsass', 'services', 'system', 'registry', 'audiodg', 'svchost')
# shell/terminal hosts: only ever killed by name or path match, never by
# command-line match alone (a shell that merely mentions the target must live)
$script:UniShellNames = @('bash', 'sh', 'cmd', 'powershell', 'pwsh', 'conhost', 'windows.terminal', 'windowsterminal', 'wt', 'openconsole', 'freebuff', 'bun', 'node', 'code', 'cursor')
$script:UniShellNames = @($script:UniShellNames | ForEach-Object { $_.ToLowerInvariant() })
$script:UniProtectedPids = @{ $PID = $true }
$script:UniTargetsFile=Join-Path $PSScriptRoot 'uni.targets.json'
$script:UniReferencesFile=Join-Path $PSScriptRoot 'uni.references.json'
# Shell hosts are protected independently of process ancestry. Never use WMI here.
$script:UniNeverKill += @('powershell','pwsh','cmd','conhost','windowsterminal','openconsole','explorer')
$script:UniRmReady = $false
function Get-UniLockerPids {
    param([string]$Path)
    if (-not $script:UniRmReady) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class UniRm {
    [StructLayout(LayoutKind.Sequential)] private struct RM_UNIQUE_PROCESS { public int dwProcessId; public long ProcessStartTime; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct RM_PROCESS_INFO { public RM_UNIQUE_PROCESS Process; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName; public uint ApplicationType; public uint AppStatus; public uint TSSessionId; [MarshalAs(UnmanagedType.Bool)] public bool bRestartable; }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] private static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] private static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);
    [DllImport("rstrtmgr.dll")] private static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
    [DllImport("rstrtmgr.dll")] private static extern int RmEndSession(uint pSessionHandle);
    public static int[] GetLockers(string path) {
        var list = new List<int>();
        uint handle; uint reboot = 0;
        if (RmStartSession(out handle, 0, Guid.NewGuid().ToString("N")) != 0) return list.ToArray();
        try {
            if (RmRegisterResources(handle, 1, new string[] { path }, 0, null, 0, null) != 0) return list.ToArray();
            uint needed = 0; uint count = 0;
            if (RmGetList(handle, out needed, ref count, null, ref reboot) == 234) {
                var arr = new RM_PROCESS_INFO[needed];
                count = needed;
                if (RmGetList(handle, out needed, ref count, arr, ref reboot) == 0)
                    for (uint i = 0; i < count; i++) { if (arr[i].Process.dwProcessId > 0) list.Add(arr[i].Process.dwProcessId); }
            }
        } finally { RmEndSession(handle); }
        return list.ToArray();
    }
}
'@ -ErrorAction Stop
        } catch { }
        $script:UniRmReady = $true
    }
    if (-not ('UniRm' -as [type])) { return @() }
    try { return @([UniRm]::GetLockers($Path)) } catch { return @() }
}

# ---------------------------------------------------------------------------
# live progress line (single \r-updated status row + permanent event lines)
# ---------------------------------------------------------------------------
$script:UniPhase = 0
$script:UniPhaseCount = 12
$script:UniStart = [DateTime]::UtcNow
$script:UniLogicalProcessors = [math]::Max(1, [Environment]::ProcessorCount)
# Keep the machine interactive while a sweep walks millions of paths.  The old
# policy created up to 64 workers per root and 32 registry workers; on this host
# that saturated the scheduler.  Bound the whole filesystem wave to four
# below-normal scanner workers and the registry sweep to at most four scanners.
$script:UniMaxConcurrentRoots = if ($script:UniLogicalProcessors -ge 8) { 2 } else { 1 }
$script:UniFsWorkersPerRoot = if ($script:UniLogicalProcessors -ge 4) { 2 } else { 1 }
$script:UniRegistryWorkers = [math]::Max(1, [math]::Min(4, [math]::Floor($script:UniLogicalProcessors / 4)))

function Get-UniWidth {
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 40) { return $Host.UI.RawUI.WindowSize.Width } } catch { }
    return 100
}
function Update-UniLine {
    param([string]$Text)
    $w = Get-UniWidth
    $t = [string]$Text
    if ($t.Length -gt ($w - 2)) { $t = $t.Substring(0, $w - 2) }
    Write-Host ("`r" + $t.PadRight($w - 1)) -NoNewline
}
function Clear-UniLine {
    $w = Get-UniWidth
    Write-Host ("`r" + (' ' * ($w - 1)) + "`r") -NoNewline
}
function Get-UniElapsed {
    $secs = [int](([DateTime]::UtcNow) - $script:UniStart).TotalSeconds
    return ('{0}:{1:d2}' -f [math]::Floor($secs / 60), ($secs % 60))
}
function Write-UniPhase {
    param([string]$Title)
    if ('UniProgressV1' -as [type]) { [UniProgressV1]::Phase = $Title }
    $script:UniPhase++
    Clear-UniLine
    Write-Host ("  [{0}/{1}] {2} ..." -f $script:UniPhase, $script:UniPhaseCount, $Title) -ForegroundColor Cyan
    Update-UniLine ("[{0}] {1}: working ..." -f (Get-UniElapsed), $Title)
}
function Invoke-UniPhaseSafely {
    param([Parameter(Mandatory=$true)][string]$Title,[Parameter(Mandatory=$true)][scriptblock]$Action)
    try {
        & $Action
    } catch {
        $message = '{0}: {1}' -f $Title,$_.Exception.Message
        if($script:UniFailed){[void]$script:UniFailed.Add($message)}
        Write-Warning ('Continuing after independent phase failure: '+$message)
    }
}

# ---------------------------------------------------------------------------
# parallel filesystem collector (junction-safe, counters exposed for progress)
# compiled lazily so phases 1-5 start instantly; only the sweep needs it
# ---------------------------------------------------------------------------
$script:UniCollectOk = $false
function Ensure-UniSweepCollect {
    if ($script:UniCollectOk) { return }
    if ('UniSweepCollectV8' -as [type]) { $script:UniCollectOk = $true; return }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public static class UniSweepCollectV8
{
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
    private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x400;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFileAttributesW(string lpFileName);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint QueryDosDevice(string name, System.Text.StringBuilder target, int length);
    public static string ResolveDevicePath(string path) {
        foreach (string drive in Environment.GetLogicalDrives()) {
            var target = new System.Text.StringBuilder(32768);
            if (QueryDosDevice(drive.Substring(0, 2), target, target.Capacity) == 0) continue;
            string device = target.ToString().Split('\0')[0];
            if (path.StartsWith(device + "\\", StringComparison.OrdinalIgnoreCase)) return drive.Substring(0, 2) + path.Substring(device.Length);
        }
        return null;
    }

    private static long _errors;
    private static volatile bool _cancelled;
    public static long Errors { get { return Interlocked.Read(ref _errors); } }
    public static void Cancel() { _cancelled = true; }
    private static readonly ConcurrentQueue<string> _errorDetails = new ConcurrentQueue<string>();
    public static string[] ErrorDetails { get { return _errorDetails.ToArray(); } }
    private static void ScanError(string path = "scanner queue limit", Exception error = null) {
        long count = Interlocked.Increment(ref _errors);
        if (count <= 100) _errorDetails.Enqueue(path + (error == null ? "" : " [" + error.GetType().Name + "; HRESULT " + error.HResult + "]"));
    }
    private static long _scanned;
    private static long _matched;
    public static long Scanned { get { return Interlocked.Read(ref _scanned); } }
    public static long Matched { get { return Interlocked.Read(ref _matched); } }
    public static void ResetCounters() { _cancelled = false; string ignored; while (_errorDetails.TryDequeue(out ignored)) {} Interlocked.Exchange(ref _errors, 0); Interlocked.Exchange(ref _scanned, 0); Interlocked.Exchange(ref _matched, 0); }
    public static int ClampWorkerCount(int requested) { return Math.Max(1, Math.Min(2, requested)); }

    private class Item { public string Path; public string Parent; public string Mode; public int ItemDepth; }

    public static Task<List<string>> CollectAsync(string root, string mode, string exactPattern, string loosePattern, string[] denyPaths, string[] protectedFiles, string[] rootDeny, int workerCount)
    {
        return Task.Run(() => Collect(root, mode, exactPattern, loosePattern, denyPaths, protectedFiles, rootDeny, workerCount));
    }

    public static List<string> Collect(string root, string mode, string exactPattern, string loosePattern, string[] denyPaths, string[] protectedFiles, string[] rootDeny, int workerCount)
    {
        if (root.EndsWith(":", StringComparison.Ordinal)) root = root + "\\";
        var reExact = new Regex(exactPattern, RegexOptions.IgnoreCase);
        var reLoose = new Regex(loosePattern, RegexOptions.IgnoreCase);
        var rem = new Regex("removed|backup|bak|old", RegexOptions.IgnoreCase);
        var extRe = new Regex(@"^\.(dll|exe|cpl|sys|cmd|bat|ps1|psm1|psd1|vbs|js|mjs|cjs|flow|json|xml|pak|log|tmp|dat|ini|cfg|db|wasm|map|ico|png|url|appref-ms|lnk)$", RegexOptions.IgnoreCase);
        var rootSet = new HashSet<string>(rootDeny ?? new string[0], StringComparer.OrdinalIgnoreCase);
        var del = new ConcurrentDictionary<string, byte>(StringComparer.OrdinalIgnoreCase);
        var queue = new ConcurrentQueue<Item>();
        long pending = 0;

        string[] top;
        try { top = Directory.GetFileSystemEntries(root); }
        catch (Exception error) { ScanError(root, error); return new List<string>(); }
        foreach (var e in top)
        {
            string name = Path.GetFileName(e);
            if (rootSet.Contains(name)) continue;
            uint a = GetFileAttributesW(e);
            if (a == 0xFFFFFFFF) { int code = Marshal.GetLastWin32Error(); if (code != 2 && code != 3) ScanError(e, new System.ComponentModel.Win32Exception(code)); continue; }
            if ((a & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
            {
                // An exact orphan-name junction/symlink is a removable link
                // candidate, but never descend through it. PowerShell later
                // validates and unlinks only the link object in orphan mode.
                if (reExact.IsMatch(name) && !IsDenied(e, denyPaths) && !IsProtected(e, protectedFiles))
                {
                    del.TryAdd(e, 0); Interlocked.Increment(ref _matched);
                }
                continue;
            }
            if (name == ".git" || name == "__pycache__" || name == "$Recycle.Bin") continue;
            if (IsProtected(e, protectedFiles)) continue;
            if (IsDenied(e, denyPaths)) continue;
            if ((a & FILE_ATTRIBUTE_DIRECTORY) != 0) { Interlocked.Increment(ref pending); queue.Enqueue(new Item { Path = e, Parent = Path.GetFileName(root), Mode = mode, ItemDepth = 1 }); }
            else ProcessFile(e, name, Path.GetFileName(root), mode, 1, reExact, reLoose, rem, extRe, denyPaths, protectedFiles, del);
        }

        int workers = ClampWorkerCount(workerCount);
        var threads = new List<Thread>();
        for (int w = 0; w < workers; w++)
        {
            var t = new Thread(() => Worker(queue, ref pending, reExact, reLoose, rem, extRe, denyPaths, protectedFiles, del));
            t.IsBackground = true;
            t.Priority = ThreadPriority.BelowNormal;
            t.Start();
            threads.Add(t);
        }
        foreach (var t in threads) t.Join();

        var flat = new List<string>(del.Keys);
        // No parent promotion: siblings and containers have separate ownership.
        return TopOnly(new List<string>(del.Keys), del);
    }

    private static void Worker(ConcurrentQueue<Item> queue, ref long pending, Regex reExact, Regex reLoose, Regex rem, Regex extRe, string[] deny, string[] prot, ConcurrentDictionary<string, byte> del)
    {
        while (!_cancelled)
        {
            if (Interlocked.Read(ref pending) > 100000) { ScanError(); Cancel(); return; }
            Item it;
            if (queue.TryDequeue(out it))
            {
                try { ProcessDir(it, reExact, reLoose, rem, extRe, deny, prot, del, queue, ref pending); }
                catch (Exception error) { ScanError(it.Path, error); }
                finally { Interlocked.Decrement(ref pending); }
            }
            else
            {
                if (Volatile.Read(ref pending) == 0) return;
                Thread.Sleep(2);
            }
        }
    }

    private static void ProcessDir(Item it, Regex reExact, Regex reLoose, Regex rem, Regex extRe, string[] deny, string[] prot, ConcurrentDictionary<string, byte> del, ConcurrentQueue<Item> queue, ref long pending)
    {
        Interlocked.Increment(ref _scanned);
        string name = Path.GetFileName(it.Path);
        bool deleteDir = false;
        bool exactMatch = reExact.IsMatch(name);
        if (exactMatch)
        {
            // Nuclear mode: ignore depth limits for exact matches
            if (it.Mode == "N" || it.Mode == "T") deleteDir = true;
            else if (it.Mode == "B") deleteDir = (it.ItemDepth <= 3 || (it.ItemDepth <= 4 && reExact.IsMatch(it.Parent)) || it.Parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || rem.IsMatch(name));
            else deleteDir = (it.ItemDepth <= 3 || (it.ItemDepth <= 4 && reExact.IsMatch(it.Parent)));
        }
        else if (it.Mode == "N")
        {
            // In Nuclear mode, also check loose matches but with relaxed depth
            if (reLoose.IsMatch(name))
            {
                deleteDir = (it.ItemDepth <= 5 || (it.ItemDepth <= 6 && reLoose.IsMatch(it.Parent)));
            }
        }
        if (deleteDir) { del.TryAdd(it.Path, 0); Interlocked.Increment(ref _matched); return; }
        string[] entries;
        try { entries = Directory.GetFileSystemEntries(it.Path); }
        catch (DirectoryNotFoundException) { return; }
        catch (Exception error) { ScanError(it.Path, error); return; }
        if (entries.Length == 0 && reExact.IsMatch(name)) { del.TryAdd(it.Path, 0); Interlocked.Increment(ref _matched); return; }
        string childMode = it.Mode;
        int childStartDepth;
        // Nuclear mode propagates to all children
        if (it.Mode == "N") { childMode = "N"; childStartDepth = it.ItemDepth + 1; }
        else if (it.Mode == "B" && name.Equals("AppData", StringComparison.OrdinalIgnoreCase)) { childMode = "A"; childStartDepth = 1; }
        else if (it.Mode == "B" && name.Equals("scoop", StringComparison.OrdinalIgnoreCase)) { childMode = "A"; childStartDepth = it.ItemDepth + 1; }
        else if (it.Mode != "T" && name.Equals("Temp", StringComparison.OrdinalIgnoreCase)) { childMode = "T"; childStartDepth = it.ItemDepth + 1; }
        else { childStartDepth = it.ItemDepth + 1; }
        foreach (var e in entries)
        {
            string nm = Path.GetFileName(e);
            if (nm == ".git" || nm == "__pycache__" || nm == "$Recycle.Bin") continue;
            uint a = GetFileAttributesW(e);
            if (a == 0xFFFFFFFF) { int code = Marshal.GetLastWin32Error(); if (code != 2 && code != 3) ScanError(e, new System.ComponentModel.Win32Exception(code)); continue; }
            if ((a & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
            {
                // Keep link targets opaque; exact-name links are handled as
                // link objects only by the orphan fallback.
                if (reExact.IsMatch(nm) && !IsDenied(e, deny) && !IsProtected(e, prot))
                {
                    del.TryAdd(e, 0); Interlocked.Increment(ref _matched);
                }
                continue;
            }
            if (IsDenied(e, deny)) continue;
            if (IsProtected(e, prot)) continue;
            if ((a & FILE_ATTRIBUTE_DIRECTORY) != 0) { Interlocked.Increment(ref pending); queue.Enqueue(new Item { Path = e, Parent = name, Mode = childMode, ItemDepth = childStartDepth }); }
            else ProcessFile(e, nm, name, childMode, childStartDepth, reExact, reLoose, rem, extRe, deny, prot, del);
        }
    }

    private static void ProcessFile(string path, string name, string parent, string mode, int itemDepth, Regex reExact, Regex reLoose, Regex rem, Regex extRe, string[] deny, string[] prot, ConcurrentDictionary<string, byte> del)
    {
        Interlocked.Increment(ref _scanned);
        string ext = Path.GetExtension(name);
        bool isShortcut = ext != null && (ext.Equals(".lnk", StringComparison.OrdinalIgnoreCase) || ext.Equals(".url", StringComparison.OrdinalIgnoreCase) || ext.Equals(".appref-ms", StringComparison.OrdinalIgnoreCase));
        bool deleteFile = false;
        bool exactMatch = reExact.IsMatch(name);
        bool looseMatch = reLoose.IsMatch(name);
        
        if (exactMatch)
        {
            // Nuclear mode: ignore depth limits for exact matches
            if (mode == "N" || mode == "T") deleteFile = true;
            else if (mode == "A") deleteFile = (itemDepth <= 1 || (itemDepth <= 4 && looseMatch) || parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || rem.IsMatch(name) || (ext != null && extRe.IsMatch(ext)));
            else deleteFile = (itemDepth <= 1 || parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || looseMatch || rem.IsMatch(name) || (ext != null && extRe.IsMatch(ext)));
        }
        else if (looseMatch)
        {
            if (isShortcut || mode == "T") deleteFile = true;
            else if (mode == "N")
            {
                // Nuclear mode: relaxed depth for loose matches
                deleteFile = (itemDepth <= 3 || (itemDepth <= 5 && looseMatch) || parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || rem.IsMatch(name) || (ext != null && extRe.IsMatch(ext)));
            }
            else if (mode == "A") deleteFile = (itemDepth <= 1 || (itemDepth <= 4 && looseMatch) || parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || rem.IsMatch(name) || (ext != null && extRe.IsMatch(ext)));
            else deleteFile = (itemDepth <= 1 || parent.Equals("node_modules", StringComparison.OrdinalIgnoreCase) || looseMatch || rem.IsMatch(name) || (ext != null && extRe.IsMatch(ext)));
        }
        if (deleteFile) { del.TryAdd(path, 0); Interlocked.Increment(ref _matched); }
    }

    private static bool IsProtected(string path, string[] prot)
    {
        if (prot == null) return false;
        foreach (var p in prot) if (path.Equals(p, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }
    private static bool IsDenied(string path, string[] deny)
    {
        if (deny == null) return false;
        foreach (var d in deny) if (path.Equals(d, StringComparison.OrdinalIgnoreCase) || path.StartsWith(d.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static void Prune(List<string> del, ConcurrentDictionary<string, byte> delSet, string[] deny, string[] prot, string root)
    {
        var queue = new List<string>(del);
        for (int i = 0; i < queue.Count; i++)
        {
            string p = queue[i];
            if (string.IsNullOrEmpty(p)) continue;
            string parent = Path.GetDirectoryName(p);
            while (!string.IsNullOrEmpty(parent) && parent.Length > root.Length && !parent.Equals(root, StringComparison.OrdinalIgnoreCase))
            {
                if (delSet.ContainsKey(parent)) { parent = Path.GetDirectoryName(parent); continue; }
                if (IsProtected(parent, prot) || IsDenied(parent, deny)) break;
                string[] kids;
                try { kids = Directory.GetFileSystemEntries(parent); } catch { break; }
                bool empty = true;
                foreach (var k in kids) { if (!delSet.ContainsKey(k)) { empty = false; break; } }
                if (!empty) break;
                if (delSet.TryAdd(parent, 0)) { del.Add(parent); queue.Add(parent); }
                parent = Path.GetDirectoryName(parent);
            }
        }
    }

    private static List<string> TopOnly(List<string> del, ConcurrentDictionary<string, byte> delSet)
    {
        var sorted = new List<string>(del);
        sorted.Sort((a, b) => a.Length.CompareTo(b.Length));
        var result = new List<string>();
        var resultSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in sorted)
        {
            bool hasAncestor = false;
            string cur = Path.GetDirectoryName(p);
            while (!string.IsNullOrEmpty(cur))
            {
                if (resultSet.Contains(cur)) { hasAncestor = true; break; }
                string next = Path.GetDirectoryName(cur);
                if (next == cur || next == null) break;
                cur = next;
            }
            if (!hasAncestor) { result.Add(p); resultSet.Add(p); }
        }
        return result;
    }
}
'@ -ErrorAction Stop
        $script:UniCollectOk = $true
    } catch {
        $script:UniCollectOk = $false
    }
}

# ---------------------------------------------------------------------------
# parallel registry collector (Software hives + HKCR/COM), counters + progress
# also compiled lazily - only the deep registry phase needs it
# ---------------------------------------------------------------------------
$script:UniRegOk = $false
function Ensure-UniRegCollect {
    if ($script:UniRegOk) { return }
    if ('UniRegCollectV8' -as [type]) { $script:UniRegOk = $true; return }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

public static class UniRegCollectV8
{
    private static long _errors;
    private static volatile bool _cancelled;
    public static long Errors { get { return Interlocked.Read(ref _errors); } }
    public static void Cancel() { _cancelled = true; }
    private static readonly ConcurrentQueue<string> _errorDetails = new ConcurrentQueue<string>();
    public static string[] ErrorDetails { get { return _errorDetails.ToArray(); } }
    private static void ScanError(string path = "scanner queue limit", Exception error = null) {
        long count = Interlocked.Increment(ref _errors);
        if (count <= 100) _errorDetails.Enqueue(path + (error == null ? "" : " [" + error.GetType().Name + "; HRESULT " + error.HResult + "]"));
    }
    private static long _scanned;
    private static long _matched;
    public static long Scanned { get { return Interlocked.Read(ref _scanned); } }
    public static long Matched { get { return Interlocked.Read(ref _matched); } }
    public static void ResetCounters() { _cancelled = false; string ignored; while (_errorDetails.TryDequeue(out ignored)) {} Interlocked.Exchange(ref _errors, 0); Interlocked.Exchange(ref _scanned, 0); Interlocked.Exchange(ref _matched, 0); }
    public static int ClampWorkerCount(int requested) { return Math.Max(1, Math.Min(4, requested)); }

    private class Work { public int Hive; public string Rel; public string Full; public bool IsClass; public bool InDeny; }

    public static Task<List<string>> CollectAsync(string exactPattern, string loosePattern, string[] denyPrefixes, int workerCount)
    {
        return Task.Run(() => Collect(exactPattern, loosePattern, denyPrefixes, workerCount));
    }

    public static List<string> Collect(string exactPattern, string loosePattern, string[] denyPrefixes, int workerCount)
    {
        var reExact = new Regex(exactPattern, RegexOptions.IgnoreCase);
        var reLoose = new Regex(loosePattern, RegexOptions.IgnoreCase);
        var reGuid = new Regex(@"^\{[0-9A-Fa-f\-]+\}$");
        var results = new ConcurrentDictionary<string, byte>(StringComparer.OrdinalIgnoreCase);
        var queue = new ConcurrentStack<Work>();
        long pending = 0;

        EnqueueRoot(queue, ref pending, 0, "Software", "HKLM\\SOFTWARE", false, false);
        // The 64-bit Software traversal already visits the physical WOW6432Node.
        EnqueueRoot(queue, ref pending, 2, "Software", "HKCU\\Software", false, false);
        EnqueueRoot(queue, ref pending, 3, "", "HKCR", true, false);

        int workers = ClampWorkerCount(workerCount);
        var threads = new List<Thread>();
        for (int w = 0; w < workers; w++)
        {
            var t = new Thread(() => Worker(queue, ref pending, reExact, reLoose, reGuid, denyPrefixes, results));
            t.IsBackground = true;
            t.Priority = ThreadPriority.BelowNormal;
            t.Start();
            threads.Add(t);
        }
        foreach (var t in threads) t.Join();

        var k = new List<string>();
        var v = new List<string>();
        foreach (var s in results.Keys)
        {
            if (s.StartsWith("K:", StringComparison.Ordinal)) k.Add(s); else v.Add(s);
        }
        k.Sort(StringComparer.OrdinalIgnoreCase);
        v.Sort(StringComparer.OrdinalIgnoreCase);
        k.AddRange(v);
        return k;
    }

    private static void EnqueueRoot(ConcurrentStack<Work> queue, ref long pending, int hive, string rel, string full, bool isClass, bool inDeny)
    {
        Interlocked.Increment(ref pending);
        queue.Push(new Work { Hive = hive, Rel = rel, Full = full, IsClass = isClass, InDeny = inDeny });
    }

    private static RegistryKey OpenWork(Work it)
    {
        try
        {
            if (it.Hive == 0) { using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) return hive.OpenSubKey(it.Rel); }
            if (it.Hive == 1) { using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32)) return hive.OpenSubKey(it.Rel); }
            if (it.Hive == 2) { using (var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Default)) return hive.OpenSubKey(it.Rel); }
            if (it.Rel.Length == 0) return Registry.ClassesRoot;
            return Registry.ClassesRoot.OpenSubKey(it.Rel);
        }
        catch (Exception error) { ScanError(it.Full, error); return null; }
    }

    private static void Worker(ConcurrentStack<Work> queue, ref long pending, Regex reExact, Regex reLoose, Regex reGuid, string[] deny, ConcurrentDictionary<string, byte> results)
    {
        while (!_cancelled)
        {
            Work it;
            if (queue.TryPop(out it))
            {
                try { Process(it, reExact, reLoose, reGuid, deny, results, queue, ref pending); }
                catch (Exception error) { ScanError(it.Full, error); }
                finally { Interlocked.Decrement(ref pending); }
            }
            else
            {
                if (Volatile.Read(ref pending) == 0) return;
                Thread.Sleep(2);
            }
        }
    }

    private static void Process(Work it, Regex reExact, Regex reLoose, Regex reGuid, string[] deny, ConcurrentDictionary<string, byte> results, ConcurrentStack<Work> queue, ref long pending)
    {
        Interlocked.Increment(ref _scanned);
        using (var key = OpenWork(it))
        {
            if (key == null) return;
            string name = key.Name;
            int idx = name.LastIndexOf('\\');
            string leaf = idx >= 0 ? name.Substring(idx + 1) : name;

            if (!it.InDeny && reExact.IsMatch(leaf))
            {
                results.TryAdd("K:" + it.Full, 0);
                Interlocked.Increment(ref _matched);
                return;
            }
            if (it.IsClass && reGuid.IsMatch(leaf) && !it.InDeny)
            {
                object def = null;
                try { def = key.GetValue(null); } catch (Exception error) { ScanError(it.Full, error); }
                string ds = def as string;
                if (ds != null && reExact.IsMatch(ds))
                {
                    results.TryAdd("K:" + it.Full, 0);
                    Interlocked.Increment(ref _matched);
                    return;
                }
            }

            string[] vns = null;
            try { vns = key.GetValueNames(); } catch (Exception error) { ScanError(it.Full, error); }
            if (vns != null)
            {
                foreach (string vn in vns)
                {
                    bool match = false;
                    if (reExact.IsMatch(vn)) match = true;
                    if (!match)
                    {
                        object data = null;
                        try { data = key.GetValue(vn); } catch (Exception error) { ScanError(it.Full + " :: " + vn, error); }
                        string s = data as string;
                        if (s != null) match = reExact.IsMatch(s);
                        else
                        {
                            string[] ss = data as string[];
                            if (ss != null)
                            {
                                foreach (string x in ss)
                                {
                                    if (x != null && reExact.IsMatch(x)) { match = true; break; }
                                }
                            }
                        }
                    }
                    if (match)
                    {
                        results.TryAdd("V:" + it.Full + "\u0001" + vn, 0);
                        Interlocked.Increment(ref _matched);
                    }
                }
            }

            string[] sns = null;
            try { sns = key.GetSubKeyNames(); } catch (Exception error) { ScanError(it.Full, error); }
            if (sns != null)
            {
                foreach (string sn in sns)
                {
                    if (_cancelled) return;
                    if (!it.IsClass && sn.Equals("Classes", StringComparison.OrdinalIgnoreCase)) continue;
                    string childFull = it.Full + "\\" + sn;
                    bool childDeny = it.InDeny || IsDeny(deny, childFull);
                    string childRel = it.Rel.Length == 0 ? sn : it.Rel + "\\" + sn;
                    var child = new Work { Hive = it.Hive, Rel = childRel, Full = childFull, IsClass = it.IsClass, InDeny = childDeny };
                    // Depth-first traversal limits the frontier. At capacity,
                    // finish this branch inline instead of abandoning the scan.
                    if (Interlocked.Increment(ref pending) > 100000) {
                        Interlocked.Decrement(ref pending);
                        try { Process(child, reExact, reLoose, reGuid, deny, results, queue, ref pending); }
                        catch (Exception error) { ScanError(child.Full, error); }
                    } else queue.Push(child);
                }
            }
        }
    }

    private static bool IsDeny(string[] deny, string full)
    {
        if (deny == null) return false;
        foreach (var d in deny) if (full.StartsWith(d, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }
}
'@ -ErrorAction Stop
        $script:UniRegOk = $true
    } catch {
        $script:UniRegOk = $false
    }
}

# ---------------------------------------------------------------------------
# delete one target with escalating force: direct -> long-path cmd -> attrib
# No unrelated lock-holder termination, ACL takeover, or recursive shell fallback.
# ---------------------------------------------------------------------------
$script:UniIsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Remove-UniTarget {
    param([string]$Path, [ValidateRange(1,3)][int]$MaxRounds = 3)
    if (-not (Test-UniOwnedPath $Path)) {
        Write-Warning "Preserved without exclusive ownership evidence: $Path"
        return $false
    }
    try {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $true }
        # Nonrecursive .NET deletion of each verified child. No shell interpolation,
        # ACL takeover, junction traversal, or termination of unrelated lock holders.
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $dirs = New-Object 'System.Collections.Generic.List[string]'
        $complete = $true
        $pending.Push([IO.Path]::GetFullPath($Path))
        while ($pending.Count) {
            $current=$pending.Pop()
            if (-not (Test-UniOwnedPath $current)) {
                $complete=$false
                Write-Warning ("Ownership or link changed; preserved: {0}" -f $current)
                continue
            }
            try {
                $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
                Update-UniLine ("[{0}] deleting: {1}" -f (Get-UniElapsed),$current)
                if ($item.PSIsContainer) {
                    $dirs.Add($current)
                    foreach($child in [IO.Directory]::EnumerateFileSystemEntries($current)) { $pending.Push($child) }
                } else {
                    [IO.File]::SetAttributes($current, ($item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
                    [IO.File]::Delete($current)
                }
            } catch {
                $complete=$false
                $message=("Unremoved: {0}: {1}" -f $current,$_.Exception.Message)
                if($script:UniFailed -and -not $script:UniFailed.Contains($message)) {[void]$script:UniFailed.Add($message)}
                Write-Warning $message
            }
        }
        for($i=$dirs.Count-1;$i -ge 0;$i--) {
            $dir=$dirs[$i]
            if (-not (Test-UniOwnedPath $dir)) {
                $complete=$false
                Write-Warning ("Ownership changed during deletion; preserved: {0}" -f $dir)
                continue
            }
            try {
                if([IO.Directory]::Exists($dir)){[IO.Directory]::Delete($dir,$false)}
            } catch {
                $complete=$false
                $message=("Unremoved: {0}: {1}" -f $dir,$_.Exception.Message)
                if($script:UniFailed -and -not $script:UniFailed.Contains($message)) {[void]$script:UniFailed.Add($message)}
                Write-Warning $message
            }
        }
        if(Test-Path -LiteralPath $Path -ErrorAction Stop){
            if($MaxRounds -gt 1){
                Write-Host ('Owned path remains after deletion; reconciling another storage layer: '+$Path)
                return (Remove-UniTarget -Path $Path -MaxRounds ($MaxRounds-1))
            }
            return $false
        }
        return $complete
    } catch {
        Write-Warning ("Unremoved: {0}: {1}" -f $Path,$_.Exception.Message)
        return $false
    }
}

# ---------------------------------------------------------------------------
# tokens / patterns: exact (full names) + loose (full names + 6+ letter
# shared-substrings, so 'ccleaner' also catches '-cccleanup' style markers)
# ---------------------------------------------------------------------------
$script:UniDenyTokens = @(
    'windows', 'win', 'microsoft', 'system', 'sys', 'system32', 'syswow64', 'program', 'programs', 'programdata',
    'users', 'user', 'public', 'common', 'commonfiles', 'temp', 'tmp', 'appdata', 'local', 'locals', 'localdata',
    'network', 'shared', 'microsoftshared', 'config', 'data', 'core', 'kernel', 'driver', 'drivers', 'service',
    'services', 'fonts', 'log', 'logs', 'install', 'installer', 'update', 'runtime', 'default', 'desktop',
    'documents', 'document', 'download', 'downloads', 'start', 'startmenu', 'windowsapps', 'windowsnt',
    'internetexplorer', 'dotnet', 'powershell', 'ps1', 'exe', 'bin', 'lib', 'dll', 'ini', 'cfg', 'dat', 'db',
    'node', 'git', 'test', 'setup', 'help', 'docs', 'readme', 'license', 'version', 'release', 'debug', 'build',
    'source', 'sample', 'samples', 'example', 'examples', 'demo', 'device', 'storage', 'cache', 'history',
    'recent', 'roaming', 'registry', 'shell', 'cmd', 'console', 'photo', 'photos', 'picture', 'pictures',
    'music', 'video', 'videos', 'movie', 'movies', 'image', 'images', 'file', 'files', 'folder', 'backup',
    'archive', 'project', 'projects', 'work', 'report', 'account', 'profile', 'settings', 'game', 'games',
    'save', 'saved', 'app', 'application', 'msi', 'mst', 'htm', 'html', 'xml', 'json', 'png', 'jpg', 'jpeg',
    'gif', 'ico', 'txt', 'md', 'pdf', 'zip', 'rar', '7z', 'tar', 'gz',
    # v3 additions - common words that must never be sweeped on their own
    'viewer', 'player', 'reader', 'editor', 'manager', 'center', 'centre', 'studio', 'cloud', 'sync',
    'launcher', 'helper', 'assistant', 'server', 'client', 'mobile', 'tablet', 'search', 'browser',
    'navigator', 'cleaner', 'cleaners', 'cleanup', 'clean', 'cleans', 'cleaned', 'cleaning',
    'uncleaned', 'leaner', 'cleane', 'disk', 'drive', 'volume', 'memory', 'optimize',
    'optimizer', 'booster', 'speed', 'quick', 'fast', 'note', 'notes', 'notebook', 'updater', 'updates',
    'folder', 'folders', 'directory', 'directories', 'filename', 'path', 'home', 'menu', 'view', 'views',
    'panel', 'widget', 'gadget', 'tray', 'taskbar', 'startup', 'favorite', 'favorites', 'recentdocs',
    'crash', 'crashreport', 'dump', 'dumps', 'session', 'sessions', 'bookmark', 'bookmarks', 'cookie',
    'cookies', 'template', 'templates', 'theme', 'themes', 'skin', 'skins', 'icon', 'icons', 'asset',
    'assets', 'resource', 'resources', 'package', 'packages', 'module', 'modules', 'plugin', 'plugins',
    'extension', 'extensions', 'component', 'components', 'library', 'libraries', 'framework', 'platform',
    'engine', 'api', 'sdk', 'ide', 'compiler', 'interpreter', 'daemon', 'agent', 'broker', 'proxy',
    'gateway', 'host', 'vm', 'container', 'database', 'dataset', 'table', 'record', 'field', 'form',
    'query', 'sql', 'environment', 'var', 'variable', 'value', 'key', 'hives', 'root', 'branch', 'leaf',
    'parent', 'child', 'os', 'kernel', 'device', 'hardware', 'firmware', 'software', 'suite', 'pack',
    'bundle', 'uninstaller', 'configurator', 'virtual', 'vms', 'aws', 'azure', 'gcp', 'google', 'oracle',
    'amazon', 'apple', 'linux', 'unix', 'mac', 'macos', 'ios', 'android', 'web', 'www', 'internet',
    'online', 'offline', 'local', 'remote', 'restore', 'recovery', 'snapshot', 'iso', 'vhd', 'vhdx',
    'vmdk', 'mount', 'format', 'filesystem', 'ntfs', 'swap', 'pagefile', 'hiberfil', 'error', 'warning',
    'fail', 'failure', 'exception', 'bug', 'issue', 'problem', 'fix', 'repair', 'patch', 'hotfix',
    'upgrade', 'downgrade', 'uninstall', 'remove', 'delete', 'erase', 'wipe', 'purge', 'sweep', 'prune',
    'trim', 'defrag', 'compact', 'compress', 'cab', 'msp', 'mst', 'ocx', 'com', 'vxd', 'drv', 'inf',
    'mdb', 'mdf', 'ldf', 'ndf', 'csv', 'tsv', 'yaml', 'yml', 'toml', 'properties', 'props', 'admin',
    'administrator', 'guest', 'domain', 'group', 'everyone', 'authenticated', 'anonymous', 'interactive',
    'batch', 'scheduler', 'scheduled', 'jobs', 'at', 'once', 'daily', 'weekly', 'monthly', 'hourly',
    'logon', 'boot', 'reboot', 'shutdown', 'restart', 'sleep', 'hibernate', 'resume', 'wake', 'power',
    'battery', 'acl', 'dacl', 'sacl', 'ace', 'owner', 'inherit', 'write', 'execute', 'modify', 'deny',
    'allow', 'grant', 'permission', 'right', 'privilege', 'elevated', 'elevation', 'uac', 'sudo',
    'runas', 'token', 'handle', 'object', 'event', 'mutex', 'semaphore', 'timer', 'wait', 'thread',
    'fiber', 'apc', 'dpc', 'dma', 'io', 'filter', 'fs', 'storage', 'media', 'cd', 'dvd', 'bluray',
    'floppy', 'tape', 'ssd', 'hdd', 'nvme', 'sata', 'scsi', 'usb', 'thunderbolt', 'firewire', 'pci',
    'pcie', 'vga', 'dvi', 'hdmi', 'serial', 'parallel', 'ps2', 'jack', 'socket', 'slot', 'bus',
    'bridge', 'controller', 'hub', 'switch', 'router', 'modem', 'nic', 'tcp', 'udp', 'icmp', 'arp',
    'dns', 'dhcp', 'http', 'https', 'ftp', 'sftp', 'ssh', 'telnet', 'smtp', 'pop', 'imap', 'ntp',
    'ldap', 'kerberos', 'ssl', 'tls', 'rdp', 'vnc', 'teamviewer', 'anydesk', 'chrome', 'chromium',
    'firefox', 'safari', 'opera', 'edge', 'ie', 'webview', 'electron', 'qt', 'gtk', 'java',
    'javascript', 'typescript', 'python', 'php', 'ruby', 'go', 'golang', 'rust', 'swift', 'kotlin',
    'c', 'cpp', 'c++', 'c#', 'vb', 'node', 'npm', 'yarn', 'pnpm', 'bun', 'kubernetes', 'k8s',
    'ubuntu', 'debian', 'fedora', 'arch', 'centos', 'redhat', 'alpine', 'suse', 'manjaro', 'mint',
    'kali', 'wifi', 'bluetooth', 'ethernet', 'wlan', 'wan', 'vpn', 'security', 'secure', 'protect',
    'protection', 'guard', 'shield', 'defender', 'antivirus', 'malware', 'spyware', 'adware', 'trojan',
    'virus', 'worm', 'ransomware', 'rootkit', 'botnet', 'phishing', 'scam', 'fraud', 'crack', 'keygen',
    'hack', 'cheat', 'mod', 'overlay', 'stream', 'broadcast', 'record', 'writer', 'find', 'index',
    'crawler', 'spider', 'bot', 'automation', 'script', 'macro', 'shortcut', 'link', 'url', 'uri',
    'dir', 'drive', 'name', 'label', 'tag', 'keyword', 'term', 'column', 'row', 'entry', 'item',
    'list', 'array', 'map', 'hash', 'dict', 'class', 'type', 'interface', 'enum', 'struct',
    'namespace', 'assembly', 'binary', 'executable', 'pid', 'job', 'schedule', 'trigger', 'action',
    'condition', 'parameter', 'argument', 'flag', 'switch', 'sibling', 'ancestor', 'descendant',
    'bios', 'uefi', 'iphone', 'ipad', 'watch', 'tv', 'intranet', 'extranet', 'fat32', 'exfat', 'ext4',
    'btrfs', 'xfs', 'zfs', 'raid', 'lvm', 'minidump', 'warnings', 'failures', 'exceptions', 'tasks',
    'minutes', 'hour', 'hours', 'day', 'days', 'week', 'weeks', 'month', 'months', 'year', 'years'
)

function Get-UniTokenPattern {
    param([string]$Token)
    $sb = ''
    foreach ($c in $Token.ToCharArray()) {
        if ($sb.Length) { $sb += '[^a-z0-9]*' }
        $sb += [regex]::Escape($c.ToString())
    }
    return $sb
}

function Get-UniPatterns {
    param([string[]]$Names)
    $parts = @(); $orphanParts = @(); $tokens = @()
    # An unresolved app can still leave deliberately named artifact containers
    # (for example GMenuRepair, GMenuRuntime, or .gmenu-work-*).  The orphan
    # pattern permits only a finite, artifact-shaped suffix; it never changes
    # the normal exact-name ownership pattern used for registered apps.
    $orphanSuffix = '(?:repair|runtime|payload|work|backup|link|audit|cache|data|config|log|logs|code|module|modules|function|functions|fallback|test|tests|final|restore|publish|launch|credential|credentials|saved|availability|resume|install|proof|result|manifest|file|files|dir|directory|app|service|task|setup|package|extension|plugin|hook|startup|source|project|projects|update|version|build|session|temp|debug|report|history|cleanup|removal|verification|regression|release)'
    foreach ($name in $Names) {
        $name = ([string]$name).Trim()
        $token = ($name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
        if ($token.Length -lt 4 -or $script:UniDenyTokens -contains $token) { continue }
        if ($name -match '[\\/:*?"<>|\x00-\x1f]') { throw "Invalid app name: $name" }
        $tokens += $token
        # Full token only. Never invent substrings or cross directory separators.
        $body = (([regex]::Split($name, '[ ._-]+') | ForEach-Object { [regex]::Escape($_) }) -join '[ ._-]*')
        $parts += '(?<![A-Za-z0-9])' + $body + '(?![A-Za-z0-9])'
        $orphanParts += '(?<![A-Za-z0-9])' + [regex]::Escape($token) + '(?:$|(?=[ ._-])|(?=[0-9])|' + $orphanSuffix + '(?![A-Za-z0-9]))'
    }
    if (-not $parts.Count) { return $null }
    $pattern = '(?:' + ($parts -join '|') + ')'
    return @{ Tokens=@($tokens | Select-Object -Unique); Exact=$pattern; Loose=$pattern; Orphan=('(?:' + ($orphanParts -join '|') + ')') }
}

# ---------------------------------------------------------------------------
# stats
# ---------------------------------------------------------------------------
$script:UniStats = @{ Processes = 0; Services = 0; Tasks = 0; Firewall = 0; RegKeys = 0; RegValues = 0; EnvVars = 0; Shortcuts = 0; Files = 0; Dirs = 0 }
$script:UniFailed = New-Object System.Collections.Generic.List[string]
$script:UniProtectedArtifacts = New-Object System.Collections.Generic.List[string]
$script:UniRegSweepFound = $false
$script:UniOrphanMode = $false
$script:UniOrphanMatches = 0
$script:UniGMenuCleanupAuthorized = $false
$script:UniOrphanPattern = $null

function Add-UniProtectedArtifact {
    param([string]$Path,[string]$Reason = 'Preserved without exclusive ownership evidence')
    if($null -eq $script:UniProtectedArtifacts){return}
    $entry = if([string]::IsNullOrWhiteSpace($Reason)){[string]$Path}else{('{0}: {1}' -f $Reason,$Path)}
    if(-not $script:UniProtectedArtifacts.Contains($entry)){[void]$script:UniProtectedArtifacts.Add($entry)}
}

# ---------------------------------------------------------------------------
# 1. kill every related process (name / path / command line / window title)
# ---------------------------------------------------------------------------
function Invoke-UniKillProcesses {
    param($ReExact,[object[]]$Candidates)
    $stopped=New-Object 'System.Collections.Generic.List[object]'
    if(-not $PSBoundParameters.ContainsKey('Candidates')){$Candidates=@(Get-Process -ErrorAction Stop)}
    foreach($candidate in $Candidates) {
        try {
            if ($script:UniProtectedPids.ContainsKey($candidate.Id)) { continue }
            if ($script:UniNeverKill -contains $candidate.ProcessName.ToLowerInvariant()) { continue }
            $exe=$candidate.Path
            if (-not (Test-UniTargetExecutable $exe)) { continue }
            if([IO.Path]::GetFileName($exe) -match '^(unins\d*|uninstall|setup|.*installer)\.exe$'){continue}
            $started=$candidate.StartTime
            # Reopen and validate creation time and executable immediately before Kill.
            $live=Get-Process -Id $candidate.Id -ErrorAction Stop
            if ($live.StartTime -ne $started -or $live.Path -ine $exe -or -not (Test-UniTargetExecutable $live.Path)) { continue }
            Write-Host ("Stopping owned process: {0} PID {1}" -f $exe,$live.Id)
            $live.Kill()
            $stopped.Add($live)
            $script:UniStats.Processes++
        } catch {
            if ($exe -and (Test-UniTargetExecutable $exe)) {
                $script:UniFailed.Add(('Process close failed: {0} PID {1}: {2}' -f $exe,$candidate.Id,$_.Exception.Message))
                Write-Warning ('Unable to force-close verified target; continuing: '+$exe+' PID '+$candidate.Id)
            }
        } finally { $exe=$null }
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    foreach($live in $stopped){
        $remaining=[math]::Max(0,[int]($deadline-[DateTime]::UtcNow).TotalMilliseconds)
        if(-not $live.WaitForExit($remaining)){$script:UniFailed.Add('Process did not exit within five seconds: '+$live.Id)}
    }
}

# ---------------------------------------------------------------------------
# 2. stop + delete related services (WMI + registry Services key)
# ---------------------------------------------------------------------------
function Invoke-UniServices {
 param($ReExact)
 Add-Type -AssemblyName System.ServiceProcess -ErrorAction Stop
 # SCM + registry are independent of a broken/hung Win32_Service WMI provider.
 foreach($service in [ServiceProcess.ServiceController]::GetServices()) {
  $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\'+$service.ServiceName)
  if(-not $key){$service.Dispose();continue}
  try {$image=[Environment]::ExpandEnvironmentVariables([string]$key.GetValue('ImagePath'))} finally {$key.Close()}
  $command=Split-UniCommand $image
  if(-not $command -or -not(Test-UniTargetExecutable $command.File)){$service.Dispose();continue}
  try {
   if(@($service.DependentServices | Where-Object Status -NE Stopped).Count){$script:UniFailed.Add('Running service dependents: '+$service.ServiceName);continue}
   Write-Host ('Stopping owned service: '+$service.ServiceName)
   if($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped){$service.Stop();$service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10))}
   $info=New-Object Diagnostics.ProcessStartInfo
   $info.FileName="$env:SystemRoot\System32\sc.exe";$info.Arguments='delete "'+$service.ServiceName+'"';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
   $proc=[Diagnostics.Process]::Start($info)
   if(-not $proc.WaitForExit(10000)){$proc.Kill();throw 'Service deletion command timed out'}
   if($proc.ExitCode -ne 0){throw ('Service deletion failed: '+$proc.ExitCode)}
   if(Get-Service -Name $service.ServiceName -ErrorAction SilentlyContinue){$script:UniFailed.Add('Service pending deletion: '+$service.ServiceName)}else{$script:UniStats.Services++}
  } catch {$script:UniFailed.Add('Service: '+$service.ServiceName+': '+$_.Exception.Message)}
  finally {$service.Dispose()}
 }
}

# ---------------------------------------------------------------------------
# 3. delete related scheduled tasks (incl. .job leftovers via filesystem pass)
# ---------------------------------------------------------------------------
function Test-UniRequestedTaskName {
 param([string]$TaskPath)
 if(-not $TaskPath){return $false}
 $leaf=[IO.Path]::GetFileName($TaskPath.TrimEnd('\'))
 $taskCompact=((Get-UniIdentity $leaf) -replace '[^a-z0-9]','')
 if(-not $taskCompact){return $false}
 $scope=@($script:UniRequestedIdentities)
 if($script:UniDriverBoosterRequested){$scope += 'driverbooster'}
 if($script:UniIObitRequested){$scope += 'iobit'}
 foreach($identity in @($scope | Select-Object -Unique)){
  $idCompact=(([string]$identity) -replace '[^a-z0-9]','')
  if(-not $idCompact -or -not $taskCompact.StartsWith($idCompact,[StringComparison]::OrdinalIgnoreCase)){continue}
  $suffix=$taskCompact.Substring($idCompact.Length)
  # A task whose leaf is exactly the requested product name is an app-owned
  # startup entry (for example \MichStartupMaster\Telegram). Keep this exact
  # match narrow; unrelated suffixes still require an approved task role.
  if($suffix -eq ''){return $true}
   if($suffix -match '^(?:scheduler|schedule|update|updater|skipuac(?:user)?|uninstall|uninstaller|maintenance|helper|service|tray|monitor|agent|fls[0-9]*sale(?:onetime)?|sale(?:onetime)?|(?:desktop)?watchdog|d?killstartservice|(?:start|stop|restart)?service|health(?:fix|check)?|wsl(?:health|integration)?|proxy|backend|vm|network|cleanup|reset|restore|autostart|autoupdate)$'){return $true}
 }
 return $false
}
function Test-UniTaskAction {
 param($Action,[string]$TaskPath)
 if($Action.Type -ne 0){return $false}
 $executable=[Environment]::ExpandEnvironmentVariables([string]$Action.Path).Trim('"')
 if(Test-UniTargetExecutable $executable){return $true}
 # Vendor tasks often use a shared Windows host (PowerShell, cmd, or
 # wscript) and put the app-specific script in the arguments. Require both
 # an approved task role and an exact requested identity in those arguments;
 # the host executable itself is never treated as an app target.
 if((Test-UniRequestedTaskName $TaskPath) -and $executable -match '(?i)\\(?:wscript|cscript|powershell|pwsh|cmd)\.exe$'){
  $argumentText=[string]$Action.Arguments
  foreach($identity in @(Get-UniRequestedScopeIdentities)){
   $idCompact=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant()
   if($idCompact.Length -ge 5 -and $argumentText -match ('(?i)(?:^|[^A-Za-z0-9])'+[regex]::Escape($idCompact)+'(?:[^A-Za-z0-9]|$)')){return $true}
  }
 }
 # A registered task can outlive the uninstall registration and point to a
 # portable F: executable whose metadata is no longer readable. Identify only
 # exact vendor task roles and require the action path to carry the same
 # requested product identity. This authorizes task removal, never F: deletion.
 if(Test-UniRequestedTaskName $TaskPath){
  if($executable -notmatch '^[A-Za-z]:\\[^\r\n<>|*?]+\.exe$' -or $executable.Substring(2).Contains(':')){return $false}
  $pathCompact=(($executable -replace '[^A-Za-z0-9]','').ToLowerInvariant())
  $scope=@($script:UniRequestedIdentities)
  if($script:UniDriverBoosterRequested){$scope += 'driverbooster'}
  if($script:UniIObitRequested){$scope += 'iobit'}
  foreach($identity in @($scope | Select-Object -Unique)){
   $idCompact=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant()
   if($idCompact.Length -ge 5 -and $pathCompact.Contains($idCompact)){return $true}
  }
 }
 # This shared manager encodes one executable plus its arguments as UTF-8
 # base64. Remove only that app's task; never make the manager a kill target.
 if($TaskPath -notmatch '^\\MichStartupMaster\\[^\\]+$' -or $executable -ine 'F:\study\Windows\Applications\Desktop\Utilities\System\Startup\Managers\mich-startup-master\build\MichStartupMaster.exe'){return $false}
 if([string]$Action.Arguments -notmatch '^--tray-run ([A-Za-z0-9+/]+={0,2})$'){return $false}
 try {$decoded=(New-Object Text.UTF8Encoding($false,$true)).GetString([Convert]::FromBase64String($matches[1]))} catch {return $false}
 $parts=$decoded -split "`n",2
 $target=$parts[0].TrimEnd("`r")
 if(Test-UniTargetExecutable $target){return $true}
 # Stale registration: exact executable, parent product folder and task name
 # must all identify the requested app, with no additional launch arguments.
 if($target -notmatch '^[A-Za-z]:\\[^\r\n<>|*?]+\.exe$' -or $target.Substring(2).Contains(':') -or (Test-Path -LiteralPath $target)){return $false}
 if($parts.Count -gt 1 -and $parts[1].Trim()){return $false}
 $identities=@($script:UniRequestedIdentities)
 return (($identities -contains (Get-UniIdentity ([IO.Path]::GetFileNameWithoutExtension($target)))) -and
          ($identities -contains (Get-UniIdentity ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($target))))) -and
          ($identities -contains (Get-UniIdentity ([IO.Path]::GetFileName($TaskPath)))))
 }

function Get-UniTaskStoreEntries {
 param([switch]$Refresh)
 if(-not $Refresh -and $script:UniTaskStoreScanComplete){return @($script:UniTaskStoreEntries)}
 $script:UniTaskStoreScanComplete=$false
 $script:UniTaskStoreEntries=@()
 $root=if($script:UniTaskStoreRoot){[IO.Path]::GetFullPath([string]$script:UniTaskStoreRoot)}else{Join-Path $env:WINDIR 'System32\Tasks'}
 if(-not [IO.Directory]::Exists($root)){$script:UniTaskStoreScanComplete=$true;return @()}
 $queue=New-Object 'System.Collections.Generic.Queue[string]'
 [void]$queue.Enqueue($root)
 $watch=[Diagnostics.Stopwatch]::StartNew()
 try {
  while($queue.Count){
   if($watch.Elapsed.TotalSeconds -ge 10){throw 'Task-store scan exceeded ten seconds'}
   $directory=$queue.Dequeue()
   foreach($entry in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)){
    if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
    if($entry.PSIsContainer){[void]$queue.Enqueue($entry.FullName);continue}
    $relative=$entry.FullName.Substring($root.Length).TrimStart('\')
    if(-not $relative){continue}
    $taskPath='\'+$relative
    try {
     $xml=New-Object Xml.XmlDocument
     $xml.XmlResolver=$null
     $xml.LoadXml([IO.File]::ReadAllText($entry.FullName))
      $actions=New-Object 'System.Collections.Generic.List[object]'
     foreach($node in @($xml.SelectNodes("//*[local-name()='Exec']"))){
      $commandNode=$node.SelectSingleNode("./*[local-name()='Command']")
      if(-not $commandNode){continue}
      $argumentsNode=$node.SelectSingleNode("./*[local-name()='Arguments']")
      [void]$actions.Add([pscustomobject]@{Type=0;Path=[string]$commandNode.InnerText;Arguments=if($argumentsNode){[string]$argumentsNode.InnerText}else{''}})
     }
     if($actions.Count){$script:UniTaskStoreEntries += [pscustomobject]@{Path=$taskPath;Actions=@($actions.ToArray());File=$entry.FullName}}
    } catch { continue }
   }
  }
  $script:UniTaskStoreScanComplete=$true
 } catch {
  if($script:UniFailed){$script:UniFailed.Add('Task-store scan unavailable: '+$_.Exception.Message)}
 }
 return @($script:UniTaskStoreEntries)
}

function Invoke-UniTaskStoreDeletion {
 param($Entry,[ValidateRange(1,60)][int]$TimeoutSeconds=15)
 $taskPath=[string]$Entry.Path
 if($taskPath -notmatch '^\\[^\"\r\n]+$'){return $false}
 # Tests may point the reader at a private fixture directory. Production
 # always uses schtasks.exe; never delete a protected task file directly.
 if($script:UniTaskStoreRoot){
  try {Remove-Item -LiteralPath ([string]$Entry.File) -Force -ErrorAction Stop;return (-not(Test-Path -LiteralPath ([string]$Entry.File)))} catch {return $false}
 }
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=Join-Path $env:WINDIR 'System32\schtasks.exe'
 $info.Arguments='/Delete /TN "'+$taskPath.Replace('"','')+'" /F'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=$null
 try {
  $process=[Diagnostics.Process]::Start($info)
  if(-not $process.WaitForExit($TimeoutSeconds*1000)){$process.Kill();[void]$process.WaitForExit(3000);return $false}
  $code=$process.ExitCode
  $null=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd()
  if($code -ne 0){if($script:UniFailed){$script:UniFailed.Add('Scheduled task delete failed: '+$taskPath+' exit '+$code+' '+$errorText.Trim())};return $false}
  $root=Join-Path $env:WINDIR 'System32\Tasks'
  $file=[IO.Path]::Combine($root,$taskPath.TrimStart('\').Replace('\',[IO.Path]::DirectorySeparatorChar))
  $deadline=[DateTime]::UtcNow.AddSeconds(5)
  while([IO.File]::Exists($file) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
  if([IO.File]::Exists($file)){if($script:UniFailed){$script:UniFailed.Add('Scheduled task remains after deletion: '+$taskPath)};return $false}
  return $true
 } catch {if($script:UniFailed){$script:UniFailed.Add('Scheduled task delete failed: '+$taskPath+': '+$_.Exception.Message)};return $false}
 finally {if($process){$process.Dispose()}}
}

function Invoke-UniTasks {
 param($ReExact)
 $storeEntries=@(Get-UniTaskStoreEntries -Refresh)
 if($script:UniTaskStoreScanComplete){
  foreach($entry in $storeEntries){
   $actions=@($entry.Actions);$owned=$actions.Count -gt 0
   foreach($action in $actions){if(-not(Test-UniTaskAction $action $entry.Path)){$owned=$false;break}}
   if(-not $owned){continue}
   Write-Host ('Removing owned task: '+$entry.Path)
   if(Invoke-UniTaskStoreDeletion $entry){$script:UniStats.Tasks++}
  }
  Invoke-UniLegacyTasks
  return
 }
 $scheduler=$null
 try {
  $scheduler=New-Object -ComObject Schedule.Service -ErrorAction Stop
  $scheduler.Connect()
  $folders=New-Object 'System.Collections.Generic.Queue[object]'
  $folders.Enqueue($scheduler.GetFolder('\'))
  while($folders.Count){
   $folder=$folders.Dequeue()
   foreach($task in $folder.GetTasks(1)){
    $actions=@($task.Definition.Actions); if(-not $actions.Count){continue}
    $owned=$true
    foreach($action in $actions){if(-not(Test-UniTaskAction $action $task.Path)){$owned=$false}}
    if(-not $owned){continue}
    Write-Host ('Removing owned task: '+$task.Path)
    if($task.State -eq 4){$task.Stop(0)}
    $folder.DeleteTask($task.Name,0)
    $script:UniStats.Tasks++
   }
   foreach($child in $folder.GetFolders(0)){$folders.Enqueue($child)}
  }
 } catch {$script:UniFailed.Add('Scheduled-task verification: '+$_.Exception.Message)}
 finally {if($scheduler){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($scheduler)}}
 Invoke-UniLegacyTasks
}
function Get-UniLegacyTaskExecutable {
 param([byte[]]$Bytes)
 # MS-TSCH 2.4.1 / 2.4.2.1: fixed header offset and counted UTF-16 string.
 if($Bytes.Length -lt 72 -or [BitConverter]::ToUInt16($Bytes,2) -ne 1){return $null}
 $offset=[int][BitConverter]::ToUInt16($Bytes,20)
 if($offset -lt 70 -or $offset+2 -gt $Bytes.Length){return $null}
 $count=[int][BitConverter]::ToUInt16($Bytes,$offset)
 if($count -lt 2 -or $offset+2+2*$count -gt $Bytes.Length){return $null}
 $value=[Text.Encoding]::Unicode.GetString($Bytes,$offset+2,2*$count)
 if($value[$value.Length-1] -ne [char]0){return $null}
 $value=$value.Substring(0,$value.Length-1)
 if($value.Contains([string][char]0)){return $null}
 return $value
}
function Invoke-UniLegacyTasks {
 foreach($file in @(Get-ChildItem -LiteralPath 'C:\Windows\Tasks' -Filter '*.job' -File -Force -ErrorAction SilentlyContinue)){
  try {
   $full=[IO.Path]::GetFullPath($file.FullName)
   if([IO.Path]::GetDirectoryName($full) -ine 'C:\Windows\Tasks'){continue}
   $linked=$false;$current=$full
   while($current.Length -gt 3){if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){$linked=$true;break};$current=[IO.Path]::GetDirectoryName($current)}
   if($linked){continue}
   $bytes=[IO.File]::ReadAllBytes($full)
   $target=Get-UniLegacyTaskExecutable $bytes
   if(-not $target -or -not(Test-UniTargetExecutable $target)){continue}
   # Recheck the actual definition, never authorize a task by its filename.
   if([Convert]::ToBase64String([IO.File]::ReadAllBytes($full)) -cne [Convert]::ToBase64String($bytes)){throw 'Legacy task changed during verification'}
   Write-Host ('Removing verified legacy task: '+$full)
   [IO.File]::Delete($full)
   if([IO.File]::Exists($full)){throw 'Legacy task remains'}
   $script:UniStats.Tasks++
  } catch {$script:UniFailed.Add('Legacy task: '+$file.FullName+': '+$_.Exception.Message)}
 }
}

# ---------------------------------------------------------------------------
# 4. delete related firewall rules
# ---------------------------------------------------------------------------
function Invoke-UniFirewall {
    param($ReExact)
    $policy=$null
    try {
        $policy=New-Object -ComObject HNetCfg.FwPolicy2 -ErrorAction Stop
        $groups=@{}
        foreach($rule in $policy.Rules){
            $name=[string]$rule.Name
            if(-not $groups.ContainsKey($name)){$groups[$name]=@()}
            $groups[$name] += [string]$rule.ApplicationName
        }
        foreach($name in @($groups.Keys)){
            $owned=$true
            foreach($application in $groups[$name]){
                if(-not(Test-UniTargetExecutable ([Environment]::ExpandEnvironmentVariables($application)))){$owned=$false}
            }
            if(-not $owned){continue}
            # Reconcile duplicate names immediately before the name-based COM removal.
            $live=@($policy.Rules | Where-Object Name -EQ $name)
            if(-not $live.Count){continue}
            foreach($rule in $live){if(-not(Test-UniTargetExecutable ([Environment]::ExpandEnvironmentVariables([string]$rule.ApplicationName)))){$owned=$false}}
            if(-not $owned){$script:UniFailed.Add('Shared firewall rule name: '+$name);continue}
            Write-Host "Removing owned firewall rule: $name"
            $policy.Rules.Remove($name)
            if(@($policy.Rules | Where-Object Name -EQ $name).Count){$script:UniFailed.Add('Firewall rule remains: '+$name)}
            else{$script:UniStats.Firewall++}
        }
    } catch {$script:UniFailed.Add('Firewall verification unavailable: '+$_.Exception.Message);Write-Warning $script:UniFailed[$script:UniFailed.Count-1]}
    finally {if($policy){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($policy)}}
}

# ---------------------------------------------------------------------------
# 5. uninstall entries / App Paths / Run & RunOnce values
# ---------------------------------------------------------------------------
function Remove-UniRegistryKey {
    param([string]$ProviderPath)
    if (-not (Test-UniOwnedRegistry $ProviderPath)) { throw "Registry key lacks exclusive ownership: $ProviderPath" }
    Remove-Item -LiteralPath $ProviderPath -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $ProviderPath -ErrorAction Stop) { throw "Registry key remains: $ProviderPath" }
}

# remove one registry value. An empty value name means the key's DEFAULT value
# (e.g. per-app audio PolicyConfig references), which PowerShell's
# Remove-ItemProperty refuses with a parameter-binding error that
# -ErrorAction cannot silence - so empty names go through the .NET API instead.
function Test-UniOwnedRegistryValue {
 param([string]$ProviderPath,[AllowEmptyString()][string]$ValueName,[object]$Value)
 if(Test-UniOwnedRegistry $ProviderPath){return $true}
  $path=$ProviderPath -replace '^.*Registry::',''
  # Registry providers may report either HKCU:\.../HKLM:\... or the
  # separator-only HKCU\.../HKLM\... form. Normalize both before applying
  # the narrow per-value ownership rules below.
  $path=$path -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\','HKEY_CURRENT_USER\'
  $path=$path -replace '^HKLM\\','HKEY_LOCAL_MACHINE\' -replace '^HKCU\\','HKEY_CURRENT_USER\'
 # Defender exclusions are shared by the OS, but each path value is an
 # independent record.  Remove only a value whose path contains an exact
 # requested-app directory identity; never treat the whole Exclusions key as
 # owned and never match a bare product substring in arbitrary data.
 if($path -ieq 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths'){
  return (Test-UniRequestedPathReference $ValueName)
 }
 # AppListBackup is also a shared Windows value store.  Its JSON contains
 # independent app records, so Remove-UniRegistryValue performs a surgical
 # record update when at least one record belongs to the requested app.
 if($path -match '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\AppListBackup(?:\\ListOfEventDrivenBackedUpApps_[0-9]+)?$'){
  return (Test-UniAppListBackupValue $Value)
 }
 if($path -ieq 'HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'){
  if($ValueName -match '^(?<exe>.+\.exe)\.(ApplicationCompany|FriendlyAppName)$'){return (Test-UniAppReference $matches.exe)}
 }
 if($path -ieq 'HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'){return (Test-UniAppReference $ValueName)}
 if($path -match '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\(?:Explorer\\FeatureUsage\\(?:AppBadgeUpdated|AppLaunch|AppSwitched|ShowJumpView)|Search\\JumplistData)$'){
  if(Test-UniAppReference $ValueName){return $true}
  if(@($script:UniRequestedIdentities) -contains 'todoist' -and $ValueName -match '^(com\.todoist|electron\.app\.Todoist)$'){return $true}
  if(@($script:UniRequestedIdentities) -contains 'telegram' -and $ValueName -match '^Telegram\.TelegramDesktop(?:\.[0-9a-f]{32})?$'){return $true}
 }
 if($path -match '\\CurrentVersion\\Run(Once)?$'){
  $command=Split-UniCommand ([string]$Value)
  return [bool]($command -and (Test-UniTargetExecutable $command.File))
 }
 # These stores contain independent per-application values. Ownership of one
 # value never grants ownership of its shared Windows or Bitsum parent key.
 if($path -match '^HKEY_LOCAL_MACHINE\\SOFTWARE\\Bitsum\\Counters\\ProBalance_(Durations|Processes|TimeStamps)$'){
  foreach($identity in @($script:UniRequestedIdentities)){
   if($identity -match '^[a-z0-9]{3,}$' -and $ValueName -ieq ($identity+'.exe')){return $true}
  }
 }
 if($path -ieq 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'){
  foreach($identity in @($script:UniRequestedIdentities)){
   if($identity -notmatch '^[a-z0-9]{3,}$'){continue}
   $scheme=[regex]::Escape('com.'+$identity)
   if($ValueName -match ('^(?:AppX[a-z0-9]{32}|'+$scheme+')_'+$scheme+'$')){return $true}
  }
 }
 if($path -match '^(HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE)\\Software\\RegisteredApplications$'){
  $hive=$matches[1]
  if(@($script:UniRequestedIdentities) -contains (Get-UniIdentity $ValueName)){
   return (Test-UniOwnedRegistry ($hive+'\'+[string]$Value))
  }
 }
 return $false
}

function Get-UniRequestedRegistryPathIdentities {
 param()
 $ids=@(Get-UniRequestedScopeIdentities)
 # These are exact product-folder variants observed in the app's own
 # registrations.  They are deliberately finite; publisher names and loose
 # substrings do not grant registry ownership.
 if($ids -contains 'iobit'){$ids += @('iobit','iobitextracted','iobitdriverbooster','iobitrtt')}
 if($ids -contains 'driverbooster'){$ids += @('driverbooster','driverboosterpro','driverboosterproimage','driverboosterportable')}
 return @($ids | Where-Object {$_} | ForEach-Object {([string]$_).ToLowerInvariant()} | Select-Object -Unique)
}
function Test-UniRequestedPathReference {
 param([string]$Path)
 $raw=[Environment]::ExpandEnvironmentVariables([string]$Path).Trim().Trim('"')
 if(-not $raw -or $raw -match '[\x00-\x1f<>|*?]' -or $raw -notmatch '^(?:\\\\\?\\)?[A-Za-z]:\\') {return $false}
 if(Test-UniPreservedReference $raw){return $false}
 $normalized=$raw -replace '^\\\\\?\\',''
 $aliases=@(Get-UniRequestedRegistryPathIdentities)
 foreach($segment in @($normalized -split '[\\/]' | Where-Object {$_})){
  $sid=Get-UniIdentity $segment
  if($aliases -contains $sid){return $true}
 }
 return $false
}
function Get-UniAppListBackupRecords {
 param([object]$Value)
 if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)){return @()}
 $raw=[string]$Value
 try {return @((ConvertFrom-Json -InputObject $raw -ErrorAction Stop))} catch { }
 # Windows sometimes writes literal backslashes in AppListBackup JSON
 # (for example ARP\Machine\X86\...). Escape only backslashes that are not
 # already valid JSON escapes, then parse again without broad text matching.
 try {
  $escaped=[regex]::Replace($raw,'\\(?!["\\/bfnrtu])','\\\\')
  return @((ConvertFrom-Json -InputObject $escaped -ErrorAction Stop))
 } catch {return @()}
}

# Defender's Exclusions\Paths key is protected/shared.  Prefer Microsoft's
# exact provider for an owned path when it is available; never stop, enable,
# disable, or reconfigure the Defender services as part of an app purge.
function Remove-UniDefenderExclusionPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 if(-not (Test-UniRequestedPathReference $Path)){throw "Defender exclusion is not an exact requested path: $Path"}
 $modulePath=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\Modules\Defender\Defender.psd1'
 $command=Get-Command -Name 'Remove-MpPreference' -ErrorAction SilentlyContinue
 if(-not $command -or $command.ModuleName -ne 'Defender'){
  if(-not (Test-Path -LiteralPath $modulePath)){throw 'Defender PowerShell module is unavailable'}
  Import-Module -Name $modulePath -Force -ErrorAction Stop
  $command=Get-Command -Name 'Remove-MpPreference' -ErrorAction SilentlyContinue
 }
 if(-not $command -or $command.ModuleName -ne 'Defender'){throw 'Defender Remove-MpPreference provider is unavailable'}
 & $command.Name -ExclusionPath $Path -ErrorAction Stop
 $verify=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths',$false)
 if($verify){
  try {if($verify.GetValueNames() -contains $Path){throw "Defender exclusion remains after provider removal: $Path"}}
  finally {$verify.Close()}
 }
}
function Test-UniAppListBackupRecord {
 param([object]$Record)
 if(-not $Record){return $false}
 $name=[string]$Record.appName
 $appId=[string]$Record.appId
 $publisher=[string]$Record.publisher
 $scope=@(Get-UniRequestedScopeIdentities)
 foreach($identity in $scope){
  if(Test-UniProductName $name @($identity)){return $true}
  $idBase=$appId -replace '(?i)(?:_is1|-is1)$',''
  if($idBase -and (Test-UniProductName $idBase @($identity))){return $true}
 }
 # An explicit iobit request intentionally owns IObit's independently
 # registered records.  A driverbooster-only request does not own the whole
 # publisher bucket.
 return ($scope -contains 'iobit' -and $publisher.Trim() -ieq 'iobit')
}
function Test-UniAppListBackupValue {
 param([object]$Value)
 $records=@(Get-UniAppListBackupRecords $Value)
 if(-not $records.Count){return $false}
 foreach($record in $records){if(Test-UniAppListBackupRecord $record){return $true}}
 return $false
}
function Remove-UniAppListBackupValue {
 param([Parameter(Mandatory=$true)][Microsoft.Win32.RegistryKey]$Key,[AllowEmptyString()][string]$ValueName,[object]$Value)
 $records=@(Get-UniAppListBackupRecords $Value)
 if(-not $records.Count){throw 'AppListBackup value is not valid JSON; preserving it'}
 $remaining=@($records | Where-Object {-not(Test-UniAppListBackupRecord $_)})
 if($remaining.Count -eq $records.Count){throw 'AppListBackup value has no exact requested-app record'}
 if([string]$Key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne [string]$Value){throw 'AppListBackup value changed during verification'}
 if($remaining.Count -eq 0){
  $Key.DeleteValue($ValueName,$true)
 } else {
  $updated=ConvertTo-Json -InputObject $remaining -Depth 20 -Compress
  $Key.SetValue($ValueName,$updated,[Microsoft.Win32.RegistryValueKind]::String)
 }
 $check=$Key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
 if($remaining.Count -eq 0){if($Key.GetValueNames() -contains $ValueName){throw 'AppListBackup value still exists'}}
 else {
  $after=@(Get-UniAppListBackupRecords $check)
  if(@($after | Where-Object {Test-UniAppListBackupRecord $_}).Count){throw 'Requested AppListBackup record remains'}
  if($after.Count -ne $remaining.Count){throw 'Unrelated AppListBackup records changed'}
 }
}
function Remove-UniRegistryValue {
 param([string]$ProviderPath,[AllowEmptyString()][string]$ValueName)
  $path=$ProviderPath -replace '^.*Registry::',''
  $path=$path -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\','HKEY_CURRENT_USER\'
  $path=$path -replace '^HKLM\\','HKEY_LOCAL_MACHINE\' -replace '^HKCU\\','HKEY_CURRENT_USER\'
 $defenderProviderError=$null
 if($path -ieq 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths' -and (Test-UniOwnedRegistryValue $ProviderPath $ValueName $null)){
  try {Remove-UniDefenderExclusionPath -Path $ValueName; return}
  catch {$defenderProviderError=$_.Exception.Message}
 }
 $split=$path.IndexOf('\'); if($split -lt 1){throw 'Invalid registry path'}
 $hiveName=$path.Substring(0,$split);$sub=$path.Substring($split+1)
 $hive=switch($hiveName){'HKEY_LOCAL_MACHINE'{[Microsoft.Win32.Registry]::LocalMachine};'HKEY_CURRENT_USER'{[Microsoft.Win32.Registry]::CurrentUser};default{throw 'Unsupported registry hive'}}
 $key=$hive.OpenSubKey($sub,$true)
 if(-not $key){
  if($defenderProviderError){throw "Defender provider removal failed: $defenderProviderError; registry key write access denied: $path"}
  throw "Cannot open registry key for writing: $path"
 }
 try {
  $value=$key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  if(-not (Test-UniOwnedRegistryValue $ProviderPath $ValueName $value)){throw "Shared registry value preserved: $path :: $ValueName"}
  if($key.GetValueNames() -notcontains $ValueName){return}
  if($path -match '^HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\AppListBackup\\ListOfEventDrivenBackedUpApps_[0-9]+$'){
   Remove-UniAppListBackupValue -Key $key -ValueName $ValueName -Value $value
   # A target-only record lives in its own AppListBackup subkey.  Once its
   # value is gone, remove that now-empty exact record container as well;
   # never recurse into or delete the shared AppListBackup parent.
   if($key.GetValueNames().Count -eq 0 -and $key.GetSubKeyNames().Count -eq 0){
    $last=$sub.LastIndexOf('\')
    if($last -gt 0){
     $parentSub=$sub.Substring(0,$last);$childName=$sub.Substring($last+1)
     $parentKey=$hive.OpenSubKey($parentSub,$true)
     if($parentKey){try{$parentKey.DeleteSubKey($childName,$true)}finally{$parentKey.Close()}}
     if($hive.OpenSubKey($sub,$false)){throw 'Empty AppListBackup record key remains'}
    }
   }
   return
  }
  $key.DeleteValue($ValueName,$true)
  if($key.GetValueNames() -contains $ValueName){throw 'Registry value still exists'}
 } finally {$key.Close()}
}

function Test-UniAppReference {
 param([string]$Path)
 if($Path -match '^\\Device\\HarddiskVolume[0-9]+\\backup\\windowsapps\\installed\\(?<app>[a-z0-9]+)\\Package\\[0-9]+(?:\.[0-9]+)+\\app\\(?<exe>[a-z0-9]+)\.exe$'){
  return ($matches.app -ieq $matches.exe -and @($script:UniRequestedIdentities) -contains (Get-UniIdentity $matches.app))
 }
 if(Test-UniTargetExecutable $Path){return $true}
 # Historical usage stores can keep an executable path without a drive
 # prefix (for example Search\JumplistData value names). Treat it as an app
 # reference only when the executable leaf and a product-named directory both
 # agree. This remains reference-only and never grants filesystem authority.
 $scope=@(Get-UniRequestedScopeIdentities)
 if($Path -match '(?i)\.exe$'){
     $leafIdentity=Get-UniIdentity ([IO.Path]::GetFileNameWithoutExtension($Path))
     $directoryText=[IO.Path]::GetDirectoryName([string]$Path)
     foreach($identity in $scope){
         $idCompact=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant()
         if(-not $idCompact -or $leafIdentity -ne $idCompact){continue}
         foreach($segment in @(([string]$directoryText -split '[\\/]' | Where-Object {$_}))){
             $segmentIdentity=Get-UniIdentity $segment
             if($segmentIdentity.StartsWith($idCompact, [StringComparison]::OrdinalIgnoreCase)){return $true}
         }
     }
 }
 if($Path -notmatch '^[A-Za-z]:\\[^\r\n<>|*?]+\.exe$' -or $Path.Substring(2).Contains(':') -or (Test-Path -LiteralPath $Path)){return $false}
 $identities=@($script:UniRequestedIdentities)
 foreach($identity in $identities){
  if($identity -match '^[a-z0-9]+$' -and $Path -match ('\\'+[regex]::Escape($identity)+'\\Package\\[0-9]+(?:\.[0-9]+)+\\app\\'+[regex]::Escape($identity)+'\.exe$')){return $true}
 }
    if($identities -contains 'todoist' -and $Path -match '^C:\\Program Files\\WindowsApps\\88449BC3\.TodoistPlannerCalendarMSIX_[0-9.]+_x64__71ef4824z52ta\\app\\Todoist\.exe$'){return $true}
    return (($identities -contains (Get-UniIdentity ([IO.Path]::GetFileNameWithoutExtension($Path)))) -and
         ($identities -contains (Get-UniIdentity ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($Path))))))
}
function Invoke-UniCustomStartup {
 param([string]$RegistrySubKey='Software\Hermes\AllStart2')
 $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RegistrySubKey,$true)
 if(-not $key){return}
 try {
  $raw=[string]$key.GetValue('CustomJson')
  if(-not $raw){return}
  $decoded=$raw | ConvertFrom-Json -ErrorAction Stop
  $records=@($decoded)
  $remaining=@($records | Where-Object {-not(Test-UniAppReference ([string]$_.TargetPath))})
  if($remaining.Count -eq $records.Count){return}
  # Reconcile before a surgical update of this shared list.
  if([string]$key.GetValue('CustomJson') -cne $raw){throw 'Custom startup list changed during cleanup; retry required'}
  $updated=ConvertTo-Json -InputObject $remaining -Depth 100 -Compress
  $key.SetValue('CustomJson',$updated,[Microsoft.Win32.RegistryValueKind]::String)
  if([string]$key.GetValue('CustomJson') -cne $updated){throw 'Custom startup update verification failed'}
  Write-Host ('Removed '+($records.Count-$remaining.Count)+' exact app entries from the shared startup list.')
  $script:UniStats.RegValues++
 } finally {$key.Close()}
}
function Invoke-UniInstallerKeys {
 param($ReExact)
 Invoke-UniCustomStartup
 foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths','HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths')){
  if(-not(Test-Path -LiteralPath $root)){continue}
  foreach($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)){
   $target=[string]$key.GetValue('')
   if(-not(Test-UniTargetExecutable $target.Trim('"'))){continue}
   $script:UniOwnedRegistryRoots += $key.Name
   Remove-UniRegistryKey $key.PSPath
   $script:UniStats.RegKeys++
  }
 }
 foreach($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')){
  if(-not(Test-Path -LiteralPath $root)){continue}
  $key=Get-Item -LiteralPath $root -ErrorAction Stop
  try {
   foreach($name in @($key.GetValueNames())){
    $command=Split-UniCommand ([string]$key.GetValue($name))
    if(-not $command -or -not(Test-UniTargetExecutable $command.File)){continue}
    Remove-UniRegistryValue $root $name
    Remove-UniStartupApproval $root $name $command.File
    $script:UniStats.RegValues++
   }
  } finally {$key.Close()}
 }
}

# ---------------------------------------------------------------------------
# 6. deep registry sweep (Software hives + HKCR / COM / TypeLib)
# ---------------------------------------------------------------------------
function Invoke-UniRegistrySweep {
    param($ReExact, $ReLoose,[string]$OrphanPat)
    $denyPrefixes = @('HKLM\SOFTWARE\Microsoft', 'HKLM\SOFTWARE\WOW6432Node\Microsoft', 'HKCU\Software\Microsoft')
    $task = $null
    Update-UniLine ("[{0}] initializing registry scanner ..." -f (Get-UniElapsed))
    foreach($ownedKey in @($script:UniOwnedRegistryRoots | Sort-Object Length)){
        $provider='Registry::'+$ownedKey
        if(-not(Test-UniOwnedRegistry $provider)){continue}
        if(Test-Path -LiteralPath $provider -ErrorAction Stop){
            Write-Host ('Removing owned registry subtree: '+$ownedKey)
            Remove-UniRegistryKey $provider
            $script:UniStats.RegKeys++
        }
    }
    Ensure-UniRegCollect
    if ($script:UniRegOk) {
        try {
            [UniRegCollectV8]::ResetCounters()
            $task = [UniRegCollectV8]::CollectAsync($ReExact.ToString(), $ReLoose.ToString(), $denyPrefixes, $script:UniRegistryWorkers)
        } catch { $task = $null }
    }
    if (-not $task) {
        Clear-UniLine
        throw "Registry collector unavailable; cleanup incomplete."
        return
    }
    $scanWait=[Diagnostics.Stopwatch]::StartNew()
    while (-not $task.IsCompleted) {
        if($scanWait.Elapsed.TotalMinutes -ge 15){[UniRegCollectV8]::Cancel();throw 'Registry scan timed out; coverage incomplete.'}
        $sc = 0; $mt = 0
        try { $sc = [UniRegCollectV8]::Scanned; $mt = [UniRegCollectV8]::Matched } catch { }
        Update-UniLine ("[{0}] registry sweep: keys {1:N0} scanned · {2} matched · workers {3} ..." -f (Get-UniElapsed), $sc, $mt, $script:UniRegistryWorkers)
        Start-Sleep -Milliseconds 100
    }
    $items = @()
    try { $items = @($task.Result) } catch { throw }
    if([UniRegCollectV8]::Errors -gt 0){
        $script:UniFailed.Add('Registry scan errors: '+[UniRegCollectV8]::Errors)
        foreach($detail in [UniRegCollectV8]::ErrorDetails){Write-Warning ('Registry scan could not read: '+$detail)}
    }
    if ($items.Count -eq 0) {
        Clear-UniLine
        Write-Host "  registry sweep: nothing matched." -ForegroundColor Green
        return
    }
    $script:UniRegSweepFound = $true
    $i = 0
    foreach ($item in $items) {
        $i++
        if ($item.StartsWith('K:')) {
            $rp = 'Registry::' + $item.Substring(2)
            Update-UniLine ("[{0}] registry sweep [{1}/{2}]: key {3}" -f (Get-UniElapsed), $i, $items.Count, $item.Substring(2))
            if($script:UniOrphanMode){[void](Register-UniOrphanRegistryKey -ProviderPath $rp -Pattern $OrphanPat)}
            if (-not (Test-UniOwnedRegistry $rp)) { $script:UniFailed.Add('Ambiguous registry key: '+$rp); continue }
            Remove-UniRegistryKey -ProviderPath $rp
            $script:UniStats.RegKeys++
            Clear-UniLine
            Write-Host ("  registry key removed: {0}" -f $item.Substring(2)) -ForegroundColor Green
        } else {
            $sep = $item.IndexOf([char]1)
            if ($sep -lt 0) { continue }
            $rp = 'Registry::' + $item.Substring(2, $sep - 2)
            $vn = $item.Substring($sep + 1)
            if($rp.StartsWith('Registry::HKCR\',[StringComparison]::OrdinalIgnoreCase)){
                $relative=$rp.Substring('Registry::HKCR\'.Length)
                $rp=$null
                foreach($hive in @('HKEY_CURRENT_USER','HKEY_LOCAL_MACHINE')){
                    $physical='Registry::'+$hive+'\Software\Classes\'+$relative
                    $probe=Get-Item -LiteralPath $physical -ErrorAction SilentlyContinue
                    if(-not $probe){continue}
                    try {if($probe.GetValueNames() -contains $vn){$rp=$physical;break}} finally {$probe.Close()}
                }
                if(-not $rp){continue}
            }
            $vnShow = if ([string]::IsNullOrEmpty($vn)) { '(default)' } else { $vn }
            if($script:UniOrphanMode){Add-UniProtectedArtifact (('{0} :: {1}' -f $rp,$vnShow)) 'Ambiguous orphan registry value';continue}
            Update-UniLine ("[{0}] registry sweep [{1}/{2}]: value {3} :: {4}" -f (Get-UniElapsed), $i, $items.Count, $item.Substring(2, $sep - 2), $vnShow)
            $valueKey=Get-Item -LiteralPath $rp -ErrorAction SilentlyContinue
            if(-not $valueKey){continue}
            try {$value=$valueKey.GetValue($vn,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)} finally {$valueKey.Close()}
            $ownedSubtree=$null
            if($vn -eq '' -and $rp -match '^Registry::HKEY_(CURRENT_USER|LOCAL_MACHINE)\\Software\\Classes\\CLSID\\\{[a-f0-9-]{36}\}\\LocalServer32$'){
                $command=Split-UniCommand ([string]$value)
                $parent=$rp.Substring(0,$rp.LastIndexOf('\'))
                if($command -and (Test-UniAppReference $command.File) -and -not(Test-Path -LiteralPath ($parent+'\InprocServer32'))){$ownedSubtree=$parent}
            }
            if($vn -eq '' -and $rp -match '^Registry::HKCU\\Software\\Microsoft\\Internet Explorer\\LowRegistry\\Audio\\PolicyConfig\\PropertyStore\\[a-f0-9]+_[0-9]+$' -and [string]$value -match '\|(?<device>\\Device\\HarddiskVolume[0-9]+\\[^|]+\.exe)%b\{[a-f0-9-]{36}\}$'){
                $devicePath=$matches.device
                Ensure-UniSweepCollect
                $audioPath=[UniSweepCollectV8]::ResolveDevicePath($devicePath)
                if((Test-UniAppReference $devicePath) -or ($audioPath -and (Test-UniAppReference $audioPath))){$ownedSubtree=$rp}
            }
            if($ownedSubtree){
                $script:UniOwnedRegistryRoots += ($ownedSubtree -replace '^Registry::','' -replace '^HKCU\\','HKEY_CURRENT_USER\')
                Remove-UniRegistryKey $ownedSubtree
                $script:UniStats.RegKeys++
                Write-Host ('Removed exact app registration: '+$ownedSubtree)
                continue
            }
            if (-not (Test-UniOwnedRegistryValue $rp $vn $value)) {
                if($rp -match '^Registry::HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\IrisService\\Cache\\[0-9]+$' -and $vn -eq 'RawJson'){
                    Write-Host 'Preserved shared Windows recommendation cache (not an installed-app registration).' -ForegroundColor DarkGray
                } else {$script:UniFailed.Add('Shared registry value: '+$rp+' :: '+$vn)}
                continue
            }
            try {
                Remove-UniRegistryValue -ProviderPath $rp -ValueName $vn
                $script:UniStats.RegValues++
                Clear-UniLine
                Write-Host ("  registry value removed: {0} :: {1}" -f $item.Substring(2, $sep - 2), $vnShow) -ForegroundColor DarkGreen
            } catch {
                # A protected Windows value must not abort unrelated exact
                # records later in the same scan.  Keep the item visible in
                # the final incomplete result and continue with the queue.
                $detail = '{0} :: {1}: {2}' -f $rp,$vnShow,$_.Exception.Message
                if($_.Exception.Message -match '(?i)access (?:is )?not allowed|access denied|unauthorized'){
                    Add-UniProtectedArtifact $detail 'Protected registry value'
                } else {
                    $script:UniFailed.Add('Registry value cleanup failed: '+$detail)
                }
                Write-Warning ('Continuing after registry value failure: '+$detail)
                continue
            }
        }
    }
    Clear-UniLine
    Write-Host ("  registry sweep done: {0} keys, {1} values." -f $script:UniStats.RegKeys, $script:UniStats.RegValues) -ForegroundColor Green
}
function Invoke-UniOrphanRegistrySweep {
    param([string]$Pattern)
    if(-not $Pattern){return}
    $rx=New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $roots=@('HKCU:\Software','HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node','HKCU:\Software\Classes')
    $queue=New-Object 'System.Collections.Generic.Queue[object]'
    foreach($root in $roots){if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){$queue.Enqueue([pscustomobject]@{Path=$root;Depth=0})}}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $scanned=0
    Write-Host '  orphan registry scan: bounded product-key search (depth 3).' -ForegroundColor Cyan
    while($queue.Count){
        $node=$queue.Dequeue()
        if(-not $seen.Add([string]$node.Path)){continue}
        try {$children=@(Get-ChildItem -LiteralPath $node.Path -ErrorAction Stop)} catch {
            Add-UniProtectedArtifact ([string]$node.Path) 'Protected orphan-registry scan subtree'
            continue
        }
        foreach($key in $children){
            $scanned++
            if(($scanned % 250) -eq 0){Update-UniLine ("[{0}] orphan registry keys inspected: {1:N0} · depth {2} ..." -f (Get-UniElapsed),$scanned,$node.Depth)}
            $leaf=[string]$key.PSChildName
            $provider=[string]$key.PSPath
            if($rx.IsMatch($leaf) -and (Register-UniOrphanRegistryKey -ProviderPath $provider -Pattern $Pattern)){
                try {
                    Remove-UniRegistryKey -ProviderPath $provider
                    $script:UniStats.RegKeys++
                    Write-Host ('  orphan registry key removed: '+$provider) -ForegroundColor Green
                } catch {
                    if($_.Exception.Message -match '(?i)access (?:is )?denied|unauthorized'){
                        Add-UniProtectedArtifact $provider 'Protected orphan registry key'
                    } else {$script:UniFailed.Add('Orphan registry key cleanup failed: '+$provider+': '+$_.Exception.Message)}
                }
                continue
            }
            if([int]$node.Depth -ge 3){continue}
            if($leaf -match '^(?i)(Microsoft|Windows|Classes|Policies|Wow6432Node)$'){continue}
            $queue.Enqueue([pscustomobject]@{Path=$provider;Depth=([int]$node.Depth+1)})
        }
    }
    Clear-UniLine
    Write-Host ("  orphan registry scan done: {0:N0} product-key candidates inspected." -f $scanned) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 7. environment variables + PATH
# ---------------------------------------------------------------------------
function Invoke-UniEnvVars {
    param($ReExact)
    foreach($scope in @('User','Machine')) {
        $vars=[Environment]::GetEnvironmentVariables($scope)
        foreach($key in @($vars.Keys)) {
            # Never remove a shared variable wholesale because its data mentions an app.
            if ([string]$key -ieq 'Path') { continue }
            if (-not (Test-UniOwnedPath ([string]$vars[$key]))) { continue }
            if ([string]$key -match '^(SystemRoot|windir|ComSpec|TEMP|TMP|USERPROFILE|APPDATA|LOCALAPPDATA|ProgramData|ProgramFiles|PSModulePath|PATHEXT)$') { continue }
            [Environment]::SetEnvironmentVariable($key,$null,$scope)
            $script:UniStats.EnvVars++
        }
        $old=[Environment]::GetEnvironmentVariable('Path',$scope)
        if ($null -eq $old) { continue }
        $parts=@($old -split ';')
        $keep=@($parts | Where-Object { -not (Test-UniOwnedPath $_) })
        if ($keep.Count -ne $parts.Count) {
            [Environment]::SetEnvironmentVariable('Path',($keep -join ';'),$scope)
            $script:UniStats.EnvVars++
        }
    }
    # Preserve machine entries, process-only entries, ordering and empty segments.
    $env:Path=(@($env:Path -split ';' | Where-Object { -not (Test-UniOwnedPath $_) }) -join ';')
}

# ---------------------------------------------------------------------------
# 8. shortcuts / pins (Start Menu, Desktop, Taskbar, Recent)
# ---------------------------------------------------------------------------
function Test-UniShortcutTarget {
    param([string]$ShortcutPath,[string]$TargetPath)
    if(-not $TargetPath){return $false}
    if(Test-UniTargetExecutable $TargetPath){return $true}
    $target=[Environment]::ExpandEnvironmentVariables([string]$TargetPath).Trim().Trim('"')
    if($ShortcutPath -notmatch '\.(?:lnk|url|appref-ms)$' -or $target -notmatch '^[A-Za-z]:\\[^\r\n<>|*?]+\.exe$' -or $target.Substring(2).Contains(':')){return $false}
    $targetLeaf=[IO.Path]::GetFileName($target)
    if($targetLeaf -notmatch '^(?:unins\d*|uninstall|setup|remove)\.exe$'){return $false}
    $shortcutCompact=((Get-UniIdentity ([IO.Path]::GetFileNameWithoutExtension($ShortcutPath))) -replace '[^a-z0-9]','').ToLowerInvariant()
    $targetCompact=(($target -replace '[^A-Za-z0-9]','').ToLowerInvariant())
    $scope=@($script:UniRequestedIdentities)
    if($script:UniDriverBoosterRequested){$scope += 'driverbooster'}
    if($script:UniIObitRequested){$scope += 'iobit'}
    foreach($identity in @($scope | Select-Object -Unique)){
        $idCompact=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant()
        if($idCompact.Length -ge 5 -and $shortcutCompact.Contains($idCompact) -and $targetCompact.Contains($idCompact)){return $true}
    }
    return $false
}
function Invoke-UniShortcuts {
    param($ReLoose)
    $dirs = @()
    foreach ($d in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        ([Environment]::GetFolderPath('CommonDesktopDirectory')),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent')
    )) {
        if ($d -and (Test-Path -LiteralPath $d -PathType Container)) { $dirs += $d }
    }
    $dirs += @($script:UniExtraShortcutDirs | Where-Object {Test-Path -LiteralPath $_ -PathType Container})
    $dirs=@($dirs | Select-Object -Unique)
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { }
    foreach ($d in $dirs) {
        $files = @()
        try {
            $files = @(Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(lnk|url|appref-ms)$' })
        } catch { }
        foreach ($f in $files) {
            $hit = $false
            if (-not $hit -and $shell) {
                try {
                    $sc = $shell.CreateShortcut($f.FullName)
                    if ($sc.TargetPath -and (Test-UniShortcutTarget $f.FullName ([string]$sc.TargetPath))) { $hit = $true }
                } catch { }
            }
            if ($hit) {
                Update-UniLine ("[{0}] shortcuts: {1}" -f (Get-UniElapsed), $f.FullName)
                [void]$script:UniOwnedFiles.Add($f.FullName)
                if (Remove-UniTarget -Path $f.FullName) {
                    $script:UniStats.Shortcuts++
                    Clear-UniLine
                    Write-Host ("  shortcut removed: {0}" -f $f.FullName) -ForegroundColor Green
                    $parent=$f.Directory.FullName
                    if($parent -ine $d -and (Test-UniSafeRoot $parent) -and -not [IO.Directory]::EnumerateFileSystemEntries($parent).GetEnumerator().MoveNext()){
                        [IO.Directory]::Delete($parent,$false)
                    }
                }
            }
        }
    }
    Clear-UniLine
    Write-Host ("  shortcuts: {0} removed." -f $script:UniStats.Shortcuts) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 9. MRU / recent entries
# ---------------------------------------------------------------------------
function Invoke-UniMru {
 param($ReExact)
 # MRU lists are shared Explorer data, not application-owned registrations.
 # The read-only registry sweep reports references without deleting shared lists.
 Write-Host 'Shared Explorer history preserved; matching references are reported by the registry scan.'
}

# ---------------------------------------------------------------------------
# 10. filesystem obliteration (parallel scan + live counters + per-item log)
# ---------------------------------------------------------------------------
function Invoke-UniFileSweep {
    param([string]$ExactPat, [string]$LoosePat, [string[]]$ExplicitPaths, [switch]$SkipDriveSweep,[string]$OrphanPat)
    Invoke-UniKillProcesses
    $scanExact=$ExactPat
    $scanLoose=$LoosePat
    if($script:UniOrphanMode -and $OrphanPat){$scanExact=$OrphanPat;$scanLoose=$OrphanPat}
    # Remove proven app storage before a full-drive discovery pass. This avoids
    # walking thousands of files that are already conclusively owned by the app.
    foreach($root in @($script:UniOwnedRoots | Sort-Object @{Expression={if($_ -match '\\Packages\\.*\\LocalCache\\'){0}else{1}}},Length)){
        if(-not(Test-Path -LiteralPath $root -ErrorAction Stop)){continue}
        $wasDirectory=[IO.Directory]::Exists($root)
        Write-Host ('Cleaning owned root: '+$root)
        if(Remove-UniTarget $root){
            if($wasDirectory){$script:UniStats.Dirs++}else{$script:UniStats.Files++}
        }else{
            if(Test-UniOwnedPath $root){$script:UniFailed.Add($root)}else{Add-UniProtectedArtifact $root}
        }
    }
    if($script:UniIObitRequested){
        foreach($file in @('C:\Windows\SysWOW64\version\_IObitDel.dll',($env:USERPROFILE+'\Documents\WindowsPowerShell\version\_IObitDel.dll'))){
            if(Test-Path -LiteralPath $file -ErrorAction Stop){
                if(Remove-UniTarget $file){$script:UniStats.Files++}
                elseif(Test-UniOwnedPath $file){$script:UniFailed.Add($file)}
                else{Add-UniProtectedArtifact $file}
            }
        }
    }
    # Explicit paths that have not already been removed above.
    foreach ($p in $ExplicitPaths) {
        Update-UniLine ("[{0}] explicit target: {1}" -f (Get-UniElapsed), $p)
        if (-not (Test-Path -LiteralPath $p -ErrorAction Stop)) { continue }
        if(-not(Test-UniOwnedPath $p)){
            Add-UniProtectedArtifact $p
            Clear-UniLine
            Write-Warning ("Preserved without exclusive ownership evidence: {0}" -f $p)
            continue
        }
        $explicitIsDirectory=[IO.Directory]::Exists($p)
        if (Remove-UniTarget -Path $p) {
            if($explicitIsDirectory){$script:UniStats.Dirs++}else{$script:UniStats.Files++}
            Clear-UniLine
            Write-Host ("  deleted: {0}" -f $p) -ForegroundColor Green
        } else {
            if(Test-UniOwnedPath $p){[void]$script:UniFailed.Add($p)}else{Add-UniProtectedArtifact $p}
            Clear-UniLine
            Write-Warning ("Preserved without exclusive ownership evidence: {0}" -f $p)
        }
    }
    if($SkipDriveSweep){
        Clear-UniLine
        Write-Host '  explicit path mode: drive-wide discovery skipped; only verified owned roots and explicit C: paths were changed.' -ForegroundColor Cyan
        return
    }

    $sd = [IO.Path]::GetPathRoot([Environment]::SystemDirectory)
    $prog86 = $null
    try { $prog86 = ${env:ProgramFiles(x86)} } catch { }
    $rootDenyNames = @('Windows', 'Users', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Temp', 'System Volume Information', 'Recovery', 'Windows.old', '$Recycle.Bin', 'Config.Msi', 'MSOCache', 'PerfLogs', '$WinREAgent', 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'DumpStack.log.tmp', 'bootmgr', 'BOOTSECT.BAK')
    
    # Discover package manager explicit paths for the target tokens
    $explicitPkgPaths = @()
    foreach ($tok in $pat.Tokens) {
        # Scoop
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'scoop') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:USERPROFILE 'scoop')
        }
        if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Scoop') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:LOCALAPPDATA 'Scoop')
        }
        # uv
        if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'uv') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:APPDATA 'uv')
        }
        # Chocolatey
        if (Test-Path -LiteralPath 'C:\ProgramData\chocolatey' -PathType Container) {
            $explicitPkgPaths += 'C:\ProgramData\chocolatey'
        }
        # Winget (DesktopAppInstaller packages cache)
        if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:LOCALAPPDATA 'Packages')
        }
        # npm/pnpm/yarn global
        if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'npm') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:APPDATA 'npm')
        }
        if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'pnpm') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:LOCALAPPDATA 'pnpm')
        }
        # pipx
        if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'pipx') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:APPDATA 'pipx')
        }
        # Cargo/Rust
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.cargo') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:USERPROFILE '.cargo')
        }
        # Go
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'go') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:USERPROFILE 'go')
        }
        # Bun
        if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'bun') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:APPDATA 'bun')
        }
        # Deno
        if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'deno') -PathType Container) {
            $explicitPkgPaths += (Join-Path $env:APPDATA 'deno')
        }
    }
    $explicitPkgPaths = @($explicitPkgPaths | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Container })

    $script:UniRootSpecs = @(
        @{ Path = $sd; Mode = 'A'; RootDeny = $rootDenyNames },
        @{ Path = (Join-Path $sd 'Temp'); Mode = 'T'; RootDeny = @() },
        @{ Path = (Join-Path $sd 'Windows\Temp'); Mode = 'T'; RootDeny = @() },
        @{ Path = (Join-Path $sd 'Windows\Tasks'); Mode = 'T'; RootDeny = @() },
        @{ Path = (Join-Path $sd 'Windows\System32\Tasks'); Mode = 'T'; RootDeny = @() },
        @{ Path = (Join-Path $sd 'Windows\Prefetch'); Mode = 'T'; RootDeny = @() },
        @{ Path = $env:USERPROFILE; Mode = 'B'; RootDeny = @() },
        @{ Path = $env:ProgramData; Mode = 'A'; RootDeny = @() },
        @{ Path = $env:ProgramFiles; Mode = 'A'; RootDeny = @() },
        @{ Path = $prog86; Mode = 'A'; RootDeny = @() },
        @{ Path = (Join-Path $sd 'Users\Public'); Mode = 'B'; RootDeny = @() },
        # AppData\Local\Packages (Windows App Installer / Winget cache) - Nuclear mode for exact matches
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Packages'); Mode = 'N'; RootDeny = @() },
        # AppData\Roaming (uv, pipx, npm, etc.) - Nuclear mode
        @{ Path = $env:APPDATA; Mode = 'N'; RootDeny = @() },
        # Scoop locations - Nuclear mode
        @{ Path = (Join-Path $env:USERPROFILE 'scoop'); Mode = 'N'; RootDeny = @() },
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Scoop'); Mode = 'N'; RootDeny = @() }
    )
    # Add discovered package manager paths as Nuclear mode roots
    foreach ($p in $explicitPkgPaths) {
        $script:UniRootSpecs += @{ Path = $p; Mode = 'N'; RootDeny = @() }
    }
    $script:UniRootSpecs = @($script:UniRootSpecs | Where-Object {
        $_.Path -and $_.Path.StartsWith($sd, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $_.Path -PathType Container)
    })
    $uniqueRoots=@{}
    foreach($spec in $script:UniRootSpecs){
        $key=[IO.Path]::GetFullPath($spec.Path).TrimEnd('\')
        if(-not $uniqueRoots.ContainsKey($key) -or $spec.Mode -eq 'N'){$uniqueRoots[$key]=$spec}
    }
    $script:UniRootSpecs=@($uniqueRoots.Values | Sort-Object {$_.Path.Length})
    $script:UniDenyPaths = @()
    if ($env:ProgramFiles) {
        $script:UniDenyPaths += (Join-Path $env:ProgramFiles 'WindowsApps')
        $script:UniDenyPaths += (Join-Path $env:ProgramFiles 'Microsoft Shared')
        $script:UniDenyPaths += (Join-Path $env:ProgramFiles 'Common Files\Microsoft Shared')
        $script:UniDenyPaths += (Join-Path $env:ProgramFiles 'Windows NT')
        $script:UniDenyPaths += (Join-Path $env:ProgramFiles 'Internet Explorer')
    }
    if ($prog86) {
        $script:UniDenyPaths += (Join-Path $prog86 'Microsoft Shared')
        $script:UniDenyPaths += (Join-Path $prog86 'Windows NT')
        $script:UniDenyPaths += (Join-Path $prog86 'Internet Explorer')
    }
    if ($env:ProgramData) { $script:UniDenyPaths += (Join-Path $env:ProgramData 'Package Cache') }
    # GMenu's encrypted command store, fallback sources, and repair evidence
    # are durable recovery state during unrelated cleanups. A direct `uni gmenu`
    # request is explicit ownership authorization for these exact-name artifacts.
    if(-not $script:UniGMenuCleanupAuthorized){
        $script:UniDenyPaths += (Join-Path $env:USERPROFILE '.gmenu')
        $script:UniDenyPaths += (Join-Path $env:USERPROFILE 'bin')
        $script:UniDenyPaths += (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\GMenuRepair')
        $script:UniDenyPaths += (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\GMenuFallback')
    }
     $script:UniDenyPaths = @($script:UniDenyPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })

    $protected = @()
    if ($PSCommandPath) { $protected += [System.IO.Path]::GetFullPath($PSCommandPath) }
    $mod = Get-Module -Name 'CodexProfileFunctions' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($mod -and $mod.ModuleBase) {
        $protected += (Join-Path $mod.ModuleBase ($mod.Name + '.psm1'))
        $protected += (Join-Path $mod.ModuleBase ($mod.Name + '.psd1'))
    }
    if(-not $script:UniGMenuCleanupAuthorized){
        $protected += (Join-Path $env:USERPROFILE '.gmenu')
        $protected += (Join-Path $env:USERPROFILE 'bin\gmenu.cmd')
        $protected += (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\GMenuRepair')
        $protected += (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\GMenuFallback')
    }
     $script:UniProtected = $protected

    # launch root scans in bounded parallel waves so the big roots overlap
    # instead of adding up - combined live counters while they run
    Ensure-UniSweepCollect
    if (-not $script:UniCollectOk) {
        Clear-UniLine
        throw "Filesystem collector unavailable; cleanup incomplete."
        return
    }
    [UniSweepCollectV8]::ResetCounters()
    $rootQueue = @($script:UniRootSpecs)
    $running = @()
    $completed = @()
    $maxConcurrent = $script:UniMaxConcurrentRoots
    $scanWait=[Diagnostics.Stopwatch]::StartNew()
    while ($rootQueue.Count -gt 0 -or $running.Count -gt 0) {
        if($scanWait.Elapsed.TotalMinutes -ge 30){[UniSweepCollectV8]::Cancel();throw 'Filesystem scan timed out; coverage incomplete.'}
        while ($rootQueue.Count -gt 0 -and $running.Count -lt $maxConcurrent) {
            $rs = $rootQueue[0]
            $rootQueue = @($rootQueue | Select-Object -Skip 1)
            try {
                # Explicit child roots are scanned once with their own mode.
                $scanDeny=@($script:UniDenyPaths)
                foreach($child in $script:UniRootSpecs){if($child.Path -ine $rs.Path -and (Test-UniWithin $child.Path $rs.Path)){$scanDeny += $child.Path}}
                $task = [UniSweepCollectV8]::CollectAsync($rs.Path, $rs.Mode, $scanExact, $scanLoose, $scanDeny, $script:UniProtected, @($rs.RootDeny), $script:UniFsWorkersPerRoot)
                if ($task) { $running += @{ Path = $rs.Path; Mode = $rs.Mode; Task = $task } }
            } catch { }
        }
        if ($running.Count -eq 0) { break }
        $sc = 0; $mt = 0
        try { $sc = [UniSweepCollectV8]::Scanned; $mt = [UniSweepCollectV8]::Matched } catch { }
        Update-UniLine ("[{0}] scanning roots: entries {1:N0} · matched {2} · roots {3} · workers {4} ..." -f (Get-UniElapsed), $sc, $mt, $running.Count, ($running.Count * $script:UniFsWorkersPerRoot))
        Start-Sleep -Milliseconds 100
        $still = @()
        foreach ($r in $running) {
            if ($r.Task.IsCompleted) { $completed += $r } else { $still += $r }
        }
        $running = $still
    }
    Clear-UniLine
    Write-Host ("  scanned {0} root(s): {1}" -f $completed.Count, (@($completed | ForEach-Object { $_.Path }) -join ', ')) -ForegroundColor Cyan
    Invoke-UniKillProcesses
    foreach ($t in $completed) {
        $cands = @()
        try { $cands = @($t.Task.Result) } catch { throw }
        if ($cands.Count -eq 0) {
            Clear-UniLine
            Write-Host ("  nothing matched under {0}." -f $t.Path) -ForegroundColor DarkGray
            continue
        }
        $i = 0
        foreach ($c in $cands) {
            $i++
            if($script:UniOrphanMode -and $OrphanPat -and (Test-UniOrphanLinkCandidate -Path $c -Pattern $OrphanPat)){
                $script:UniOrphanMatches=[int]$script:UniOrphanMatches+1
                if(Remove-UniOrphanLink -Path $c -Pattern $OrphanPat){$script:UniStats.Dirs++}
                continue
            }
            if($script:UniOrphanMode){[void](Register-UniOrphanCandidate -Path $c -Pattern $OrphanPat)}
            if(-not(Test-UniOwnedPath $c)){
                Clear-UniLine
                if(Test-UniPreservedReference $c){
                    Write-Host ('Preserved requested integration/source reference: '+$c) -ForegroundColor DarkGray
                }else{
                    Add-UniProtectedArtifact $c
                    Write-Warning ('Preserved without exclusive ownership evidence: '+$c)
                }
                continue
            }
            $wasDir = $false
            try { $wasDir = [System.IO.Directory]::Exists($c) } catch { }
            Update-UniLine ("[{0}] deleting [{1}/{2}] {3} ..." -f (Get-UniElapsed), $i, $cands.Count, $c)
            if (Remove-UniTarget -Path $c) {
                if ($wasDir) { $script:UniStats.Dirs++ } else { $script:UniStats.Files++ }
                Clear-UniLine
                Write-Host ("  deleted: {0}" -f $c) -ForegroundColor Green
            } else {
                if(Test-UniOwnedPath $c){[void]$script:UniFailed.Add($c)}else{Add-UniProtectedArtifact $c}
                Clear-UniLine
                if(Test-UniOwnedPath $c){Write-Host ("  BLOCKED: {0}" -f $c) -ForegroundColor Red}else{Write-Warning ('Preserved without exclusive ownership evidence: '+$c)}
            }
        }
    }
    Clear-UniLine
    Write-Host ("  filesystem sweep done: {0} file(s), {1} dir(s) deleted." -f $script:UniStats.Files, $script:UniStats.Dirs) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 11. final round: re-kill, release handles, retry blocked items + re-scan nuclear roots
# ---------------------------------------------------------------------------
function Invoke-UniFinal {
    param($ReExact,$ReLoose,[string]$ExactPat,[string]$LoosePat,$RootSpecs,$DenyPaths,$Protected)
    # Reconcile target processes and exact app registrations recreated during the
    # scan. Only the same verified target identity is eligible for termination.
    Invoke-UniEarlyStop
    foreach($ownedKey in @($script:UniOwnedRegistryRoots)){
        $provider='Registry::'+$ownedKey
        if((Test-UniOwnedRegistry $provider) -and (Test-Path -LiteralPath $provider -ErrorAction Stop)){
            Remove-UniRegistryKey $provider
        }
    }
    # Retrying deletion must never kill lock holders, restart Explorer, or elevate
    # and repeat earlier external mutations. Report blocked items instead.
    foreach($path in @($script:UniOwnedRoots)) {
        if (Test-Path -LiteralPath $path -ErrorAction Stop) {
            if (-not (Remove-UniTarget $path)) {
                if(Test-UniOwnedPath $path){
                    if (-not $script:UniFailed.Contains($path)) { $script:UniFailed.Add($path) }
                }else{Add-UniProtectedArtifact $path}
            }
        }
    }
    foreach($program in @($script:UniSelectedPrograms)) {
        $registration=[string]$program.RegistryPath
        if(-not [string]::IsNullOrWhiteSpace($registration) -and (Test-Path -LiteralPath $registration -ErrorAction Stop)) { $script:UniFailed.Add('Registration remains: '+$program.Name) }
    }
    # Reconcile exact artifacts that can be recreated while the first sweep
    # and orphan-registry pass are still running, including links the scanner
    # deliberately does not traverse.
    Remove-UniGMenuKnownArtifacts
}

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
function Write-UniSummary {
    Clear-UniLine
    # A creator can race the last delete after the scanner has already passed.
    # Validate every path Uni actually authorized after all final mutations so
    # a recreated target is never presented as a clean or merely unverified run.
    $remainingOwned=New-Object 'System.Collections.Generic.List[string]'
    foreach($path in @($script:UniOwnedRoots)){
        if(-not [string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue -PathType Any)){[void]$remainingOwned.Add([string]$path)}
    }
    foreach($path in @($script:UniOwnedFiles)){
        if(-not [string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath ([string]$path) -ErrorAction SilentlyContinue -PathType Leaf)){[void]$remainingOwned.Add([string]$path)}
    }
    foreach($path in @($remainingOwned | Select-Object -Unique)){
        $script:UniFailed.Add('Target artifact persisted or was recreated after final cleanup: '+$path)
    }
    foreach($path in @(Get-UniGMenuCleanupPaths)){
        if(Test-Path -LiteralPath $path -ErrorAction SilentlyContinue -PathType Any){
            $script:UniFailed.Add('GMenu artifact persisted or was recreated after final cleanup: '+$path)
        }
    }
    if(('UniSweepCollectV8' -as [type]) -and [UniSweepCollectV8]::Errors -gt 0){
        $script:UniFailed.Add('Filesystem scan errors: '+[UniSweepCollectV8]::Errors)
        foreach($detail in [UniSweepCollectV8]::ErrorDetails){Write-Warning ('Filesystem scan could not read: '+$detail)}
    }
    Write-Host ("Run finished in {0}. Verified file removals: {1}; directory removals: {2}." -f (Get-UniElapsed),$script:UniStats.Files,$script:UniStats.Dirs)
    if($script:UniOrphanMode){Write-Host ("Unregistered residual sweep matched {0} exact-name C: candidate(s)." -f [int]$script:UniOrphanMatches)}
    foreach($path in @($script:UniFailed | Select-Object -Unique)) { Write-Warning "Unremoved or unverified: $path" }
    foreach($path in @($script:UniProtectedArtifacts | Select-Object -Unique)) { Write-Warning "Preserved protected/ambiguous artifact: $path" }
    Write-Host 'Scan coverage excludes inaccessible and protected locations. Shared or ambiguous artifacts are preserved. Zero leftovers is not certified.'
    $global:LASTEXITCODE=if($script:UniFailed.Count -or $script:UniProtectedArtifacts.Count){2}else{0}
}

# Ownership boundary, September 2026. Name matches discover candidates; they do
# not authorize terminating a process or recursively deleting a directory.
function Get-UniIdentity {
    param([string]$Name)
    return ($Name.Trim().ToLowerInvariant() -replace '[ ._-]','')
}
function Test-UniGMenuTargeted {
    param([string[]]$Identities)
    return (@($Identities | ForEach-Object { Get-UniIdentity $_ }) -contains 'gmenu')
}
function Get-UniGMenuCleanupPaths {
    if(-not $script:UniGMenuCleanupAuthorized){return @()}
    $documents=[Environment]::GetFolderPath('MyDocuments')
    $paths=@(
        (Join-Path $env:USERPROFILE '.gmenu'),
        (Join-Path $env:USERPROFILE 'bin\gmenu.cmd'),
        (Join-Path $env:USERPROFILE 'bin\gmenu.ps1'),
        (Join-Path $documents 'WindowsPowerShell\GMenuRepair'),
        (Join-Path $documents 'WindowsPowerShell\GMenuFallback'),
        (Join-Path $documents 'WindowsPowerShell\Modules\GMenu'),
        (Join-Path $documents 'PowerShell\Modules\GMenu')
    )
    return @($paths | ForEach-Object {try{[IO.Path]::GetFullPath($_).TrimEnd('\')}catch{}} | Where-Object {$_} | Select-Object -Unique)
}
function Remove-UniGMenuKnownArtifacts {
    if(-not $script:UniGMenuCleanupAuthorized){return}
    foreach($path in @(Get-UniGMenuCleanupPaths)){
        $item=Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if($null -eq $item){continue}
        $full=[IO.Path]::GetFullPath($path).TrimEnd('\')
        $wasDir=[bool]$item.PSIsContainer
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
            # This is an explicitly named GMenu link. Unlink the link itself;
            # never recurse through its target or mutate the target tree.
            try{
                $parent=[IO.Path]::GetDirectoryName($full)
                if(-not(Test-UniSafeRoot $parent)){throw 'Unsafe GMenu link parent'}
                Update-UniLine ("[{0}] unlinking direct GMenu reparse point: {1} ..." -f (Get-UniElapsed),$full)
                if($wasDir){[IO.Directory]::Delete($full,$false)}else{[IO.File]::Delete($full)}
                if(Test-Path -LiteralPath $full -ErrorAction SilentlyContinue){throw 'GMenu reparse point remains after unlink'}
                if($wasDir){$script:UniStats.Dirs++}else{$script:UniStats.Files++}
                Clear-UniLine
                Write-Host ('  unlinked: '+$full) -ForegroundColor Green
            }catch{
                $message=('Unremoved GMenu reparse point: {0}: {1}' -f $full,$_.Exception.Message)
                if($script:UniFailed -and -not $script:UniFailed.Contains($message)){[void]$script:UniFailed.Add($message)}
                Write-Warning $message
            }
            continue
        }
        # These are fixed, exact GMenu-owned paths, so authorize only the
        # literal path for this direct GMenu request; no name-wide expansion.
        if($wasDir){
            if(@($script:UniOwnedRoots) -notcontains $full){$script:UniOwnedRoots += $full}
        }else{
            if(-not $script:UniOwnedFiles){$script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)}
            [void]$script:UniOwnedFiles.Add($full)
        }
        if(Remove-UniTarget -Path $full){
            if($wasDir){$script:UniStats.Dirs++}else{$script:UniStats.Files++}
            Clear-UniLine
            Write-Host ('  deleted: '+$full) -ForegroundColor Green
        }
    }
}
function Remove-UniStartupApproval {
 param([string]$RunKey,[string]$ValueName,[string]$Executable)
 if(-not(Test-UniTargetExecutable $Executable)){throw 'Startup approval target lacks ownership'}
 if($RunKey -notmatch '^(HKCU|HKLM):\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Run$'){return}
 $hive=if($matches[1] -eq 'HKCU'){[Microsoft.Win32.Registry]::CurrentUser}else{[Microsoft.Win32.Registry]::LocalMachine}
 $branch=if($matches[2]){'Run32'}else{'Run'}
 $key=$hive.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\'+$branch,$true)
 if(-not $key){return}
 try {
  if($key.GetValueNames() -contains $ValueName){$key.DeleteValue($ValueName,$true);$script:UniStats.RegValues++;Write-Host ('Removed startup approval for verified target: '+$ValueName)}
 } finally {$key.Close()}
}
function Test-UniProductName {
    param([string]$DisplayName,[string[]]$Identities)
    if($Identities -contains (Get-UniIdentity $DisplayName)){return $true}
    # A numeric trailing release is distinct from arbitrary product suffixes.
    $base=$DisplayName -replace '\s+(?:v(?:ersion)?\s*)?\d+(?:\.\d+)*(?:\s*\(x(?:64|86)\))?$',''
    return ($base -ne $DisplayName -and $Identities -contains (Get-UniIdentity $base))
}
function Get-UniPortableLayout {
    param([string]$Root,[string[]]$Identities)
    # Inspect a portable launcher as data; never execute it during discovery.
    try {
        $Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
        if($Root -notmatch '^[A-Za-z]:\\' -or $Root.Length -lt 5){return}
        $leaf=[IO.Path]::GetFileName($Root)
        $rootMatches=$false
        foreach($identity in $Identities){if((Get-UniIdentity $leaf) -eq $identity -or $leaf -match ('^'+[regex]::Escape($identity)+'[-_. ]')){$rootMatches=$true;break}}
        if(-not $rootMatches){return}
        foreach($launcher in @(Get-ChildItem -LiteralPath $Root -File -Filter 'Launch-*.ps1' -ErrorAction Stop)){
            $name=$launcher.BaseName.Substring(7)
            if(-not(Test-UniProductName $name $Identities)){continue}
            $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($launcher.FullName,[ref]$t,[ref]$e)
            if($e.Count){continue}
            foreach($assignment in $ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
                if($assignment.Left.Extent.Text -ine '$executable'){continue}
                $rhs=$assignment.Right.Extent.Text
                if($rhs -notmatch '^Join-Path\s+\$PSScriptRoot\s+''(?<rel>[^'']+\.exe)''$'){continue}
                $exe=[IO.Path]::GetFullPath((Join-Path $Root $matches.rel))
                if(-not(Test-UniWithin $exe $Root) -or -not[IO.File]::Exists($exe)){continue}
                $linked=$false
                foreach($check in @($exe,$launcher.FullName)){
                    $current=$check
                    while($current.Length -gt 3){
                        if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){$linked=$true;break}
                        $current=[IO.Path]::GetDirectoryName($current)
                    }
                }
                if($linked){continue}
                $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
                if(-not(Test-UniProductName $info.ProductName $Identities) -or -not(Test-UniProductName ([IO.Path]::GetFileNameWithoutExtension($exe)) $Identities)){continue}
                return [pscustomobject]@{Root=$Root;Executable=$exe;Launcher=$launcher.FullName;Product=$info.ProductName}
            }
        }
    } catch {return}
}
function Test-UniVerifiedExecutable {
    param([string]$Path,[string[]]$Identities)
    try {
        if(-not $Identities.Count -or $Path -notmatch '^[A-Za-z]:\\.*\.exe$'){return $false}
        $leaf=[IO.Path]::GetFileNameWithoutExtension($Path)
        if(-not(Test-UniProductName $leaf $Identities) -and -not(Test-UniProductName ($leaf -replace '(32|64)$','') $Identities)){return $false}
        $full=[IO.Path]::GetFullPath($Path);$current=$full
        while($current.Length -gt 3){
            if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}
            $current=[IO.Path]::GetDirectoryName($current)
        }
        $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($full)
        return (Test-UniProductName $info.ProductName $Identities)
    } catch {return $false}
}
function Get-UniRequestedScopeIdentities {
    $scope=@($script:UniRequestedIdentities)
    if($scope -contains 'iobit' -or $scope -contains 'driverbooster'){$scope += 'driverbooster'}
    return @($scope | Where-Object {$_} | ForEach-Object {([string]$_).ToLowerInvariant()} | Select-Object -Unique)
}
function Add-UniTaskReferenceRoots {
    param([string]$TaskPath,[object[]]$Actions,[string[]]$Scope,[ref]$Found)
    $actionsArray=@($Actions)
    $ownedTask=$actionsArray.Count -gt 0
    foreach($candidateAction in $actionsArray){if(-not(Test-UniTaskAction $candidateAction $TaskPath)){$ownedTask=$false;break}}
    if($ownedTask){
        $script:UniTaskReferenceFound=$true
        Write-Host ('Verified requested task reference: '+$TaskPath) -ForegroundColor DarkGray
    }
    foreach($action in $actionsArray){
        if($action.Type -ne 0){continue}
        $exe=[Environment]::ExpandEnvironmentVariables([string]$action.Path).Trim('"')
        if($exe -notmatch '^[A-Za-z]:\\[^\r\n<>|*?]+\.exe$' -or $exe.Substring(2).Contains(':')){continue}
        $compact=(($exe -replace '[^A-Za-z0-9]','').ToLowerInvariant())
        $matched=$false
        foreach($identity in $Scope){$id=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant();if($id.Length -ge 5 -and $compact.Contains($id)){$matched=$true;break}}
        if(-not $matched){continue}
        $current=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($exe))
        while($current -and $current.Length -gt 3){
            $leaf=Get-UniIdentity ([IO.Path]::GetFileName($current))
            foreach($identity in $Scope){$id=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant();if($id.Length -ge 5 -and $leaf.StartsWith($id,[StringComparison]::OrdinalIgnoreCase)){$Found.Value += $current;$current=$null;break}}
            if($current){$current=[IO.Path]::GetDirectoryName($current)}
        }
    }
}
function Initialize-UniReferenceExecutionRoots {
    # Read exact requested-app task actions during ownership discovery. A
    # stale portable registration can still tell us which executable tree is
    # related even when its file metadata or uninstall entry is gone. These
    # are reference roots only; Test-UniOwnedPath remains C:-only.
    $scope=@(Get-UniRequestedScopeIdentities)
    if(-not $scope.Count){return}
    if(-not $script:UniExecutionRoots){$script:UniExecutionRoots=@()}
    $found=@()
    $storeEntries=@(Get-UniTaskStoreEntries)
    if($script:UniTaskStoreScanComplete){
        foreach($entry in $storeEntries){Add-UniTaskReferenceRoots -TaskPath $entry.Path -Actions @($entry.Actions) -Scope $scope -Found ([ref]$found)}
    } else {
        $scheduler=$null
        try {
            $scheduler=New-Object -ComObject Schedule.Service -ErrorAction Stop
            $scheduler.Connect()
            $folders=New-Object 'System.Collections.Generic.Queue[object]'
            $folders.Enqueue($scheduler.GetFolder('\'))
            while($folders.Count){
                $folder=$folders.Dequeue()
                foreach($task in $folder.GetTasks(1)){
                    $taskPath=[string]$task.Path
                    $actions=@($task.Definition.Actions)
                    Add-UniTaskReferenceRoots -TaskPath $taskPath -Actions $actions -Scope $scope -Found ([ref]$found)
                }
                foreach($child in $folder.GetFolders(0)){$folders.Enqueue($child)}
            }
        } catch { }
        finally {if($scheduler){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($scheduler)}}
    }
    if($found.Count){$script:UniExecutionRoots=@($script:UniExecutionRoots+$found | Select-Object -Unique)}
}
function Invoke-UniEarlyStop {
    # Process identity is self-contained and must be checked before any COM
    # scheduler traversal. A slow or damaged task store must never delay the
    # first force-close action or make the command look hung.
    $before=[int]$script:UniStats.Processes
    $verified=@()
    $processes=@()
    try {$processes=@(Get-Process -ErrorAction Stop)} catch {
        $script:UniFailed.Add('Process enumeration failed during early force-close: '+$_.Exception.Message)
        Write-Warning 'Unable to enumerate processes for early force-close; continuing ownership discovery.'
    }
    foreach($process in $processes){
        try {if(Test-UniVerifiedExecutable $process.Path $script:UniRequestedIdentities){$verified += $process}} catch {}
    }
    if($verified.Count){Invoke-UniKillProcesses -Candidates $verified}
    else {Write-Host 'No running executable matched the requested product identity.'}
    $script:UniEarlyStopped=[int]$script:UniStats.Processes-$before
}
function Test-UniOrphanScriptCommand {
    param([string]$Command,[string]$Pattern)
    if([string]::IsNullOrWhiteSpace($Command)){return $false}
    $scope=@(Get-UniRequestedScopeIdentities | Where-Object {([string]$_).Length -ge 4})
    if(-not $scope.Count){return $false}
    # Only inspect an actual script path token.  A command such as
    # "pwsh -Command ... 'gmenu' ..." is not evidence that a gmenu target is
    # running and must never be enough to stop an unrelated PowerShell host.
    $scriptToken='(?i)(?:"(?<path>[^"]+\.(?:ps1|psm1|py|pyw|js|mjs|cjs|vbs|cmd|bat))"|(?<path>[^\s"''<>|]+\.(?:ps1|psm1|py|pyw|js|mjs|cjs|vbs|cmd|bat)))'
    foreach($match in [regex]::Matches($Command,$scriptToken)){
        $candidate=[string]$match.Groups['path'].Value
        if([string]::IsNullOrWhiteSpace($candidate)){continue}
        foreach($identity in $scope){
            $compact=(([string]$identity) -replace '[^a-z0-9]','').ToLowerInvariant()
            if($compact.Length -lt 4){continue}
            $charPattern=(([char[]]$compact | ForEach-Object {[regex]::Escape([string]$_)}) -join '[^A-Za-z0-9]*')
            $identityPattern='(?i)(?<![A-Za-z0-9])'+$charPattern+'(?![A-Za-z0-9])'
            # This accepts both gmenu-entrypoint.py and Driver Booster\*.ps1,
            # while rejecting NotGMenuRepair.ps1 and driverboosterhelper.ps1.
            if($candidate -match $identityPattern){return $true}
            # Artifact-shaped suffixes (GMenuRepair, GMenuPublish, ...) are
            # already bounded by the orphan pattern, so allow those names too.
            if(-not [string]::IsNullOrWhiteSpace($Pattern) -and $candidate -match $Pattern){return $true}
        }
    }
    return $false
}
function Invoke-UniOrphanProcessStop {
    param([string]$Pattern)
    if(-not $script:UniOrphanMode -or [string]::IsNullOrWhiteSpace($Pattern)){return}
    $hosts=@('python.exe','pythonw.exe','pwsh.exe','powershell.exe','node.exe','nodejs.exe','wscript.exe','cscript.exe','cmd.exe','dotnet.exe')
    $currentPid=[Diagnostics.Process]::GetCurrentProcess().Id
    $rows=@()
    try {
        # Command-line ownership is needed for script-hosted apps, but the
        # query is bounded so a damaged WMI provider cannot make Uni hang.
        $rows=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,ExecutablePath,CommandLine -OperationTimeoutSec 5 -ErrorAction Stop)
    } catch {
        $message='Orphan process command-line scan unavailable: '+$_.Exception.Message
        $script:UniFailed.Add($message)
        Write-Warning $message
        return
    }
    $stopped=New-Object 'System.Collections.Generic.List[object]'
    $parentMap=@{}
    foreach($row in $rows){
        try {$parentMap[[int]$row.ProcessId]=[int]$row.ParentProcessId} catch {}
    }
    $ownTree=@{ $currentPid = $true }
    $cursor=$currentPid
    for($depth=0;$depth -lt 16 -and $parentMap.ContainsKey($cursor);$depth++){
        $cursor=[int]$parentMap[$cursor]
        if($cursor -le 0 -or $ownTree.ContainsKey($cursor)){break}
        $ownTree[$cursor]=$true
    }
    foreach($row in $rows){
        try {
            $targetPid=[int]$row.ProcessId
            if($targetPid -le 0 -or $ownTree.ContainsKey($targetPid)){continue}
            $exe=[Environment]::ExpandEnvironmentVariables([string]$row.ExecutablePath).Trim().Trim('"')
            $hostName=[IO.Path]::GetFileName($exe).ToLowerInvariant()
            if($hosts -notcontains $hostName){continue}
            $command=[string]$row.CommandLine
            if([string]::IsNullOrWhiteSpace($command)){continue}
            if($command -match '(?i)(?:^|[\\/])uni\.ps1(?:["''\s]|$)'){continue}
            if(-not (Test-UniOrphanScriptCommand -Command $command -Pattern $Pattern)){continue}
            if($script:UniProtectedPids.ContainsKey($targetPid)){continue}
            $live=Get-Process -Id $targetPid -ErrorAction Stop
            $liveHost=[IO.Path]::GetFileName($exe).ToLowerInvariant()
            if($script:UniNeverKill -contains $live.ProcessName.ToLowerInvariant() -and @('powershell.exe','pwsh.exe') -notcontains $liveHost){continue}
            Write-Host ("Stopping unregistered script-hosted target: {0} PID {1}" -f $exe,$targetPid)
            $live.Kill()
            [void]$stopped.Add($live)
            $script:UniStats.Processes++
        } catch {
            if($targetPid -and (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)){
                $script:UniFailed.Add(('Process close failed for orphan script host PID {0}: {1}' -f $targetPid,$_.Exception.Message))
            }
        }
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    foreach($live in $stopped){
        try {
            $remaining=[math]::Max(0,[int]($deadline-[DateTime]::UtcNow).TotalMilliseconds)
            if(-not $live.WaitForExit($remaining)){$script:UniFailed.Add('Orphan script host did not exit within five seconds: '+$live.Id)}
        } catch {}
    }
}
function Test-UniTargetExecutable {
    param([string]$Path)
    $Path=[Environment]::ExpandEnvironmentVariables([string]$Path).Trim().Trim('"')
    if(Test-UniVerifiedExecutable $Path $script:UniRequestedIdentities){return $true}
    if(Test-UniOwnedPath $Path){return $true}
    if($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[*?<>|]' -or $Path.Substring(2).Contains(':')){return $false}
    $full=[IO.Path]::GetFullPath($Path)
    $current=$full
    try {while($current.Length -gt 3){
        if(Test-Path -LiteralPath $current -ErrorAction Stop){if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}}
        $current=[IO.Path]::GetDirectoryName($current)
    }} catch {return $false}
    foreach($root in @($script:UniExecutionRoots)){
        if(Test-UniWithin $full $root){return $true}
    }
    # Startup references must remain identifiable when the portable app is closed.
    $root=[IO.Path]::GetDirectoryName($full);$folder=[IO.Path]::GetFileName($root)
    $kind=Get-UniIdentity $folder
    if($folder -match '^\d+(\.\d+)+$'){$kind=Get-UniIdentity ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($root)))}
    $mainFiles=@()
    if($script:UniCCleanerRequested -and $kind -eq 'ccleaner'){$mainFiles=@('CCleaner64.exe','CCleaner.exe')}
    if($script:UniDriverBoosterRequested -and $kind -eq 'driverbooster'){$mainFiles=@('DriverBooster.exe')}
    foreach($main in $mainFiles){
        $mainPath=Join-Path $root $main
        if(-not [IO.File]::Exists($mainPath)){continue}
        try {
            if((Get-Item -LiteralPath $mainPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($mainPath)
            if(($kind -eq 'ccleaner' -and $version.ProductName -eq 'CCleaner' -and $version.CompanyName -match '^(Gen Digital Inc\.|Piriform(?: Ltd\.?)?)$') -or ($kind -eq 'driverbooster' -and $version.ProductName -eq 'Driver Booster' -and $version.CompanyName -eq 'IObit')){return $true}
        } catch {return $false}
    }
    # A removed portable copy can leave a task, service, or startup reference
    # after its executable metadata is gone. Accept that reference only when
    # the non-C: path has both the exact requested executable identity and an
    # exact matching product directory somewhere above it. This identifies the
    # stale reference for cleanup while Test-UniOwnedPath still refuses every
    # non-C: filesystem mutation.
    if($full -notmatch '^C:\\' -and -not [IO.File]::Exists($full)){
        $leafIdentity=Get-UniIdentity ([IO.Path]::GetFileNameWithoutExtension($full))
        $scope=@($script:UniRequestedIdentities)
        $leafMatches=($scope -contains $leafIdentity)
        if($leafMatches){
            $current=[IO.Path]::GetDirectoryName($full)
            while($current -and $current.Length -gt 3){
                if($scope -contains (Get-UniIdentity ([IO.Path]::GetFileName($current)))){return $true}
                $current=[IO.Path]::GetDirectoryName($current)
            }
        }
    }
    return $false
}
function Initialize-UniExecutionRoots {
    # Metadata verifies portable copies without granting file deletion outside C:.
    $script:UniExecutionRoots=@()
    $processes=@()
    try {$processes=@(Get-Process -ErrorAction Stop)} catch {
        $script:UniFailed.Add('Process enumeration failed during ownership discovery: '+$_.Exception.Message)
        Write-Warning 'Unable to enumerate processes during ownership discovery; continuing with registrations and references.'
    }
    foreach($process in $processes){
        try {
            $path=$process.Path
            if(-not $path){continue}
            $leaf=[IO.Path]::GetFileName($path)
            $kind=$null
            if($script:UniCCleanerRequested -and $leaf -match '^CCleaner(?:64)?\.exe$'){$kind='ccleaner'}
            if($script:UniDriverBoosterRequested -and $leaf -ieq 'DriverBooster.exe'){$kind='driverbooster'}
            if(-not $kind){continue}
            $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $verified=($kind -eq 'ccleaner' -and $version.ProductName -eq 'CCleaner' -and $version.CompanyName -match '^(Gen Digital Inc\.|Piriform(?: Ltd\.?)?)$') -or ($kind -eq 'driverbooster' -and $version.ProductName -eq 'Driver Booster' -and $version.CompanyName -eq 'IObit')
            if($verified){
                $root=[IO.Path]::GetDirectoryName($path)
                # Never authorize a shared portable directory based on one executable.
                $parent=[IO.Path]::GetFileName($root)
                if($parent -match '^\d+(\.\d+)+$'){$parent=[IO.Path]::GetFileName([IO.Path]::GetDirectoryName($root))}
                if((Get-UniIdentity $parent) -eq $kind){
                    $script:UniExecutionRoots += $root
                    Write-Host ('Verified target process location (file deletion still C: only): '+$root)
                }
            }
        } catch {$script:UniFailed.Add('Process identity inspection: '+$_.Exception.Message)}
    }
    $script:UniExecutionRoots=@($script:UniExecutionRoots | Select-Object -Unique)
}
function Test-UniWithin {
    param([string]$Path,[string]$Root)
    if(-not $Path -or -not $Root){return $false}
    return $Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Test-UniSafeRoot {
    param([string]$Path)
    try {
        if($Path -notmatch '^C:\\' -or $Path -match '[*?<>|\x00-\x1f]' -or $Path.Substring(2).Contains(':')){return $false}
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
        if($full.Length -le 3){return $false}
        $blocked=@('C:\Windows','C:\Recovery','C:\System Volume Information','C:\$Recycle.Bin','C:\Program Files\Common Files','C:\Program Files (x86)\Common Files','C:\Program Files\WindowsApps','C:\ProgramData\Package Cache')
        foreach($b in $blocked){if(Test-UniWithin $full $b){return $false}}
        $containers=@('C:','C:\Users','C:\Program Files','C:\Program Files (x86)','C:\ProgramData','C:\Temp',$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA,$env:PUBLIC)
        foreach($b in $containers){if($b -and $full -ieq $b.TrimEnd('\')){return $false}}
        # Refuse user-profile roots and shared AppData containers, regardless of user.
        if($full -match '^C:\\Users\\[^\\]+(\\(AppData(\\(Local|LocalLow|Roaming))?|Desktop|Documents|Downloads))?$'){return $false}
        $current=$full
        while($current -and $current.Length -gt 3){
            if(Test-Path -LiteralPath $current -ErrorAction Stop){
                $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}
            }
            $current=[IO.Path]::GetDirectoryName($current)
        }
        return $true
    } catch {return $false}
}
function Test-UniCDeletionRoot {
    param([string]$Path)
    # Every filesystem mutation in Uni is C:-only. F:, UNC, and other volumes
    # may be used as verified process/launcher references, never as delete roots.
    return [bool]($Path -and $Path -match '^C:\\' -and (Test-UniSafeRoot $Path))
}
function Test-UniOwnedPath {
    param([string]$Path)
    if(Test-UniKnownResidualFile $Path){return $true}
    if(-not (Test-UniSafeRoot $Path)){return $false}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach($other in @($script:UniOtherRoots)) {if(Test-UniWithin $full $other){return $false}}
    if($script:UniOwnedFiles -and $script:UniOwnedFiles.Contains($full)){return $true}
    foreach($root in @($script:UniOwnedRoots)){if(Test-UniWithin $full $root){return $true}}
    return $false
}
function Register-UniOrphanCandidate {
    param([string]$Path,[string]$Pattern)
    if(-not $script:UniOrphanMode -or [string]::IsNullOrWhiteSpace($Pattern)){return $false}
    try {
        if(-not(Test-UniCDeletionRoot $Path)){return $false}
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
        foreach($other in @($script:UniOtherRoots)){
            if((Test-UniWithin $full $other) -or (Test-UniWithin $other $full)){return $false}
        }
        if(Test-UniPreservedReference $full){return $false}
        $leaf=[IO.Path]::GetFileName($full)
        $rx=New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(-not $rx.IsMatch($leaf)){return $false}
        if([IO.Directory]::Exists($full)){
            if(@($script:UniOwnedRoots) -notcontains $full){$script:UniOwnedRoots += $full}
        } else {
            if(-not $script:UniOwnedFiles){$script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)}
            [void]$script:UniOwnedFiles.Add($full)
        }
        $script:UniOrphanMatches=[int]$script:UniOrphanMatches+1
        return $true
    } catch {return $false}
}
function Test-UniOrphanLinkCandidate {
    param([string]$Path,[string]$Pattern)
    if(-not $script:UniOrphanMode -or [string]::IsNullOrWhiteSpace($Pattern)){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
        if($full -notmatch '^C:\\' -or $full.Length -le 3){return $false}
        $rx=New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(-not $rx.IsMatch([IO.Path]::GetFileName($full))){return $false}
        $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if(-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
        $parent=[IO.Path]::GetDirectoryName($full)
        if(-not (Test-UniSafeRoot $parent)){return $false}
        foreach($other in @($script:UniOtherRoots)){
            if((Test-UniWithin $full $other) -or (Test-UniWithin $other $full)){return $false}
        }
        if(Test-UniPreservedReference $full){return $false}
        return $true
    } catch {return $false}
}
function Remove-UniOrphanLink {
    param([string]$Path,[string]$Pattern)
    if(-not (Test-UniOrphanLinkCandidate -Path $Path -Pattern $Pattern)){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
        Update-UniLine ("[{0}] unlinking exact-name reparse point: {1} ..." -f (Get-UniElapsed),$full)
        $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if($item.PSIsContainer){[IO.Directory]::Delete($full,$false)}else{[IO.File]::Delete($full)}
        if(Test-Path -LiteralPath $full -ErrorAction SilentlyContinue){throw 'Reparse point remains after unlink'}
        return $true
    } catch {
        $message=("Unremoved reparse point: {0}: {1}" -f $Path,$_.Exception.Message)
        if($script:UniFailed -and -not $script:UniFailed.Contains($message)){[void]$script:UniFailed.Add($message)}
        Write-Warning $message
        return $false
    }
}
function Test-UniKnownResidualFile {
    param([string]$Path)
    if(-not $script:UniIObitRequested -or -not $Path){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path)
        $allowed=@('C:\Windows\SysWOW64\version\_IObitDel.dll',($env:USERPROFILE+'\Documents\WindowsPowerShell\version\_IObitDel.dll'))
        if($allowed -inotcontains $full -or [IO.Directory]::Exists($full)){return $false}
        $current=$full
        while($current.Length -gt 3){
            if(Test-Path -LiteralPath $current -ErrorAction Stop){if((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}}
            $current=[IO.Path]::GetDirectoryName($current)
        }
        return $true
    } catch {return $false}
}
function Split-UniCommand {
    param([string]$Command)
    $command=[Environment]::ExpandEnvironmentVariables($Command).Trim()
    if($command -match '^"(?<exe>[A-Za-z]:\\[^"\r\n]+)"(?<args>\s.*)?$' -or $command -match '^(?<exe>[A-Za-z]:\\[^\s"]+\.exe)(?<args>\s.*)?$'){
        return @{File=$matches.exe; Arguments=([string]$matches.args).Trim()}
    }
    return $null # Ambiguous unquoted path, DLL/script host, or bare executable.
}
function Test-UniOwnedRegistry {
    param([string]$Path)
    $path=$Path -replace '^.*Registry::','' -replace '^HKLM:?', 'HKEY_LOCAL_MACHINE' -replace '^HKCU:?', 'HKEY_CURRENT_USER'
    foreach($root in @($script:UniDeferredRegistryRoots)){if((Test-UniWithin $path $root) -or (Test-UniWithin $root $path)){return $false}}
    foreach($root in @($script:UniOwnedRegistryRoots)){if(Test-UniWithin $path $root){return $true}}
    return $false
}
function Register-UniOrphanRegistryKey {
    param([string]$ProviderPath,[string]$Pattern)
    if(-not $script:UniOrphanMode -or [string]::IsNullOrWhiteSpace($Pattern)){return $false}
    try {
        $path=$ProviderPath -replace '^.*Registry::',''
        $path=$path -replace '^HKLM:\','HKEY_LOCAL_MACHINE\' -replace '^HKCU:\','HKEY_CURRENT_USER\'
        $path=$path -replace '^HKLM\','HKEY_LOCAL_MACHINE\' -replace '^HKCU\','HKEY_CURRENT_USER\'
        # Orphan registry ownership is restricted to product-shaped keys in
        # Software. Shared Microsoft/Windows and merged HKCR trees stay out.
        if($path -notmatch '^(?:HKEY_CURRENT_USER\Software\|HKEY_LOCAL_MACHINE\SOFTWARE\)'){return $false}
        if($path -match '\(?:Microsoft|Windows)(?:\|$)'){return $false}
        if($path -match '^HKEY_LOCAL_MACHINE\SOFTWARE\Classes(?:\|$)'){return $false}
        $leaf=[IO.Path]::GetFileName($path)
        $rx=New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(-not $rx.IsMatch($leaf)){return $false}
        if(@($script:UniOwnedRegistryRoots) -notcontains $path){$script:UniOwnedRegistryRoots += $path}
        return $true
    } catch {return $false}
}
function Test-UniOrphanProtocol {
    param([string]$KeyPath,[string]$Scheme,[string]$Identity,[string]$CommandText,[object]$RegistryKey)
    # A deleted portable installation can leave its dedicated URL handler.
    # Verify the entire inert registration; never run its command or claim
    # ownership of the shell executable or the former installation directory.
    $command=Split-UniCommand $CommandText
    if(-not $command -or $command.File -ine ($env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe')){return $false}
    if($command.Arguments -notmatch '^(?i)-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "(?<launcher>[A-Za-z]:\\[^"\r\n]+\.ps1)" "%1"$'){return $false}
    $launcher=$matches.launcher
    if([IO.File]::Exists($launcher)){return $false}
    if([IO.Path]::GetFileName($launcher) -ine ('Launch-'+$Identity+'.ps1')){return $false}
    if((Get-UniIdentity ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($launcher)))) -ne $Identity){return $false}
    $ownedKey=$false
    if($RegistryKey){$key=$RegistryKey}else{$key=Get-Item -LiteralPath $KeyPath -ErrorAction Stop;$ownedKey=$true}
    try {return (($key.GetValueNames() -contains 'URL Protocol') -and ([string]$key.GetValue('') -ieq ('URL:'+$Scheme)))} finally {if($ownedKey){$key.Close()}}
}
function Get-UniIdentities {
 param([string[]]$Names)
 $identities=@($Names | ForEach-Object {Get-UniIdentity $_} | Select-Object -Unique)
 if($identities -contains 'telegram' -or $identities -contains 'telegramdesktop'){$identities += @('telegram','telegramdesktop')}
 if($identities -contains 'docker' -or $identities -contains 'dockerdesktop'){$identities += @('docker','dockerdesktop')}
 return @($identities | Select-Object -Unique)
}
function Test-UniPreservedReference {
 param([string]$Path)
 foreach($reference in @($script:UniPreservedReferences)){if(Test-UniWithin $Path $reference){return $true}}
 return $false
}
function Initialize-UniOwnership {
    param([string[]]$Names,[string[]]$Paths)
    $script:UniOwnedRoots=@(); $script:UniOtherRoots=@(); $script:UniSelectedPrograms=@(); $script:UniOwnedRegistryRoots=@(); $script:UniDeferredRegistryRoots=@(); $script:UniPortableExecutionRoots=@();$script:UniExtraShortcutDirs=@();$script:UniTaskReferenceFound=$false
    $script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $identities=@(Get-UniIdentities $Names)
    $script:UniGMenuCleanupAuthorized=Test-UniGMenuTargeted $identities
    $script:UniPreservedReferences=@()
    if($script:UniReferencesFile -and [IO.File]::Exists($script:UniReferencesFile)){
        $references=[IO.File]::ReadAllText($script:UniReferencesFile) | ConvertFrom-Json -ErrorAction Stop
        foreach($entry in $references.PSObject.Properties){if($identities -contains (Get-UniIdentity $entry.Name)){$script:UniPreservedReferences += @($entry.Value)}}
    }
    $script:UniRequestedIdentities=@($identities)
    $script:UniDockerRequested=($identities -contains 'docker' -or $identities -contains 'dockerdesktop')
    if($script:UniDockerRequested){$identities += 'dockerdesktop'}
    $script:UniIObitRequested=$identities -contains 'iobit'
    $script:UniDriverBoosterRequested=($identities -contains 'driverbooster' -or $script:UniIObitRequested)
    $script:UniCCleanerRequested=$identities -contains 'ccleaner'
    if($script:UniDriverBoosterRequested){$identities += 'driverbooster'}
    $all=@()
    foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
        if(-not (Test-Path -LiteralPath $root)){continue}
        foreach($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)){
            $p=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if(-not $p.DisplayName){continue}
            $selected=(Test-UniProductName ([string]$p.DisplayName) $identities) -or ($script:UniIObitRequested -and ([string]$p.Publisher).Trim() -eq 'IObit')
            $location=([string]$p.InstallLocation).Trim().Trim('"').TrimEnd('\')
            foreach($explicit in @($Paths)){
                if($location -and (Test-UniSafeRoot $location) -and [IO.Path]::GetFullPath($explicit).TrimEnd('\') -ieq [IO.Path]::GetFullPath($location).TrimEnd('\')){$selected=$true}
            }
            $record=[pscustomobject]@{Name=[string]$p.DisplayName; Location=$location; Selected=$selected; RegistryPath=$key.PSPath; Quiet=[string]$p.QuietUninstallString; Command=[string]$p.UninstallString; KeyName=$key.PSChildName; WindowsInstaller=$p.WindowsInstaller}
            $all += $record
            if($selected){
                $script:UniSelectedPrograms += $record
                $nativeRegistry=([string]$key.PSPath -replace '^.*Registry::','')
                if($nativeRegistry -match '^HKEY_(CURRENT_USER|LOCAL_MACHINE)\\'){$script:UniOwnedRegistryRoots += $nativeRegistry}
            }
            elseif($location -match '^C:\\' -and $location.Length -gt 3){$script:UniOtherRoots += [IO.Path]::GetFullPath($location)}
        }
    }
    $candidateRoots=@($Paths)+@(Get-UniApprovedPaths $Names)
    $portableRoots=@()
    $patterns=Get-UniPatterns $Names
    if($patterns){
        foreach($base in @('C:\tmp','C:\Temp',($env:LOCALAPPDATA+'\Programs'))){
            foreach($dir in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)){
                if($dir.Name -match $patterns.Exact){$portableRoots += $dir.FullName}
            }
        }
    }
    foreach($identity in $identities){
        if($identity -notmatch '^[a-z0-9]+$'){continue}
        foreach($scheme in @($identity,('com.'+$identity))){
            foreach($hive in @('HKCU','HKLM')){
                $keyPath=$hive+':\Software\Classes\'+$scheme
                $registryHive=if($hive -eq 'HKCU'){[Microsoft.Win32.Registry]::CurrentUser}else{[Microsoft.Win32.Registry]::LocalMachine}
                $protocolKey=$registryHive.OpenSubKey(('Software\Classes\'+$scheme),$false)
                if(-not $protocolKey){continue}
                $key=$protocolKey.OpenSubKey('shell\open\command',$false)
                if(-not $key){$protocolKey.Close();continue}
                try {
                    $commandText=[string]$key.GetValue('')
                    if(Test-UniOrphanProtocol $keyPath $scheme $identity $commandText $protocolKey){
                        $script:UniOwnedRegistryRoots += $keyPath.Replace('HKCU:','HKEY_CURRENT_USER').Replace('HKLM:','HKEY_LOCAL_MACHINE')
                        continue
                    }
                    $command=Split-UniCommand $commandText
                    if($command -and $command.Arguments -match '(?i)(?:^|\s)-File\s+"(?<script>[A-Za-z]:\\[^"\r\n]+\.ps1)"'){
                        $launcher=$matches.script
                        $layout=Get-UniPortableLayout ([IO.Path]::GetDirectoryName($launcher)) $identities
                        if($layout -and $layout.Launcher -ieq $launcher){
                            $portableRoots += $layout.Root
                            $script:UniOwnedRegistryRoots += $keyPath.Replace('HKCU:','HKEY_CURRENT_USER').Replace('HKLM:','HKEY_LOCAL_MACHINE')
                        }
                    }
                } finally {$key.Close();$protocolKey.Close()}
            }
        }
    }
    foreach($root in @($portableRoots | Select-Object -Unique)){
        $layout=Get-UniPortableLayout $root $identities
        if(-not $layout){continue}
        Write-Host ('Verified portable app: '+$layout.Product+' at '+$layout.Root)
        $script:UniPortableExecutionRoots += $layout.Root
        if($layout.Root -match '^C:\\'){$candidateRoots += $layout.Root}
    }
    $relative=@();$registryRelative=@()
    if($identities -contains 'todoist'){
        # Dedicated per-app restore data; the parent can hold other applications.
        $script:UniOwnedRegistryRoots += 'HKEY_CURRENT_USER\Software\Micha\DockerAppRestore\Todoist'
    }
    if($script:UniCCleanerRequested){$relative += @('Piriform\CCleaner','CCleaner');$registryRelative += 'Piriform\CCleaner'}
    if($script:UniDriverBoosterRequested){$relative += 'IObit\Driver Booster';$registryRelative += 'IObit\Driver Booster'}
    if($script:UniIObitRequested){$relative += 'IObit';$registryRelative += 'IObit';$candidateRoots += 'C:\Temp\iobit-db-license-tmp'}
    $storageBases=@('C:\ProgramData','C:\Program Files','C:\Program Files (x86)')
    if($identities -contains 'telegram'){
        $relative += 'Telegram Desktop';$registryRelative += @('Telegram Desktop','TelegramDesktop')
        $script:UniOwnedRegistryRoots += 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\PushNotifications\Backup\Microsoft.YourPhone_8wekyb3d8bbwe!YourPhoneNotifications_org.telegram.messenger'
        foreach($hive in @('HKCU:\Software\Classes','HKLM:\Software\Classes')){
            foreach($scheme in @('tg','tdesktop.tg','tonsite','tdesktop.tonsite')){
                $keyPath=$hive+'\'+$scheme
                $key=Get-Item -LiteralPath ($keyPath+'\shell\open\command') -ErrorAction SilentlyContinue
                if(-not $key){continue}
                try {$command=Split-UniCommand ([string]$key.GetValue(''))} finally {$key.Close()}
                if($command -and (Test-UniAppReference $command.File)){
                    $script:UniOwnedRegistryRoots += $keyPath.Replace('HKCU:','HKEY_CURRENT_USER').Replace('HKLM:','HKEY_LOCAL_MACHINE')
                }
            }
        }
    }
    foreach($userDir in [IO.Directory]::EnumerateDirectories('C:\Users')){
        foreach($part in @('Local','LocalLow','Roaming')){$storageBases += $userDir+'\AppData\'+$part}
        $packages=$userDir+'\AppData\Local\Packages'
        if(Test-UniSafeRoot ($packages+'\OwnershipProbe')){
            foreach($package in @(Get-ChildItem -LiteralPath $packages -Directory -ErrorAction SilentlyContinue)){
                $script:UniExtraShortcutDirs += $package.FullName+'\LocalCache\Roaming\Microsoft\Windows\Start Menu\Programs'
                foreach($part in @('Local','LocalLow','Roaming')){$storageBases += $package.FullName+'\LocalCache\'+$part}
            }
        }
    }
    foreach($base in $storageBases){foreach($rel in $relative){$candidate=$base+'\'+$rel;if([IO.Directory]::Exists($candidate)){$candidateRoots += $candidate}}}
    foreach($hive in @('HKEY_CURRENT_USER\Software','HKEY_LOCAL_MACHINE\SOFTWARE','HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')){
        foreach($rel in $registryRelative){$script:UniOwnedRegistryRoots += $hive+'\'+$rel}
    }
    if($script:UniDockerRequested){
        # Vendor-documented residual locations, C: only. Shared-root overlap checks
        # below still apply. No global WSL shutdown, distro removal or VM guessing.
        $candidateRoots += @('C:\Program Files\Docker','C:\ProgramData\Docker','C:\ProgramData\DockerDesktop')
        foreach($userDir in [IO.Directory]::EnumerateDirectories('C:\Users')){
            if(-not(Test-UniSafeRoot ($userDir+'\AppData\Local\Docker'))){continue}
            $candidateRoots += @(@($userDir+'\AppData\Local\Docker';$userDir+'\AppData\Roaming\Docker';$userDir+'\AppData\Roaming\Docker Desktop';$userDir+'\.docker') | Where-Object { [IO.Directory]::Exists($_) })
        }
        foreach($hive in @('HKEY_CURRENT_USER\Software','HKEY_LOCAL_MACHINE\SOFTWARE','HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')){
            $script:UniOwnedRegistryRoots += @($hive+'\Docker Inc.\Docker Desktop';$hive+'\Docker Desktop')
        }
    }
    foreach($p in $script:UniSelectedPrograms){
        if($p.Location -and (Test-UniCDeletionRoot $p.Location)){$candidateRoots += $p.Location}
        elseif($p.Location){Write-Host ('Preserving out-of-scope installation reference (C: cleanup only): '+$p.Location) -ForegroundColor DarkGray}
        # Product-specific registry subtrees only, never a publisher subtree.
        foreach($hive in @('HKEY_CURRENT_USER\Software','HKEY_LOCAL_MACHINE\SOFTWARE','HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')){
            $script:UniOwnedRegistryRoots += $hive+'\'+$p.Name
        }
    }
    # Exact product folder names in app storage; never arbitrary same-name docs.
    foreach($base in @($env:APPDATA,$env:LOCALAPPDATA,$env:ProgramData,$env:ProgramFiles,${env:ProgramFiles(x86)})){
        if(-not $base -or -not (Test-Path -LiteralPath $base)){continue}
        foreach($dir in @(Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction Stop)){
            if($identities -contains (Get-UniIdentity $dir.Name)){$candidateRoots += $dir.FullName}
        }
    }
    foreach($candidate in @($candidateRoots | Select-Object -Unique)){
        if(-not (Test-UniCDeletionRoot $candidate)){
            Write-Host ('Reference only; no filesystem deletion outside C:: '+$candidate) -ForegroundColor DarkGray
            continue
        }
        $full=[IO.Path]::GetFullPath($candidate).TrimEnd('\')
        $conflict=$false
        foreach($other in $script:UniOtherRoots){if((Test-UniWithin $full $other) -or (Test-UniWithin $other $full)){$conflict=$true;break}}
        if($conflict){$script:UniFailed.Add('Shared installation preserved: '+$full);continue}
        $script:UniOwnedRoots += $full
        Write-Host "Owned app root: $full"
    }
    $script:UniOwnedRoots=@($script:UniOwnedRoots | Select-Object -Unique)
    Initialize-UniExecutionRoots
    # Registered F: installations remain reference-only, but their verified
    # executable roots must still identify services, tasks, and shortcuts that
    # belong to the requested app. Seed those roots before the optional task
    # reference traversal so a normal registered install never waits on the
    # entire Task Scheduler tree. This never authorizes F: file deletion:
    # Remove-UniTarget and Test-UniOwnedPath retain the C:-only boundary.
    foreach($program in @($script:UniSelectedPrograms)){
        if($program.Location -and $program.Location -match '^C:\\|^F:\\'){
            $script:UniExecutionRoots += [IO.Path]::GetFullPath($program.Location).TrimEnd('\')
        }
    }
    $script:UniExecutionRoots=@($script:UniExecutionRoots | Select-Object -Unique)
    $script:UniExecutionRoots += @($script:UniPortableExecutionRoots)
    if(-not $script:UniExecutionRoots.Count){Initialize-UniReferenceExecutionRoots}
    $script:UniNoVerifiedTarget=(-not $script:UniOwnedRoots.Count -and -not $script:UniSelectedPrograms.Count -and -not $script:UniOwnedRegistryRoots.Count -and -not $script:UniExecutionRoots.Count -and -not $script:UniTaskReferenceFound)
}
function Invoke-UniOfficialUninstall {
    param([ValidateRange(1,180)][int]$TimeoutSeconds=180)
    foreach($program in @($script:UniSelectedPrograms)){
        # A prior attempt may already have removed its registration asynchronously.
        if(-not(Test-Path -LiteralPath $program.RegistryPath -ErrorAction Stop)){
            Write-Host ('Already unregistered: '+$program.Name)
            continue
        }
        if(-not $program.Location -or -not (Test-UniCDeletionRoot $program.Location)){
            $message=$program.Name+': official uninstaller skipped because its installation scope is not a verified C: root'
            $script:UniFailed.Add($message)
            Write-Host ('C:-only policy: '+$message) -ForegroundColor Yellow
            continue
        }
        if($program.WindowsInstaller -eq 1 -and $program.KeyName -match '^\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$'){
            $command=@{File="$env:SystemRoot\System32\msiexec.exe";Arguments=''}
        } else { $command=Split-UniCommand $program.Quiet }
        if(-not $command){$command=Split-UniCommand $program.Command}
        if(-not $command){Set-UniUninstallIncomplete $program 'No unambiguous registered uninstaller executable';continue}
        $isMsi=([IO.Path]::GetFullPath($command.File) -ieq "$env:SystemRoot\System32\msiexec.exe") -or ([IO.Path]::GetFullPath($command.File) -ieq "$env:SystemRoot\SysWOW64\msiexec.exe")
        if($isMsi){
            if($program.WindowsInstaller -ne 1 -or $program.KeyName -notmatch '^\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$'){Set-UniUninstallIncomplete $program 'MSI product identity could not be verified';continue}
            $command.Arguments='/x '+$program.KeyName+' /qn /norestart'
        } elseif(-not (Test-UniOwnedPath $command.File)) {Set-UniUninstallIncomplete $program ('Official uninstaller is outside exclusive C: app roots: '+$command.File);continue}
        $alreadyRunning=$false
        if(-not $isMsi){
            foreach($running in @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($command.File)) -ErrorAction SilentlyContinue)){
                if(-not $running.Path -or $running.Path -ieq $command.File){
                    $closed=$false
                    try {
                        if($running.Path -and (Test-UniOwnedPath $running.Path)){
                            Write-Host ('Force closing verified running uninstaller PID '+$running.Id)
                            if(-not $running.HasExited){$running.Kill();[void]$running.WaitForExit(5000)}
                            $closed=$running.HasExited
                        }
                    } catch {$closed=$false}
                    if(-not $closed){
                        Set-UniUninstallIncomplete $program ('Existing uninstaller PID '+$running.Id+' could not be force-closed; no duplicate started')
                        $alreadyRunning=$true
                        break
                    }
                }
            }
        }
        if($alreadyRunning){continue}
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=$command.File; $info.Arguments=$command.Arguments; $info.UseShellExecute=$false
        $info.WorkingDirectory=[IO.Path]::GetDirectoryName($command.File)
        if(-not [IO.File]::Exists($command.File)){
            Set-UniUninstallIncomplete $program ('Registered uninstaller is missing: '+$command.File)
            continue
        }
        Write-Host "Running official uninstaller: $($program.Name)"
        try {$process=[Diagnostics.Process]::Start($info)} catch {
            Set-UniUninstallIncomplete $program ('Uninstaller could not start: '+$_.Exception.Message)
            continue
        }
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $timedOut=$false
        while(-not $process.WaitForExit(1000)){
            Write-Host ("Official uninstaller PID {0}; elapsed {1}s; limit {2}s." -f $process.Id,[int]$watch.Elapsed.TotalSeconds,$TimeoutSeconds)
            if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){Set-UniUninstallIncomplete $program ('Uninstaller still running, PID '+$process.Id+'; timed out');$timedOut=$true;break}
        }
        if($timedOut){
            # The process was started from an exact, verified registration. A
            # timeout must not leave the app locked while later C: cleanup
            # phases run. Kill only this process instance; no name-wide kill.
            try {
                if(-not $process.HasExited){
                    Write-Host ('Force closing timed-out verified uninstaller PID '+$process.Id)
                    $process.Kill()
                    [void]$process.WaitForExit(5000)
                }
                if(-not $process.HasExited){$script:UniFailed.Add('Timed-out uninstaller remains active: '+$command.File)}
            } catch {$script:UniFailed.Add('Timed-out uninstaller force-close failed: '+$command.File+': '+$_.Exception.Message)}
            $process.Dispose();continue
        }
        $code=$process.ExitCode
        $process.Dispose()
        if($code -in @(1641,3010)){
            Set-UniUninstallIncomplete $program ('Uninstaller requests reboot; exit '+$code)
            continue
        }
        if($code -ne 0){
            Set-UniUninstallIncomplete $program ('Official uninstaller exited with code '+$code+'; executable '+$command.File)
            continue
        }
        if(Test-Path -LiteralPath $program.RegistryPath){
            Set-UniUninstallIncomplete $program 'Registration remains after the uninstaller exited successfully'
        }
    }
}
function Set-UniUninstallIncomplete {
    param($Program,[string]$Reason)
    $message=$Program.Name+': '+$Reason
    $script:UniFailed.Add($message)
    # A failed or timed-out vendor uninstaller is not proof that its
    # installation is safe to recursively delete.  Reclassify the verified
    # C: location as an explicitly protected sibling before later cleanup
    # phases inspect ownership.  Test-UniOwnedPath checks UniOtherRoots first,
    # so this also wins if an earlier discovery pass added the same root to
    # UniOwnedRoots.
    if($Program.Location -and (Test-UniCDeletionRoot $Program.Location)){
        try {
            $failedRoot=[IO.Path]::GetFullPath([string]$Program.Location).TrimEnd('\')
            $script:UniOtherRoots=@($script:UniOtherRoots + $failedRoot | Select-Object -Unique)
        } catch { }
    }
    Write-Host ('UNINSTALL INCOMPLETE: '+$message) -ForegroundColor Yellow
    Write-Host 'Continuing verified cleanup for this target; shared or ambiguous roots remain protected.'
}


# ---------------------------------------------------------------------------
# the nuclear entry point
# ---------------------------------------------------------------------------
function Start-UniHeartbeat {
 if(-not ('UniProgressV1' -as [type])){
  Add-Type -TypeDefinition @"
using System;
using System.Threading;
using System.Diagnostics;
public static class UniProgressV1 {
 private static Timer timer;
 private static Stopwatch watch;
 public static string Phase = "Initializing";
 public static void Start() {
  watch=Stopwatch.StartNew();
  timer=new Timer(delegate(object state) {
   try { Console.WriteLine("[RUNNING {0:0}s] {1}",watch.Elapsed.TotalSeconds,Phase); } catch { }
  },null,1000,1000);
 }
 public static void Stop() { if(timer!=null){timer.Dispose();timer=null;} }
}
"@ -ErrorAction Stop
 }
 [UniProgressV1]::Stop()
 [UniProgressV1]::Phase='Initializing'
 [UniProgressV1]::Start()
}
function Get-UniApprovedPaths {
    param([string[]]$Names)
    if(-not $script:UniTargetsFile -or -not [IO.File]::Exists($script:UniTargetsFile)){return @()}
    $config=[IO.File]::ReadAllText($script:UniTargetsFile) | ConvertFrom-Json -ErrorAction Stop
    $identities=@(Get-UniIdentities $Names)
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $config.PSObject.Properties){
        if($identities -notcontains (Get-UniIdentity $entry.Name)){continue}
        foreach($path in @($entry.Value)){
            if(-not(Test-UniSafeRoot ([string]$path))){throw ('Unsafe approved cleanup path: '+$path)}
            [void]$paths.Add([IO.Path]::GetFullPath([string]$path).TrimEnd('\'))
        }
    }
    if($paths.Count){Write-Host ('Loaded '+$paths.Count+' user-approved exact cleanup paths.')}
    return @($paths)
}
function Read-UniExactList {
    param([string]$ListPath)
    if(-not [IO.File]::Exists($ListPath)){throw ('Removal list does not exist: '+$ListPath)}
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($line in [IO.File]::ReadAllLines($ListPath)){
        $path=$line.Trim()
        if(-not $path){continue}
        if($path.StartsWith('"') -and $path.EndsWith('"')){$path=$path.Substring(1,$path.Length-2)}
        if(-not(Test-UniSafeRoot $path)){throw ('Unsafe or linked path in removal list: '+$path)}
        [void]$paths.Add([IO.Path]::GetFullPath($path).TrimEnd('\'))
    }
    if(-not $paths.Count){throw 'Removal list is empty'}
    return @($paths)
}
function Invoke-UniExactList {
    param([string]$ListPath,[switch]$DryRun)
    # Every entry is validated before any external mutation. Only explicitly
    # listed files/directories become owned; filenames do not expand the scope.
    $paths=@(Read-UniExactList $ListPath)
    Write-Host ('EXACT C: REMOVAL LIST: '+$paths.Count+' literal paths')
    if($DryRun){foreach($path in $paths){Write-Host ('Preview: '+$path)};$global:LASTEXITCODE=0;return}
    $script:UniOwnedRoots=@($paths);$script:UniOtherRoots=@();$script:UniExecutionRoots=@()
    $script:UniOwnedRegistryRoots=@();$script:UniSelectedPrograms=@()
    $script:UniIObitRequested=$false;$script:UniCCleanerRequested=$false;$script:UniDriverBoosterRequested=$false
    $script:UniRequestedIdentities=@()
    $script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $script:UniPhaseCount=3
    Write-UniPhase 'Stopping processes inside explicitly listed paths'
    Invoke-UniKillProcesses $null
    Write-UniPhase 'Removing explicitly listed C: paths'
    $index=0
    foreach($path in @($paths | Sort-Object Length)){
        $index++
        if(-not(Test-Path -LiteralPath $path -ErrorAction Stop)){continue}
        Write-Host ('Removing [{0}/{1}]: {2}' -f $index,$paths.Count,$path)
        $wasDirectory=[IO.Directory]::Exists($path)
        if(Remove-UniTarget $path){if($wasDirectory){$script:UniStats.Dirs++}else{$script:UniStats.Files++}}
        else {$script:UniFailed.Add($path)}
    }
    Write-UniPhase 'Verifying every explicitly listed path'
    $remaining=@($paths | Where-Object {Test-Path -LiteralPath $_ -ErrorAction Stop})
    Write-Host ('EXACT LIST VERIFIED: {0} checked; {1} remaining.' -f $paths.Count,$remaining.Count)
    foreach($path in $remaining){Write-Warning ('Still present: '+$path)}
    $global:LASTEXITCODE=if($remaining.Count -or $script:UniFailed.Count){2}else{0}
}
function uni {
    $ErrorActionPreference = 'Stop'
    $script:UniFailed = New-Object 'System.Collections.Generic.List[string]'
    $script:UniProtectedArtifacts = New-Object 'System.Collections.Generic.List[string]'
    $script:UniOrphanMode = $false
    $script:UniOrphanMatches = 0
    $script:UniOrphanPattern = $null
    $script:UniPhase=0
    $script:UniPhaseCount=12
    $script:UniEarlyStopped=0
    $dryRun=$false
    $raw = @($args)
    if($raw -contains '--paths-file'){
        $listIndex=[Array]::IndexOf($raw,'--paths-file')
        if($listIndex+1 -ge $raw.Count){throw '--paths-file requires a list filename'}
        $listPath=[string]$raw[$listIndex+1]
        $expected=2
        if($raw -contains '--dry-run'){$expected++}
        if($raw.Count -ne $expected){throw '--paths-file accepts only its filename and optional --dry-run'}
        Invoke-UniExactList -ListPath $listPath -DryRun:($raw -contains '--dry-run')
        return
    }
    $names = New-Object System.Collections.Generic.List[string]
    $paths = New-Object System.Collections.Generic.List[string]
    $sweepOnly = $false
    foreach ($a in $raw) {
        $s = [string]$a
        if ($s -eq '--dry-run') { $dryRun=$true; continue }
        elseif ($s -match '^(/|--|-)[A-Za-z]') { throw "Unknown option: $s" }
        elseif ($s -match '^[A-Za-z]:[\\/]' -or $s -match '^\\\\' -or $s -match '^\.{1,2}[\\/]') {
            $paths.Add($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($s))
        }
        else { $names.Add($s) }
    }
    if ($names.Count -eq 0 -and $paths.Count -eq 0) {
        Write-Host 'uni: no target app names or paths given.' -ForegroundColor Yellow
        return
    }
    $requestedNames=@($names)
    if ($paths.Count -gt 0) {
        foreach($p in $paths) {
            if (-not (Test-UniSafeRoot $p)) {
                # Explicit paths outside C: are references for process,
                # registration, and shortcut matching only.  They must never
                # become deletion roots, but they also must not abort a
                # requested C:-only cleanup before ownership discovery.
                if (Test-UniCDeletionRoot $p) {
                    throw "Unsafe explicit app path: $p"
                }
                Write-Host ('Reference-only explicit path (C: cleanup only): '+$p) -ForegroundColor DarkGray
            }
            $names.Add([IO.Path]::GetFileNameWithoutExtension($p.TrimEnd('\')))
        }
    }
    if(@($requestedNames | ForEach-Object {Get-UniIdentity $_}) -contains 'docker'){
        $names.Add('Docker Desktop')
    }
    if(@(Get-UniIdentities $requestedNames) -contains 'telegram'){$names.Add('Telegram');$names.Add('Telegram Desktop')}
    $pat = Get-UniPatterns -Names @($names)
    if (-not $pat) {
        Write-Host ("uni: names too short or too generic to sweep safely: {0}" -f (@($names) -join ', ')) -ForegroundColor Yellow
        return
    }
    $ReExact = New-Object System.Text.RegularExpressions.Regex($pat.Exact, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $ReLoose = New-Object System.Text.RegularExpressions.Regex($pat.Loose, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    Write-Host ('  SEARCH TERMS: {0}' -f ($pat.Tokens -join ', ')) -ForegroundColor Cyan
    Write-Host '  Preserving shared resources; reporting unverified leftovers.' -ForegroundColor DarkGray
    $script:UniStart = [DateTime]::UtcNow

    $script:UniRequestedIdentities=@(Get-UniIdentities $requestedNames)
    # Seed aliases needed by the pre-ownership force-close pass. Ownership
    # discovery sets these again from the authoritative registrations.
    $script:UniIObitRequested=$script:UniRequestedIdentities -contains 'iobit'
    $script:UniDriverBoosterRequested=($script:UniRequestedIdentities -contains 'driverbooster' -or $script:UniIObitRequested)
    $script:UniCCleanerRequested=$script:UniRequestedIdentities -contains 'ccleaner'
    if(-not $dryRun){
        $script:UniPhaseCount=13
        Write-UniPhase 'Force closing verified requested applications'
        Invoke-UniPhaseSafely 'Force closing verified requested applications' { Invoke-UniEarlyStop }
    }
    Initialize-UniOwnership -Names $requestedNames -Paths @($paths)
    $script:UniOrphanMode=[bool]$script:UniNoVerifiedTarget
    $script:UniOrphanPattern=$pat.Orphan
    if($script:UniOrphanMode){
        Write-Host ('No verified uninstall target found: '+($requestedNames -join ', ')) -ForegroundColor Yellow
        Write-Host 'No installer or portable ownership was verified; running exact-name residual cleanup on C:.' -ForegroundColor Cyan
        Write-Host 'Services, scheduled tasks, uninstallers, firewall rules, and shared registry values remain protected without ownership evidence.' -ForegroundColor DarkGray
        if($dryRun){
            Write-Host 'DRY RUN: orphan residual candidates would be matched by exact app identity and artifact-shaped suffixes; no cleanup executed.'
            $global:LASTEXITCODE=0
            return
        }
        $script:UniPhaseCount=5
        Write-UniPhase 'Force closing unregistered script-hosted targets'
        Invoke-UniPhaseSafely 'Force closing unregistered script-hosted targets' { Invoke-UniOrphanProcessStop -Pattern $script:UniOrphanPattern }
        Write-UniPhase 'Removing exact-name C: residuals'
        Invoke-UniPhaseSafely 'Removing exact-name C: residuals' { Invoke-UniFileSweep -ExactPat $pat.Exact -LoosePat $pat.Loose -ExplicitPaths @($paths) -OrphanPat $script:UniOrphanPattern }
        Write-UniPhase 'Removing exact-name orphan registry keys'
        Invoke-UniPhaseSafely 'Removing exact-name orphan registry keys' { Invoke-UniOrphanRegistrySweep -Pattern $script:UniOrphanPattern }
        Write-UniPhase 'Final cleanup round'
        Invoke-UniPhaseSafely 'Final cleanup round' { Invoke-UniFinal -ReExact $ReExact -ReLoose $ReLoose -ExactPat $pat.Exact -LoosePat $pat.Loose -RootSpecs $script:UniRootSpecs -DenyPaths $script:UniDenyPaths -Protected $script:UniProtected }
        Write-UniSummary
        return
    }
    if($dryRun){
        Write-Host 'DRY RUN: identity and ownership preview only. No uninstallers or cleanup actions executed.'
        foreach($program in $script:UniSelectedPrograms){Write-Host ('Selected registration: '+$program.Name)}
        $global:LASTEXITCODE=0
        return
    }
    Write-UniPhase 'Stopping remaining verified target processes'
    Invoke-UniPhaseSafely 'Stopping remaining verified target processes' { Invoke-UniKillProcesses -ReExact $ReExact }
    Write-UniPhase 'Removing verified target services'
    Invoke-UniPhaseSafely 'Removing verified target services' { Invoke-UniServices -ReExact $ReExact }
    Write-UniPhase 'Deleting scheduled tasks'
    Invoke-UniPhaseSafely 'Deleting scheduled tasks' { Invoke-UniTasks -ReExact $ReExact }
    Write-UniPhase 'Running exact registered uninstallers'
    Invoke-UniPhaseSafely 'Running exact registered uninstallers' { Invoke-UniOfficialUninstall }
    Write-UniPhase 'Removing firewall rules'
    Invoke-UniPhaseSafely 'Removing firewall rules' { Invoke-UniFirewall -ReExact $ReExact }
    Write-UniPhase 'Uninstall / App Paths / Run keys'
    Invoke-UniPhaseSafely 'Uninstall / App Paths / Run keys' { Invoke-UniInstallerKeys -ReExact $ReExact }
    Write-UniPhase 'Deep registry & COM sweep'
    Invoke-UniPhaseSafely 'Deep registry & COM sweep' { Invoke-UniRegistrySweep -ReExact $ReExact -ReLoose $ReLoose }
    Write-UniPhase 'Cleaning environment variables'
    Invoke-UniPhaseSafely 'Cleaning environment variables' { Invoke-UniEnvVars -ReExact $ReExact }
    Write-UniPhase 'Removing shortcuts and pins'
    Invoke-UniPhaseSafely 'Removing shortcuts and pins' { Invoke-UniShortcuts -ReLoose $ReLoose }
    Write-UniPhase 'Cleaning MRU and recent lists'
    Invoke-UniPhaseSafely 'Cleaning MRU and recent lists' { Invoke-UniMru -ReExact $ReExact }
    Write-UniPhase 'Removing verified C: app files'
    Invoke-UniPhaseSafely 'Removing verified C: app files' { Invoke-UniFileSweep -ExactPat $pat.Exact -LoosePat $pat.Loose -ExplicitPaths @($paths) -SkipDriveSweep:($paths.Count -gt 0 -and $requestedNames.Count -eq 0) -OrphanPat $script:UniOrphanPattern }
    Write-UniPhase 'Final cleanup round'
    Invoke-UniPhaseSafely 'Final cleanup round' { Invoke-UniFinal -ReExact $ReExact -ReLoose $ReLoose -ExactPat $pat.Exact -LoosePat $pat.Loose -RootSpecs $script:UniRootSpecs -DenyPaths $script:UniDenyPaths -Protected $script:UniProtected }

    Write-UniSummary
}

function Get-UniConcurrencyKey {
    param([object[]]$Raw)
    $nameInputs=New-Object 'System.Collections.Generic.List[string]'
    $parts=New-Object 'System.Collections.Generic.List[string]'
    $exactList=$false
    for($i=0;$i -lt @($Raw).Count;$i++){
        $s=[string]$Raw[$i]
        if($s -eq '--dry-run'){continue}
        if($s -eq '--paths-file'){$exactList=$true; $i++; continue}
        if($s -match '^[A-Za-z]:[\\/]' -or $s -match '^\\\\' -or $s -match '^\.{1,2}[\\/]'){
            try{$resolved=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($s)}catch{$resolved=$s}
            [void]$parts.Add('path:'+([string]$resolved).TrimEnd('\\').ToLowerInvariant())
            try{[void]$nameInputs.Add([IO.Path]::GetFileNameWithoutExtension($s.TrimEnd('\\')))}catch{}
        } elseif($s -notmatch '^(/|--|-)[A-Za-z]') {
            [void]$nameInputs.Add($s)
        }
    }
    # Exact path lists are arbitrary C: mutation sets. Keep one diagnostic key
    # for a request, but the mutating entry point below uses one global queue:
    # two different lists or a broad/narrow name pair can overlap unknowably.
    if($exactList){return 'exact-list'}
    $nameArray=@($nameInputs | ForEach-Object {[string]$_})
    $identities=@(Get-UniIdentities $nameArray)
    if($identities -contains 'iobit' -or $identities -contains 'driverbooster'){$identities += @('iobit','driverbooster')}
    if($identities -contains 'ccleaner' -or $identities -contains 'ccleanercrashreporting'){$identities += @('ccleaner','ccleanercrashreporting')}
    foreach($identity in @($identities | Where-Object {$_} | Select-Object -Unique | Sort-Object)){[void]$parts.Add('name:'+([string]$identity).ToLowerInvariant())}
    if(-not $parts.Count){return 'empty'}
    $payload=(@($parts | Sort-Object) -join '|')
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$bytes=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))}finally{[void]$sha.Dispose()}
    return (([BitConverter]::ToString($bytes) -replace '-','').ToLowerInvariant())
}

if ($MyInvocation.InvocationName -ne '.') {
    $global:LASTEXITCODE=2
    Write-Host 'Starting Uni: resolving exact application ownership.'
    $runtime=Join-Path $PSScriptRoot 'uni.runtime.dll'
    if(-not(Test-Path -LiteralPath $runtime)){throw 'Uni runtime missing. Run the documented build script.'}
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($runtime))
    Start-UniHeartbeat
    $script:UniRunLock=$null
    $script:UniHasLock=$false
    try {
        $lockRequired=(@($args).Count -gt 0 -and @($args) -notcontains '--dry-run')
        if($lockRequired){
            $lockKey=Get-UniConcurrencyKey -Raw @($args)
            # Every mutating cleanup shares one abandoned-mutex-safe queue.
            # Per-request keys remain in the message for reconciliation/debug
            # output, but cannot allow an unknown broad/narrow overlap to race.
            $lockName='Global\UniOwnedCleanupV8'
            $script:UniRunLock=New-Object Threading.Mutex($false,$lockName)
            [UniProgressV1]::Phase='Waiting for same-target Uni run'
            $reportedWait=$false
            while(-not $script:UniHasLock){
                try{$script:UniHasLock=$script:UniRunLock.WaitOne(1000)} catch [Threading.AbandonedMutexException] {$script:UniHasLock=$true}
                if(-not $script:UniHasLock -and -not $reportedWait){
                    Write-Host ('Another Uni run is active; waiting for it to finish before reconciling target key '+$lockKey+'.') -ForegroundColor Yellow
                    $reportedWait=$true
                }
            }
        }
        [UniProgressV1]::Phase='Initializing'
        & 'uni' @args
    }
    catch {
        $global:LASTEXITCODE=2
        Write-Host ('INCOMPLETE: '+$_.Exception.Message) -ForegroundColor Red
        Write-Host 'Subsequent cleanup stopped. Completed external actions are not rolled back; reconcile before retrying.'
        # Convert unexpected top-level failures into the same explicit
        # incomplete result used by phase-level error handling.  Re-throwing
        # here only adds a PowerShell stack trace after the safety boundary has
        # already stopped mutation, which makes callers look hung and obscures
        # the live status/exit code.  The non-zero exit code remains fail-closed.
    } finally {
        if('UniSweepCollectV8' -as [type]){[UniSweepCollectV8]::Cancel()}
        if('UniRegCollectV8' -as [type]){[UniRegCollectV8]::Cancel()}
        if($script:UniHasLock){$script:UniRunLock.ReleaseMutex()}
        if($script:UniRunLock){$script:UniRunLock.Dispose()}
        [UniProgressV1]::Stop()
    }
    exit $global:LASTEXITCODE
}
