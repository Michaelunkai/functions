using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class BridgeAgentBootstrap
{
    private const int CurrentVersion = 1;
    private const string FileName = "agent-bootstrap.json";
    private static readonly byte[] DpapiEntropy =
        SHA256.HashData(Encoding.UTF8.GetBytes("CodexPcBridge local agent bootstrap v1"));

    private BridgeAgentBootstrap(string deviceId, byte[] pipeSecret)
    {
        DeviceId = deviceId;
        PipeSecret = pipeSecret;
    }

    public string DeviceId { get; }
    public byte[] PipeSecret { get; }

    public static BridgeAgentBootstrap Ensure(
        BridgeMachineIdentity identity,
        string machineStateRoot)
    {
        var root = Path.GetFullPath(machineStateRoot);
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, FileName);
        if (!File.Exists(path))
        {
            var payload = JsonSerializer.Serialize(
                new
                {
                    version = CurrentVersion,
                    deviceId = identity.DeviceId,
                    protectedPipeSecret = Convert.ToBase64String(
                        ProtectedData.Protect(
                            identity.AgentPipeSecret,
                            DpapiEntropy,
                            DataProtectionScope.LocalMachine)),
                    createdAt = DateTimeOffset.UtcNow
                },
                new JsonSerializerOptions { WriteIndented = true });
            var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temporaryPath, payload, new UTF8Encoding(false));
                SecureBootstrapFile(temporaryPath);
                try
                {
                    File.Move(temporaryPath, path);
                }
                catch (IOException) when (File.Exists(path))
                {
                }
            }
            finally
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
        }
        return Load(root);
    }

    public static BridgeAgentBootstrap Load(string machineStateRoot)
    {
        var path = Path.Combine(Path.GetFullPath(machineStateRoot), FileName);
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.GetProperty("version").GetInt32() != CurrentVersion)
        {
            throw new InvalidDataException("Unsupported local agent bootstrap version.");
        }
        var deviceId = root.GetProperty("deviceId").GetString();
        var protectedSecret = root.GetProperty("protectedPipeSecret").GetString();
        if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(protectedSecret))
        {
            throw new InvalidDataException("Local agent bootstrap is incomplete.");
        }
        try
        {
            var secret = ProtectedData.Unprotect(
                Convert.FromBase64String(protectedSecret),
                DpapiEntropy,
                DataProtectionScope.LocalMachine);
            if (secret.Length < 32)
            {
                CryptographicOperations.ZeroMemory(secret);
                throw new InvalidDataException("Local agent bootstrap secret is too short.");
            }
            return new BridgeAgentBootstrap(deviceId, secret);
        }
        catch (CryptographicException exception)
        {
            throw new InvalidDataException(
                "Local agent bootstrap cannot be decrypted on this machine.",
                exception);
        }
    }

    private static void SecureBootstrapFile(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var security = new FileSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            FileSystemRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            FileSystemRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            FileSystemRights.Read,
            AccessControlType.Allow));
        new FileInfo(path).SetAccessControl(security);
    }
}
