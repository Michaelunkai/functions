using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class ProtocolV2RelayClient : IAsyncDisposable
{
    private const int MaxFrameBytes = 1024 * 1024;
    private const int MaxPendingDeliveryAcks = 256;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly string stateRoot;
    private readonly ProtocolV2Identity identity;
    private readonly ProtocolV2CommandProcessor processor;
    private readonly CancellationTokenSource cancellation = new();
    private readonly ConcurrentDictionary<string, Task> groupTasks = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, RelayConnection> connections =
        new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<
        string,
        TaskCompletionSource<ProtocolV2PeerCommandResult>> pendingResponses =
        new(StringComparer.Ordinal);
    private int connectedGroups;
    private Task? monitorTask;

    public ProtocolV2RelayClient(
        string stateRoot,
        string deviceId,
        ProtocolV2CommandProcessor processor)
    {
        this.stateRoot = Path.GetFullPath(stateRoot);
        identity = ProtocolV2Identity.LoadOrCreate(this.stateRoot, deviceId);
        this.processor = processor;
    }

    public bool IsRunning => monitorTask is { IsCompleted: false };
    public bool IsReady => Volatile.Read(ref connectedGroups) > 0;

    public void Start()
    {
        if (IsRunning)
        {
            return;
        }
        monitorTask = Task.Run(() => MonitorAsync(cancellation.Token));
    }

    public async Task<ProtocolV2PeerCommandResult> SendRequestAsync(
        ProtocolV2PeerCommandRequest request,
        CancellationToken cancellationToken)
    {
        var prepared = processor.PrepareOutgoing(request);
        if (prepared.CompletedResult is not null)
        {
            return prepared.CompletedResult;
        }
        if (!connections.TryGetValue(prepared.Profile.GroupId, out var connection)
            || connection.Socket.State != WebSocketState.Open)
        {
            throw new ProtocolV2Exception(
                "relay_not_ready",
                "The encrypted relay connection is not ready.");
        }

        var key = ResponseKey(
            prepared.Profile.AndroidIdentity.DeviceId,
            request.Action,
            request.JobId,
            request.IdempotencyKey);
        var created = new TaskCompletionSource<ProtocolV2PeerCommandResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var completion = pendingResponses.GetOrAdd(key, created);
        try
        {
            if (ReferenceEquals(completion, created))
            {
                var node = JsonSerializer.SerializeToNode(
                    prepared.RequestEnvelope,
                    JsonOptions)
                    ?? throw new InvalidDataException(
                        "Could not serialize the peer-command envelope.");
                node["type"] = "envelope";
                await connection.SendAsync(
                    Encoding.UTF8.GetBytes(node.ToJsonString(JsonOptions)),
                    cancellationToken);
            }
            return await completion.Task.WaitAsync(
                TimeSpan.FromSeconds(75),
                cancellationToken);
        }
        catch (TimeoutException)
        {
            throw new ProtocolV2Exception(
                "peer_response_timeout",
                "The Android peer did not return a response before the timeout.");
        }
        finally
        {
            pendingResponses.TryRemove(
                new KeyValuePair<
                    string,
                    TaskCompletionSource<ProtocolV2PeerCommandResult>>(
                    key,
                    completion));
        }
    }

    public async ValueTask DisposeAsync()
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
        }
        identity.Dispose();
        cancellation.Dispose();
    }

    private async Task MonitorAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            foreach (var profile in ProtocolV2RelayRegistration.Load(stateRoot))
            {
                _ = groupTasks.GetOrAdd(
                    profile.GroupId,
                    _ => Task.Run(
                        () => RunGroupAsync(profile, cancellationToken),
                        cancellationToken));
            }
            foreach (var completed in groupTasks.Where(item => item.Value.IsCompleted).ToArray())
            {
                groupTasks.TryRemove(completed.Key, out _);
            }
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
        }
        await Task.WhenAll(groupTasks.Values);
    }

    private async Task RunGroupAsync(
        ProtocolV2RelayProfile profile,
        CancellationToken cancellationToken)
    {
        var delay = TimeSpan.FromSeconds(1);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using var socket = new ClientWebSocket();
                socket.Options.KeepAliveInterval = TimeSpan.FromSeconds(20);
                await socket.ConnectAsync(
                    ConnectUri(profile),
                    cancellationToken);
                var connection = new RelayConnection(socket);
                connections[profile.GroupId] = connection;
                Interlocked.Increment(ref connectedGroups);
                try
                {
                    delay = TimeSpan.FromSeconds(1);
                    await ReceiveLoopAsync(connection, cancellationToken);
                }
                finally
                {
                    connections.TryRemove(
                        new KeyValuePair<string, RelayConnection>(
                            profile.GroupId,
                            connection));
                    Interlocked.Decrement(ref connectedGroups);
                    connection.Dispose();
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception)
            {
                await Task.Delay(delay, cancellationToken);
                delay = TimeSpan.FromSeconds(Math.Min(30, delay.TotalSeconds * 2));
            }
        }
    }

    private async Task ReceiveLoopAsync(
        RelayConnection connection,
        CancellationToken cancellationToken)
    {
        var socket = connection.Socket;
        var buffer = new byte[64 * 1024];
        using var message = new MemoryStream();
        var pendingDeliveryAcks = new Dictionary<string, string>(
            StringComparer.Ordinal);
        while (socket.State == WebSocketState.Open
            && !cancellationToken.IsCancellationRequested)
        {
            var result = await socket.ReceiveAsync(buffer, cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                await socket.CloseOutputAsync(
                    WebSocketCloseStatus.NormalClosure,
                    "reconnect",
                    cancellationToken);
                return;
            }
            if (result.MessageType != WebSocketMessageType.Text)
            {
                throw new InvalidDataException("Relay returned a non-text frame.");
            }
            message.Write(buffer, 0, result.Count);
            if (message.Length > MaxFrameBytes)
            {
                throw new InvalidDataException("Relay frame exceeds the size limit.");
            }
            if (!result.EndOfMessage)
            {
                continue;
            }
            var raw = Encoding.UTF8.GetString(message.GetBuffer(), 0, checked((int)message.Length));
            message.SetLength(0);
            using var document = JsonDocument.Parse(raw);
            if (!document.RootElement.TryGetProperty("type", out var type))
            {
                continue;
            }
            if (type.GetString() == "ack")
            {
                var messageId = document.RootElement.TryGetProperty(
                    "messageId",
                    out var acknowledgedMessage)
                    ? acknowledgedMessage.GetString()
                    : null;
                if (messageId is not null
                    && pendingDeliveryAcks.Remove(
                        messageId,
                        out var deliveredMessageId))
                {
                    await SendDeliveryAcknowledgementAsync(
                        connection,
                        deliveredMessageId,
                        cancellationToken);
                }
                continue;
            }
            if (type.GetString() != "envelope")
            {
                continue;
            }
            var envelope = JsonSerializer.Deserialize<ProtocolV2Envelope>(raw, JsonOptions)
                ?? throw new InvalidDataException("Relay envelope is missing.");
            if (envelope.Capability.EndsWith(".result", StringComparison.Ordinal))
            {
                var peerResult = processor.AcceptOutgoingResponse(envelope);
                var key = ResponseKey(
                    peerResult.PeerDeviceId,
                    peerResult.RequestEnvelope.Capability,
                    peerResult.RequestEnvelope.JobId,
                    peerResult.RequestEnvelope.IdempotencyKey);
                if (pendingResponses.TryGetValue(key, out var completion))
                {
                    completion.TrySetResult(peerResult);
                }
                await SendDeliveryAcknowledgementAsync(
                    connection,
                    envelope.MessageId,
                    cancellationToken);
                continue;
            }

            var response = await processor.ExecuteAsync(envelope, cancellationToken);
            var responseJson = JsonSerializer.SerializeToNode(response, JsonOptions)
                ?? throw new InvalidDataException("Could not serialize relay response.");
            responseJson["type"] = "envelope";
            var bytes = Encoding.UTF8.GetBytes(responseJson.ToJsonString(JsonOptions));
            if (pendingDeliveryAcks.Count >= MaxPendingDeliveryAcks)
            {
                throw new InvalidDataException(
                    "Too many relay responses await durable acknowledgement.");
            }
            pendingDeliveryAcks[response.MessageId] = envelope.MessageId;
            await connection.SendAsync(
                bytes,
                cancellationToken);
        }
    }

    private static async Task SendDeliveryAcknowledgementAsync(
        RelayConnection connection,
        string messageId,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            type = "delivery-ack",
            messageIds = new[] { messageId }
        }, JsonOptions);
        await connection.SendAsync(
            payload,
            cancellationToken);
    }

    private Uri ConnectUri(ProtocolV2RelayProfile profile)
    {
        var relay = new Uri(profile.RelayAddress);
        var builder = new UriBuilder(relay)
        {
            Scheme = relay.Scheme == Uri.UriSchemeHttps ? "wss" : "ws",
            Path = $"/v2/groups/{profile.GroupId}/connect",
            Query = AuthenticationQuery(profile.GroupId)
        };
        return builder.Uri;
    }

    private string AuthenticationQuery(string groupId)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("O");
        var nonce = "nonce-" + Guid.NewGuid().ToString("N");
        var transcript = Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-relay-connect-v1",
            groupId,
            identity.DeviceId,
            timestamp,
            nonce));
        return string.Join(
            "&",
            "deviceId=" + Uri.EscapeDataString(identity.DeviceId),
            "timestamp=" + Uri.EscapeDataString(timestamp),
            "nonce=" + Uri.EscapeDataString(nonce),
            "signature=" + Uri.EscapeDataString(
                Convert.ToBase64String(identity.SignRaw(transcript))));
    }

    private static string ResponseKey(
        string peerDeviceId,
        string action,
        string jobId,
        string idempotencyKey) =>
        string.Join("\n", peerDeviceId, action, jobId, idempotencyKey);

    private sealed class RelayConnection : IDisposable
    {
        private readonly SemaphoreSlim sendLock = new(1, 1);

        public RelayConnection(ClientWebSocket socket)
        {
            Socket = socket;
        }

        public ClientWebSocket Socket { get; }

        public async Task SendAsync(
            ReadOnlyMemory<byte> payload,
            CancellationToken cancellationToken)
        {
            await sendLock.WaitAsync(cancellationToken);
            try
            {
                await Socket.SendAsync(
                    payload,
                    WebSocketMessageType.Text,
                    endOfMessage: true,
                    cancellationToken);
            }
            finally
            {
                sendLock.Release();
            }
        }

        public void Dispose()
        {
            sendLock.Dispose();
        }
    }
}
