using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class BridgeCommandDispatcher : IAsyncDisposable
{
    private static readonly HashSet<string> MutatingActions = new(StringComparer.Ordinal)
    {
        "fs.write", "fs.writechunk", "fs.mkdir", "fs.copy", "fs.move", "fs.quarantine", "fs.restore", "fs.purge",
        "process.exec", "process.start", "process.cancel", "process.resume",
        "shell", "powershell", "run", "open"
    };

    private static readonly string[] Capabilities =
    [
        "status", "diagnostics", "capabilities",
        "fs.volumes", "fs.stat", "fs.list", "fs.read", "fs.readchunk", "fs.write", "fs.writechunk", "fs.transferstatus", "fs.mkdir",
        "fs.copy", "fs.move", "fs.quarantine", "fs.restore", "fs.purge",
        "process.exec", "process.start", "process.status", "process.cancel", "process.resume",
        "shell", "powershell", "run", "open"
    ];

    private readonly BridgeRuntimeOptions options;
    private readonly Func<DateTimeOffset> clock;
    private readonly BridgeFileSystem fileSystem;
    private readonly BridgeProcessManager processes;
    private readonly IInteractiveAgent? interactiveAgent;
    private readonly string idempotencyRoot;
    private readonly string auditRoot;

    public BridgeCommandDispatcher(
        BridgeRuntimeOptions? options = null,
        Func<DateTimeOffset>? clock = null,
        IInteractiveAgent? interactiveAgent = null)
    {
        this.options = options ?? BridgeRuntimeOptions.CreateDefault();
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        this.interactiveAgent = interactiveAgent;
        Directory.CreateDirectory(this.options.StateRoot);
        idempotencyRoot = Path.Combine(this.options.StateRoot, "idempotency");
        auditRoot = Path.Combine(this.options.StateRoot, "audit");
        Directory.CreateDirectory(idempotencyRoot);
        Directory.CreateDirectory(auditRoot);
        fileSystem = new BridgeFileSystem(this.options, this.clock);
        processes = new BridgeProcessManager(this.options, this.clock);
    }

    public async Task<BridgeDispatchResult> ExecuteAsync(JsonElement request, CancellationToken cancellationToken)
    {
        var action = BridgeFileSystem.GetString(request, "action")?.Trim().ToLowerInvariant() ?? "status";
        var metadataFailure = ValidateMetadata(request, action);
        if (metadataFailure is not null)
        {
            return new BridgeDispatchResult(400, metadataFailure);
        }

        var idempotencyKey = BridgeFileSystem.GetString(request, "idempotencyKey");
        if (MutatingActions.Contains(action) && !string.IsNullOrWhiteSpace(idempotencyKey))
        {
            var replay = ReadIdempotentResult(idempotencyKey!);
            if (replay is not null)
            {
                return new BridgeDispatchResult(200, AddReplayMarker(replay.Value));
            }
        }

        var stopwatch = Stopwatch.StartNew();
        object body;
        try
        {
            if (RequiresInteractiveRouting(action, request)
                && interactiveAgent is { IsConnected: true })
            {
                body = await interactiveAgent.ExecuteAsync(request, cancellationToken);
            }
            else if (RequiresInteractiveRouting(action, request)
                && !options.InteractiveFallbackLocal)
            {
                body = BridgeFileSystem.Failure(
                    "Interactive user agent is not connected.",
                    "interactive_agent_unavailable");
            }
            else
            {
                body = action switch
                {
                    "capabilities" => BridgeFileSystem.Success(
                        ("action", action),
                        ("protocolVersion", 2),
                        ("capabilities", Capabilities)),
                    "fs.volumes" => fileSystem.Volumes(),
                    "fs.stat" => fileSystem.Stat(request),
                    "fs.list" => fileSystem.List(request),
                    "fs.read" => fileSystem.Read(request),
                    "fs.readchunk" => fileSystem.ReadChunk(request),
                    "fs.write" => fileSystem.Write(request),
                    "fs.writechunk" => fileSystem.WriteChunk(request),
                    "fs.transferstatus" => fileSystem.TransferStatus(request),
                    "fs.mkdir" => fileSystem.Mkdir(request),
                    "fs.copy" => fileSystem.Copy(request),
                    "fs.move" => fileSystem.Move(request),
                    "fs.quarantine" => fileSystem.Quarantine(request),
                    "fs.restore" => fileSystem.Restore(request),
                    "fs.purge" => fileSystem.Purge(request),
                    "process.exec" => await processes.ExecuteAsync(request, cancellationToken),
                    "process.start" => await processes.StartAsync(request, cancellationToken),
                    "process.status" => processes.Status(request),
                    "process.cancel" => processes.Cancel(request),
                    "process.resume" => await processes.ResumeAsync(request, cancellationToken),
                    "shell" or "powershell" => await processes.ExecuteAsync(request, cancellationToken, powerShellAlias: true),
                    "run" => BridgeFileSystem.GetBoolean(request, "wait", false)
                        ? await processes.ExecuteAsync(request, cancellationToken)
                        : await processes.StartAsync(request, cancellationToken),
                    "open" => Open(request),
                    _ => BridgeFileSystem.Failure($"Unsupported action: {action}.", "unsupported_action")
                };
            }
        }
        catch (Exception exception)
        {
            body = BridgeFileSystem.Failure(exception.Message, "request_failed");
        }
        stopwatch.Stop();

        var success = BridgeFileSystem.IsSuccess(body);
        if (success && MutatingActions.Contains(action) && !string.IsNullOrWhiteSpace(idempotencyKey))
        {
            WriteIdempotentResult(idempotencyKey!, body);
        }
        if (MutatingActions.Contains(action))
        {
            WriteAuditReceipt(action, request, success, stopwatch.Elapsed);
        }
        return new BridgeDispatchResult(200, body);
    }

    public ValueTask DisposeAsync() => processes.DisposeAsync();

    private object? ValidateMetadata(JsonElement request, string action)
    {
        if (!request.TryGetProperty("protocolVersion", out var versionProperty))
        {
            return null;
        }
        if (!versionProperty.TryGetInt32(out var version) || version != 2)
        {
            return BridgeFileSystem.Failure("Unsupported protocolVersion.", "unsupported_protocol");
        }

        foreach (var field in new[] { "messageId", "deviceId" })
        {
            var value = BridgeFileSystem.GetString(request, field);
            if (!IsIdentifier(value))
            {
                return BridgeFileSystem.Failure($"Invalid or missing {field}.", "invalid_metadata");
            }
        }
        if (!IsCapabilityName(BridgeFileSystem.GetString(request, "capability")))
        {
            return BridgeFileSystem.Failure("Invalid or missing capability.", "invalid_metadata");
        }
        if (MutatingActions.Contains(action) && !IsIdentifier(BridgeFileSystem.GetString(request, "idempotencyKey")))
        {
            return BridgeFileSystem.Failure("Invalid or missing idempotencyKey.", "invalid_metadata");
        }
        if (!request.TryGetProperty("sequence", out var sequence) || !sequence.TryGetInt64(out var sequenceValue) || sequenceValue < 0)
        {
            return BridgeFileSystem.Failure("Invalid or missing sequence.", "invalid_metadata");
        }
        if (!TryGetTimestamp(request, "issuedAt", out var issuedAt)
            || !TryGetTimestamp(request, "expiresAt", out var expiresAt))
        {
            return BridgeFileSystem.Failure("Invalid issuedAt or expiresAt.", "invalid_metadata");
        }
        var now = clock();
        if (expiresAt <= now)
        {
            return BridgeFileSystem.Failure("Request has expired.", "request_expired");
        }
        if (issuedAt > now.AddMinutes(5) || issuedAt >= expiresAt)
        {
            return BridgeFileSystem.Failure("Invalid request validity window.", "invalid_metadata");
        }
        var capability = BridgeFileSystem.GetString(request, "capability");
        if (!string.Equals(capability, action, StringComparison.Ordinal))
        {
            return BridgeFileSystem.Failure("capability must match action.", "invalid_metadata");
        }
        return null;
    }

    private static object Open(JsonElement request)
    {
        var target = BridgeFileSystem.GetString(request, "target");
        if (string.IsNullOrWhiteSpace(target))
        {
            return BridgeFileSystem.Failure("Missing target.", "missing_target");
        }
        try
        {
            using var process = Process.Start(new ProcessStartInfo(target) { UseShellExecute = true })
                ?? throw new InvalidOperationException("Process did not start.");
            return BridgeFileSystem.Success(("action", "open"), ("target", target), ("pid", process.Id));
        }
        catch (Exception exception)
        {
            return BridgeFileSystem.Failure($"Unable to open target: {exception.Message}", "open_failed");
        }
    }

    private static bool RequiresInteractiveRouting(string action, JsonElement request) =>
        action == "open"
        || string.Equals(
            BridgeFileSystem.GetString(request, "executionContext"),
            "user",
            StringComparison.OrdinalIgnoreCase);

    private JsonElement? ReadIdempotentResult(string key)
    {
        var path = IdempotencyPath(key);
        if (!File.Exists(path))
        {
            return null;
        }
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        return document.RootElement.Clone();
    }

    private void WriteIdempotentResult(string key, object body)
    {
        var path = IdempotencyPath(key);
        var temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temp, JsonSerializer.Serialize(body));
        File.Move(temp, path, overwrite: true);
    }

    private string IdempotencyPath(string key)
    {
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
        return Path.Combine(idempotencyRoot, digest + ".json");
    }

    private static object AddReplayMarker(JsonElement body)
    {
        var result = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var property in body.EnumerateObject())
        {
            result[property.Name] = property.Value.Clone();
        }
        result["idempotentReplay"] = true;
        return result;
    }

    private void WriteAuditReceipt(string action, JsonElement request, bool success, TimeSpan elapsed)
    {
        var requestId = BridgeFileSystem.GetString(request, "messageId") ?? Guid.NewGuid().ToString("N");
        var summary = action switch
        {
            "shell" or "powershell" => $"powershell length={(BridgeFileSystem.GetString(request, "command") ?? string.Empty).Length}",
            "process.exec" or "process.start" or "run" =>
                $"process executable={Path.GetFileName(BridgeFileSystem.GetString(request, "executable")
                    ?? BridgeFileSystem.GetString(request, "fileName")
                    ?? BridgeFileSystem.GetString(request, "target")
                    ?? string.Empty)}",
            _ => $"path={Path.GetFileName(BridgeFileSystem.GetString(request, "path")
                ?? BridgeFileSystem.GetString(request, "destination")
                ?? string.Empty)}"
        };
        var receipt = new
        {
            requestId,
            action,
            summary,
            success,
            elapsedMilliseconds = (long)elapsed.TotalMilliseconds,
            completedAt = clock()
        };
        var safeName = IsIdentifier(requestId) ? requestId! : Guid.NewGuid().ToString("N");
        File.WriteAllText(Path.Combine(auditRoot, safeName + ".json"), JsonSerializer.Serialize(receipt));
    }

    private static bool TryGetTimestamp(JsonElement request, string name, out DateTimeOffset timestamp)
    {
        timestamp = default;
        if (!request.TryGetProperty(name, out var property))
        {
            return false;
        }
        if (property.ValueKind == JsonValueKind.String
            && DateTimeOffset.TryParse(property.GetString(), out timestamp))
        {
            return true;
        }
        if (property.TryGetInt64(out var epoch))
        {
            timestamp = DateTimeOffset.FromUnixTimeSeconds(epoch);
            return true;
        }
        return false;
    }

    private static bool IsIdentifier(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Length <= 128
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');

    private static bool IsCapabilityName(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Length <= 128
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');
}
