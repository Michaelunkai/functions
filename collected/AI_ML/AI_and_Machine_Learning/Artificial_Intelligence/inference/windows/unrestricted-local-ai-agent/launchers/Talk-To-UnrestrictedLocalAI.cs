using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class TalkToUnrestrictedLocalAI
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

    private static string DefaultRoot()
    {
        string profile = Environment.GetEnvironmentVariable("USERPROFILE");
        return Path.Combine(
            profile ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "UnrestrictedAgent"
        );
    }

    private static string PersistedAgentRoot(out bool pointerExists)
    {
        pointerExists = false;
        try
        {
            string programData = Environment.GetEnvironmentVariable("ProgramData");
            if (String.IsNullOrWhiteSpace(programData))
            {
                programData = Environment.GetFolderPath(
                    Environment.SpecialFolder.CommonApplicationData
                );
            }
            if (String.IsNullOrWhiteSpace(programData))
            {
                return null;
            }

            string pointer = Path.Combine(
                programData,
                "UnrestrictedLocalAI",
                "deployment-root.txt"
            );
            if (!File.Exists(pointer))
            {
                return null;
            }
            pointerExists = true;

            string root = File.ReadAllText(pointer).Trim();
            if (String.IsNullOrWhiteSpace(root))
            {
                throw new InvalidDataException(
                    "The recorded local AI deployment root is empty: " + pointer
                );
            }
            return root;
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new InvalidDataException(
                "Unable to read the recorded local AI deployment root.",
                exception
            );
        }
    }

    private static string AgentRoot()
    {
        string configured = Environment.GetEnvironmentVariable("UNRESTRICTED_AGENT_ROOT");
        if (!String.IsNullOrWhiteSpace(configured))
        {
            return configured;
        }

        bool pointerExists;
        string persisted = PersistedAgentRoot(out pointerExists);
        if (pointerExists)
        {
            if (!Directory.Exists(persisted) ||
                !File.Exists(Path.Combine(persisted, "run_agent.ps1")))
            {
                throw new FileNotFoundException(
                    "The recorded local AI deployment is incomplete. Re-run the installer.",
                    persisted
                );
            }
            return persisted;
        }
        return DefaultRoot();
    }

    public static int Main(string[] args)
    {
        try
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            string root = AgentRoot();
            string launcher = Path.Combine(root, "run_agent.ps1");
            if (!File.Exists(launcher))
            {
                string installer = Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory,
                    "Install-UnrestrictedLocalAI.exe"
                );
                Console.Error.WriteLine("The local AI is not installed at: " + root);
                Console.Error.WriteLine("Run the installer first: " + installer);
                return 2;
            }

            Console.WriteLine("Starting Unrestricted Local AI from: " + root);
            StringBuilder arguments = new StringBuilder();
            arguments.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File ");
            arguments.Append(Quote(launcher));
            foreach (string argument in args)
            {
                arguments.Append(" ");
                arguments.Append(Quote(argument));
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = PowerShellPath();
            startInfo.Arguments = arguments.ToString();
            startInfo.WorkingDirectory = root;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = false;

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("Interactive launcher failed: " + exception.Message);
            return 1;
        }
    }
}
