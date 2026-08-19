using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class BridgeAgentCredential
{
    private const int CurrentVersion = 1;
    private const string FileName = "agent-credential.json";
    private static readonly byte[] DpapiEntropy =
        SHA256.HashData(Encoding.UTF8.GetBytes("CodexPcBridge interactive agent v1"));

    private BridgeAgentCredential(string deviceId, byte[] pipeSecret)
    {
        DeviceId = deviceId;
        PipeSecret = pipeSecret;
    }

    public string DeviceId { get; }
    public byte[] PipeSecret { get; }

    public static BridgeAgentCredential Provision(
        BridgeMachineIdentity machineIdentity,
        string userStateRoot)
    {
        ArgumentNullException.ThrowIfNull(machineIdentity);
        return Provision(
            machineIdentity.DeviceId,
            machineIdentity.AgentPipeSecret,
            userStateRoot);
    }

    public static BridgeAgentCredential LoadOrProvisionFromBootstrap(
        string userStateRoot,
        string machineStateRoot)
    {
        var path = Path.Combine(Path.GetFullPath(userStateRoot), FileName);
        if (File.Exists(path))
        {
            return Load(userStateRoot);
        }
        var bootstrap = BridgeAgentBootstrap.Load(machineStateRoot);
        try
        {
            return Provision(bootstrap.DeviceId, bootstrap.PipeSecret, userStateRoot);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bootstrap.PipeSecret);
        }
    }

    private static BridgeAgentCredential Provision(
        string deviceId,
        byte[] pipeSecret,
        string userStateRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userStateRoot);
        var root = Path.GetFullPath(userStateRoot);
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, FileName);
        var payload = JsonSerializer.Serialize(
            new
            {
                version = CurrentVersion,
                deviceId,
                protectedPipeSecret = Convert.ToBase64String(
                    ProtectedData.Protect(
                        pipeSecret,
                        DpapiEntropy,
                        DataProtectionScope.CurrentUser)),
                provisionedAt = DateTimeOffset.UtcNow
            },
            new JsonSerializerOptions { WriteIndented = true });
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, payload, new UTF8Encoding(false));
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
        return Load(root);
    }

    public static BridgeAgentCredential Load(string userStateRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userStateRoot);
        var path = Path.Combine(Path.GetFullPath(userStateRoot), FileName);
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.GetProperty("version").GetInt32() != CurrentVersion)
        {
            throw new InvalidDataException("Unsupported interactive-agent credential version.");
        }
        var deviceId = root.GetProperty("deviceId").GetString();
        var protectedSecret = root.GetProperty("protectedPipeSecret").GetString();
        if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(protectedSecret))
        {
            throw new InvalidDataException("Interactive-agent credential is incomplete.");
        }
        try
        {
            var secret = ProtectedData.Unprotect(
                Convert.FromBase64String(protectedSecret),
                DpapiEntropy,
                DataProtectionScope.CurrentUser);
            if (secret.Length < 32)
            {
                CryptographicOperations.ZeroMemory(secret);
                throw new InvalidDataException("Interactive-agent secret is too short.");
            }
            return new BridgeAgentCredential(deviceId, secret);
        }
        catch (CryptographicException exception)
        {
            throw new InvalidDataException(
                "Interactive-agent credential belongs to another Windows user or machine.",
                exception);
        }
    }

    public static string DefaultStateRoot =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexPcBridge");
}
