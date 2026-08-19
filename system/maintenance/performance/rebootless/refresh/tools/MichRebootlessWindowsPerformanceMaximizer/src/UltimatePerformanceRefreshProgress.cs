using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class NativeMem
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public sealed class MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;

        public MEMORYSTATUSEX()
        {
            dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
}

internal sealed class Snapshot
{
    public DateTime Time;
    public uint MemoryLoad;
    public ulong AvailPhys;
    public int ProcessCount;
    public long TempBytes;
    public long TempEntries;
    public long CFreeBytes;
    public long HandleCount;
    public long ThreadCount;

    public static Snapshot Capture()
    {
        Snapshot s = new Snapshot();
        s.Time = DateTime.Now;

        NativeMem.MEMORYSTATUSEX m = new NativeMem.MEMORYSTATUSEX();
        if (NativeMem.GlobalMemoryStatusEx(m))
        {
            s.MemoryLoad = m.dwMemoryLoad;
            s.AvailPhys = m.ullAvailPhys;
        }

        try
        {
            Process[] ps = Process.GetProcesses();
            s.ProcessCount = ps.Length;
            long handles = 0;
            long threads = 0;
            foreach (Process p in ps)
            {
                try { handles += p.HandleCount; } catch { }
                try { threads += p.Threads.Count; } catch { }
                try { p.Dispose(); } catch { }
            }
            s.HandleCount = handles;
            s.ThreadCount = threads;
        }
        catch { }

        try
        {
            string temp = Path.GetTempPath();
            int seen = 0;
            foreach (string f in Directory.EnumerateFiles(temp, "*", SearchOption.TopDirectoryOnly))
            {
                try
                {
                    FileInfo fi = new FileInfo(f);
                    s.TempBytes += fi.Length;
                    s.TempEntries++;
                }
                catch { }
                seen++;
                if (seen > 1500) break;
            }
        }
        catch { }

        try
        {
            s.CFreeBytes = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)).AvailableFreeSpace;
        }
        catch { }

        return s;
    }
}

internal static class Program
{
    public static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HermesUltimateRefresh");
    public static readonly string ScriptLog = Path.Combine(Root, "last-run.log");
    public static readonly string ExeLog = Path.Combine(Root, "exe-last-run.log");
    public const string TaskName = "Hermes Ultimate Performance Refresh";
    public const int WorkerBudgetSeconds = 15;

    [STAThread]
    private static int Main(string[] args)
    {
        Directory.CreateDirectory(Root);
        if (args.Length > 0 && args[0].Equals("--verify", StringComparison.OrdinalIgnoreCase)) return VerifyConsole();

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ProgressForm());
        return 0;
    }

    public static int RunTask()
    {
        return RunNative(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe"), "/Run /TN \"" + TaskName + "\"", 15000);
    }

    public static int QueryTask()
    {
        return RunNative(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe"), "/Query /TN \"" + TaskName + "\"", 10000);
    }

    public static int RunNative(string file, string args, int timeoutMs)
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo(file, args);
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process p = Process.Start(psi);
            if (p == null) return -10;
            if (!p.WaitForExit(timeoutMs))
            {
                try { p.Kill(); } catch { }
                return -11;
            }
            return p.ExitCode;
        }
        catch (Exception ex)
        {
            try { File.AppendAllText(ExeLog, DateTime.Now.ToString("o") + " ERR " + ex.Message + Environment.NewLine); } catch { }
            return -12;
        }
    }

    public static string Fmt(Snapshot s)
    {
        return "time=" + s.Time.ToString("HH:mm:ss", CultureInfo.InvariantCulture) +
               " memory-load=" + s.MemoryLoad + "%" +
               " avail-ram=" + Mb(s.AvailPhys) + "MB" +
               " processes=" + s.ProcessCount +
               " handles=" + s.HandleCount +
               " threads=" + s.ThreadCount +
               " temp=" + Mb((ulong)Math.Max(0, s.TempBytes)) + "MB/" + s.TempEntries + "files" +
               " c-free=" + Mb((ulong)Math.Max(0, s.CFreeBytes)) + "MB";
    }

    public static string Delta(Snapshot before, Snapshot after)
    {
        long availDelta = ((long)after.AvailPhys - (long)before.AvailPhys) / 1048576L;
        long tempDelta = (before.TempBytes - after.TempBytes) / 1048576L;
        long diskDelta = (after.CFreeBytes - before.CFreeBytes) / 1048576L;
        long handleDelta = after.HandleCount - before.HandleCount;
        long threadDelta = after.ThreadCount - before.ThreadCount;
        return "avail-ram=" + Signed(availDelta) + "MB" +
               " memory-load=" + Signed((long)after.MemoryLoad - (long)before.MemoryLoad) + "%" +
               " temp-removed=" + tempDelta + "MB" +
               " disk-free=" + Signed(diskDelta) + "MB" +
               " processes=" + Signed(after.ProcessCount - before.ProcessCount) +
               " handles=" + Signed(handleDelta) +
               " threads=" + Signed(threadDelta);
    }

    private static string Signed(long value)
    {
        return value >= 0 ? "+" + value.ToString(CultureInfo.InvariantCulture) : value.ToString(CultureInfo.InvariantCulture);
    }

    private static string Mb(ulong bytes)
    {
        return (bytes / 1048576UL).ToString(CultureInfo.InvariantCulture);
    }

    private static int VerifyConsole()
    {
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("VERIFY MichRebootlessWindowsPerformanceMaximizer");
        sb.AppendLine("root=" + Root);
        sb.AppendLine("worker-budget-seconds=" + WorkerBudgetSeconds.ToString(CultureInfo.InvariantCulture));
        sb.AppendLine("task-query-exit=" + QueryTask());
        sb.AppendLine("worker-exists=" + File.Exists(Path.Combine(Root, "UltimatePerformanceRefresh.ps1")));
        sb.AppendLine("runner-exists=" + File.Exists(Path.Combine(Root, "Run-UltimatePerformanceRefresh.ps1")));
        sb.AppendLine("snapshot=" + Fmt(Snapshot.Capture()));
        Console.Write(sb.ToString());
        return sb.ToString().IndexOf("task-query-exit=0", StringComparison.OrdinalIgnoreCase) >= 0 ? 0 : 2;
    }
}

internal sealed class ProgressForm : Form
{
    private TextBox box;
    private ProgressBar bar;
    private Label status;
    private Button close;
    private Timer timer;
    private Snapshot before;
    private DateTime start;
    private bool finished;
    private string last = "";

    public ProgressForm()
    {
        Text = "Mich Rebootless Windows Performance Maximizer - live progress";
        Width = 1120;
        Height = 790;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        Font = new Font("Segoe UI", 9F);

        status = new Label();
        status.Left = 12;
        status.Top = 12;
        status.Width = 1070;
        status.Height = 28;
        status.Text = "Preparing <=15s no-app-close Windows refresh: memory, network, shell, graphics, app caches, WMI, storage, and power.";
        status.Font = new Font("Segoe UI", 10F, FontStyle.Bold);

        bar = new ProgressBar();
        bar.Left = 12;
        bar.Top = 45;
        bar.Width = 1075;
        bar.Height = 22;
        bar.Style = ProgressBarStyle.Marquee;
        bar.MarqueeAnimationSpeed = 22;

        box = new TextBox();
        box.Left = 12;
        box.Top = 78;
        box.Width = 1075;
        box.Height = 625;
        box.Multiline = true;
        box.ScrollBars = ScrollBars.Both;
        box.WordWrap = false;
        box.ReadOnly = true;
        box.Font = new Font("Consolas", 9F);

        close = new Button();
        close.Left = 12;
        close.Top = 715;
        close.Width = 125;
        close.Height = 30;
        close.Text = "Close";
        close.Enabled = false;
        close.Click += delegate { Close(); };

        Controls.Add(status);
        Controls.Add(bar);
        Controls.Add(box);
        Controls.Add(close);
        Shown += delegate { BeginRun(); };
    }

    private void BeginRun()
    {
        start = DateTime.Now;
        before = Snapshot.Capture();
        Append("BEFORE: " + Program.Fmt(before));
        Append("");
        Append("Launching elevated scheduled task: " + Program.TaskName);
        Append("Hard worker budget: " + Program.WorkerBudgetSeconds.ToString(CultureInfo.InvariantCulture) + " seconds.");
        try { if (File.Exists(Program.ScriptLog)) File.Delete(Program.ScriptLog); } catch { }
        Append("Scheduled task query exit: " + Program.QueryTask());
        Append("Scheduled task launch exit: " + Program.RunTask());

        timer = new Timer();
        timer.Interval = 500;
        timer.Tick += delegate { Tick(); };
        timer.Start();
    }

    private void Tick()
    {
        string text = "";
        try { if (File.Exists(Program.ScriptLog)) text = File.ReadAllText(Program.ScriptLog); } catch { }

        if (!text.Equals(last, StringComparison.Ordinal))
        {
            box.Text = "BEFORE: " + Program.Fmt(before) + Environment.NewLine + Environment.NewLine + "LIVE EXACT ACTION LOG:" + Environment.NewLine + text;
            box.SelectionStart = box.TextLength;
            box.ScrollToCaret();
            last = text;
            status.Text = "Running refresh... " + EstimatePhase(text) + " elapsed=" + (int)(DateTime.Now - start).TotalSeconds + "s";
        }

        if (text.IndexOf("END ", StringComparison.OrdinalIgnoreCase) >= 0 && !finished) Finish(text, false);
        if ((DateTime.Now - start).TotalSeconds > 22 && !finished) Finish(text + Environment.NewLine + "TIMEOUT waiting for END within app budget", true);
    }

    private static string EstimatePhase(string text)
    {
        int steps = 0;
        using (StringReader sr = new StringReader(text ?? ""))
        {
            string line;
            while ((line = sr.ReadLine()) != null) if (line.IndexOf(" STEP ", StringComparison.OrdinalIgnoreCase) >= 0) steps++;
        }
        return "steps=" + steps.ToString(CultureInfo.InvariantCulture);
    }

    private void Finish(string live, bool timeout)
    {
        finished = true;
        if (timer != null) timer.Stop();
        Snapshot after = Snapshot.Capture();
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("BEFORE: " + Program.Fmt(before));
        sb.AppendLine("AFTER : " + Program.Fmt(after));
        sb.AppendLine("DIFF  : " + Program.Delta(before, after));
        sb.AppendLine("DURATION: " + (int)(DateTime.Now - start).TotalSeconds + "s");
        sb.AppendLine();
        sb.AppendLine("EXACT ACTION LOG:");
        sb.Append(live);
        box.Text = sb.ToString();
        box.SelectionStart = box.TextLength;
        box.ScrollToCaret();
        status.Text = timeout ? "Timed out waiting for worker END within the <=15s worker contract; partial log is shown." : "Completed. Before/after/diff proof is shown below.";
        bar.Style = ProgressBarStyle.Blocks;
        bar.Value = timeout ? 50 : 100;
        close.Enabled = true;
        TopMost = false;
    }

    private void Append(string s)
    {
        box.AppendText(s + Environment.NewLine);
    }
}
