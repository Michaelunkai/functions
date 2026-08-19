using System.Security.Cryptography;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class BridgeMachineIdentity
{
    private const int CurrentVersion = 1;
    private const string IdentityFileName = "identity.json";
    private static readonly byte[] DpapiEntropy =
        SHA256.HashData(Encoding.UTF8.GetBytes("CodexPcBridge machine identity v1"));

    private BridgeMachineIdentity(string deviceId, byte[] gatewaySecret, byte[] agentPipeSecret)
    {
        DeviceId = deviceId;
        GatewaySecret = gatewaySecret;
        AgentPipeSecret = agentPipeSecret;
    }

    public string DeviceId { get; }
    public byte[] GatewaySecret { get; }
    public byte[] AgentPipeSecret { get; }

    public static BridgeMachineIdentity LoadOrCreate(string stateRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(stateRoot);
        var fullRoot = Path.GetFullPath(stateRoot);
        Directory.CreateDirectory(fullRoot);
        SecureDirectory(fullRoot);
        var path = Path.Combine(fullRoot, IdentityFileName);

        if (File.Exists(path))
        {
            return Read(path);
        }

        var identity = new BridgeMachineIdentity(
            "pc-" + Guid.NewGuid().ToString("N"),
            RandomNumberGenerator.GetBytes(32),
            RandomNumberGenerator.GetBytes(32));
        Write(path, identity);
        return Read(path);
    }

    private static BridgeMachineIdentity Read(string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        var version = root.GetProperty("version").GetInt32();
        if (version != CurrentVersion)
        {
            throw new InvalidDataException($"Unsupported machine identity version '{version}'.");
        }

        var deviceId = root.GetProperty("deviceId").GetString();
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            throw new InvalidDataException("Machine identity deviceId is missing.");
        }

        return new BridgeMachineIdentity(
            deviceId,
            Unprotect(root.GetProperty("protectedGatewaySecret").GetString(), "gateway"),
            Unprotect(root.GetProperty("protectedAgentPipeSecret").GetString(), "agent pipe"));
    }

    private static void Write(string path, BridgeMachineIdentity identity)
    {
        var payload = JsonSerializer.Serialize(
            new
            {
                version = CurrentVersion,
                deviceId = identity.DeviceId,
                createdAt = DateTimeOffset.UtcNow,
                protectedGatewaySecret = Protect(identity.GatewaySecret),
                protectedAgentPipeSecret = Protect(identity.AgentPipeSecret)
            },
            new JsonSerializerOptions { WriteIndented = true });

        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, payload, new UTF8Encoding(false));
            SecureFile(temporaryPath);
            try
            {
                File.Move(temporaryPath, path);
            }
            catch (IOException) when (File.Exists(path))
            {
                // Another startup won the creation race. Its identity is authoritative.
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

    private static string Protect(byte[] secret) =>
        Convert.ToBase64String(
            ProtectedData.Protect(secret, DpapiEntropy, DataProtectionScope.LocalMachine));

    private static byte[] Unprotect(string? protectedSecret, string name)
    {
        if (string.IsNullOrWhiteSpace(protectedSecret))
        {
            throw new InvalidDataException($"Protected {name} secret is missing.");
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
                throw new InvalidDataException($"Protected {name} secret is too short.");
            }
            return secret;
        }
        catch (FormatException exception)
        {
            throw new InvalidDataException($"Protected {name} secret is invalid.", exception);
        }
        catch (CryptographicException exception)
        {
            throw new InvalidDataException($"Protected {name} secret cannot be decrypted on this machine.", exception);
        }
    }

    private static void SecureDirectory(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var security = new DirectorySecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
            PropagationFlags.None,
            AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
            PropagationFlags.None,
            AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            FileSystemRights.ReadAndExecute,
            InheritanceFlags.None,
            PropagationFlags.None,
            AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(security);
    }

    private static void SecureFile(string path)
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
        new FileInfo(path).SetAccessControl(security);
    }
}
