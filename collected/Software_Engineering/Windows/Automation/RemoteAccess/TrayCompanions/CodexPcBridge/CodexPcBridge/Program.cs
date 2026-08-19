using CodexPcBridge.Core;
using System.Diagnostics;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace CodexPcBridge;

internal static class Program
{
    private const string SingleInstanceMutexName = @"Local\CodexPcBridge.SingleInstance";
    private const string AgentMutexName = @"Local\CodexPcBridge.Agent.SingleInstance";
    private const string AgentFatalNoPopupMarker = "CODEX_PC_BRIDGE_AGENT_FATAL_NO_POPUP_V1";

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Any(argument => string.Equals(argument, "--service", StringComparison.OrdinalIgnoreCase))
            || args.Any(argument => string.Equals(argument, "--service-console", StringComparison.OrdinalIgnoreCase)))
        {
            return WindowsServiceMode.Run(args);
        }

        if (args.Any(argument => string.Equals(argument, "--provision-agent", StringComparison.OrdinalIgnoreCase)))
        {
            var machineRoot = GetArgument(args, "--machine-state-root") ?? BridgePaths.MachineStateRoot;
            var userRoot = GetArgument(args, "--user-state-root") ?? BridgeAgentCredential.DefaultStateRoot;
            BridgeAgentCredential.LoadOrProvisionFromBootstrap(userRoot, machineRoot);
            return 0;
        }

        if (args.Length == 2 && string.Equals(args[0], "--export-pairing", StringComparison.OrdinalIgnoreCase))
        {
            var settings = GatewaySettings.LoadOrCreate();
            var host = GatewaySettings.FindTailnetAddress()?.ToString()
                ?? throw new InvalidOperationException("No active Tailscale address is available.");
            var destination = Path.GetFullPath(args[1]);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.WriteAllText(destination, settings.CreatePairingJson(host));
            return 0;
        }

        var agentMode = args.Any(argument => string.Equals(argument, "--agent", StringComparison.OrdinalIgnoreCase));
        var mutexName = agentMode ? AgentMutexName : SingleInstanceMutexName;
        using var singleInstanceMutex = new Mutex(true, mutexName, out var ownsMutex);
        if (!ownsMutex)
        {
            return 0;
        }

        try
        {
            ApplicationConfiguration.Initialize();
            using ApplicationContext context = agentMode
                ? new AgentApplicationContext(
                    GetArgument(args, "--user-state-root") ?? BridgeAgentCredential.DefaultStateRoot,
                    GetArgument(args, "--machine-state-root") ?? BridgePaths.MachineStateRoot,
                    GetArgument(args, "--pipe-name") ?? BridgeServiceHost.AgentPipeName)
                : new BridgeApplicationContext();
            Application.Run(context);
            return 0;
        }
        catch (Exception exception)
        {
            if (agentMode)
            {
                try
                {
                    BridgeAuditLog.Write(
                        $"{AgentFatalNoPopupMarker} type={exception.GetType().FullName}.");
                }
                catch
                {
                    // Automatic agent startup must fail closed without opening UI.
                }
                return 1;
            }
            MessageBox.Show(
                exception.Message,
                "Codex PC Bridge",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            singleInstanceMutex.ReleaseMutex();
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
}

internal static class BridgePaths
{
    public static string MachineStateRoot =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "CodexPcBridge");
}

internal sealed class BridgeApplicationContext : ApplicationContext
{
    private const int WaitingForTailnetIntervalMs = 1_000;
    private const int ConnectedTailnetIntervalMs = 15_000;
    private const int ServerStartAttempts = 20;
    private const int ServerStartRetryDelayMs = 250;

    private GatewaySettings settings;
    private GatewayServer server;
    private readonly NotifyIcon trayIcon;
    private readonly System.Drawing.Icon inactiveIcon;
    private readonly System.Drawing.Icon connectedIcon;
    private readonly ToolStripMenuItem elevationItem;
    private readonly ToolStripMenuItem tailnetItem;
    private readonly SynchronizationContext uiContext;
    private readonly System.Windows.Forms.Timer tailnetMonitor;
    private readonly BridgeCommandDispatcher interactiveDispatcher;
    private readonly InteractiveAgentClient interactiveClient;
    private readonly CancellationTokenSource interactiveCancellation = new();
    private readonly Task interactiveAgentTask;
    private readonly ScheduledTaskSupervisor gatewaySupervisor;
    private readonly ScheduledTaskSupervisor controlPlaneSupervisor;
    private bool agentConnected;
    private bool tailnetRebinding;

    public BridgeApplicationContext()
    {
        uiContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        settings = GatewaySettings.LoadOrCreate();
        settings = ResolveTailnetSettings(settings);
        settings.Save();
        server = new GatewayServer(settings);
        StartServerWithRetry();
        server.AuthenticatedRequestAccepted += OnAuthenticatedRequestAccepted;
        server.AuthenticatedActionRequested += OnAuthenticatedActionRequested;
        var credential = BridgeAgentCredential.LoadOrProvisionFromBootstrap(
            BridgeAgentCredential.DefaultStateRoot,
            BridgePaths.MachineStateRoot);
        interactiveDispatcher = new BridgeCommandDispatcher(
            new BridgeRuntimeOptions(
                Path.Combine(BridgeAgentCredential.DefaultStateRoot, "agent-state"))
            {
                InteractiveFallbackLocal = true
            });
        interactiveClient = new InteractiveAgentClient(
            BridgeServiceHost.AgentPipeName,
            credential.PipeSecret);
        interactiveClient.ConnectionChanged += OnInteractiveConnectionChanged;
        interactiveAgentTask = Task.Run(
            () => interactiveClient.RunAsync(
                ExecuteInteractiveAsync,
                interactiveCancellation.Token),
            interactiveCancellation.Token);
        gatewaySupervisor = new ScheduledTaskSupervisor(@"\CodexAutonomyGateway");
        gatewaySupervisor.Start();
        controlPlaneSupervisor = new ScheduledTaskSupervisor(@"\CodexControlPlaneAgent");
        controlPlaneSupervisor.Start();
        BridgeAuditLog.Write($"Bridge started on port {settings.Port}; tailnet={server.TailnetAddress ?? "disabled"}; elevated={IsElevated()}.");

        elevationItem = new ToolStripMenuItem();
        tailnetItem = new ToolStripMenuItem();
        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Copy pairing JSON", null, (_, _) => CopyPairing()));
        menu.Items.Add(new ToolStripMenuItem("Show bridge status", null, (_, _) => ShowStatus()));
        menu.Items.Add(new ToolStripMenuItem("Open activity log", null, (_, _) => OpenActivityLog()));
        menu.Items.Add(tailnetItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(elevationItem);
        menu.Items.Add(new ToolStripMenuItem("Exit", null, (_, _) => ExitThread()));

        inactiveIcon = LoadExecutableIcon();
        connectedIcon = LoadConnectedIcon();
        trayIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = inactiveIcon,
            Text = "Codex PC Bridge",
            Visible = true
        };
        trayIcon.DoubleClick += (_, _) => CopyPairing();
        tailnetMonitor = new System.Windows.Forms.Timer
        {
            Interval = server.TailnetAddress is null ? WaitingForTailnetIntervalMs : ConnectedTailnetIntervalMs
        };
        tailnetMonitor.Tick += OnTailnetMonitorTick;
        tailnetMonitor.Start();
        RefreshMenu();
    }

    protected override void ExitThreadCore()
    {
        interactiveCancellation.Cancel();
        try
        {
            interactiveAgentTask.Wait(TimeSpan.FromSeconds(5));
        }
        catch (AggregateException exception)
            when (exception.InnerExceptions.All(inner => inner is OperationCanceledException))
        {
        }
        interactiveClient.ConnectionChanged -= OnInteractiveConnectionChanged;
        interactiveClient.Dispose();
        interactiveDispatcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        interactiveCancellation.Dispose();
        controlPlaneSupervisor.Dispose();
        gatewaySupervisor.Dispose();
        tailnetMonitor.Stop();
        tailnetMonitor.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        inactiveIcon.Dispose();
        connectedIcon.Dispose();
        server.DisposeAsync().AsTask().GetAwaiter().GetResult();
        BridgeAuditLog.Write("Bridge stopped.");
        base.ExitThreadCore();
    }

    private void CopyPairing()
    {
        var host = server.TailnetAddress;
        if (host is null)
        {
            trayIcon.ShowBalloonTip(5000, "Codex PC Bridge", "Enable the private Tailscale endpoint before copying a remote pairing profile.", ToolTipIcon.Warning);
            return;
        }

        Clipboard.SetText(settings.CreatePairingJson(host));
        trayIcon.ShowBalloonTip(3000, "Codex PC Bridge", $"Pairing JSON copied for {host}:{settings.Port}.", ToolTipIcon.Info);
    }

    private void ToggleTailnet()
    {
        var enabled = !settings.TailscaleEnabled;
        var address = enabled ? GatewaySettings.FindTailnetAddress()?.ToString() : null;
        if (enabled && address is null)
        {
            trayIcon.ShowBalloonTip(5000, "Codex PC Bridge", "Tailscale endpoint enabled. It will bind automatically when Tailscale connects.", ToolTipIcon.Info);
        }

        server.RestartAsync(address).GetAwaiter().GetResult();
        settings = settings with { TailscaleEnabled = enabled, TailnetAddress = address };
        settings.Save();
        BridgeAuditLog.Write($"Tailscale endpoint enabled={enabled}; address={address ?? "waiting"}.");
        RefreshMenu();
    }

    private void RestartElevated()
    {
        var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Process path is unavailable.");
        Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true, Verb = "runas" });
        ExitThread();
    }

    private void RefreshMenu()
    {
        tailnetItem.Text = settings.TailscaleEnabled
            ? server.TailnetAddress is null
                ? "Disable Tailscale endpoint (waiting for Tailscale)"
                : $"Disable Tailscale endpoint ({server.TailnetAddress})"
            : "Enable Tailscale endpoint";
        tailnetItem.Click -= OnTailnetClick;
        tailnetItem.Click += OnTailnetClick;

        var elevated = IsElevated();
        elevationItem.Text = elevated ? "Running elevated" : "Restart elevated";
        elevationItem.Enabled = !elevated;
        elevationItem.Click -= OnElevationClick;
        elevationItem.Click += OnElevationClick;
        var state = agentConnected ? "connected" : "waiting";
        trayIcon.Text = $"Codex PC Bridge | {state} | {(elevated ? "elevated" : "standard")} | port {settings.Port}";
    }

    private void ShowStatus()
    {
        var endpoint = server.TailnetAddress ?? "127.0.0.1";
        var state = agentConnected ? "A signed client has connected." : "Waiting for a signed client.";
        trayIcon.ShowBalloonTip(5000, "Codex PC Bridge", $"{state} Endpoint: {endpoint}:{settings.Port}. Authenticated actions run unattended.", ToolTipIcon.Info);
    }

    private static void OpenActivityLog()
    {
        Directory.CreateDirectory(BridgeAuditLog.LogDirectory);
        if (!File.Exists(BridgeAuditLog.LogPath))
        {
            File.WriteAllText(BridgeAuditLog.LogPath, string.Empty);
        }

        Process.Start(new ProcessStartInfo(BridgeAuditLog.LogPath) { UseShellExecute = true });
    }

    private void StartServerWithRetry()
    {
        for (var attempt = 1; attempt <= ServerStartAttempts; attempt++)
        {
            try
            {
                server.StartAsync(settings.TailnetAddress).GetAwaiter().GetResult();
                return;
            }
            catch (HttpListenerException) when (attempt < ServerStartAttempts)
            {
                Thread.Sleep(ServerStartRetryDelayMs);
            }
        }

        throw new HttpListenerException((int)HttpStatusCode.ServiceUnavailable, $"Port {settings.Port} remained unavailable.");
    }

    private async void OnTailnetMonitorTick(object? sender, EventArgs eventArgs)
    {
        if (tailnetRebinding || !settings.TailscaleEnabled)
        {
            return;
        }

        var address = GatewaySettings.FindTailnetAddress()?.ToString();
        if (string.Equals(address, server.TailnetAddress, StringComparison.Ordinal))
        {
            UpdateTailnetMonitorInterval(address);
            return;
        }

        tailnetRebinding = true;
        try
        {
            await server.RestartAsync(address);
            settings = settings with { TailnetAddress = address };
            settings.Save();
            BridgeAuditLog.Write($"Tailscale endpoint rebound to {address ?? "waiting"}.");
            UpdateTailnetMonitorInterval(address);
            RefreshMenu();
        }
        catch (Exception exception)
        {
            BridgeAuditLog.Write($"Tailscale endpoint rebind failed: {exception.Message}");
            UpdateTailnetMonitorInterval(null);
        }
        finally
        {
            tailnetRebinding = false;
        }
    }

    private static GatewaySettings ResolveTailnetSettings(GatewaySettings current) =>
        current with
        {
            TailnetAddress = current.TailscaleEnabled ? GatewaySettings.FindTailnetAddress()?.ToString() : null
        };

    private void UpdateTailnetMonitorInterval(string? address)
    {
        var interval = settings.TailscaleEnabled && address is null
            ? WaitingForTailnetIntervalMs
            : ConnectedTailnetIntervalMs;
        if (tailnetMonitor.Interval != interval)
        {
            tailnetMonitor.Interval = interval;
        }
    }

    private void OnTailnetClick(object? sender, EventArgs eventArgs) => ToggleTailnet();
    private void OnElevationClick(object? sender, EventArgs eventArgs) => RestartElevated();
    private void OnAuthenticatedRequestAccepted(object? sender, EventArgs eventArgs) => uiContext.Post(_ => MarkAgentConnected(), null);
    private void OnAuthenticatedActionRequested(object? sender, GatewayActionRequest request) => BridgeAuditLog.Write($"Authenticated request: action={request.Action}; summary={request.Summary}.");
    private void OnInteractiveConnectionChanged(object? sender, bool connected) =>
        uiContext.Post(_ =>
        {
            agentConnected = connected;
            trayIcon.Icon = connected ? connectedIcon : inactiveIcon;
            RefreshMenu();
        }, null);

    private async Task<object> ExecuteInteractiveAsync(
        System.Text.Json.JsonElement request,
        CancellationToken cancellationToken)
    {
        var result = await interactiveDispatcher.ExecuteAsync(request, cancellationToken);
        return result.Body;
    }

    private void MarkAgentConnected()
    {
        if (agentConnected)
        {
            return;
        }

        agentConnected = true;
        trayIcon.Icon = connectedIcon;
        RefreshMenu();
    }

    private static System.Drawing.Icon LoadExecutableIcon()
    {
        using var icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        return icon is null ? (System.Drawing.Icon)SystemIcons.Shield.Clone() : (System.Drawing.Icon)icon.Clone();
    }

    private static System.Drawing.Icon LoadConnectedIcon()
    {
        const string resourceName = "CodexPcBridge.Assets.codex-pc-bridge-connected.ico";
        using var stream = typeof(BridgeApplicationContext).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing tray icon resource: {resourceName}");
        return new System.Drawing.Icon(stream);
    }

    private static bool IsElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
}

internal sealed class ScheduledTaskSupervisor : IDisposable
{
    private const int SupervisionIntervalMs = 30_000;
    private const int TaskSchedulerStateQueued = 2;
    private const int TaskSchedulerStateRunning = 4;
    private readonly string taskName;
    private readonly System.Windows.Forms.Timer timer;
    private int launchInProgress;
    private bool disposed;
    private bool? lastLaunchSucceeded;

    public ScheduledTaskSupervisor(string taskName)
    {
        this.taskName = taskName;
        timer = new System.Windows.Forms.Timer { Interval = SupervisionIntervalMs };
        timer.Tick += OnTimerTick;
    }

    public void Start()
    {
        _ = EnsureRunningAsync();
        timer.Start();
    }

    public void Dispose()
    {
        disposed = true;
        timer.Stop();
        timer.Tick -= OnTimerTick;
        timer.Dispose();
    }

    private void OnTimerTick(object? sender, EventArgs eventArgs) => _ = EnsureRunningAsync();

    private async Task EnsureRunningAsync()
    {
        if (disposed || Interlocked.Exchange(ref launchInProgress, 1) != 0)
        {
            return;
        }

        try
        {
            var active = await Task.Run(IsScheduledTaskActive);
            var succeeded = active || await Task.Run(StartScheduledTask);
            if (lastLaunchSucceeded != succeeded)
            {
                BridgeAuditLog.Write(
                    succeeded
                        ? $"Production control-plane task supervision active: {taskName}."
                        : $"Production control-plane task supervision failed: {taskName}.");
                lastLaunchSucceeded = succeeded;
            }
        }
        finally
        {
            Interlocked.Exchange(ref launchInProgress, 0);
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

    private static void ReleaseComObject(object? value)
    {
        if (value is not null && Marshal.IsComObject(value))
        {
            Marshal.FinalReleaseComObject(value);
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
}
