using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class PurgeUnrestrictedLocalAI
{
    private static string Quote(string value)
    {
        StringBuilder quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char character in value)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', (backslashes * 2) + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }
            quoted.Append('\\', backslashes);
            quoted.Append(character);
            backslashes = 0;
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    private static string PowerShellPath()
    {
        string windows = Environment.GetEnvironmentVariable("WINDIR") ?? @"C:\Windows";
        string candidate = Path.Combine(
            windows,
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe"
        );
        return File.Exists(candidate) ? candidate : "powershell.exe";
    }

    public static int Main(string[] args)
    {
        try
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            string packageRoot = AppDomain.CurrentDomain.BaseDirectory;
            string purgeScript = Path.Combine(packageRoot, "purge_agent.ps1");
            if (!File.Exists(purgeScript))
            {
                Console.Error.WriteLine("Purge payload is missing: " + purgeScript);
                return 2;
            }

            Console.WriteLine("Unrestricted Local AI purge");
            Console.WriteLine("Payload: " + purgeScript);
            Console.WriteLine("Only a verified deployment root and its binding state can be removed.");

            StringBuilder arguments = new StringBuilder();
            arguments.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File ");
            arguments.Append(Quote(purgeScript));
            foreach (string argument in args)
            {
                arguments.Append(" ");
                arguments.Append(Quote(argument));
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = PowerShellPath();
            startInfo.Arguments = arguments.ToString();
            startInfo.WorkingDirectory = packageRoot;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = false;

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                Console.WriteLine("Purge exit code: " + process.ExitCode);
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("Purge failed: " + exception.Message);
            return 1;
        }
    }
}
