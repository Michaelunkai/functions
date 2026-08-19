using System.Diagnostics;

static string FindProjectRoot()
{
    var dir = AppContext.BaseDirectory;
    for (var i = 0; i < 8; i++)
    {
        var up = string.Concat(Enumerable.Repeat("..\\", i));
        var candidate = Path.GetFullPath(Path.Combine(dir, up));
        var script = Path.Combine(candidate, "scripts", "Start-ZeroTouchMainWindows11.ps1");
        if (File.Exists(script))
        {
            return candidate.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
    }
    var fallback = @"F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\zero-touch-main-windows11";
    if (File.Exists(Path.Combine(fallback, "scripts", "Start-ZeroTouchMainWindows11.ps1")))
    {
        return fallback;
    }
    throw new FileNotFoundException("Could not locate scripts\\Start-ZeroTouchMainWindows11.ps1");
}

var root = FindProjectRoot();
var scriptPath = Path.Combine(root, "scripts", "Start-ZeroTouchMainWindows11.ps1");
var ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
if (!File.Exists(ps)) { ps = "powershell.exe"; }
var passThrough = args.Length == 0 ? "-AutoReboot" : string.Join(" ", args.Select(a => "\"" + a.Replace("\"", "\\\"") + "\""));
var psi = new ProcessStartInfo
{
    FileName = ps,
    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" {passThrough}",
    UseShellExecute = false,
    WorkingDirectory = root
};
using var process = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start PowerShell launcher.");
process.WaitForExit();
return process.ExitCode;
