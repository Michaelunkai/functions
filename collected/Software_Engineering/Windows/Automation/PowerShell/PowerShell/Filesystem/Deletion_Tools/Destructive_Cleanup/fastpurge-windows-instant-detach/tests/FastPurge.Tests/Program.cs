using System;
using System.Diagnostics;
using System.IO;
using Hermes.FastPurge;

internal static class Tests
{
    private static string root;

    private static int Main()
    {
        root = Path.Combine(Path.GetTempPath(), "fastpurge-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            TestRejectsUnsafeRoots();
            TestRejectsProtectedDescendantsAndWorkerBypass();
            TestRejectsTopLevelJunctionTargets();
            TestFastDetachRemovesOriginalPathAndWorkerDeletesGraveyard();
            TestMultipleFoldersAreDetached();
            TestReadonlyFilesArePurged();
            Console.WriteLine("ALL TESTS PASSED");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
        finally
        {
            TryDelete(root);
        }
    }

    private static void TestRejectsUnsafeRoots()
    {
        Assert(PathSafety.IsUnsafeDeletionTarget(Path.GetPathRoot(Environment.CurrentDirectory)), "drive root must be unsafe");
        Assert(PathSafety.IsUnsafeDeletionTarget(Environment.GetFolderPath(Environment.SpecialFolder.Windows)), "Windows folder must be unsafe");
    }

    private static void TestRejectsProtectedDescendantsAndWorkerBypass()
    {
        var windowsChild = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Temp");
        Assert(PathSafety.IsUnsafeDeletionTarget(windowsChild), "Windows descendants must be unsafe");
        if (Directory.Exists(@"C:\PROGRA~1"))
        {
            Assert(PathSafety.IsUnsafeDeletionTarget(@"C:\PROGRA~1"), "Program Files 8.3 alias must be unsafe");
        }
        if (Directory.Exists(@"C:\PROGRA~2"))
        {
            Assert(PathSafety.IsUnsafeDeletionTarget(@"C:\PROGRA~2"), "Program Files (x86) 8.3 alias must be unsafe");
        }

        var arbitrary = Path.Combine(root, "worker-bypass");
        CreateTree(arbitrary, 1, 0);
        var exit = Cli.Run(new[] { "--worker", arbitrary }, Console.Out, Console.Error);
        Assert(exit != 0, "worker mode must not purge arbitrary folders");
        Assert(Directory.Exists(arbitrary), "worker bypass target should remain");
    }

    private static void TestRejectsTopLevelJunctionTargets()
    {
        var real = Path.Combine(root, "junction-real");
        var link = Path.Combine(root, "junction-link");
        Directory.CreateDirectory(real);
        File.WriteAllText(Path.Combine(real, "sentinel.txt"), "must survive");

        var p = Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/c mklink /J \"" + link + "\" \"" + real + "\"",
            UseShellExecute = false,
            CreateNoWindow = true
        });
        p.WaitForExit();
        if (p.ExitCode != 0 || !Directory.Exists(link))
        {
            Console.WriteLine("SKIP junction test: mklink /J unavailable");
            return;
        }

        Assert(PathSafety.IsDirectoryReparsePoint(link), "junction should be detected as a reparse point");
        var exit = Cli.Run(new[] { "--no-worker", link }, Console.Out, Console.Error);
        Assert(exit != 0, "top-level junction purge should be refused");
        Assert(File.Exists(Path.Combine(real, "sentinel.txt")), "junction target contents must survive");
        TryDelete(link);
    }

    private static void TestFastDetachRemovesOriginalPathAndWorkerDeletesGraveyard()
    {
        var victim = Path.Combine(root, "victim");
        CreateTree(victim, 400, 0);

        var result = PurgePlanner.DetachForBackgroundPurge(victim, root, false);

        Assert(result.OriginalPathGone, "original path should be gone after detach");
        Assert(!Directory.Exists(victim), "victim directory should not exist after detach");
        Assert(Directory.Exists(result.GraveyardPath), "graveyard path should exist before worker purge");

        BackgroundPurger.Purge(result.GraveyardPath, TimeSpan.FromSeconds(20));
        Assert(!Directory.Exists(result.GraveyardPath), "graveyard should be deleted by worker");
    }

    private static void TestMultipleFoldersAreDetached()
    {
        var a = Path.Combine(root, "multi-a");
        var b = Path.Combine(root, "multi-b");
        CreateTree(a, 20, 0);
        CreateTree(b, 20, 0);

        var exit = Cli.Run(new[] { "--no-worker", "--graveyard", root, a, b }, Console.Out, Console.Error);

        Assert(exit == 0, "multi-folder CLI should return success");
        Assert(!Directory.Exists(a), "first folder should be detached");
        Assert(!Directory.Exists(b), "second folder should be detached");
    }

    private static void TestReadonlyFilesArePurged()
    {
        var victim = Path.Combine(root, "readonly-victim");
        CreateTree(victim, 30, 2);

        var result = PurgePlanner.DetachForBackgroundPurge(victim, root, false);
        BackgroundPurger.Purge(result.GraveyardPath, TimeSpan.FromSeconds(20));

        Assert(!Directory.Exists(result.GraveyardPath), "readonly graveyard should be deleted");
    }

    private static void CreateTree(string path, int files, int readonlyEvery)
    {
        Directory.CreateDirectory(path);
        for (var i = 0; i < files; i++)
        {
            var dir = Path.Combine(path, "d" + (i % 10));
            Directory.CreateDirectory(dir);
            var file = Path.Combine(dir, "f" + i + ".bin");
            File.WriteAllBytes(file, new byte[1024]);
            if (readonlyEvery > 0 && i % readonlyEvery == 0)
            {
                File.SetAttributes(file, File.GetAttributes(file) | FileAttributes.ReadOnly);
            }
        }
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void TryDelete(string path)
    {
        if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) return;
        try
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            {
                Directory.Delete(path, false);
                return;
            }
        }
        catch { }

        foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
        {
            try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
        }
        try { Directory.Delete(path, true); } catch { }
    }
}
