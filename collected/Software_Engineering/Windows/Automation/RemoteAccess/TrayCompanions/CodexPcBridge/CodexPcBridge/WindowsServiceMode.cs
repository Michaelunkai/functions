using CodexPcBridge.Core;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.ServiceProcess;

namespace CodexPcBridge;

internal static class WindowsServiceMode
{
    internal const string ServiceName = "CodexPcBridgeV2";
    internal const string FailureLogMarker = "CODEX_PC_BRIDGE_SERVICE_FAILURE_LOG_V1";

    public static int Run(string[] args)
    {
        var stateRoot = GetArgument(args, "--state-root") ?? BridgePaths.MachineStateRoot;
        if (args.Any(argument =>
                string.Equals(argument, "--service-console", StringComparison.OrdinalIgnoreCase)))
        {
            return RunConsoleAsync(args, stateRoot).GetAwaiter().GetResult();
        }

        ServiceBase.Run(new CodexPcBridgeWindowsService(stateRoot));
        return 0;
    }

    private static async Task<int> RunConsoleAsync(string[] args, string stateRoot)
    {
        var port = TryGetIntArgument(args, "--port");
        var runForSeconds = TryGetIntArgument(args, "--run-for-seconds");
        using var cancellation = new CancellationTokenSource();
        if (runForSeconds is > 0)
        {
            cancellation.CancelAfter(TimeSpan.FromSeconds(runForSeconds.Value));
        }
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            cancellation.Cancel();
        };

        try
        {
            await BridgeServiceLoop.RunAsync(
                stateRoot,
                portOverride: port,
                superviseTray: false,
                cancellationToken: cancellation.Token);
            return 0;
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            return 0;
        }
        catch (Exception exception)
        {
            ServiceLog.Write(
                stateRoot,
                $"{FailureLogMarker} stage=console type={exception.GetType().FullName}.");
            Console.Error.WriteLine(exception);
            return 1;
        }
    }

    private static string? GetArgument(string[] args, string name)
    {
        for (var index = 0; index < args.Length - 1; index++)
        {
            if (string.Equals(args[index], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[index + 1];
            }
        }
        return null;
    }

    private static int? TryGetIntArgument(string[] args, string name) =>
        int.TryParse(GetArgument(args, name), out var value) ? value : null;
}

internal sealed class CodexPcBridgeWindowsService : ServiceBase
{
    private readonly object lifecycleLock = new();
    private readonly string stateRoot;
    private CancellationTokenSource? cancellation;
    private Task? backgroundTask;

    public CodexPcBridgeWindowsService(string stateRoot)
    {
        this.stateRoot = Path.GetFullPath(stateRoot);
        ServiceName = WindowsServiceMode.ServiceName;
        CanStop = true;
        CanShutdown = true;
        AutoLog = false;
    }

    protected override void OnStart(string[] args)
    {
        lock (lifecycleLock)
        {
            cancellation = new CancellationTokenSource();
            backgroundTask = Task.Run(
                () => BridgeServiceLoop.RunAsync(
                    stateRoot,
                    portOverride: null,
                    superviseTray: true,
                    cancellationToken: cancellation.Token),
                cancellation.Token);
            _ = backgroundTask.ContinueWith(
                task => ServiceLog.Write(
                    stateRoot,
                    $"{WindowsServiceMode.FailureLogMarker} stage=background "
                    + $"type={task.Exception?.GetBaseException().GetType().FullName ?? "unknown"}."),
                CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted,
                TaskScheduler.Default);
        }

        ServiceLog.Write(stateRoot, "SCM start accepted; background initialization scheduled.");
    }

    protected override void OnStop() => StopBackground();
    protected override void OnShutdown() => StopBackground();

    private void StopBackground()
    {
        Task? task;
        lock (lifecycleLock)
        {
            cancellation?.Cancel();
            task = backgroundTask;
        }

        if (task is not null)
        {
            try
            {
                task.Wait(TimeSpan.FromSeconds(15));
            }
            catch (AggregateException exception)
                when (exception.InnerExceptions.All(inner => inner is OperationCanceledException))
            {
            }
        }

        lock (lifecycleLock)
        {
            cancellation?.Dispose();
            cancellation = null;
            backgroundTask = null;
        }
        ServiceLog.Write(stateRoot, "Service stopped.");
    }
}

internal static class BridgeServiceLoop
{
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(2);

    public static async Task RunAsync(
        string stateRoot,
        int? portOverride,
        bool superviseTray,
        CancellationToken cancellationToken)
    {
        var persistedSettings = BridgeServiceSettings.LoadOrCreate(stateRoot);
        var settings = portOverride.HasValue
            ? persistedSettings with { Port = portOverride.Value, ShadowMode = true }
            : persistedSettings;
        Task? traySupervisorTask = null;
        if (superviseTray)
        {
            var traySupervisor = new ServiceScheduledTaskSupervisor(
                @"\CodexPcBridgeTray",
                stateRoot);
            traySupervisorTask = traySupervisor.RunAsync(cancellationToken);
        }

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    await using var host = new BridgeServiceHost(stateRoot, settings);
                    await host.StartAsync(cancellationToken);
                    ServiceLog.Write(
                        stateRoot,
                        $"Gateway ready; device={host.DeviceId}; port={settings.Port}; "
                        + $"tailnet={host.TailnetAddress ?? "waiting"}; shadow={settings.ShadowMode}.");
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception exception)
                {
                    ServiceLog.Write(
                        stateRoot,
                        $"{WindowsServiceMode.FailureLogMarker} stage=initialization "
                        + $"type={exception.GetType().FullName}; "
                        + $"retrySeconds={RetryDelay.TotalSeconds:0}.");
                    await Task.Delay(RetryDelay, cancellationToken);
                }
            }
        }
        finally
        {
            if (traySupervisorTask is not null)
            {
                try
                {
                    await traySupervisorTask;
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                }
            }
        }
    }
}

internal sealed class ServiceScheduledTaskSupervisor
{
    private static readonly TimeSpan SupervisionInterval = TimeSpan.FromSeconds(30);
    private const int TaskSchedulerStateQueued = 2;
    private const int TaskSchedulerStateRunning = 4;

    private readonly string taskName;
    private readonly string stateRoot;
    private bool? lastSucceeded;

    public ServiceScheduledTaskSupervisor(string taskName, string stateRoot)
    {
        this.taskName = taskName;
        this.stateRoot = Path.GetFullPath(stateRoot);
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        await EnsureRunningAsync(cancellationToken);
        using var timer = new PeriodicTimer(SupervisionInterval);
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await EnsureRunningAsync(cancellationToken);
        }
    }

    private async Task EnsureRunningAsync(CancellationToken cancellationToken)
    {
        var active = false;
        var started = false;
        string? failureType = null;
        try
        {
            active = await Task.Run(IsScheduledTaskActive, cancellationToken);
            if (!active)
            {
                started = await Task.Run(StartScheduledTask, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            failureType = exception.GetType().FullName;
        }

        var succeeded = active || started;
        if (started)
        {
            ServiceLog.Write(
                stateRoot,
                $"Scheduled task restarted by service supervision: {taskName}.");
        }
        if (lastSucceeded != succeeded)
        {
            ServiceLog.Write(
                stateRoot,
                succeeded
                    ? $"Scheduled task supervision active: {taskName}."
                    : $"Scheduled task supervision failed: {taskName}; "
                        + $"type={failureType ?? "launch_failed"}.");
            lastSucceeded = succeeded;
        }
    }

    private bool IsScheduledTaskActive()
    {
        object? scheduler = null;
        object? folder = null;
        object? task = null;
        try
        {
            var schedulerType = Type.GetTypeFromProgID("Schedule.Service");
            scheduler = schedulerType is null ? null : Activator.CreateInstance(schedulerType);
            if (scheduler is null)
            {
                return false;
            }

            dynamic schedulerObject = scheduler;
            schedulerObject.Connect();
            folder = schedulerObject.GetFolder(@"\");
            dynamic folderObject = folder;
            task = folderObject.GetTask(taskName);
            dynamic taskObject = task;
            var state = (int)taskObject.State;
            return state is TaskSchedulerStateQueued or TaskSchedulerStateRunning;
        }
        catch (COMException)
        {
            return false;
        }
        finally
        {
            ReleaseComObject(task);
            ReleaseComObject(folder);
            ReleaseComObject(scheduler);
        }
    }

    private bool StartScheduledTask()
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "schtasks.exe"),
            Arguments = $"/Run /TN \"{taskName}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
        if (process is null)
        {
            return false;
        }
        if (!process.WaitForExit(10_000))
        {
            process.Kill(entireProcessTree: true);
            return false;
        }
        return process.ExitCode == 0;
    }

    private static void ReleaseComObject(object? value)
    {
        if (value is not null && Marshal.IsComObject(value))
        {
            Marshal.FinalReleaseComObject(value);
        }
    }
}

internal static class ServiceLog
{
    private const long MaxLogBytes = 1024 * 1024;

    public static void Write(string stateRoot, string message)
    {
        var directory = Path.Combine(Path.GetFullPath(stateRoot), "logs");
        BridgeAuditLog.AppendBounded(
            Path.Combine(directory, "service.log"),
            message,
            MaxLogBytes);
    }
}
