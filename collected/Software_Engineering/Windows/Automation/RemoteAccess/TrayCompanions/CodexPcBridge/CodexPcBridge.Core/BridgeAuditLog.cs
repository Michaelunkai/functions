using System.Text;

namespace CodexPcBridge.Core;

public static class BridgeAuditLog
{
    public const long MaxLogBytes = 1024 * 1024;
    private const int MaxEntryCharacters = 4096;
    private static readonly object Sync = new();

    public static string LogDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexPcBridge", "logs");

    public static string LogPath => Path.Combine(LogDirectory, "bridge.log");

    public static void Write(string message) =>
        AppendBounded(LogPath, message, MaxLogBytes);

    public static void AppendBounded(string path, string message, long maxBytes)
    {
        if (maxBytes < 1024 || maxBytes > int.MaxValue)
        {
            throw new ArgumentOutOfRangeException(nameof(maxBytes));
        }

        try
        {
            lock (Sync)
            {
                var fullPath = Path.GetFullPath(path);
                Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
                var boundedMessage = message.Length <= MaxEntryCharacters
                    ? message
                    : message[..MaxEntryCharacters];
                var entry =
                    $"{DateTimeOffset.UtcNow:O} {boundedMessage}{Environment.NewLine}";
                var entryBytes = Encoding.UTF8.GetByteCount(entry);
                if (File.Exists(fullPath)
                    && new FileInfo(fullPath).Length + entryBytes > maxBytes)
                {
                    RotateBoundedTail(fullPath, maxBytes / 2);
                }
                File.AppendAllText(fullPath, entry, new UTF8Encoding(false));
            }
        }
        catch
        {
            // Logging must never break gateway or agent operation.
        }
    }

    private static void RotateBoundedTail(string path, long tailBytes)
    {
        var archivePath = path + ".1";
        using var source = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        var count = checked((int)Math.Min(tailBytes, source.Length));
        var buffer = new byte[count];
        if (count > 0)
        {
            source.Seek(-count, SeekOrigin.End);
            source.ReadExactly(buffer);
        }
        var start = source.Length > count
            ? Array.IndexOf(buffer, (byte)'\n') + 1
            : 0;
        if (start < 0 || start > count)
        {
            start = count;
        }
        File.WriteAllBytes(archivePath, buffer[start..]);
        File.WriteAllText(path, string.Empty, new UTF8Encoding(false));
    }
}
