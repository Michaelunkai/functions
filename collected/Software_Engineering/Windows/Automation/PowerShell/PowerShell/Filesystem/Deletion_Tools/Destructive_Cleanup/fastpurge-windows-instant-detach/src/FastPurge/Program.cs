using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;

namespace Hermes.FastPurge
{
    public sealed class DetachResult
    {
        public string OriginalPath { get; private set; }
        public string GraveyardPath { get; private set; }
        public bool OriginalPathGone { get; private set; }
        public TimeSpan Elapsed { get; private set; }

        public DetachResult(string originalPath, string graveyardPath, bool originalPathGone, TimeSpan elapsed)
        {
            OriginalPath = originalPath;
            GraveyardPath = graveyardPath;
            OriginalPathGone = originalPathGone;
            Elapsed = elapsed;
        }
    }

    public static class Program
    {
        public static int Main(string[] args)
        {
            return Cli.Run(args, Console.Out, Console.Error);
        }
    }

    public static class Cli
    {
        public static int Run(string[] args, TextWriter stdout, TextWriter stderr)
        {
            try
            {
                if (args.Length == 0 || args.Contains("--help"))
                {
                    PrintUsage(stdout);
                    return args.Length == 0 ? 2 : 0;
                }

                if (args.Length >= 2 && args[0] == "--worker")
                {
                    if (!PathSafety.IsValidWorkerGraveyard(args[1]))
                    {
                        stderr.WriteLine("REFUSED unsafe worker target: " + args[1]);
                        return 1;
                    }

                    bool completed = BackgroundPurger.Purge(args[1], TimeSpan.FromDays(3650));
                    return completed ? 0 : 1;
                }

                bool launchWorker = true;
                string graveyardRoot = null;
                var targets = new List<string>();
                for (int i = 0; i < args.Length; i++)
                {
                    string arg = args[i];
                    if (arg == "--no-worker")
                    {
                        launchWorker = false;
                    }
                    else if (arg == "--graveyard")
                    {
                        if (i + 1 >= args.Length) throw new ArgumentException("--graveyard requires a folder path");
                        graveyardRoot = args[++i];
                    }
                    else if (arg.StartsWith("--", StringComparison.Ordinal))
                    {
                        throw new ArgumentException("Unknown option: " + arg);
                    }
                    else
                    {
                        targets.Add(arg);
                    }
                }

                if (targets.Count == 0) throw new ArgumentException("No folder target supplied.");

                int failures = 0;
                foreach (string target in targets)
                {
                    if (PathSafety.IsUnsafeDeletionTarget(target))
                    {
                        stderr.WriteLine("REFUSED unsafe target: " + target);
                        failures++;
                        continue;
                    }

                    try
                    {
                        var result = PurgePlanner.DetachForBackgroundPurge(target, graveyardRoot, launchWorker);
                        stdout.WriteLine("DETACHED {0} -> {1} in {2:0.000}s", result.OriginalPath, result.GraveyardPath, result.Elapsed.TotalSeconds);
                    }
                    catch (Exception ex)
                    {
                        stderr.WriteLine("FAILED " + target + ": " + ex.Message);
                        failures++;
                    }
                }

                return failures == 0 ? 0 : 1;
            }
            catch (Exception ex)
            {
                stderr.WriteLine("ERROR: " + ex.Message);
                return 1;
            }
        }

        private static void PrintUsage(TextWriter output)
        {
            output.WriteLine("Usage: app.exe <folder to purge> [more folders]");
            output.WriteLine("Semantics: the original path is detached immediately; deletion continues in a hidden background worker.");
        }
    }

    public static class PurgePlanner
    {
        public static DetachResult DetachForBackgroundPurge(string targetPath, string graveyardRoot, bool launchWorker)
        {
            if (string.IsNullOrWhiteSpace(targetPath)) throw new ArgumentException("Target path is empty.");

            string fullTarget = Path.GetFullPath(targetPath.Trim('"'));
            if (!Directory.Exists(fullTarget)) throw new DirectoryNotFoundException("Folder does not exist: " + fullTarget);
            if (PathSafety.IsUnsafeDeletionTarget(fullTarget)) throw new InvalidOperationException("Unsafe deletion target: " + fullTarget);
            if (PathSafety.IsDirectoryReparsePoint(fullTarget)) throw new InvalidOperationException("Refusing top-level junction/symlink/reparse-point target: " + fullTarget);

            string graveyard = BuildGraveyardPath(fullTarget, graveyardRoot);
            string graveyardParent = Path.GetDirectoryName(graveyard);
            Directory.CreateDirectory(graveyardParent);
            TrySetHidden(graveyardParent);

            EnsureSameVolume(fullTarget, graveyard);

            var sw = Stopwatch.StartNew();
            try { File.SetAttributes(fullTarget, FileAttributes.Normal); } catch { }
            MoveAsideWithRetries(fullTarget, graveyard);
            sw.Stop();

            if (launchWorker)
            {
                WorkerLauncher.Launch(graveyard);
            }

            return new DetachResult(fullTarget, graveyard, !Directory.Exists(fullTarget), sw.Elapsed);
        }

        private static string BuildGraveyardPath(string fullTarget, string graveyardRoot)
        {
            string parent = Path.GetDirectoryName(fullTarget);
            if (string.IsNullOrEmpty(parent)) throw new InvalidOperationException("Target has no parent directory.");

            string root = string.IsNullOrWhiteSpace(graveyardRoot)
                ? Path.Combine(parent, ".fastpurge-graveyard")
                : Path.GetFullPath(graveyardRoot.Trim('"'));

            string name = Path.GetFileName(fullTarget.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            string stamp = DateTime.UtcNow.ToString("yyyyMMddHHmmssfff") + "-" + Guid.NewGuid().ToString("N");
            return Path.Combine(root, name + ".purging." + stamp);
        }

        private static void EnsureSameVolume(string source, string destination)
        {
            string sourceRoot = Path.GetPathRoot(source) ?? string.Empty;
            string destinationRoot = Path.GetPathRoot(destination) ?? string.Empty;
            if (!string.Equals(sourceRoot, destinationRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Graveyard must be on the same drive/volume as the target for instant detach.");
            }
        }

        private static void TrySetHidden(string path)
        {
            try { File.SetAttributes(path, File.GetAttributes(path) | FileAttributes.Hidden); } catch { }
        }

        private static void MoveAsideWithRetries(string source, string destination)
        {
            Exception last = null;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    Directory.Move(source, destination);
                    return;
                }
                catch (Exception ex)
                {
                    last = ex;
                    Thread.Sleep(50 * (attempt + 1));
                }
            }

            throw new IOException("Could not detach folder quickly. A process may hold a non-delete-sharing handle. Last error: " + last.Message, last);
        }

    }

    public static class BackgroundPurger
    {
        public static bool Purge(string graveyardPath, TimeSpan maxDuration)
        {
            if (string.IsNullOrWhiteSpace(graveyardPath) || !Directory.Exists(graveyardPath)) return true;

            DateTime deadline = DateTime.UtcNow.Add(maxDuration);
            if (IsReparsePoint(graveyardPath))
            {
                TryDeleteDirectory(graveyardPath);
                return !Directory.Exists(graveyardPath);
            }

            DeleteChildrenDepthFirst(graveyardPath, deadline);
            TryDeleteDirectory(graveyardPath);
            return !Directory.Exists(graveyardPath) || !Directory.EnumerateFileSystemEntries(graveyardPath).Any();
        }

        private static void DeleteChildrenDepthFirst(string root, DateTime deadline)
        {
            foreach (string childDirectory in SafeChildDirectories(root))
            {
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Purge worker deadline reached.");

                if (IsReparsePoint(childDirectory))
                {
                    TryDeleteDirectory(childDirectory);
                    continue;
                }

                DeleteChildrenDepthFirst(childDirectory, deadline);
                TryDeleteDirectory(childDirectory);
            }

            foreach (string file in SafeChildFiles(root))
            {
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Purge worker deadline reached.");
                TryDeleteFile(file);
            }
        }

        private static IEnumerable<string> SafeChildDirectories(string root)
        {
            try { return Directory.EnumerateDirectories(root).ToArray(); }
            catch { return new string[0]; }
        }

        private static IEnumerable<string> SafeChildFiles(string root)
        {
            try { return Directory.EnumerateFiles(root).ToArray(); }
            catch { return new string[0]; }
        }

        private static bool IsReparsePoint(string path)
        {
            try { return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0; }
            catch { return true; }
        }

        private static void TryDeleteFile(string file)
        {
            try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            try { File.Delete(file); } catch { }
        }

        private static void TryDeleteDirectory(string directory)
        {
            try
            {
                FileAttributes attributes = File.GetAttributes(directory);
                File.SetAttributes(directory, attributes & ~FileAttributes.ReadOnly);
            }
            catch { }

            try { Directory.Delete(directory, false); } catch { }
        }
    }

    public static class WorkerLauncher
    {
        public static void Launch(string graveyardPath)
        {
            string exe = Assembly.GetExecutingAssembly().Location;
            var info = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "--worker " + Quote(graveyardPath),
                CreateNoWindow = true,
                UseShellExecute = false,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            Process.Start(info);
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }

    public static class PathSafety
    {
        public static bool IsUnsafeDeletionTarget(string candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate)) return true;
            string full;
            try { full = Normalize(candidate); }
            catch { return true; }

            string root = (Path.GetPathRoot(full) ?? string.Empty).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (string.Equals(full, root, StringComparison.OrdinalIgnoreCase)) return true;

            string[] exactProtectedPaths =
            {
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            };

            if (exactProtectedPaths
                .Where(p => !string.IsNullOrWhiteSpace(p))
                .Select(Normalize)
                .Any(p => string.Equals(full, p, StringComparison.OrdinalIgnoreCase)))
            {
                return true;
            }

            string[] protectedTrees =
            {
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData)
            };

            return protectedTrees
                .Where(p => !string.IsNullOrWhiteSpace(p))
                .Select(Normalize)
                .Any(p => IsSameOrBelow(full, p));
        }

        public static bool IsValidWorkerGraveyard(string candidate)
        {
            if (IsUnsafeDeletionTarget(candidate)) return false;
            string full;
            try { full = Normalize(candidate); }
            catch { return false; }

            string name = Path.GetFileName(full);
            string parent = Path.GetFileName(Path.GetDirectoryName(full) ?? string.Empty);
            return name.IndexOf(".purging.", StringComparison.OrdinalIgnoreCase) >= 0
                && string.Equals(parent, ".fastpurge-graveyard", StringComparison.OrdinalIgnoreCase);
        }

        public static bool IsDirectoryReparsePoint(string path)
        {
            try { return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0; }
            catch { return true; }
        }

        private static string Normalize(string path)
        {
            string full = Path.GetFullPath(path.Trim('"')).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            return ExpandShortPathNames(full).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static string ExpandShortPathNames(string path)
        {
            var buffer = new StringBuilder(32768);
            int length = GetLongPathName(path, buffer, buffer.Capacity);
            if (length > 0 && length < buffer.Capacity)
            {
                return buffer.ToString();
            }

            return path;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern int GetLongPathName(string shortPath, StringBuilder longPath, int bufferLength);

        private static bool IsSameOrBelow(string full, string protectedRoot)
        {
            return string.Equals(full, protectedRoot, StringComparison.OrdinalIgnoreCase)
                || full.StartsWith(protectedRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                || full.StartsWith(protectedRoot + Path.AltDirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
        }
    }
}
