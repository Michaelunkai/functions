namespace CodexPcBridge.Core;

public sealed record BridgeRuntimeOptions(string StateRoot)
{
    public int MaxReadBytes { get; init; } = 4 * 1024 * 1024;
    public int MaxTransferChunkBytes { get; init; } = 128 * 1024;
    public int MaxListEntries { get; init; } = 5_000;
    public int MaxOutputBytes { get; init; } = 1024 * 1024;
    public bool InteractiveFallbackLocal { get; init; } = true;
    public string PowerShell5Path { get; init; } =
        Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
    public string? PowerShell7Path { get; init; }

    public static BridgeRuntimeOptions CreateDefault()
    {
        var commonData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = !string.IsNullOrWhiteSpace(commonData) && Directory.Exists(commonData)
            ? Path.Combine(commonData, "CodexPcBridge")
            : Path.Combine(localData, "CodexPcBridge");
        return new BridgeRuntimeOptions(root);
    }
}

public sealed record BridgeDispatchResult(int StatusCode, object Body);
