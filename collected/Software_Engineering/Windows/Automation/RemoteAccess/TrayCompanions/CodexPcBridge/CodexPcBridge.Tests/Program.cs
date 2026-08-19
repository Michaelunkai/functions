using CodexPcBridge.Core;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

NativeMethods.SetErrorMode(NativeMethods.SEM_NOGPFAULTERRORBOX);

var secret = Enumerable.Range(0, 32).Select(value => (byte)value).ToArray();
var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
const string nonce = "codex-pc-bridge-test-nonce-0001";
const string body = "{\"action\":\"status\"}";
var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["X-Codex-Timestamp"] = timestamp,
    ["X-Codex-Nonce"] = nonce,
    ["X-Codex-Signature"] = Sign(secret, timestamp, nonce, body)
};

var authenticator = new GatewayAuthenticator(secret);
Assert.Equal(AuthenticationResult.Accepted, authenticator.Authenticate(headers, body));
Assert.Equal(AuthenticationResult.ReplayRejected, authenticator.Authenticate(headers, body));

var encodedSecret = Convert.ToBase64String(secret);
var legacyTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
const string legacyNonce = "codex-pc-bridge-legacy-client-0001";
var legacyHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["X-Codex-Timestamp"] = legacyTimestamp,
    ["X-Codex-Nonce"] = legacyNonce,
    ["X-Codex-Signature"] = Sign(Encoding.UTF8.GetBytes(encodedSecret), legacyTimestamp, legacyNonce, body)
};
Assert.Equal(AuthenticationResult.Accepted, new GatewayAuthenticator(encodedSecret).Authenticate(legacyHeaders, body));

using var statusDocument = JsonDocument.Parse("{\"action\":\"status\"}");
Assert.Equal(false, GatewayActionRequest.FromJson(statusDocument.RootElement).RequiresInteractiveApproval);

using var shellDocument = JsonDocument.Parse("{\"action\":\"shell\",\"command\":\"Get-Date\"}");
Assert.Equal(true, GatewayActionRequest.FromJson(shellDocument.RootElement).RequiresInteractiveApproval);

var pairing = JsonDocument.Parse(new GatewaySettings(1, 18766, Convert.ToBase64String(secret), null).CreatePairingJson("100.64.0.10"));
Assert.Equal("100.64.0.10", pairing.RootElement.GetProperty("host").GetString());
Assert.Equal("tailscale", pairing.RootElement.GetProperty("transport").GetString());
Assert.Equal(false, pairing.RootElement.GetProperty("interactiveApprovalRequired").GetBoolean());
Assert.Equal(true, new GatewaySettings(2, 18766, Convert.ToBase64String(secret), null).TailscaleEnabled);
Assert.Equal(false, new GatewaySettings(3, 18766, Convert.ToBase64String(secret), null).InteractiveApprovalRequired);
Assert.Equal(18767, GatewaySettings.DefaultPort);
var defaultServiceRoot = Path.Combine(
    Path.GetTempPath(),
    "codex-pc-bridge-default-settings-" + Guid.NewGuid().ToString("N"));
try
{
    var defaultServiceSettings = BridgeServiceSettings.LoadOrCreate(defaultServiceRoot);
    Assert.Equal(BridgeServiceSettings.ShadowPort, defaultServiceSettings.Port);
    Assert.Equal(true, defaultServiceSettings.ShadowMode);
    Assert.Equal(18776, BridgeServiceSettings.ShadowPort);
    File.WriteAllText(
        Path.Combine(defaultServiceRoot, "service-settings.json"),
        JsonSerializer.Serialize(new BridgeServiceSettings(
            1,
            GatewaySettings.DefaultPort,
            TailscaleEnabled: true,
            RelayEnabled: false,
            RelayUrl: null,
            ShadowMode: false)));
    var migratedServiceSettings = BridgeServiceSettings.LoadOrCreate(defaultServiceRoot);
    Assert.Equal(BridgeServiceSettings.CurrentVersion, migratedServiceSettings.Version);
    Assert.Equal(BridgeServiceSettings.ShadowPort, migratedServiceSettings.Port);
    Assert.Equal(true, migratedServiceSettings.ShadowMode);
}
finally
{
    Directory.Delete(defaultServiceRoot, recursive: true);
}

var boundedLogRoot = Path.Combine(
    Path.GetTempPath(),
    "codex-pc-bridge-bounded-log-" + Guid.NewGuid().ToString("N"));
var boundedLogPath = Path.Combine(boundedLogRoot, "bridge.log");
try
{
    for (var index = 0; index < 80; index++)
    {
        BridgeAuditLog.AppendBounded(
            boundedLogPath,
            $"entry-{index:D2}-" + new string('x', 96),
            1024);
    }
    var activeLog = new FileInfo(boundedLogPath);
    var archivedLog = new FileInfo(boundedLogPath + ".1");
    Assert.Equal(true, activeLog.Exists);
    Assert.Equal(true, archivedLog.Exists);
    Assert.Equal(true, activeLog.Length <= 1200);
    Assert.Equal(true, archivedLog.Length <= 512);
    Assert.Equal(true, activeLog.Length + archivedLog.Length <= 1712);
    Assert.Contains("entry-79-", File.ReadAllText(boundedLogPath));
}
finally
{
    if (Directory.Exists(boundedLogRoot))
    {
        Directory.Delete(boundedLogRoot, recursive: true);
    }
}

var port = GatewaySettings.FindAvailablePort(21000);
await using var server = new GatewayServer(new GatewaySettings(2, port, Convert.ToBase64String(secret), null));
await server.StartAsync();
using var client = new HttpClient();
using var request = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/")
{
    Content = new StringContent(body, Encoding.UTF8, "application/json")
};
var remoteTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
var remoteNonce = "codex-pc-bridge-android-compat-0001";
request.Headers.Add("X-Codex-Timestamp", remoteTimestamp);
request.Headers.Add("X-Codex-Nonce", remoteNonce);
request.Headers.Add("X-Codex-Signature", Sign(secret, remoteTimestamp, remoteNonce, body));
using var response = await client.SendAsync(request);
Assert.Equal(HttpStatusCode.OK, response.StatusCode);
using var status = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
Assert.Equal(true, status.RootElement.GetProperty("ok").GetBoolean());
Assert.Equal("CODEX_WINDOWS_AUTONOMY_GATEWAY_READY", status.RootElement.GetProperty("gateway").GetString());
Assert.Equal(false, status.RootElement.GetProperty("policy").GetProperty("interactiveApprovalRequired").GetBoolean());

const string shellBody = "{\"action\":\"powershell\",\"command\":\"Write-Output CODEX_UNATTENDED_ACTION_OK\"}";
using var shellRequest = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/")
{
    Content = new StringContent(shellBody, Encoding.UTF8, "application/json")
};
var shellTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
var shellNonce = "codex-pc-bridge-unattended-action-0001";
shellRequest.Headers.Add("X-Codex-Timestamp", shellTimestamp);
shellRequest.Headers.Add("X-Codex-Nonce", shellNonce);
shellRequest.Headers.Add("X-Codex-Signature", Sign(secret, shellTimestamp, shellNonce, shellBody));
using var shellResponse = await client.SendAsync(shellRequest);
Assert.Equal(HttpStatusCode.OK, shellResponse.StatusCode);
using var shellResult = JsonDocument.Parse(await shellResponse.Content.ReadAsStringAsync());
Assert.Equal(true, shellResult.RootElement.GetProperty("ok").GetBoolean());
Assert.Contains("CODEX_UNATTENDED_ACTION_OK", shellResult.RootElement.GetProperty("stdout").GetString());

var quotedShellBody = JsonSerializer.Serialize(new
{
    action = "powershell",
    command = "$message = \"CODEX QUOTED POWERSHELL OK\"; Write-Output $message"
});
using var quotedShellRequest = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/")
{
    Content = new StringContent(quotedShellBody, Encoding.UTF8, "application/json")
};
var quotedShellTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
const string quotedShellNonce = "codex-pc-bridge-quoted-action-0001";
quotedShellRequest.Headers.Add("X-Codex-Timestamp", quotedShellTimestamp);
quotedShellRequest.Headers.Add("X-Codex-Nonce", quotedShellNonce);
quotedShellRequest.Headers.Add("X-Codex-Signature", Sign(secret, quotedShellTimestamp, quotedShellNonce, quotedShellBody));
using var quotedShellResponse = await client.SendAsync(quotedShellRequest);
Assert.Equal(HttpStatusCode.OK, quotedShellResponse.StatusCode);
using var quotedShellResult = JsonDocument.Parse(await quotedShellResponse.Content.ReadAsStringAsync());
Assert.Equal(true, quotedShellResult.RootElement.GetProperty("ok").GetBoolean());
Assert.Contains("CODEX QUOTED POWERSHELL OK", quotedShellResult.RootElement.GetProperty("stdout").GetString());

var fixtureRoot = Path.Combine(Path.GetTempPath(), "codex-pc-bridge-tests-" + Guid.NewGuid().ToString("N"));
var stateRoot = Path.Combine(fixtureRoot, "state");
var dataRoot = Path.Combine(fixtureRoot, "data");
Directory.CreateDirectory(dataRoot);
try
{
    var bridgeOptions = new BridgeRuntimeOptions(stateRoot)
    {
        MaxReadBytes = 32,
        MaxTransferChunkBytes = 8,
        MaxListEntries = 100,
        MaxOutputBytes = 64
    };
    await using var dispatcher = new BridgeCommandDispatcher(bridgeOptions);

    var capabilities = await DispatchAsync(dispatcher, new { action = "capabilities" });
    Assert.Equal(true, capabilities.GetProperty("ok").GetBoolean());
    Assert.ArrayContains("fs.quarantine", capabilities.GetProperty("capabilities"));
    Assert.ArrayContains("fs.writechunk", capabilities.GetProperty("capabilities"));
    Assert.ArrayContains("process.resume", capabilities.GetProperty("capabilities"));

    var filePath = Path.Combine(dataRoot, "alpha.txt");
    var writeRequest = new
    {
        protocolVersion = 2,
        messageId = "message-write-0001",
        idempotencyKey = "write-alpha-0001",
        deviceId = "device-test-0001",
        issuedAt = DateTimeOffset.UtcNow.AddSeconds(-1),
        expiresAt = DateTimeOffset.UtcNow.AddMinutes(1),
        sequence = 1,
        capability = "fs.write",
        action = "fs.write",
        path = filePath,
        content = "first"
    };
    var firstWrite = await DispatchAsync(dispatcher, writeRequest);
    Assert.Equal(true, firstWrite.GetProperty("ok").GetBoolean());
    File.WriteAllText(filePath, "changed-outside-dispatcher");
    var replayedWrite = await DispatchAsync(dispatcher, writeRequest);
    Assert.Equal(true, replayedWrite.GetProperty("idempotentReplay").GetBoolean());
    Assert.Equal("changed-outside-dispatcher", File.ReadAllText(filePath));

    var overwriteRefused = await DispatchAsync(dispatcher, new
    {
        action = "fs.write",
        path = filePath,
        content = "refused"
    });
    Assert.Equal(false, overwriteRefused.GetProperty("ok").GetBoolean());
    Assert.Contains("overwrite", overwriteRefused.GetProperty("error").GetString());

    var overwriteAccepted = await DispatchAsync(dispatcher, new
    {
        action = "fs.write",
        path = filePath,
        content = "restored",
        overwrite = true
    });
    Assert.Equal(true, overwriteAccepted.GetProperty("ok").GetBoolean());

    var read = await DispatchAsync(dispatcher, new { action = "fs.read", path = filePath });
    Assert.Equal("restored", read.GetProperty("content").GetString());

    var transferPath = Path.Combine(dataRoot, "chunked.bin");
    var transferBytes = Encoding.UTF8.GetBytes("chunked-transfer");
    var transferHash = Convert.ToHexString(SHA256.HashData(transferBytes)).ToLowerInvariant();
    var firstChunk = transferBytes[..8];
    var secondChunk = transferBytes[8..];
    var firstChunkRequest = new
    {
        action = "fs.writeChunk",
        transferId = "transfer-chunked-0001",
        path = transferPath,
        offset = 0,
        totalBytes = transferBytes.Length,
        content = Convert.ToBase64String(firstChunk),
        chunkSha256 = Convert.ToHexString(SHA256.HashData(firstChunk)).ToLowerInvariant(),
        fileSha256 = transferHash
    };
    var firstChunkResult = await DispatchAsync(dispatcher, firstChunkRequest);
    Assert.Equal(false, firstChunkResult.GetProperty("complete").GetBoolean());
    Assert.Equal(8L, firstChunkResult.GetProperty("nextOffset").GetInt64());
    var duplicateChunk = await DispatchAsync(dispatcher, firstChunkRequest);
    Assert.Equal(true, duplicateChunk.GetProperty("duplicate").GetBoolean());
    var transferStatus = await DispatchAsync(dispatcher, new
    {
        action = "fs.transferStatus",
        transferId = "transfer-chunked-0001"
    });
    Assert.Equal(8L, transferStatus.GetProperty("nextOffset").GetInt64());
    var completedChunk = await DispatchAsync(dispatcher, new
    {
        action = "fs.writeChunk",
        transferId = "transfer-chunked-0001",
        path = transferPath,
        offset = 8,
        totalBytes = transferBytes.Length,
        content = Convert.ToBase64String(secondChunk),
        chunkSha256 = Convert.ToHexString(SHA256.HashData(secondChunk)).ToLowerInvariant(),
        fileSha256 = transferHash
    });
    Assert.Equal(true, completedChunk.GetProperty("complete").GetBoolean());
    Assert.Equal(transferHash, completedChunk.GetProperty("fileSha256").GetString());
    Assert.Equal(true, transferBytes.SequenceEqual(File.ReadAllBytes(transferPath)));
    var readChunk = await DispatchAsync(dispatcher, new
    {
        action = "fs.readChunk",
        path = transferPath,
        offset = 8,
        maxBytes = 8
    });
    Assert.Equal(Convert.ToBase64String(secondChunk), readChunk.GetProperty("content").GetString());
    Assert.Equal(true, readChunk.GetProperty("eof").GetBoolean());
    Assert.Equal(transferHash, readChunk.GetProperty("fileSha256").GetString());

    var copyPath = Path.Combine(dataRoot, "copy.txt");
    var movePath = Path.Combine(dataRoot, "moved.txt");
    Assert.Equal(true, (await DispatchAsync(dispatcher, new { action = "fs.copy", source = filePath, destination = copyPath })).GetProperty("ok").GetBoolean());
    Assert.Equal(true, (await DispatchAsync(dispatcher, new { action = "fs.move", source = copyPath, destination = movePath })).GetProperty("ok").GetBoolean());
    Assert.Equal(true, File.Exists(movePath));

    var listing = await DispatchAsync(dispatcher, new { action = "fs.list", path = dataRoot });
    Assert.ArrayObjectContains("name", "moved.txt", listing.GetProperty("entries"));

    var quarantined = await DispatchAsync(dispatcher, new { action = "fs.quarantine", path = movePath });
    Assert.Equal(true, quarantined.GetProperty("ok").GetBoolean());
    Assert.Equal(false, File.Exists(movePath));
    var quarantineReceiptId = quarantined.GetProperty("receiptId").GetString()!;
    var restored = await DispatchAsync(dispatcher, new { action = "fs.restore", receiptId = quarantineReceiptId });
    Assert.Equal(true, restored.GetProperty("ok").GetBoolean());
    Assert.Equal(true, File.Exists(movePath));

    var quarantinedForPurge = await DispatchAsync(dispatcher, new { action = "fs.quarantine", path = movePath });
    var purgeReceiptId = quarantinedForPurge.GetProperty("receiptId").GetString()!;
    var purged = await DispatchAsync(dispatcher, new { action = "fs.purge", receiptId = purgeReceiptId });
    Assert.Equal(true, purged.GetProperty("ok").GetBoolean());

    var expired = await DispatchAsync(dispatcher, new
    {
        protocolVersion = 2,
        messageId = "message-expired-0001",
        idempotencyKey = "expired-0001",
        deviceId = "device-test-0001",
        issuedAt = DateTimeOffset.UtcNow.AddMinutes(-10),
        expiresAt = DateTimeOffset.UtcNow.AddMinutes(-5),
        sequence = 2,
        capability = "fs.mkdir",
        action = "fs.mkdir",
        path = Path.Combine(dataRoot, "expired")
    });
    Assert.Equal(false, expired.GetProperty("ok").GetBoolean());
    Assert.Contains("expired", expired.GetProperty("error").GetString());

    var missing = await DispatchAsync(dispatcher, new { action = "fs.stat", path = Path.Combine(dataRoot, "missing") });
    Assert.Equal(false, missing.GetProperty("ok").GetBoolean());
    Assert.Contains("not found", missing.GetProperty("error").GetString());

    var volumes = await DispatchAsync(dispatcher, new { action = "fs.volumes" });
    Assert.Equal(true, volumes.GetProperty("ok").GetBoolean());
    Assert.Equal(true, volumes.GetProperty("volumes").GetArrayLength() > 0);

    var powershell = Path.Combine(
        Environment.SystemDirectory,
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe");
    var truncatedOutput = await DispatchAsync(dispatcher, new
    {
        action = "process.exec",
        executable = powershell,
        arguments = new[]
        {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "[Console]::Out.Write(('x' * 200))"
        },
        timeoutSeconds = 10,
        maxOutputBytes = 64
    });
    Assert.Equal(true, truncatedOutput.GetProperty("ok").GetBoolean());
    Assert.Equal(true, truncatedOutput.GetProperty("stdoutTruncated").GetBoolean());
    Assert.Equal(true, Encoding.UTF8.GetByteCount(truncatedOutput.GetProperty("stdout").GetString()!) <= 64);

    var timedOut = await DispatchAsync(dispatcher, new
    {
        action = "process.exec",
        executable = powershell,
        arguments = new[]
        {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Start-Sleep -Seconds 5"
        },
        timeoutSeconds = 1
    });
    Assert.Equal(false, timedOut.GetProperty("ok").GetBoolean());
    Assert.Equal(true, timedOut.GetProperty("timedOut").GetBoolean());

    var background = await DispatchAsync(dispatcher, new
    {
        action = "process.start",
        jobId = "background-job-0001",
        executable = powershell,
        arguments = new[]
        {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Start-Sleep -Seconds 30"
        }
    });
    Assert.Equal(true, background.GetProperty("ok").GetBoolean());
    Assert.Equal("running", background.GetProperty("status").GetString());

    await using var restartedDispatcher = new BridgeCommandDispatcher(bridgeOptions);
    var interrupted = await DispatchAsync(restartedDispatcher, new
    {
        action = "process.status",
        jobId = "background-job-0001"
    });
    Assert.Equal("interrupted", interrupted.GetProperty("job").GetProperty("Status").GetString());

    var cancelledOriginal = await DispatchAsync(dispatcher, new
    {
        action = "process.cancel",
        jobId = "background-job-0001"
    });
    Assert.Equal(true, cancelledOriginal.GetProperty("ok").GetBoolean());
    await WaitForJobStatus(dispatcher, "background-job-0001", "cancelled");

    var resumed = await DispatchAsync(restartedDispatcher, new
    {
        action = "process.resume",
        jobId = "background-job-0001"
    });
    Assert.Equal(true, resumed.GetProperty("ok").GetBoolean());
    Assert.Equal("running", resumed.GetProperty("status").GetString());
    Assert.Equal(true, (await DispatchAsync(restartedDispatcher, new
    {
        action = "process.cancel",
        jobId = "background-job-0001"
    })).GetProperty("ok").GetBoolean());
    await WaitForJobStatus(restartedDispatcher, "background-job-0001", "cancelled");

    const string auditSecret = "DO_NOT_PERSIST_THIS_COMMAND_TEXT";
    var audited = await DispatchAsync(dispatcher, new
    {
        action = "powershell",
        command = $"Write-Output '{auditSecret}'"
    });
    Assert.Equal(true, audited.GetProperty("ok").GetBoolean());
    var auditText = string.Join(
        Environment.NewLine,
        Directory.EnumerateFiles(Path.Combine(stateRoot, "audit"), "*.json")
            .Select(File.ReadAllText));
    Assert.DoesNotContain(auditSecret, auditText);
    Assert.Contains("powershell length=", auditText);

    var unsupported = await DispatchAsync(dispatcher, new { action = "not-a-capability" });
    Assert.Equal(false, unsupported.GetProperty("ok").GetBoolean());
    Assert.Contains("Unsupported action", unsupported.GetProperty("error").GetString());

    var pipeSecret = RandomNumberGenerator.GetBytes(32);
    var pipeName = "CodexPcBridge.Tests." + Guid.NewGuid().ToString("N");
    await using var pipeServer = new InteractiveAgentServer(pipeName, pipeSecret);
    using var pipeCancellation = new CancellationTokenSource();
    var pipeClient = new InteractiveAgentClient(pipeName, pipeSecret);
    var pipeClientTask = pipeClient.RunAsync(
        (payload, _) => Task.FromResult<object>(new
        {
            ok = true,
            action = payload.GetProperty("action").GetString(),
            target = payload.GetProperty("target").GetString(),
            context = "interactive-user"
        }),
        pipeCancellation.Token);
    await pipeServer.WaitForConnectionAsync(TimeSpan.FromSeconds(5), CancellationToken.None);
    using var pipeRequest = JsonDocument.Parse("{\"action\":\"open\",\"target\":\"test-target\"}");
    var pipeResponse = await pipeServer.ExecuteAsync(pipeRequest.RootElement, CancellationToken.None);
    using var pipeResponseDocument = JsonDocument.Parse(JsonSerializer.Serialize(pipeResponse));
    Assert.Equal(true, pipeResponseDocument.RootElement.GetProperty("ok").GetBoolean());
    Assert.Equal("interactive-user", pipeResponseDocument.RootElement.GetProperty("context").GetString());
    pipeCancellation.Cancel();
    await IgnoreCancellation(pipeClientTask);

    var identityRoot = Path.Combine(fixtureRoot, "machine-identity");
    var firstIdentity = BridgeMachineIdentity.LoadOrCreate(identityRoot);
    var secondIdentity = BridgeMachineIdentity.LoadOrCreate(identityRoot);
    Assert.Equal(firstIdentity.DeviceId, secondIdentity.DeviceId);
    Assert.SequenceEqual(firstIdentity.GatewaySecret, secondIdentity.GatewaySecret);
    Assert.SequenceEqual(firstIdentity.AgentPipeSecret, secondIdentity.AgentPipeSecret);
    var identityFileText = File.ReadAllText(Path.Combine(identityRoot, "identity.json"));
    Assert.DoesNotContain(Convert.ToBase64String(firstIdentity.GatewaySecret), identityFileText);
    Assert.DoesNotContain(Convert.ToBase64String(firstIdentity.AgentPipeSecret), identityFileText);

    var credentialRoot = Path.Combine(fixtureRoot, "user-credential");
    var provisionedCredential = BridgeAgentCredential.Provision(firstIdentity, credentialRoot);
    var loadedCredential = BridgeAgentCredential.Load(credentialRoot);
    Assert.Equal(firstIdentity.DeviceId, loadedCredential.DeviceId);
    Assert.SequenceEqual(firstIdentity.AgentPipeSecret, loadedCredential.PipeSecret);
    Assert.SequenceEqual(provisionedCredential.PipeSecret, loadedCredential.PipeSecret);
    var credentialFileText = File.ReadAllText(Path.Combine(credentialRoot, "agent-credential.json"));
    Assert.DoesNotContain(Convert.ToBase64String(firstIdentity.AgentPipeSecret), credentialFileText);

    var bootstrapRoot = Path.Combine(fixtureRoot, "bootstrap-machine");
    var bootstrapIdentity = BridgeMachineIdentity.LoadOrCreate(bootstrapRoot);
    var bootstrap = BridgeAgentBootstrap.Ensure(bootstrapIdentity, bootstrapRoot);
    Assert.SequenceEqual(bootstrapIdentity.AgentPipeSecret, bootstrap.PipeSecret);
    var bootstrapUserRoot = Path.Combine(fixtureRoot, "bootstrap-user");
    var bootstrappedCredential = BridgeAgentCredential.LoadOrProvisionFromBootstrap(
        bootstrapUserRoot,
        bootstrapRoot);
    Assert.Equal(bootstrapIdentity.DeviceId, bootstrappedCredential.DeviceId);
    Assert.SequenceEqual(bootstrapIdentity.AgentPipeSecret, bootstrappedCredential.PipeSecret);
    var bootstrapFileText = File.ReadAllText(Path.Combine(bootstrapRoot, "agent-bootstrap.json"));
    Assert.DoesNotContain(Convert.ToBase64String(bootstrapIdentity.AgentPipeSecret), bootstrapFileText);

    var serviceRoot = Path.Combine(fixtureRoot, "service-host");
    var servicePort = GatewaySettings.FindAvailablePort(22000);
    var servicePipeName = "CodexPcBridge.Service.Tests." + Guid.NewGuid().ToString("N");
    var serviceSettings = new BridgeServiceSettings(
        BridgeServiceSettings.CurrentVersion,
        servicePort,
        TailscaleEnabled: false,
        RelayEnabled: false,
        RelayUrl: null,
        ShadowMode: true);
    await using var serviceHost = new BridgeServiceHost(serviceRoot, serviceSettings, servicePipeName);
    await serviceHost.StartAsync();
    Assert.Equal(true, serviceHost.GatewayReady);
    var serviceIdentity = BridgeMachineIdentity.LoadOrCreate(serviceRoot);
    using var serviceAgentCancellation = new CancellationTokenSource();
    var serviceAgent = new InteractiveAgentClient(servicePipeName, serviceIdentity.AgentPipeSecret);
    var serviceAgentTask = serviceAgent.RunAsync(
        (payload, _) => Task.FromResult<object>(new
        {
            ok = true,
            action = payload.GetProperty("action").GetString(),
            context = "interactive-user",
            target = payload.GetProperty("target").GetString()
        }),
        serviceAgentCancellation.Token);
    await serviceHost.WaitForAgentAsync(TimeSpan.FromSeconds(5), CancellationToken.None);
    Assert.Equal(true, serviceHost.AgentConnected);
    using var serviceHealth = await client.GetAsync(
        $"http://127.0.0.1:{servicePort}/v2/health");
    Assert.Equal(HttpStatusCode.OK, serviceHealth.StatusCode);
    using var serviceHealthDocument = JsonDocument.Parse(
        await serviceHealth.Content.ReadAsStringAsync());
    Assert.Equal(
        true,
        serviceHealthDocument.RootElement.GetProperty("gatewayReady").GetBoolean());
    Assert.Equal(
        true,
        serviceHealthDocument.RootElement.GetProperty("agentConnected").GetBoolean());
    Assert.Equal(
        true,
        serviceHealthDocument.RootElement.GetProperty("shadowMode").GetBoolean());

    var interactiveBody = JsonSerializer.Serialize(new
    {
        protocolVersion = 2,
        messageId = "service-open-message-0001",
        idempotencyKey = "service-open-idempotency-0001",
        deviceId = "android-test-device",
        jobId = "service-open-job-0001",
        capability = "open",
        sequence = 1,
        issuedAt = DateTimeOffset.UtcNow.AddSeconds(-1),
        expiresAt = DateTimeOffset.UtcNow.AddMinutes(1),
        action = "open",
        target = "codex-pc-bridge-test"
    });
    using var interactiveResponse = await PostSignedAsync(
        servicePort,
        serviceIdentity.GatewaySecret,
        interactiveBody,
        "codex-pc-bridge-service-agent-0001");
    Assert.Equal("interactive-user", interactiveResponse.RootElement.GetProperty("context").GetString());
    Assert.Equal("codex-pc-bridge-test", interactiveResponse.RootElement.GetProperty("target").GetString());
    serviceAgentCancellation.Cancel();
    await IgnoreCancellation(serviceAgentTask);
    Console.WriteLine("TEST_CHECKPOINT_SERVICE_AGENT_DONE");

    var protocolPcRoot = Path.Combine(fixtureRoot, "protocol-pc");
    var protocolAndroidRoot = Path.Combine(fixtureRoot, "protocol-android");
    const string protocolPcDeviceId = "pc-protocol-test";
    const string protocolAndroidDeviceId = "android-protocol-test";
    using var androidProtocolIdentity = ProtocolV2Identity.LoadOrCreate(
        protocolAndroidRoot,
        protocolAndroidDeviceId);
    EnrollmentChallenge enrollmentChallenge;
    using (var enrollment = new ProtocolV2EnrollmentManager(
        protocolPcRoot,
        protocolPcDeviceId))
    {
        enrollmentChallenge = enrollment.CreateChallenge("https://relay.test.invalid");
        Assert.Equal(2, enrollmentChallenge.ProtocolVersion);
        Assert.Equal(true, enrollmentChallenge.ExpiresAt <= enrollmentChallenge.IssuedAt.AddMinutes(5));
        var enrollmentResponse = ProtocolV2EnrollmentManager.CreateResponse(
            enrollmentChallenge,
            androidProtocolIdentity,
            "Android protocol test");
        var enrollmentReceipt = enrollment.Complete(enrollmentResponse);
        Assert.Equal(protocolAndroidDeviceId, enrollmentReceipt.DeviceId);
        await ExpectProtocolErrorAsync(
            "challenge_used",
            () => Task.FromResult(enrollment.Complete(enrollmentResponse)));
    }

    var expiredClock = enrollmentChallenge.IssuedAt;
    using (var expiringEnrollment = new ProtocolV2EnrollmentManager(
        Path.Combine(fixtureRoot, "protocol-expired"),
        "pc-protocol-expired",
        () => expiredClock))
    {
        var expiredChallenge = expiringEnrollment.CreateChallenge(null);
        var expiredResponse = ProtocolV2EnrollmentManager.CreateResponse(
            expiredChallenge,
            androidProtocolIdentity,
            "Android expired test");
        expiredClock = expiredClock.AddMinutes(6);
        await ExpectProtocolErrorAsync(
            "challenge_expired",
            () => Task.FromResult(expiringEnrollment.Complete(expiredResponse)));
    }

    var protocolRuntime = new BridgeRuntimeOptions(Path.Combine(protocolPcRoot, "runtime"))
    {
        InteractiveFallbackLocal = false
    };
    await using var protocolProcessor = new ProtocolV2CommandProcessor(
        protocolPcRoot,
        protocolPcDeviceId,
        protocolRuntime);
    var encryptedDirectory = Path.Combine(dataRoot, "protocol-v2-directory");
    var protocolNow = DateTimeOffset.UtcNow;
    var encryptedRequest = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-0001",
        "protocol-idempotency-0001",
        "protocol-job-0001",
        "fs.mkdir",
        sequence: 1,
        issuedAt: protocolNow.AddSeconds(-1),
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "fs.mkdir",
            path = encryptedDirectory
        });
    var encryptedResponse = await protocolProcessor.ExecuteAsync(
        encryptedRequest,
        CancellationToken.None);
    Assert.Equal(true, Directory.Exists(encryptedDirectory));
    var decryptedResponse = ProtocolV2Crypto.Decrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        encryptedResponse,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        "completed",
        decryptedResponse.GetProperty("finalStatus").GetString());
    Assert.Equal(
        true,
        decryptedResponse.GetProperty("result").GetProperty("ok").GetBoolean());

    var duplicateResponse = await protocolProcessor.ExecuteAsync(
        encryptedRequest,
        CancellationToken.None);
    Assert.Equal(
        JsonSerializer.Serialize(encryptedResponse),
        JsonSerializer.Serialize(duplicateResponse));
    await using (var restartedProtocolProcessor = new ProtocolV2CommandProcessor(
        protocolPcRoot,
        protocolPcDeviceId,
        protocolRuntime))
    {
        var restartedDuplicateResponse = await restartedProtocolProcessor.ExecuteAsync(
            encryptedRequest,
            CancellationToken.None);
        Assert.Equal(
            JsonSerializer.Serialize(encryptedResponse),
            JsonSerializer.Serialize(restartedDuplicateResponse));
    }
    var duplicatePayload = ProtocolV2Crypto.Decrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        duplicateResponse,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        false,
        duplicatePayload.GetProperty("acknowledgement").GetProperty("duplicate").GetBoolean());
    Console.WriteLine("TEST_CHECKPOINT_PROTOCOL_DUPLICATE_DONE");

    var protocolBrowserRoot = Path.Combine(fixtureRoot, "protocol-browser");
    using var browserProtocolIdentity = ProtocolV2Identity.LoadOrCreate(
        protocolBrowserRoot,
        "browser-protocol-test");
    Directory.CreateDirectory(Path.Combine(protocolPcRoot, "protocol-v2-relay"));
    File.WriteAllText(
        Path.Combine(
            protocolPcRoot,
            "protocol-v2-relay",
            enrollmentChallenge.ChallengeId + ".json"),
        JsonSerializer.Serialize(new ProtocolV2RelayProfile(
            "https://relay.test.invalid",
            "group-protocol-test",
            protocolPcDeviceId,
            protocolAndroidDeviceId,
            protocolNow)));
    protocolProcessor.Peers.AddOrUpdate(
        androidProtocolIdentity.PublicIdentity,
        "Android protocol test",
        "group-protocol-test",
        protocolNow);
    var browserApprovalRequest = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-browser-approval",
        "protocol-idempotency-browser-approval",
        "protocol-job-browser-approval",
        "bridge.peer.approve",
        sequence: 2,
        issuedAt: protocolNow,
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "bridge.peer.approve",
            groupId = "group-protocol-test",
            displayName = "Protocol browser",
            browserIdentity = browserProtocolIdentity.PublicIdentity
        });
    var browserApprovalResponse = await protocolProcessor.ExecuteAsync(
        browserApprovalRequest,
        CancellationToken.None);
    var browserApprovalPayload = ProtocolV2Crypto.Decrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        browserApprovalResponse,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        browserProtocolIdentity.DeviceId,
        browserApprovalPayload.GetProperty("result").GetProperty("authorizedDeviceId").GetString());
    Console.WriteLine("TEST_CHECKPOINT_BROWSER_APPROVAL_DONE");

    var browserDirectory = Path.Combine(dataRoot, "browser-authorized-directory");
    var browserCommand = ProtocolV2Crypto.Encrypt(
        browserProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-browser-command",
        "protocol-idempotency-browser-command",
        "protocol-job-browser-command",
        "fs.mkdir",
        sequence: 1,
        issuedAt: protocolNow,
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "fs.mkdir",
            path = browserDirectory
        });
    var browserCommandResponse = await protocolProcessor.ExecuteAsync(
        browserCommand,
        CancellationToken.None);
    var browserCommandPayload = ProtocolV2Crypto.Decrypt(
        browserProtocolIdentity,
        protocolProcessor.PublicIdentity,
        browserCommandResponse,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        true,
        browserCommandPayload.GetProperty("result").GetProperty("ok").GetBoolean());
    Assert.Equal(true, Directory.Exists(browserDirectory));
    Console.WriteLine("TEST_CHECKPOINT_BROWSER_COMMAND_DONE");

    using var untrustedBrowserIdentity = ProtocolV2Identity.LoadOrCreate(
        Path.Combine(fixtureRoot, "protocol-untrusted-browser"),
        "browser-untrusted-test");
    var forbiddenBrowserApproval = ProtocolV2Crypto.Encrypt(
        browserProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-forbidden-browser-approval",
        "protocol-idempotency-forbidden-browser-approval",
        "protocol-job-forbidden-browser-approval",
        "bridge.peer.approve",
        sequence: 2,
        issuedAt: protocolNow,
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "bridge.peer.approve",
            groupId = "group-protocol-test",
            displayName = "Untrusted browser",
            browserIdentity = untrustedBrowserIdentity.PublicIdentity
        });
    await ExpectProtocolErrorAsync(
        "peer_approval_forbidden",
        () => protocolProcessor.ExecuteAsync(
            forbiddenBrowserApproval,
            CancellationToken.None));
    Console.WriteLine("TEST_CHECKPOINT_BROWSER_FORBIDDEN_DONE");

    using var peerArguments = JsonDocument.Parse("{}");
    var preparedPeerCommand = protocolProcessor.PrepareOutgoing(
        new ProtocolV2PeerCommandRequest
        {
            TargetDeviceId = protocolAndroidDeviceId,
            Action = "status",
            JobId = "protocol-job-peer-status",
            IdempotencyKey = "protocol-idempotency-peer-status",
            Arguments = peerArguments.RootElement.Clone()
        });
    var decryptedPeerCommand = ProtocolV2Crypto.Decrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        preparedPeerCommand.RequestEnvelope,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        "status",
        decryptedPeerCommand.GetProperty("action").GetString());
    var peerResponseNow = DateTimeOffset.UtcNow;
    var peerResponse = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-response-peer-status",
        preparedPeerCommand.RequestEnvelope.IdempotencyKey,
        preparedPeerCommand.RequestEnvelope.JobId,
        "status.result",
        sequence: 3,
        issuedAt: peerResponseNow,
        expiresAt: peerResponseNow.AddMinutes(1),
        payload: new
        {
            acknowledgement = new
            {
                messageId = preparedPeerCommand.RequestEnvelope.MessageId,
                duplicate = false
            },
            finalStatus = "completed",
            result = new
            {
                ok = true,
                status = "verified",
                action = "status"
            },
            completedAt = peerResponseNow
        });
    var acceptedPeerResponse = protocolProcessor.AcceptOutgoingResponse(peerResponse);
    Assert.Equal(
        true,
        acceptedPeerResponse.Payload
            .GetProperty("result")
            .GetProperty("ok")
            .GetBoolean());
    var replayedPeerCommand = protocolProcessor.PrepareOutgoing(
        new ProtocolV2PeerCommandRequest
        {
            TargetDeviceId = protocolAndroidDeviceId,
            Action = "status",
            JobId = "protocol-job-peer-status",
            IdempotencyKey = "protocol-idempotency-peer-status",
            Arguments = peerArguments.RootElement.Clone()
        });
    Assert.Equal(true, replayedPeerCommand.CompletedResult?.Replayed);
    Assert.Equal(
        preparedPeerCommand.RequestEnvelope.MessageId,
        replayedPeerCommand.RequestEnvelope.MessageId);
    Console.WriteLine("TEST_CHECKPOINT_OUTBOUND_PEER_COMMAND_DONE");

    var tamperedCiphertext = Convert.FromBase64String(encryptedRequest.EncryptedPayload);
    tamperedCiphertext[0] ^= 0x01;
    var tamperedRequest = encryptedRequest with
    {
        EncryptedPayload = Convert.ToBase64String(tamperedCiphertext),
        MessageId = "protocol-message-tampered"
    };
    await ExpectProtocolErrorAsync(
        "signature_invalid",
        () => protocolProcessor.ExecuteAsync(tamperedRequest, CancellationToken.None));

    var reusedSequence = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-reused-sequence",
        "protocol-idempotency-reused",
        "protocol-job-reused",
        "fs.stat",
        sequence: 1,
        issuedAt: protocolNow,
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "fs.stat",
            path = encryptedDirectory
        });
    await ExpectProtocolErrorAsync(
        "replay_rejected",
        () => protocolProcessor.ExecuteAsync(reusedSequence, CancellationToken.None));

    var expiredEnvelope = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-expired",
        "protocol-idempotency-expired",
        "protocol-job-expired",
        "fs.stat",
        sequence: 2,
        issuedAt: protocolNow.AddMinutes(-10),
        expiresAt: protocolNow.AddMinutes(-5),
        payload: new
        {
            action = "fs.stat",
            path = encryptedDirectory
        });
    await ExpectProtocolErrorAsync(
        "request_expired",
        () => protocolProcessor.ExecuteAsync(expiredEnvelope, CancellationToken.None));

    protocolProcessor.Peers.Revoke(protocolAndroidDeviceId, DateTimeOffset.UtcNow);
    var revokedEnvelope = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        protocolProcessor.PublicIdentity,
        "protocol-message-revoked",
        "protocol-idempotency-revoked",
        "protocol-job-revoked",
        "fs.stat",
        sequence: 2,
        issuedAt: protocolNow,
        expiresAt: protocolNow.AddMinutes(1),
        payload: new
        {
            action = "fs.stat",
            path = encryptedDirectory
        });
    await ExpectProtocolErrorAsync(
        "device_revoked",
        () => protocolProcessor.ExecuteAsync(revokedEnvelope, CancellationToken.None));

    var endpointRoot = Path.Combine(fixtureRoot, "protocol-endpoint");
    var endpointPort = GatewaySettings.FindAvailablePort(24000);
    var endpointSecret = RandomNumberGenerator.GetBytes(32);
    var endpointOptions = new BridgeRuntimeOptions(endpointRoot)
    {
        InteractiveFallbackLocal = false
    };
    await using var endpointServer = new GatewayServer(
        new GatewaySettings(
            GatewaySettings.CurrentVersion,
            endpointPort,
            Convert.ToBase64String(endpointSecret),
            null,
            TailscaleEnabled: false),
        endpointOptions,
        protocolDeviceId: "pc-endpoint-test",
        relayAddress: null,
        peerCommand: (request, _) =>
        {
            Assert.Equal("status", request.Action);
            return Task.FromResult(acceptedPeerResponse);
        });
    await endpointServer.StartAsync();
    using var endpointClient = new HttpClient();
    using var corsRequest = new HttpRequestMessage(
        HttpMethod.Options,
        $"http://127.0.0.1:{endpointPort}/v2/enroll/challenge");
    corsRequest.Headers.TryAddWithoutValidation(
        "Origin",
        "https://mich-nvidia-app.netlify.app");
    corsRequest.Headers.TryAddWithoutValidation(
        "Access-Control-Request-Method",
        "POST");
    corsRequest.Headers.TryAddWithoutValidation(
        "Access-Control-Request-Private-Network",
        "true");
    using var corsResponse = await endpointClient.SendAsync(corsRequest);
    Assert.Equal(HttpStatusCode.NoContent, corsResponse.StatusCode);
    Assert.Equal(
        "https://mich-nvidia-app.netlify.app",
        corsResponse.Headers.GetValues("Access-Control-Allow-Origin").Single());
    Assert.Equal(
        "true",
        corsResponse.Headers.GetValues(
            "Access-Control-Allow-Private-Network").Single());
    using var deniedCorsRequest = new HttpRequestMessage(
        HttpMethod.Options,
        $"http://127.0.0.1:{endpointPort}/v2/enroll/challenge");
    deniedCorsRequest.Headers.TryAddWithoutValidation(
        "Origin",
        "https://not-approved.example");
    using var deniedCorsResponse = await endpointClient.SendAsync(deniedCorsRequest);
    Assert.Equal(HttpStatusCode.Forbidden, deniedCorsResponse.StatusCode);
    using var oversizedRequest = new HttpRequestMessage(
        HttpMethod.Post,
        $"http://127.0.0.1:{endpointPort}/v2/enroll/challenge")
    {
        Content = new ByteArrayContent(new byte[(1024 * 1024) + 1])
    };
    oversizedRequest.Content.Headers.ContentType =
        new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
    using var oversizedResponse = await endpointClient.SendAsync(oversizedRequest);
    Assert.Equal(HttpStatusCode.BadRequest, oversizedResponse.StatusCode);
    var oversizedResponseText = await oversizedResponse.Content.ReadAsStringAsync();
    using var oversizedPayload = JsonDocument.Parse(oversizedResponseText);
    Assert.Equal(
        "request_failed",
        oversizedPayload.RootElement.GetProperty("errorCode").GetString());
    Assert.Equal(
        "The Windows bridge could not complete the request.",
        oversizedPayload.RootElement.GetProperty("error").GetString());
    Assert.DoesNotContain("MaxBodyBytes", oversizedResponseText);
    Assert.DoesNotContain("InvalidDataException", oversizedResponseText);

    var trayProgramPath = FindRepositoryFile(
        Path.Combine("CodexPcBridge", "Program.cs"));
    var trayProgramSource = File.ReadAllText(trayProgramPath);
    var agentFailureBranch = trayProgramSource.IndexOf(
        "if (agentMode)",
        StringComparison.Ordinal);
    var fatalMessageBox = trayProgramSource.IndexOf(
        "MessageBox.Show(",
        StringComparison.Ordinal);
    Assert.Equal(true, agentFailureBranch >= 0);
    Assert.Equal(true, fatalMessageBox > agentFailureBranch);
    Assert.Contains(
        "AgentFatalNoPopupMarker",
        trayProgramSource[agentFailureBranch..fatalMessageBox]);
    Assert.Contains(
        "CODEX_PC_BRIDGE_AGENT_FATAL_NO_POPUP_V1",
        trayProgramSource);
    Assert.Contains(
        "return 1;",
        trayProgramSource[agentFailureBranch..fatalMessageBox]);
    var taskSupervisorBranch = trayProgramSource.IndexOf(
        "internal sealed class ScheduledTaskSupervisor",
        StringComparison.Ordinal);
    var taskStateProbe = trayProgramSource.IndexOf(
        "Task.Run(IsScheduledTaskActive)",
        taskSupervisorBranch,
        StringComparison.Ordinal);
    var taskLaunch = trayProgramSource.IndexOf(
        "Task.Run(StartScheduledTask)",
        taskSupervisorBranch,
        StringComparison.Ordinal);
    Assert.Equal(true, taskSupervisorBranch >= 0);
    Assert.Equal(true, taskStateProbe > taskSupervisorBranch);
    Assert.Equal(true, taskLaunch > taskStateProbe);
    Assert.Contains(
        "TaskSchedulerStateQueued or TaskSchedulerStateRunning",
        trayProgramSource[taskSupervisorBranch..]);
    var gatewaySupervisor = trayProgramSource.IndexOf(
        "new ScheduledTaskSupervisor(@\"\\CodexAutonomyGateway\")",
        StringComparison.Ordinal);
    var controlPlaneSupervisor = trayProgramSource.IndexOf(
        "new ScheduledTaskSupervisor(@\"\\CodexControlPlaneAgent\")",
        StringComparison.Ordinal);
    Assert.Equal(true, gatewaySupervisor >= 0);
    Assert.Equal(true, controlPlaneSupervisor > gatewaySupervisor);
    Assert.Contains(
        "gatewaySupervisor.Start();",
        trayProgramSource[gatewaySupervisor..controlPlaneSupervisor]);
    Assert.Contains(
        "gatewaySupervisor.Dispose();",
        trayProgramSource);

    var serviceProgramPath = FindRepositoryFile(
        Path.Combine("CodexPcBridge", "WindowsServiceMode.cs"));
    var serviceProgramSource = File.ReadAllText(serviceProgramPath);
    Assert.Contains(
        "CODEX_PC_BRIDGE_SERVICE_FAILURE_LOG_V1",
        serviceProgramSource);
    Assert.DoesNotContain("exception.Message", serviceProgramSource);
    Assert.DoesNotContain("{task.Exception}", serviceProgramSource);
    Assert.Contains(
        "new ServiceScheduledTaskSupervisor(",
        serviceProgramSource);
    Assert.Contains(
        "@\"\\CodexPcBridgeTray\"",
        serviceProgramSource);
    Assert.Contains("superviseTray: true", serviceProgramSource);
    Assert.Contains("superviseTray: false", serviceProgramSource);
    Assert.Contains(
        "TaskSchedulerStateQueued or TaskSchedulerStateRunning",
        serviceProgramSource);
    Assert.Contains(
        "new PeriodicTimer(SupervisionInterval)",
        serviceProgramSource);

    using var identityResponse = await endpointClient.GetAsync(
        $"http://127.0.0.1:{endpointPort}/v2/identity");
    Assert.Equal(HttpStatusCode.OK, identityResponse.StatusCode);
    using var identityPayload = JsonDocument.Parse(
        await identityResponse.Content.ReadAsStringAsync());
    var protocolJsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };
    var endpointIdentity = JsonSerializer.Deserialize<ProtocolPublicIdentity>(
        identityPayload.RootElement.GetProperty("identity").GetRawText(),
        protocolJsonOptions)
        ?? throw new InvalidOperationException("Endpoint identity was missing.");

    using var challengeResponse = await endpointClient.PostAsync(
        $"http://127.0.0.1:{endpointPort}/v2/enroll/challenge",
        new StringContent("{}", Encoding.UTF8, "application/json"));
    Assert.Equal(HttpStatusCode.OK, challengeResponse.StatusCode);
    var endpointChallenge = JsonSerializer.Deserialize<EnrollmentChallenge>(
        await challengeResponse.Content.ReadAsStringAsync(),
        protocolJsonOptions)
        ?? throw new InvalidOperationException("Endpoint enrollment challenge was missing.");
    var endpointEnrollmentResponse = ProtocolV2EnrollmentManager.CreateResponse(
        endpointChallenge,
        androidProtocolIdentity,
        "Android endpoint test");
    using var enrollmentCompleteResponse = await endpointClient.PostAsync(
        $"http://127.0.0.1:{endpointPort}/v2/enroll/complete",
        new StringContent(
            JsonSerializer.Serialize(endpointEnrollmentResponse, protocolJsonOptions),
            Encoding.UTF8,
            "application/json"));
    Assert.Equal(HttpStatusCode.OK, enrollmentCompleteResponse.StatusCode);
    var endpointReceipt = JsonSerializer.Deserialize<EnrollmentReceipt>(
        await enrollmentCompleteResponse.Content.ReadAsStringAsync(),
        protocolJsonOptions)
        ?? throw new InvalidOperationException("Endpoint enrollment receipt was missing.");
    Assert.Equal(true, Convert.FromBase64String(endpointReceipt.ReceiptPayload).Length > 0);
    var endpointRelayRoot = Path.Combine(endpointRoot, "protocol-v2-relay");
    Directory.CreateDirectory(endpointRelayRoot);
    File.WriteAllText(
        Path.Combine(endpointRelayRoot, endpointReceipt.GroupId + ".json"),
        JsonSerializer.Serialize(
            new ProtocolV2RelayProfile(
                "https://relay.example.test",
                endpointReceipt.GroupId,
                "pc-endpoint-test",
                androidProtocolIdentity.DeviceId,
                endpointReceipt.EnrolledAt),
            protocolJsonOptions));
    using var profileResponse = await endpointClient.GetAsync(
        $"http://127.0.0.1:{endpointPort}/v2/profile");
    Assert.Equal(HttpStatusCode.OK, profileResponse.StatusCode);
    using var profilePayload = JsonDocument.Parse(
        await profileResponse.Content.ReadAsStringAsync());
    var advertisedProfile = profilePayload.RootElement
        .GetProperty("profiles")
        .EnumerateArray()
        .Single();
    Assert.Equal(endpointReceipt.GroupId, advertisedProfile.GetProperty("groupId").GetString());
    Assert.Equal(
        androidProtocolIdentity.DeviceId,
        advertisedProfile.GetProperty("androidIdentity").GetProperty("deviceId").GetString());
    Assert.Equal(
        "pc-endpoint-test",
        advertisedProfile.GetProperty("pcIdentity").GetProperty("deviceId").GetString());
    Console.WriteLine("TEST_CHECKPOINT_PROFILE_ENDPOINT_DONE");

    var peerRouteBody = JsonSerializer.Serialize(new ProtocolV2PeerCommandRequest
    {
        TargetDeviceId = protocolAndroidDeviceId,
        Action = "status",
        JobId = "protocol-job-peer-route",
        IdempotencyKey = "protocol-idempotency-peer-route",
        Arguments = peerArguments.RootElement.Clone()
    });
    using var unauthorizedPeerRoute = await endpointClient.PostAsync(
        $"http://127.0.0.1:{endpointPort}/v2/peer/request",
        new StringContent(peerRouteBody, Encoding.UTF8, "application/json"));
    Assert.Equal(HttpStatusCode.Unauthorized, unauthorizedPeerRoute.StatusCode);
    using var peerRoutePayload = await PostSignedPathAsync(
        endpointPort,
        endpointSecret,
        "/v2/peer/request",
        peerRouteBody,
        "nonce-protocol-peer-route");
    Assert.Equal(
        true,
        peerRoutePayload.RootElement.GetProperty("ok").GetBoolean());
    Assert.Equal(
        protocolAndroidDeviceId,
        peerRoutePayload.RootElement.GetProperty("peerDeviceId").GetString());
    Console.WriteLine("TEST_CHECKPOINT_OUTBOUND_PEER_ROUTE_DONE");

    var endpointDirectory = Path.Combine(dataRoot, "protocol-endpoint-directory");
    var endpointRequest = ProtocolV2Crypto.Encrypt(
        androidProtocolIdentity,
        endpointIdentity,
        "endpoint-message-0001",
        "endpoint-idempotency-0001",
        "endpoint-job-0001",
        "fs.mkdir",
        sequence: 1,
        issuedAt: DateTimeOffset.UtcNow.AddSeconds(-1),
        expiresAt: DateTimeOffset.UtcNow.AddMinutes(1),
        payload: new
        {
            action = "fs.mkdir",
            path = endpointDirectory
        });
    using var endpointCommandResponse = await endpointClient.PostAsync(
        $"http://127.0.0.1:{endpointPort}/v2",
        new StringContent(
            JsonSerializer.Serialize(endpointRequest),
            Encoding.UTF8,
            "application/json"));
    Assert.Equal(HttpStatusCode.OK, endpointCommandResponse.StatusCode);
    var endpointEncryptedResponse = JsonSerializer.Deserialize<ProtocolV2Envelope>(
        await endpointCommandResponse.Content.ReadAsStringAsync())
        ?? throw new InvalidOperationException("Encrypted endpoint response was missing.");
    var endpointDecryptedResponse = ProtocolV2Crypto.Decrypt(
        androidProtocolIdentity,
        endpointIdentity,
        endpointEncryptedResponse,
        DateTimeOffset.UtcNow);
    Assert.Equal(
        true,
        endpointDecryptedResponse.GetProperty("result").GetProperty("ok").GetBoolean());
    Assert.Equal(true, Directory.Exists(endpointDirectory));
    Console.WriteLine("TEST_CHECKPOINT_ENDPOINT_COMMAND_DONE");
}
finally
{
    if (Directory.Exists(fixtureRoot))
    {
        Directory.Delete(fixtureRoot, recursive: true);
    }
}

Console.WriteLine("CODEX_PC_BRIDGE_TESTS_OK");

static async Task<JsonElement> DispatchAsync(BridgeCommandDispatcher dispatcher, object request)
{
    using var document = JsonDocument.Parse(JsonSerializer.Serialize(request));
    var result = await dispatcher.ExecuteAsync(document.RootElement, CancellationToken.None);
    using var serialized = JsonDocument.Parse(JsonSerializer.Serialize(result.Body));
    return serialized.RootElement.Clone();
}

static async Task WaitForJobStatus(BridgeCommandDispatcher dispatcher, string jobId, string expected)
{
    var deadline = DateTimeOffset.UtcNow.AddSeconds(10);
    do
    {
        var status = await DispatchAsync(dispatcher, new { action = "process.status", jobId });
        if (string.Equals(
                expected,
                status.GetProperty("job").GetProperty("Status").GetString(),
                StringComparison.Ordinal))
        {
            return;
        }
        await Task.Delay(100);
    } while (DateTimeOffset.UtcNow < deadline);

    throw new InvalidOperationException($"Job '{jobId}' did not reach status '{expected}'.");
}

static async Task IgnoreCancellation(Task task)
{
    try
    {
        await task.WaitAsync(TimeSpan.FromSeconds(5));
    }
    catch (OperationCanceledException)
    {
    }
}

static async Task ExpectProtocolErrorAsync<T>(
    string expectedCode,
    Func<Task<T>> operation)
{
    try
    {
        await operation();
    }
    catch (ProtocolV2Exception exception)
    {
        Assert.Equal(expectedCode, exception.Code);
        return;
    }
    throw new InvalidOperationException($"Expected ProtocolV2Exception '{expectedCode}'.");
}

static async Task<JsonDocument> PostSignedAsync(
    int port,
    byte[] secret,
    string body,
    string nonce)
{
    using var client = new HttpClient();
    using var request = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/")
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json")
    };
    var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
    request.Headers.Add("X-Codex-Timestamp", timestamp);
    request.Headers.Add("X-Codex-Nonce", nonce);
    request.Headers.Add("X-Codex-Signature", Sign(secret, timestamp, nonce, body));
    using var response = await client.SendAsync(request);
    var responseBody = await response.Content.ReadAsStringAsync();
    if (response.StatusCode != HttpStatusCode.OK)
    {
        throw new InvalidOperationException(
            $"Expected HTTP 200, got {(int)response.StatusCode}: {responseBody}");
    }
    return JsonDocument.Parse(responseBody);
}

static async Task<JsonDocument> PostSignedPathAsync(
    int port,
    byte[] secret,
    string path,
    string body,
    string nonce)
{
    using var client = new HttpClient();
    using var request = new HttpRequestMessage(
        HttpMethod.Post,
        $"http://127.0.0.1:{port}{path}")
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json")
    };
    var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
    request.Headers.Add("X-Codex-Timestamp", timestamp);
    request.Headers.Add("X-Codex-Nonce", nonce);
    request.Headers.Add("X-Codex-Signature", Sign(secret, timestamp, nonce, body));
    using var response = await client.SendAsync(request);
    var responseBody = await response.Content.ReadAsStringAsync();
    if (response.StatusCode != HttpStatusCode.OK)
    {
        throw new InvalidOperationException(
            $"Expected HTTP 200, got {(int)response.StatusCode}: {responseBody}");
    }
    return JsonDocument.Parse(responseBody);
}

static string FindRepositoryFile(string relativePath)
{
    foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
    {
        var directory = new DirectoryInfo(Path.GetFullPath(start));
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }
            directory = directory.Parent;
        }
    }
    throw new FileNotFoundException(
        $"Could not locate repository file '{relativePath}'.");
}

static string Sign(byte[] secret, string timestamp, string nonce, string body)
{
    using var hmac = new HMACSHA256(secret);
    return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes($"{timestamp}\n{nonce}\n{body}"))).ToLowerInvariant();
}

static class Assert
{
    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"Expected '{expected}', got '{actual}'.");
        }
    }

    public static void Contains(string expected, string? actual)
    {
        if (actual is null || !actual.Contains(expected, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Expected '{actual}' to contain '{expected}'.");
        }
    }

    public static void DoesNotContain(string unexpected, string? actual)
    {
        if (actual is not null && actual.Contains(unexpected, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Expected '{actual}' not to contain '{unexpected}'.");
        }
    }

    public static void ArrayContains(string expected, JsonElement array)
    {
        if (!array.EnumerateArray().Any(item => string.Equals(expected, item.GetString(), StringComparison.Ordinal)))
        {
            throw new InvalidOperationException($"Expected array to contain '{expected}'.");
        }
    }

    public static void ArrayObjectContains(string propertyName, string expected, JsonElement array)
    {
        if (!array.EnumerateArray().Any(item =>
                item.TryGetProperty(propertyName, out var property)
                && string.Equals(expected, property.GetString(), StringComparison.Ordinal)))
        {
            throw new InvalidOperationException($"Expected array object property '{propertyName}' to contain '{expected}'.");
        }
    }

    public static void SequenceEqual<T>(IEnumerable<T> expected, IEnumerable<T> actual)
    {
        if (!expected.SequenceEqual(actual))
        {
            throw new InvalidOperationException("Expected sequences to match.");
        }
    }
}

static class NativeMethods
{
    public const uint SEM_NOGPFAULTERRORBOX = 0x0002;

    [DllImport("kernel32.dll")]
    public static extern uint SetErrorMode(uint mode);
}
