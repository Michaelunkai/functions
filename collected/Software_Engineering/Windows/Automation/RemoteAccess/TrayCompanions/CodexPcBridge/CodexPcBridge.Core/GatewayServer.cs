using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class GatewayServer : IAsyncDisposable
{
    private const int MaxBodyBytes = 1024 * 1024;
    internal const int MaxConcurrentRequests = 16;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };
    private readonly GatewaySettings settings;
    private readonly GatewayAuthenticator authenticator;
    private readonly BridgeCommandDispatcher dispatcher;
    private readonly ProtocolV2CommandProcessor? protocolV2;
    private readonly ProtocolV2EnrollmentManager? enrollment;
    private readonly Func<
        ProtocolV2PeerCommandRequest,
        CancellationToken,
        Task<ProtocolV2PeerCommandResult>>? peerCommand;
    private readonly Func<object>? healthSnapshot;
    private readonly CancellationTokenSource cancellation = new();
    private readonly SemaphoreSlim requestSlots = new(
        MaxConcurrentRequests,
        MaxConcurrentRequests);
    private readonly ConcurrentDictionary<long, Task> activeRequests = new();
    private HttpListener? listener;
    private Task? acceptLoop;
    private long nextRequestId;

    public event EventHandler? AuthenticatedRequestAccepted;
    public event EventHandler<GatewayActionRequest>? AuthenticatedActionRequested;

    public GatewayServer(
        GatewaySettings settings,
        BridgeRuntimeOptions? runtimeOptions = null,
        IInteractiveAgent? interactiveAgent = null,
        string? protocolDeviceId = null,
        string? relayAddress = null,
        Func<object>? healthSnapshot = null,
        Func<
            ProtocolV2PeerCommandRequest,
            CancellationToken,
            Task<ProtocolV2PeerCommandResult>>? peerCommand = null)
    {
        this.settings = settings;
        authenticator = new GatewayAuthenticator(settings.SecretBase64);
        var options = runtimeOptions ?? BridgeRuntimeOptions.CreateDefault();
        dispatcher = new BridgeCommandDispatcher(options, interactiveAgent: interactiveAgent);
        if (!string.IsNullOrWhiteSpace(protocolDeviceId))
        {
            protocolV2 = new ProtocolV2CommandProcessor(
                options.StateRoot,
                protocolDeviceId,
                options,
                interactiveAgent,
                dispatcher: dispatcher);
            enrollment = new ProtocolV2EnrollmentManager(
                options.StateRoot,
                protocolDeviceId);
            RelayAddress = relayAddress;
        }
        this.peerCommand = peerCommand;
        this.healthSnapshot = healthSnapshot;
    }

    public bool IsRunning => listener?.IsListening == true;
    public string? TailnetAddress { get; private set; }
    public string? RelayAddress { get; }
    public ProtocolPublicIdentity? ProtocolIdentity => protocolV2?.PublicIdentity;
    internal ProtocolV2CommandProcessor? ProtocolV2Processor => protocolV2;

    internal Task<ProtocolV2Envelope> ExecuteProtocolV2Async(
        ProtocolV2Envelope envelope,
        CancellationToken cancellationToken) =>
        protocolV2?.ExecuteAsync(envelope, cancellationToken)
        ?? Task.FromException<ProtocolV2Envelope>(
            new ProtocolV2Exception(
                "protocol_v2_disabled",
                "Protocol v2 is not enabled."));

    public Task StartAsync(string? tailnetAddress = null)
    {
        if (IsRunning)
        {
            return Task.CompletedTask;
        }

        listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{settings.Port}/");
        if (!string.IsNullOrWhiteSpace(tailnetAddress) && IPAddress.TryParse(tailnetAddress, out var address) && IsTailnetAddress(address))
        {
            listener.Prefixes.Add($"http://{tailnetAddress}:{settings.Port}/");
            TailnetAddress = tailnetAddress;
        }

        listener.Start();
        acceptLoop = Task.Run(AcceptLoopAsync);
        return Task.CompletedTask;
    }

    public async Task RestartAsync(string? tailnetAddress)
    {
        await StopAsync();
        await StartAsync(tailnetAddress);
    }

    public async Task StopAsync()
    {
        if (listener is null)
        {
            return;
        }

        listener.Close();
        listener = null;
        if (acceptLoop is not null)
        {
            try
            {
                await acceptLoop;
            }
            catch (OperationCanceledException)
            {
            }
        }

        TailnetAddress = null;
    }

    public async ValueTask DisposeAsync()
    {
        cancellation.Cancel();
        await StopAsync();
        await Task.WhenAll(activeRequests.Values);
        if (protocolV2 is not null)
        {
            await protocolV2.DisposeAsync();
        }
        enrollment?.Dispose();
        await dispatcher.DisposeAsync();
        requestSlots.Dispose();
        cancellation.Dispose();
    }

    private async Task AcceptLoopAsync()
    {
        while (!cancellation.IsCancellationRequested && listener is { IsListening: true } activeListener)
        {
            try
            {
                var context = await activeListener.GetContextAsync();
                if (!requestSlots.Wait(0))
                {
                    await RejectBusyAsync(context);
                    continue;
                }
                var requestId = Interlocked.Increment(ref nextRequestId);
                var requestTask = HandleBoundedAsync(context);
                activeRequests[requestId] = requestTask;
                _ = ObserveRequestAsync(requestId, requestTask);
            }
            catch (HttpListenerException) when (cancellation.IsCancellationRequested || listener is null)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }
        }
    }

    private async Task HandleBoundedAsync(HttpListenerContext context)
    {
        try
        {
            await HandleAsync(context);
        }
        finally
        {
            requestSlots.Release();
        }
    }

    private async Task ObserveRequestAsync(long requestId, Task requestTask)
    {
        try
        {
            await requestTask;
        }
        catch
        {
            // HandleAsync emits bounded protocol errors whenever the response is writable.
        }
        finally
        {
            activeRequests.TryRemove(requestId, out _);
        }
    }

    private static async Task RejectBusyAsync(HttpListenerContext context)
    {
        try
        {
            context.Response.Headers["Retry-After"] = "1";
            await WriteJsonAsync(
                context.Response,
                HttpStatusCode.ServiceUnavailable,
                new
                {
                    ok = false,
                    errorCode = "request_capacity_reached",
                    error = "The Windows bridge request pool is busy."
                });
        }
        catch (HttpListenerException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
        finally
        {
            try
            {
                context.Response.Close();
            }
            catch (ObjectDisposedException)
            {
            }
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        try
        {
            if (!ApplyCorsPolicy(context.Request, context.Response))
            {
                await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
                {
                    ok = false,
                    errorCode = "origin_not_allowed"
                });
                return;
            }
            if (string.Equals(
                context.Request.HttpMethod,
                "OPTIONS",
                StringComparison.OrdinalIgnoreCase))
            {
                context.Response.StatusCode = (int)HttpStatusCode.NoContent;
                return;
            }
            var path = context.Request.Url?.AbsolutePath ?? string.Empty;
            if (string.Equals(path, "/v2/health", StringComparison.Ordinal)
                && string.Equals(context.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
            {
                await HandleHealthAsync(context);
                return;
            }
            if (string.Equals(path, "/v2/identity", StringComparison.Ordinal)
                && string.Equals(context.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
            {
                await HandleIdentityAsync(context);
                return;
            }
            if (string.Equals(path, "/v2/profile", StringComparison.Ordinal)
                && string.Equals(context.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
            {
                await HandleProfileAsync(context);
                return;
            }
            if (!string.Equals(context.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
                {
                    ok = false,
                    error = "Unsupported endpoint."
                });
                return;
            }

            var body = await ReadBodyAsync(context.Request);
            if (path == "/")
            {
                await HandleLegacyAsync(context, body);
                return;
            }
            if (path == "/v2")
            {
                await HandleProtocolV2Async(context, body);
                return;
            }
            if (path == "/v2/enroll/challenge")
            {
                await HandleEnrollmentChallengeAsync(context, body);
                return;
            }
            if (path == "/v2/enroll/complete")
            {
                await HandleEnrollmentCompleteAsync(context, body);
                return;
            }
            if (path == "/v2/peer/request")
            {
                await HandlePeerRequestAsync(context, body);
                return;
            }
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                error = "Unsupported endpoint."
            });
        }
        catch (JsonException)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.BadRequest, new { ok = false, error = "Invalid JSON request body." });
        }
        catch (Exception)
        {
            await WriteJsonAsync(
                context.Response,
                HttpStatusCode.BadRequest,
                new
                {
                    ok = false,
                    errorCode = "request_failed",
                    error = "The Windows bridge could not complete the request."
                });
        }
        finally
        {
            context.Response.Close();
        }
    }

    private async Task HandleLegacyAsync(HttpListenerContext context, string body)
    {
        var headers = context.Request.Headers.AllKeys
            .Where(key => key is not null)
            .ToDictionary(
                key => key!,
                key => context.Request.Headers[key!] ?? string.Empty,
                StringComparer.OrdinalIgnoreCase);
        var authentication = authenticator.Authenticate(headers, body);
        if (authentication != AuthenticationResult.Accepted)
        {
            var status = authentication == AuthenticationResult.ReplayRejected
                ? HttpStatusCode.Conflict
                : HttpStatusCode.Unauthorized;
            await WriteJsonAsync(context.Response, status, new
            {
                ok = false,
                error = authentication.ToString()
            });
            return;
        }

        AuthenticatedRequestAccepted?.Invoke(this, EventArgs.Empty);
        using var payload = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
        var actionRequest = GatewayActionRequest.FromJson(payload.RootElement);
        AuthenticatedActionRequested?.Invoke(this, actionRequest);
        var result = await ExecuteAsync(payload.RootElement, cancellation.Token);
        await WriteJsonAsync(
            context.Response,
            (HttpStatusCode)result.StatusCode,
            result.Body);
    }

    private async Task HandleProtocolV2Async(
        HttpListenerContext context,
        string body)
    {
        if (protocolV2 is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                errorCode = "protocol_v2_disabled"
            });
            return;
        }
        try
        {
            var envelope = JsonSerializer.Deserialize<ProtocolV2Envelope>(body, JsonOptions)
                ?? throw new ProtocolV2Exception("invalid_envelope", "Envelope is missing.");
            var response = await protocolV2.ExecuteAsync(
                envelope,
                cancellation.Token);
            AuthenticatedRequestAccepted?.Invoke(this, EventArgs.Empty);
            await WriteJsonAsync(context.Response, HttpStatusCode.OK, response);
        }
        catch (ProtocolV2Exception exception)
        {
            await WriteProtocolErrorAsync(context.Response, exception);
        }
    }

    private async Task HandlePeerRequestAsync(
        HttpListenerContext context,
        string body)
    {
        if (!IsLoopbackRequest(context.Request))
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
            {
                ok = false,
                errorCode = "loopback_required"
            });
            return;
        }
        if (peerCommand is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.ServiceUnavailable, new
            {
                ok = false,
                errorCode = "peer_command_unavailable"
            });
            return;
        }
        var headers = context.Request.Headers.AllKeys
            .Where(key => key is not null)
            .ToDictionary(
                key => key!,
                key => context.Request.Headers[key!] ?? string.Empty,
                StringComparer.OrdinalIgnoreCase);
        var authentication = authenticator.Authenticate(headers, body);
        if (authentication != AuthenticationResult.Accepted)
        {
            await WriteJsonAsync(
                context.Response,
                authentication == AuthenticationResult.ReplayRejected
                    ? HttpStatusCode.Conflict
                    : HttpStatusCode.Unauthorized,
                new
                {
                    ok = false,
                    errorCode = authentication.ToString()
                });
            return;
        }
        try
        {
            var request = JsonSerializer.Deserialize<ProtocolV2PeerCommandRequest>(
                body,
                JsonOptions)
                ?? throw new ProtocolV2Exception(
                    "invalid_payload",
                    "Peer-command request is missing.");
            var result = await peerCommand(request, cancellation.Token);
            AuthenticatedRequestAccepted?.Invoke(this, EventArgs.Empty);
            await WriteJsonAsync(context.Response, HttpStatusCode.OK, result);
        }
        catch (ProtocolV2Exception exception)
        {
            await WriteProtocolErrorAsync(context.Response, exception);
        }
    }

    private async Task HandleIdentityAsync(HttpListenerContext context)
    {
        if (!IsLoopbackRequest(context.Request))
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
            {
                ok = false,
                errorCode = "loopback_required"
            });
            return;
        }
        if (protocolV2 is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                errorCode = "protocol_v2_disabled"
            });
            return;
        }
        await WriteJsonAsync(context.Response, HttpStatusCode.OK, new
        {
            ok = true,
            identity = protocolV2.PublicIdentity,
            relayAddress = RelayAddress
        });
    }

    private async Task HandleProfileAsync(HttpListenerContext context)
    {
        if (!IsLoopbackRequest(context.Request))
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
            {
                ok = false,
                errorCode = "loopback_required"
            });
            return;
        }
        if (protocolV2 is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                errorCode = "protocol_v2_disabled"
            });
            return;
        }
        await WriteJsonAsync(context.Response, HttpStatusCode.OK, new
        {
            ok = true,
            profiles = protocolV2.ConnectionProfiles()
        });
    }

    private async Task HandleHealthAsync(HttpListenerContext context)
    {
        if (!IsLoopbackRequest(context.Request))
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
            {
                ok = false,
                errorCode = "loopback_required"
            });
            return;
        }
        await WriteJsonAsync(
            context.Response,
            HttpStatusCode.OK,
            healthSnapshot?.Invoke() ?? new
            {
                ok = true,
                service = "codex-pc-bridge",
                protocolVersion = 2,
                gatewayReady = IsRunning,
                port = settings.Port
            });
    }

    private async Task HandleEnrollmentChallengeAsync(
        HttpListenerContext context,
        string body)
    {
        if (!IsLoopbackRequest(context.Request))
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.Forbidden, new
            {
                ok = false,
                errorCode = "loopback_required"
            });
            return;
        }
        if (enrollment is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                errorCode = "protocol_v2_disabled"
            });
            return;
        }
        string? requestedRelay = null;
        var directAddresses = new List<string>();
        if (!string.IsNullOrWhiteSpace(body))
        {
            using var request = JsonDocument.Parse(body);
            requestedRelay = GetString(request.RootElement, "relayAddress");
            if (request.RootElement.TryGetProperty("directAddresses", out var requestedAddresses)
                && requestedAddresses.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in requestedAddresses.EnumerateArray())
                {
                    if (item.ValueKind == JsonValueKind.String
                        && IsSafeDirectAddress(item.GetString()))
                    {
                        directAddresses.Add(item.GetString()!.Trim().TrimEnd('/'));
                    }
                }
            }
        }
        if (!string.IsNullOrWhiteSpace(TailnetAddress))
        {
            directAddresses.Add($"http://{TailnetAddress}:{settings.Port}");
        }
        var challenge = enrollment.CreateChallenge(
            requestedRelay ?? RelayAddress,
            directAddresses);
        await WriteJsonAsync(context.Response, HttpStatusCode.OK, challenge);
    }

    private async Task HandleEnrollmentCompleteAsync(
        HttpListenerContext context,
        string body)
    {
        if (enrollment is null)
        {
            await WriteJsonAsync(context.Response, HttpStatusCode.NotFound, new
            {
                ok = false,
                errorCode = "protocol_v2_disabled"
            });
            return;
        }
        try
        {
            var response = JsonSerializer.Deserialize<EnrollmentResponse>(body, JsonOptions)
                ?? throw new ProtocolV2Exception(
                    "invalid_enrollment",
                    "Enrollment response is missing.");
            var receipt = string.IsNullOrWhiteSpace(RelayAddress)
                ? enrollment.Complete(response)
                : enrollment.CompleteWithRelayRegistration(response, RelayAddress);
            await WriteJsonAsync(context.Response, HttpStatusCode.OK, receipt);
        }
        catch (ProtocolV2Exception exception)
        {
            await WriteProtocolErrorAsync(context.Response, exception);
        }
    }

    private async Task<BridgeDispatchResult> ExecuteAsync(JsonElement request, CancellationToken cancellationToken)
    {
        var action = GetString(request, "action")?.ToLowerInvariant() ?? "status";
        return action switch
        {
            "status" => new BridgeDispatchResult(200, new
            {
                ok = true,
                gateway = "CODEX_WINDOWS_AUTONOMY_GATEWAY_READY",
                companion = "CODEX_PC_BRIDGE_READY",
                protocolVersion = 2,
                protocolV2 = protocolV2 is null
                    ? null
                    : new
                    {
                        enabled = true,
                        deviceId = protocolV2.PublicIdentity.DeviceId,
                        fingerprint = protocolV2.PublicIdentity.Fingerprint,
                        relayAddress = RelayAddress
                    },
                elevated = IsElevated(),
                user = Environment.UserName,
                computer = Environment.MachineName,
                time = DateTimeOffset.UtcNow,
                port = settings.Port,
                tailnetAddress = TailnetAddress,
                policy = new
                {
                    interactiveApprovalRequired = settings.InteractiveApprovalRequired,
                    stateChangingActions = new[] { "shell", "powershell", "run", "open" },
                    readOnlyActions = new[] { "status", "diagnostics" }
                }
            }),
            "diagnostics" => new BridgeDispatchResult(200, new
            {
                ok = true,
                action = "diagnostics",
                listener = new
                {
                    loopback = true,
                    tailnetAddress = TailnetAddress,
                    port = settings.Port
                },
                process = new
                {
                    elevated = IsElevated(),
                    user = Environment.UserName,
                    computer = Environment.MachineName,
                    startedAt = Process.GetCurrentProcess().StartTime.ToUniversalTime()
                }
            }),
            "clipboard-get" => new BridgeDispatchResult(
                200,
                new
                {
                    ok = false,
                    error = "Clipboard access requires an interactive Windows action. Use the shell action."
                }),
            _ => await dispatcher.ExecuteAsync(request, cancellationToken)
        };
    }

    private static bool IsElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static string? GetString(JsonElement request, string name) =>
        request.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;

    private static bool IsTailnetAddress(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && bytes[0] == 100 && bytes[1] is >= 64 and <= 127;
    }

    private static bool IsSafeDirectAddress(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || uri.UserInfo.Length > 0
            || !string.IsNullOrEmpty(uri.Fragment)
            || uri.Scheme is not ("http" or "https"))
        {
            return false;
        }
        if (uri.Scheme == "https")
        {
            return true;
        }
        return IPAddress.TryParse(uri.Host, out var address)
            && (IPAddress.IsLoopback(address)
                || IsTailnetAddress(address)
                || IsPrivateAddress(address));
    }

    private static bool IsPrivateAddress(IPAddress address)
    {
        if (address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
        {
            return false;
        }
        var bytes = address.GetAddressBytes();
        return bytes[0] == 10
            || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31)
            || (bytes[0] == 192 && bytes[1] == 168);
    }

    private static bool IsLoopbackRequest(HttpListenerRequest request) =>
        request.RemoteEndPoint is { Address: var address }
        && IPAddress.IsLoopback(address);

    private static bool ApplyCorsPolicy(
        HttpListenerRequest request,
        HttpListenerResponse response)
    {
        var origin = request.Headers["Origin"];
        if (string.IsNullOrWhiteSpace(origin))
        {
            return true;
        }
        if (!IsAllowedBrowserOrigin(origin))
        {
            return false;
        }
        response.Headers["Access-Control-Allow-Origin"] = origin;
        response.Headers["Vary"] = "Origin";
        response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
        response.Headers["Access-Control-Allow-Headers"] = "Content-Type";
        response.Headers["Access-Control-Max-Age"] = "600";
        if (string.Equals(
            request.Headers["Access-Control-Request-Private-Network"],
            "true",
            StringComparison.OrdinalIgnoreCase))
        {
            response.Headers["Access-Control-Allow-Private-Network"] = "true";
        }
        return true;
    }

    private static bool IsAllowedBrowserOrigin(string origin)
    {
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri)
            || !string.IsNullOrEmpty(uri.UserInfo)
            || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment))
        {
            return false;
        }
        if (uri.Scheme == Uri.UriSchemeHttps)
        {
            return string.Equals(
                    uri.Host,
                    "mich-nvidia-app.netlify.app",
                    StringComparison.OrdinalIgnoreCase);
        }
        return uri.Scheme == Uri.UriSchemeHttp
            && (string.Equals(uri.Host, "127.0.0.1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase));
    }

    private static async Task<string> ReadBodyAsync(HttpListenerRequest request)
    {
        if (request.ContentLength64 is < 0 or > MaxBodyBytes)
        {
            throw new InvalidDataException("Request body exceeds MaxBodyBytes.");
        }
        using var reader = new StreamReader(
            request.InputStream,
            request.ContentEncoding ?? Encoding.UTF8,
            false,
            MaxBodyBytes,
            leaveOpen: false);
        var body = await reader.ReadToEndAsync();
        if (Encoding.UTF8.GetByteCount(body) > MaxBodyBytes)
        {
            throw new InvalidDataException("Request body exceeds MaxBodyBytes.");
        }
        return body;
    }

    private static async Task WriteProtocolErrorAsync(
        HttpListenerResponse response,
        ProtocolV2Exception exception)
    {
        var status = exception.Code switch
        {
            "unknown_device" or "device_revoked" or "signature_invalid" =>
                HttpStatusCode.Unauthorized,
            "replay_rejected" or "challenge_used" =>
                HttpStatusCode.Conflict,
            "relay_not_ready" or "peer_unavailable" =>
                HttpStatusCode.ServiceUnavailable,
            "peer_response_timeout" =>
                HttpStatusCode.GatewayTimeout,
            _ => HttpStatusCode.BadRequest
        };
        await WriteJsonAsync(response, status, new
        {
            ok = false,
            errorCode = exception.Code,
            error = exception.Message
        });
    }

    private static async Task WriteJsonAsync(HttpListenerResponse response, HttpStatusCode status, object value)
    {
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value, JsonOptions));
        response.StatusCode = (int)status;
        response.ContentType = "application/json";
        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes);
    }
}
