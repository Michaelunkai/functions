using System.IO.Pipes;
using System.Security.Cryptography;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public interface IInteractiveAgent
{
    bool IsConnected { get; }
    Task<object> ExecuteAsync(JsonElement request, CancellationToken cancellationToken);
}

public sealed class InteractiveAgentServer : IInteractiveAgent, IAsyncDisposable
{
    private readonly string pipeName;
    private readonly byte[] secret;
    private readonly CancellationTokenSource cancellation = new();
    private readonly SemaphoreSlim requestLock = new(1, 1);
    private readonly object connectionLock = new();
    private readonly TaskCompletionSource connectionReady =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Task acceptLoop;
    private PipeConnection? connection;

    public InteractiveAgentServer(string pipeName, byte[] secret)
    {
        if (string.IsNullOrWhiteSpace(pipeName))
        {
            throw new ArgumentException("Pipe name is required.", nameof(pipeName));
        }
        if (secret.Length < 32)
        {
            throw new ArgumentException("Pipe secret must contain at least 32 bytes.", nameof(secret));
        }
        this.pipeName = pipeName;
        this.secret = secret.ToArray();
        acceptLoop = Task.Run(AcceptLoopAsync);
    }

    public bool IsConnected
    {
        get
        {
            lock (connectionLock)
            {
                return connection?.Pipe.IsConnected == true;
            }
        }
    }

    public async Task WaitForConnectionAsync(TimeSpan timeout, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        linked.CancelAfter(timeout);
        await connectionReady.Task.WaitAsync(linked.Token);
    }

    public async Task<object> ExecuteAsync(JsonElement request, CancellationToken cancellationToken)
    {
        await requestLock.WaitAsync(cancellationToken);
        try
        {
            PipeConnection active;
            lock (connectionLock)
            {
                active = connection
                    ?? throw new InvalidOperationException("Interactive user agent is not connected.");
            }

            var requestId = Guid.NewGuid().ToString("N");
            var envelope = JsonSerializer.Serialize(new
            {
                type = "request",
                requestId,
                payload = request
            });
            try
            {
                await active.Writer.WriteLineAsync(envelope.AsMemory(), cancellationToken);
                var line = await active.Reader.ReadLineAsync(cancellationToken);
                if (line is null)
                {
                    throw new IOException("Interactive user agent disconnected.");
                }
                using var response = JsonDocument.Parse(line);
                if (!string.Equals(
                        requestId,
                        response.RootElement.GetProperty("requestId").GetString(),
                        StringComparison.Ordinal))
                {
                    throw new InvalidDataException("Interactive agent response id mismatch.");
                }
                return response.RootElement.GetProperty("body").Clone();
            }
            catch
            {
                ClearConnection(active);
                throw;
            }
        }
        finally
        {
            requestLock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        cancellation.Cancel();
        PipeConnection? active;
        lock (connectionLock)
        {
            active = connection;
            connection = null;
        }
        active?.Dispose();
        try
        {
            await acceptLoop;
        }
        catch (OperationCanceledException)
        {
        }
        requestLock.Dispose();
        cancellation.Dispose();
        CryptographicOperations.ZeroMemory(secret);
    }

    private async Task AcceptLoopAsync()
    {
        while (!cancellation.IsCancellationRequested)
        {
            var pipe = NamedPipeServerStreamAcl.Create(
                pipeName,
                PipeDirection.InOut,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.WriteThrough,
                4096,
                4096,
                CreatePipeSecurity());
            try
            {
                await pipe.WaitForConnectionAsync(cancellation.Token);
                var reader = new StreamReader(pipe, Encoding.UTF8, false, 4096, leaveOpen: true);
                var writer = new StreamWriter(pipe, new UTF8Encoding(false), 4096, leaveOpen: true)
                {
                    AutoFlush = true
                };
                var helloLine = await reader.ReadLineAsync(cancellation.Token);
                if (helloLine is null || !AuthenticateHello(helloLine))
                {
                    await writer.WriteLineAsync("{\"ok\":false,\"error\":\"authentication_failed\"}");
                    reader.Dispose();
                    writer.Dispose();
                    pipe.Dispose();
                    continue;
                }
                await writer.WriteLineAsync("{\"ok\":true,\"protocolVersion\":2}");
                var accepted = new PipeConnection(pipe, reader, writer);
                lock (connectionLock)
                {
                    connection?.Dispose();
                    connection = accepted;
                }
                connectionReady.TrySetResult();

                while (!cancellation.IsCancellationRequested && pipe.IsConnected)
                {
                    await Task.Delay(250, cancellation.Token);
                }
                ClearConnection(accepted);
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                pipe.Dispose();
                return;
            }
            catch
            {
                pipe.Dispose();
                await Task.Delay(250, cancellation.Token);
            }
        }
    }

    private static PipeSecurity CreatePipeSecurity()
    {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            PipeAccessRights.ReadWrite,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.NetworkSid, null),
            PipeAccessRights.FullControl,
            AccessControlType.Deny));
        return security;
    }

    private bool AuthenticateHello(string helloLine)
    {
        try
        {
            using var hello = JsonDocument.Parse(helloLine);
            var root = hello.RootElement;
            if (!string.Equals(root.GetProperty("type").GetString(), "hello", StringComparison.Ordinal))
            {
                return false;
            }
            var nonce = root.GetProperty("nonce").GetString();
            var signature = root.GetProperty("signature").GetString();
            return AgentPipeAuthentication.Verify(secret, nonce, signature);
        }
        catch
        {
            return false;
        }
    }

    private void ClearConnection(PipeConnection candidate)
    {
        lock (connectionLock)
        {
            if (ReferenceEquals(connection, candidate))
            {
                connection = null;
            }
        }
        candidate.Dispose();
    }

    private sealed class PipeConnection : IDisposable
    {
        public PipeConnection(NamedPipeServerStream pipe, StreamReader reader, StreamWriter writer)
        {
            Pipe = pipe;
            Reader = reader;
            Writer = writer;
        }

        public NamedPipeServerStream Pipe { get; }
        public StreamReader Reader { get; }
        public StreamWriter Writer { get; }

        public void Dispose()
        {
            Reader.Dispose();
            Writer.Dispose();
            Pipe.Dispose();
        }
    }
}

public sealed class InteractiveAgentClient : IDisposable
{
    private readonly string pipeName;
    private readonly byte[] secret;
    private bool disposed;

    public InteractiveAgentClient(string pipeName, byte[] secret)
    {
        this.pipeName = pipeName;
        this.secret = secret.ToArray();
    }

    public bool IsConnected { get; private set; }
    public event EventHandler<bool>? ConnectionChanged;

    public async Task RunAsync(
        Func<JsonElement, CancellationToken, Task<object>> handler,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous | PipeOptions.WriteThrough);
                await pipe.ConnectAsync(5_000, cancellationToken);
                using var cancellationRegistration = cancellationToken.Register(
                    static state => ((NamedPipeClientStream)state!).Dispose(),
                    pipe);
                using var reader = new StreamReader(pipe, Encoding.UTF8, false, 4096, leaveOpen: true);
                using var writer = new StreamWriter(pipe, new UTF8Encoding(false), 4096, leaveOpen: true)
                {
                    AutoFlush = true
                };
                var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
                await writer.WriteLineAsync(JsonSerializer.Serialize(new
                {
                    type = "hello",
                    nonce,
                    signature = AgentPipeAuthentication.Sign(secret, nonce)
                }));
                var acknowledgement = await reader.ReadLineAsync(cancellationToken);
                if (acknowledgement is null)
                {
                    throw new IOException("Service closed the agent pipe.");
                }
                using (var acknowledgementDocument = JsonDocument.Parse(acknowledgement))
                {
                    if (!acknowledgementDocument.RootElement.GetProperty("ok").GetBoolean())
                    {
                        throw new UnauthorizedAccessException("Service rejected the agent handshake.");
                    }
                }
                SetConnected(true);

                while (!cancellationToken.IsCancellationRequested && pipe.IsConnected)
                {
                    var line = await reader.ReadLineAsync(cancellationToken);
                    if (line is null)
                    {
                        break;
                    }
                    using var request = JsonDocument.Parse(line);
                    var requestId = request.RootElement.GetProperty("requestId").GetString()
                        ?? throw new InvalidDataException("Missing interactive request id.");
                    object body;
                    try
                    {
                        body = await handler(
                            request.RootElement.GetProperty("payload").Clone(),
                            cancellationToken);
                    }
                    catch (Exception exception)
                    {
                        body = new
                        {
                            ok = false,
                            error = exception.Message,
                            errorCode = "interactive_action_failed"
                        };
                    }
                    await writer.WriteLineAsync(JsonSerializer.Serialize(new
                    {
                        type = "response",
                        requestId,
                        body
                    }));
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                SetConnected(false);
                return;
            }
            catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested)
            {
                SetConnected(false);
                return;
            }
            catch (IOException) when (cancellationToken.IsCancellationRequested)
            {
                SetConnected(false);
                return;
            }
            catch
            {
                SetConnected(false);
                await Task.Delay(500, cancellationToken);
            }
            finally
            {
                SetConnected(false);
            }
        }
    }

    private void SetConnected(bool connected)
    {
        if (IsConnected == connected)
        {
            return;
        }
        IsConnected = connected;
        ConnectionChanged?.Invoke(this, connected);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        SetConnected(false);
        CryptographicOperations.ZeroMemory(secret);
    }
}

internal static class AgentPipeAuthentication
{
    public static string Sign(byte[] secret, string nonce)
    {
        using var hmac = new HMACSHA256(secret);
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes("agent-v2\n" + nonce)))
            .ToLowerInvariant();
    }

    public static bool Verify(byte[] secret, string? nonce, string? signature)
    {
        if (string.IsNullOrWhiteSpace(nonce)
            || nonce.Length is < 32 or > 128
            || !nonce.All(Uri.IsHexDigit)
            || string.IsNullOrWhiteSpace(signature)
            || signature.Length != 64
            || !signature.All(Uri.IsHexDigit))
        {
            return false;
        }
        var expected = Convert.FromHexString(Sign(secret, nonce));
        var supplied = Convert.FromHexString(signature);
        return CryptographicOperations.FixedTimeEquals(expected, supplied);
    }
}
