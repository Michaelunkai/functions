using System.Net;
using System.Security.Cryptography;

namespace CodexPcBridge.Core;

public sealed class BridgeServiceHost : IAsyncDisposable
{
    public const string AgentPipeName = "CodexPcBridge.Agent.v2";
    private static readonly TimeSpan TailnetPollInterval = TimeSpan.FromSeconds(5);

    private readonly string stateRoot;
    private readonly CancellationTokenSource cancellation = new();
    private readonly BridgeMachineIdentity identity;
    private readonly InteractiveAgentServer agentServer;
    private readonly GatewayServer gateway;
    private readonly ProtocolV2RelayClient? relayClient;
    private Task? monitorTask;

    public BridgeServiceHost(
        string stateRoot,
        BridgeServiceSettings? settings = null,
        string pipeName = AgentPipeName)
    {
        this.stateRoot = Path.GetFullPath(stateRoot);
        Settings = settings ?? BridgeServiceSettings.LoadOrCreate(this.stateRoot);
        identity = BridgeMachineIdentity.LoadOrCreate(this.stateRoot);
        BridgeAgentBootstrap.Ensure(identity, this.stateRoot);
        agentServer = new InteractiveAgentServer(pipeName, identity.AgentPipeSecret);
        var gatewaySettings = new GatewaySettings(
            GatewaySettings.CurrentVersion,
            Settings.Port,
            Convert.ToBase64String(identity.GatewaySecret),
            null,
            Settings.TailscaleEnabled,
            InteractiveApprovalRequired: false);
        var runtimeOptions = new BridgeRuntimeOptions(this.stateRoot)
        {
            InteractiveFallbackLocal = false
        };
        gateway = new GatewayServer(
            gatewaySettings,
            runtimeOptions,
            agentServer,
            identity.DeviceId,
            Settings.RelayEnabled ? Settings.RelayUrl : null,
            healthSnapshot: () => new
            {
                ok = true,
                service = "codex-pc-bridge",
                protocolVersion = 2,
                gatewayReady = GatewayReady,
                agentConnected = AgentConnected,
                relayConfigured = Settings.RelayEnabled,
                relayReady = RelayReady,
                shadowMode = Settings.ShadowMode,
                port = Settings.Port
            },
            peerCommand: SendPeerCommandAsync);
        if (Settings.RelayEnabled)
        {
            var processor = gateway.ProtocolV2Processor
                ?? throw new InvalidOperationException(
                    "Protocol v2 processor was not initialized.");
            relayClient = new ProtocolV2RelayClient(
                this.stateRoot,
                identity.DeviceId,
                processor);
        }
    }

    public BridgeServiceSettings Settings { get; }
    public string DeviceId => identity.DeviceId;
    public bool GatewayReady => gateway.IsRunning;
    public bool AgentConnected => agentServer.IsConnected;
    public string? TailnetAddress => gateway.TailnetAddress;
    public bool RelayReady => relayClient?.IsReady == true;

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (GatewayReady)
        {
            return;
        }

        var tailnetAddress = Settings.TailscaleEnabled
            ? GatewaySettings.FindTailnetAddress()?.ToString()
            : null;
        await gateway.StartAsync(tailnetAddress);
        relayClient?.Start();
        monitorTask = Task.Run(() => MonitorTailnetAsync(cancellation.Token), cancellation.Token);
    }

    public async Task WaitForAgentAsync(TimeSpan timeout, CancellationToken cancellationToken) =>
        await agentServer.WaitForConnectionAsync(timeout, cancellationToken);

    private Task<ProtocolV2PeerCommandResult> SendPeerCommandAsync(
        ProtocolV2PeerCommandRequest request,
        CancellationToken cancellationToken) =>
        relayClient?.SendRequestAsync(request, cancellationToken)
        ?? Task.FromException<ProtocolV2PeerCommandResult>(
            new ProtocolV2Exception(
                "relay_not_ready",
                "The encrypted relay client is not enabled."));

    public string CreateLegacyPairingJson(string host) =>
        new GatewaySettings(
            GatewaySettings.CurrentVersion,
            Settings.Port,
            Convert.ToBase64String(identity.GatewaySecret),
            host,
            Settings.TailscaleEnabled,
            InteractiveApprovalRequired: false)
        .CreatePairingJson(host);

    public async Task StopAsync()
    {
        cancellation.Cancel();
        if (monitorTask is not null)
        {
            try
            {
                await monitorTask;
            }
            catch (OperationCanceledException)
            {
            }
            monitorTask = null;
        }
        await gateway.StopAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        if (relayClient is not null)
        {
            await relayClient.DisposeAsync();
        }
        await gateway.DisposeAsync();
        await agentServer.DisposeAsync();
        CryptographicOperations.ZeroMemory(identity.GatewaySecret);
        CryptographicOperations.ZeroMemory(identity.AgentPipeSecret);
        cancellation.Dispose();
    }

    private async Task MonitorTailnetAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TailnetPollInterval);
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var address = Settings.TailscaleEnabled
                ? GatewaySettings.FindTailnetAddress()?.ToString()
                : null;
            if (!string.Equals(address, gateway.TailnetAddress, StringComparison.Ordinal))
            {
                try
                {
                    await gateway.RestartAsync(address);
                }
                catch (HttpListenerException)
                {
                    // The service stays alive and retries on the next monitor interval.
                }
            }
        }
    }
}
