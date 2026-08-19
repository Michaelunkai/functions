using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed record GatewaySettings(
    int Version,
    int Port,
    string SecretBase64,
    string? TailnetAddress,
    bool TailscaleEnabled = true,
    bool InteractiveApprovalRequired = false)
{
    public const int CurrentVersion = 3;
    public const int DefaultPort = 18767;

    public static GatewaySettings LoadOrCreate()
    {
        var path = GetConfigPath();
        if (File.Exists(path))
        {
            var loadedSettings = JsonSerializer.Deserialize<GatewaySettings>(File.ReadAllText(path))
                ?? throw new InvalidDataException($"Invalid gateway configuration: {path}");
            return loadedSettings.Version < CurrentVersion
                ? loadedSettings with
                {
                    Version = CurrentVersion,
                    TailscaleEnabled = true,
                    InteractiveApprovalRequired = false
                }
                : loadedSettings;
        }

        var secret = RandomNumberGenerator.GetBytes(32);
        var settings = new GatewaySettings(CurrentVersion, DefaultPort, Convert.ToBase64String(secret), null, true, false);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(settings, JsonOptions));
        return settings;
    }

    public void Save() => File.WriteAllText(GetConfigPath(), JsonSerializer.Serialize(this, JsonOptions));

    public byte[] GetSecret() => Convert.FromBase64String(SecretBase64);

    public string CreatePairingJson(string host) => JsonSerializer.Serialize(new
    {
        host,
        port = Port,
        secret = Convert.ToBase64String(GetSecret()),
        transport = "tailscale",
        interactiveApprovalRequired = InteractiveApprovalRequired
    }, JsonOptions);

    public static IPAddress? FindTailnetAddress() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(network => network.OperationalStatus == OperationalStatus.Up)
            .SelectMany(network => network.GetIPProperties().UnicastAddresses)
            .Select(address => address.Address)
            .FirstOrDefault(address => address.AddressFamily == AddressFamily.InterNetwork && IsTailnetAddress(address));

    public static int FindAvailablePort(int startingPort)
    {
        for (var port = startingPort; port <= 65535; port++)
        {
            try
            {
                using var listener = new TcpListener(IPAddress.Loopback, port);
                listener.Start();
                return port;
            }
            catch (SocketException)
            {
            }
        }

        throw new InvalidOperationException("No available TCP port was found.");
    }

    private static bool IsTailnetAddress(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes[0] == 100 && bytes[1] is >= 64 and <= 127;
    }

    private static string GetConfigPath() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CodexPcBridge", "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
}
