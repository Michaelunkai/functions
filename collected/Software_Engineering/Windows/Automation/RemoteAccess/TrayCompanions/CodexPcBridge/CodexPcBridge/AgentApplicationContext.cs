using CodexPcBridge.Core;
using System.Diagnostics;

namespace CodexPcBridge;

internal sealed class AgentApplicationContext : ApplicationContext
{
    private readonly string userStateRoot;
    private readonly BridgeAgentCredential credential;
    private readonly BridgeCommandDispatcher dispatcher;
    private readonly InteractiveAgentClient client;
    private readonly CancellationTokenSource cancellation = new();
    private readonly Task agentTask;
    private readonly NotifyIcon trayIcon;
    private readonly System.Drawing.Icon inactiveIcon;
    private readonly System.Drawing.Icon connectedIcon;
    private readonly ToolStripMenuItem connectionItem;
    private readonly SynchronizationContext uiContext;

    public AgentApplicationContext(
        string userStateRoot,
        string machineStateRoot,
        string pipeName)
    {
        this.userStateRoot = Path.GetFullPath(userStateRoot);
        credential = BridgeAgentCredential.LoadOrProvisionFromBootstrap(
            this.userStateRoot,
            machineStateRoot);
        dispatcher = new BridgeCommandDispatcher(
            new BridgeRuntimeOptions(Path.Combine(this.userStateRoot, "agent-state"))
            {
                InteractiveFallbackLocal = true
            });
        client = new InteractiveAgentClient(pipeName, credential.PipeSecret);
        uiContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        client.ConnectionChanged += OnConnectionChanged;

        connectionItem = new ToolStripMenuItem { Enabled = false };
        var menu = new ContextMenuStrip();
        menu.Items.Add(connectionItem);
        menu.Items.Add(new ToolStripMenuItem("Show agent status", null, (_, _) => ShowStatus()));
        menu.Items.Add(new ToolStripMenuItem("Open activity log", null, (_, _) => OpenActivityLog()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Exit tray agent", null, (_, _) => ExitThread()));

        inactiveIcon = LoadExecutableIcon();
        connectedIcon = LoadConnectedIcon();
        trayIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = inactiveIcon,
            Text = "Codex PC Bridge agent | connecting",
            Visible = true
        };
        trayIcon.DoubleClick += (_, _) => ShowStatus();
        RefreshStatus();
        agentTask = Task.Run(
            () => client.RunAsync(ExecuteInteractiveAsync, cancellation.Token),
            cancellation.Token);
        BridgeAuditLog.Write($"Interactive tray agent started; device={credential.DeviceId}.");
    }

    protected override void ExitThreadCore()
    {
        cancellation.Cancel();
        try
        {
            agentTask.Wait(TimeSpan.FromSeconds(5));
        }
        catch (AggregateException exception)
            when (exception.InnerExceptions.All(inner => inner is OperationCanceledException))
        {
        }
        client.ConnectionChanged -= OnConnectionChanged;
        client.Dispose();
        dispatcher.DisposeAsync().AsTask().GetAwaiter().GetResult();
        cancellation.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        inactiveIcon.Dispose();
        connectedIcon.Dispose();
        BridgeAuditLog.Write("Interactive tray agent stopped.");
        base.ExitThreadCore();
    }

    private async Task<object> ExecuteInteractiveAsync(
        System.Text.Json.JsonElement request,
        CancellationToken cancellationToken)
    {
        var result = await dispatcher.ExecuteAsync(request, cancellationToken);
        return result.Body;
    }

    private void OnConnectionChanged(object? sender, bool connected) =>
        uiContext.Post(_ => RefreshStatus(), null);

    private void RefreshStatus()
    {
        var connected = client.IsConnected;
        connectionItem.Text = connected
            ? "Service connection: connected"
            : "Service connection: reconnecting";
        trayIcon.Icon = connected ? connectedIcon : inactiveIcon;
        trayIcon.Text = connected
            ? "Codex PC Bridge agent | connected"
            : "Codex PC Bridge agent | reconnecting";
    }

    private void ShowStatus()
    {
        var status = client.IsConnected
            ? "Connected to the SYSTEM service. User-session actions and mapped drives are available."
            : "Waiting for the SYSTEM service. Reconnection is automatic.";
        trayIcon.ShowBalloonTip(5000, "Codex PC Bridge", status, ToolTipIcon.Info);
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

    private static System.Drawing.Icon LoadExecutableIcon()
    {
        using var icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        return icon is null
            ? (System.Drawing.Icon)SystemIcons.Shield.Clone()
            : (System.Drawing.Icon)icon.Clone();
    }

    private static System.Drawing.Icon LoadConnectedIcon()
    {
        const string resourceName = "CodexPcBridge.Assets.codex-pc-bridge-connected.ico";
        using var stream = typeof(AgentApplicationContext).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing tray icon resource: {resourceName}");
        return new System.Drawing.Icon(stream);
    }
}
