using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed record BridgeServiceSettings(
    int Version,
    int Port,
    bool TailscaleEnabled,
    bool RelayEnabled,
    string? RelayUrl,
    bool ShadowMode)
{
    public const int CurrentVersion = 2;
    public const int ShadowPort = 18776;
    private const string FileName = "service-settings.json";

    public static BridgeServiceSettings LoadOrCreate(string stateRoot)
    {
        var root = Path.GetFullPath(stateRoot);
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, FileName);
        if (File.Exists(path))
        {
            var loaded = JsonSerializer.Deserialize<BridgeServiceSettings>(File.ReadAllText(path))
                ?? throw new InvalidDataException($"Invalid bridge service settings: {path}");
            if (loaded.Version < CurrentVersion)
            {
                loaded = loaded with
                {
                    Version = CurrentVersion,
                    Port = ShadowPort,
                    ShadowMode = true
                };
                loaded.Save(root);
            }
            return loaded;
        }

        var settings = new BridgeServiceSettings(
            CurrentVersion,
            ShadowPort,
            TailscaleEnabled: true,
            RelayEnabled: false,
            RelayUrl: null,
            ShadowMode: true);
        settings.Save(root);
        return settings;
    }

    public void Save(string stateRoot)
    {
        var path = Path.Combine(Path.GetFullPath(stateRoot), FileName);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var payload = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
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
    }
}
