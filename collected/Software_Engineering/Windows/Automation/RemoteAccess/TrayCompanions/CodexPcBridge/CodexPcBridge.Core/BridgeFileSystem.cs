using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

internal sealed class BridgeFileSystem
{
    private readonly BridgeRuntimeOptions options;
    private readonly Func<DateTimeOffset> clock;
    private readonly string quarantineRoot;
    private readonly string quarantineReceiptsRoot;
    private readonly string transferItemsRoot;
    private readonly string transferReceiptsRoot;
    private readonly object transferLock = new();

    public BridgeFileSystem(BridgeRuntimeOptions options, Func<DateTimeOffset> clock)
    {
        this.options = options;
        this.clock = clock;
        quarantineRoot = Path.Combine(options.StateRoot, "quarantine", "items");
        quarantineReceiptsRoot = Path.Combine(options.StateRoot, "quarantine", "receipts");
        transferItemsRoot = Path.Combine(options.StateRoot, "transfers", "items");
        transferReceiptsRoot = Path.Combine(options.StateRoot, "transfers", "receipts");
        Directory.CreateDirectory(quarantineRoot);
        Directory.CreateDirectory(quarantineReceiptsRoot);
        Directory.CreateDirectory(transferItemsRoot);
        Directory.CreateDirectory(transferReceiptsRoot);
    }

    public object Volumes()
    {
        var volumes = new List<object>();
        foreach (var drive in DriveInfo.GetDrives().OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var ready = drive.IsReady;
                volumes.Add(new
                {
                    name = drive.Name,
                    driveType = drive.DriveType.ToString(),
                    ready,
                    volumeLabel = ready ? drive.VolumeLabel : null,
                    format = ready ? drive.DriveFormat : null,
                    totalBytes = ready ? drive.TotalSize : (long?)null,
                    freeBytes = ready ? drive.AvailableFreeSpace : (long?)null,
                    error = ready ? null : "Drive is not ready."
                });
            }
            catch (Exception exception)
            {
                volumes.Add(new
                {
                    name = drive.Name,
                    driveType = drive.DriveType.ToString(),
                    ready = false,
                    volumeLabel = (string?)null,
                    format = (string?)null,
                    totalBytes = (long?)null,
                    freeBytes = (long?)null,
                    error = exception.Message
                });
            }
        }

        return Success(("action", "fs.volumes"), ("volumes", volumes));
    }

    public object Stat(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        if (File.Exists(path))
        {
            var file = new FileInfo(path);
            return Success(
                ("action", "fs.stat"),
                ("path", path),
                ("type", "file"),
                ("bytes", file.Length),
                ("createdAt", file.CreationTimeUtc),
                ("updatedAt", file.LastWriteTimeUtc),
                ("attributes", file.Attributes.ToString()));
        }

        if (Directory.Exists(path))
        {
            var directory = new DirectoryInfo(path);
            return Success(
                ("action", "fs.stat"),
                ("path", path),
                ("type", "directory"),
                ("createdAt", directory.CreationTimeUtc),
                ("updatedAt", directory.LastWriteTimeUtc),
                ("attributes", directory.Attributes.ToString()));
        }

        return Failure($"Path not found: {path}", "path_not_found");
    }

    public object List(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        if (!Directory.Exists(path))
        {
            return Failure($"Directory not found: {path}", "path_not_found");
        }

        var requestedLimit = GetInt(request, "limit", options.MaxListEntries);
        var limit = Math.Clamp(requestedLimit, 1, options.MaxListEntries);
        var entries = new List<object>();
        var truncated = false;
        try
        {
            foreach (var entry in Directory.EnumerateFileSystemEntries(path))
            {
                if (entries.Count >= limit)
                {
                    truncated = true;
                    break;
                }

                var attributes = File.GetAttributes(entry);
                var isDirectory = attributes.HasFlag(FileAttributes.Directory);
                entries.Add(new
                {
                    name = Path.GetFileName(entry),
                    path = Path.GetFullPath(entry),
                    type = isDirectory ? "directory" : "file",
                    bytes = isDirectory ? (long?)null : new FileInfo(entry).Length,
                    updatedAt = isDirectory
                        ? new DirectoryInfo(entry).LastWriteTimeUtc
                        : new FileInfo(entry).LastWriteTimeUtc,
                    attributes = attributes.ToString()
                });
            }
        }
        catch (Exception exception)
        {
            return Failure($"Unable to list directory: {exception.Message}", "access_failed");
        }

        return Success(
            ("action", "fs.list"),
            ("path", path),
            ("entries", entries),
            ("truncated", truncated),
            ("limit", limit));
    }

    public object Read(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        if (!File.Exists(path))
        {
            return Failure($"File not found: {path}", "path_not_found");
        }

        var maxBytes = Math.Clamp(GetInt(request, "maxBytes", options.MaxReadBytes), 1, options.MaxReadBytes);
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var buffer = new byte[Math.Min(maxBytes + 1, options.MaxReadBytes + 1)];
            var read = stream.Read(buffer, 0, buffer.Length);
            var truncated = read > maxBytes || stream.Position < stream.Length;
            var length = Math.Min(read, maxBytes);
            var bytes = buffer.AsSpan(0, length).ToArray();
            var encoding = GetString(request, "encoding")?.ToLowerInvariant() ?? "utf8";
            var content = encoding switch
            {
                "base64" => Convert.ToBase64String(bytes),
                "utf8" => Encoding.UTF8.GetString(bytes),
                _ => throw new InvalidDataException("encoding must be utf8 or base64.")
            };
            return Success(
                ("action", "fs.read"),
                ("path", path),
                ("encoding", encoding),
                ("content", content),
                ("bytes", length),
                ("sha256", Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()),
                ("truncated", truncated));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to read file: {exception.Message}", "access_failed");
        }
    }

    public object Write(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        var overwrite = GetBoolean(request, "overwrite", false);
        if ((File.Exists(path) || Directory.Exists(path)) && !overwrite)
        {
            return Failure("Target exists; set overwrite=true to replace it.", "overwrite_required");
        }

        if (Directory.Exists(path))
        {
            return Failure("Target path is a directory.", "path_is_directory");
        }

        var content = GetString(request, "content") ?? string.Empty;
        var encoding = GetString(request, "encoding")?.ToLowerInvariant() ?? "utf8";
        byte[] bytes;
        try
        {
            bytes = encoding switch
            {
                "base64" => Convert.FromBase64String(content),
                "utf8" => Encoding.UTF8.GetBytes(content),
                _ => throw new InvalidDataException("encoding must be utf8 or base64.")
            };
        }
        catch (Exception exception)
        {
            return Failure($"Invalid file content: {exception.Message}", "invalid_content");
        }

        var directory = Path.GetDirectoryName(path)
            ?? throw new InvalidDataException("Target path has no parent directory.");
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(path)}.codex-tmp-{Guid.NewGuid():N}");
        try
        {
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, path, overwrite);
            return Success(
                ("action", "fs.write"),
                ("path", path),
                ("bytes", bytes.Length),
                ("sha256", Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to write file: {exception.Message}", "write_failed");
        }
        finally
        {
            if (File.Exists(temp))
            {
                File.Delete(temp);
            }
        }
    }

    public object ReadChunk(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        if (!File.Exists(path))
        {
            return Failure($"File not found: {path}", "path_not_found");
        }

        var offset = GetLong(request, "offset", 0);
        var maxBytes = Math.Clamp(
            GetInt(request, "maxBytes", options.MaxTransferChunkBytes),
            1,
            options.MaxTransferChunkBytes);
        if (offset < 0)
        {
            return Failure("Chunk offset cannot be negative.", "invalid_offset");
        }

        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            if (offset > stream.Length)
            {
                return Failure(
                    $"Chunk offset exceeds file length; expected at most {stream.Length}.",
                    "invalid_offset");
            }
            stream.Position = offset;
            var buffer = new byte[maxBytes];
            var read = stream.Read(buffer, 0, buffer.Length);
            var bytes = buffer.AsSpan(0, read).ToArray();
            var nextOffset = offset + read;
            var eof = nextOffset >= stream.Length;
            return Success(
                ("action", "fs.readchunk"),
                ("path", path),
                ("offset", offset),
                ("nextOffset", nextOffset),
                ("totalBytes", stream.Length),
                ("content", Convert.ToBase64String(bytes)),
                ("bytes", read),
                ("chunkSha256", Sha256(bytes)),
                ("fileSha256", eof ? Sha256File(path) : null),
                ("eof", eof));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to read file chunk: {exception.Message}", "access_failed");
        }
    }

    public object WriteChunk(JsonElement request)
    {
        var transferId = RequireIdentifier(request, "transferId");
        var path = RequireAbsolutePath(request, "path");
        var offset = GetLong(request, "offset", -1);
        var totalBytes = GetLong(request, "totalBytes", -1);
        var overwrite = GetBoolean(request, "overwrite", false);
        var expectedChunkHash = RequireSha256(request, "chunkSha256");
        var expectedFileHash = RequireSha256(request, "fileSha256");
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(GetString(request, "content") ?? string.Empty);
        }
        catch (FormatException)
        {
            return Failure("Chunk content is not valid base64.", "invalid_content");
        }
        try
        {
            if (bytes.Length == 0 || bytes.Length > options.MaxTransferChunkBytes)
            {
                return Failure(
                    $"Chunk must contain between 1 and {options.MaxTransferChunkBytes} bytes.",
                    "invalid_chunk_size");
            }
            if (offset < 0 || totalBytes <= 0 || offset + bytes.Length > totalBytes)
            {
                return Failure("Chunk offset or total length is invalid.", "invalid_offset");
            }
            if (!string.Equals(Sha256(bytes), expectedChunkHash, StringComparison.OrdinalIgnoreCase))
            {
                return Failure("Chunk SHA-256 does not match its content.", "chunk_hash_mismatch");
            }

            lock (transferLock)
            {
                try
                {
                    var receipt = ReadTransferReceipt(transferId);
                    if (receipt is null)
                    {
                        if (offset != 0)
                        {
                            return Failure("New transfers must begin at offset 0.", "resume_offset_required");
                        }
                        if ((File.Exists(path) || Directory.Exists(path)) && !overwrite)
                        {
                            return Failure(
                                "Target exists; set overwrite=true to replace it.",
                                "overwrite_required");
                        }
                        receipt = new TransferReceipt(
                            transferId,
                            path,
                            TransferItemPath(transferId),
                            totalBytes,
                            0,
                            expectedFileHash,
                            overwrite,
                            "receiving",
                            clock(),
                            null);
                        WriteTransferReceipt(receipt);
                    }
                    if (!string.Equals(receipt.Path, path, StringComparison.OrdinalIgnoreCase)
                        || receipt.TotalBytes != totalBytes
                        || !string.Equals(
                            receipt.FileSha256,
                            expectedFileHash,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        return Failure(
                            "Transfer metadata does not match its durable receipt.",
                            "transfer_metadata_mismatch");
                    }
                    if (string.Equals(receipt.Status, "completed", StringComparison.Ordinal))
                    {
                        return TransferSuccess(receipt, duplicate: true);
                    }
                    if (offset < receipt.ReceivedBytes)
                    {
                        if (!ChunkMatches(receipt.PartialPath, offset, bytes))
                        {
                            return Failure(
                                "A resumed chunk conflicts with durable transfer bytes.",
                                "chunk_conflict");
                        }
                        return receipt.ReceivedBytes == receipt.TotalBytes
                            ? FinalizeTransfer(receipt, duplicate: true)
                            : TransferSuccess(receipt, duplicate: true);
                    }
                    if (offset != receipt.ReceivedBytes)
                    {
                        return Failure(
                            $"Chunk offset mismatch; expected {receipt.ReceivedBytes}.",
                            "resume_offset_required");
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(receipt.PartialPath)!);
                    using (var stream = new FileStream(
                        receipt.PartialPath,
                        FileMode.OpenOrCreate,
                        FileAccess.Write,
                        FileShare.None))
                    {
                        if (stream.Length != receipt.ReceivedBytes)
                        {
                            return Failure(
                                "Durable transfer length does not match its receipt.",
                                "transfer_state_invalid");
                        }
                        stream.Position = receipt.ReceivedBytes;
                        stream.Write(bytes);
                        stream.Flush(flushToDisk: true);
                    }
                    receipt = receipt with { ReceivedBytes = receipt.ReceivedBytes + bytes.Length };
                    WriteTransferReceipt(receipt);
                    return receipt.ReceivedBytes == receipt.TotalBytes
                        ? FinalizeTransfer(receipt, duplicate: false)
                        : TransferSuccess(receipt, duplicate: false);
                }
                catch (Exception exception)
                {
                    return Failure(
                        $"Unable to write file chunk: {exception.Message}",
                        "transfer_failed");
                }
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    public object TransferStatus(JsonElement request)
    {
        var transferId = RequireIdentifier(request, "transferId");
        lock (transferLock)
        {
            var receipt = ReadTransferReceipt(transferId);
            return receipt is null
                ? Failure("Transfer receipt not found.", "transfer_not_found")
                : TransferSuccess(
                    receipt,
                    duplicate: false,
                    action: "fs.transferstatus");
        }
    }

    public object Mkdir(JsonElement request)
    {
        var path = RequireAbsolutePath(request, "path");
        try
        {
            Directory.CreateDirectory(path);
            return Success(("action", "fs.mkdir"), ("path", path));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to create directory: {exception.Message}", "mkdir_failed");
        }
    }

    public object Copy(JsonElement request)
    {
        var source = RequireAbsolutePath(request, "source");
        var destination = RequireAbsolutePath(request, "destination");
        var overwrite = GetBoolean(request, "overwrite", false);
        try
        {
            CopyPath(source, destination, overwrite);
            return Success(("action", "fs.copy"), ("source", source), ("destination", destination));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to copy path: {exception.Message}", "copy_failed");
        }
    }

    public object Move(JsonElement request)
    {
        var source = RequireAbsolutePath(request, "source");
        var destination = RequireAbsolutePath(request, "destination");
        var overwrite = GetBoolean(request, "overwrite", false);
        try
        {
            MovePath(source, destination, overwrite);
            return Success(("action", "fs.move"), ("source", source), ("destination", destination));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to move path: {exception.Message}", "move_failed");
        }
    }

    public object Quarantine(JsonElement request)
    {
        var source = RequireAbsolutePath(request, "path");
        RefuseProtectedRemoval(source);
        if (!File.Exists(source) && !Directory.Exists(source))
        {
            return Failure($"Path not found: {source}", "path_not_found");
        }

        var receiptId = Guid.NewGuid().ToString("N");
        var destinationDirectory = Path.Combine(quarantineRoot, receiptId);
        var destination = Path.Combine(destinationDirectory, Path.GetFileName(source.TrimEnd(Path.DirectorySeparatorChar)));
        try
        {
            Directory.CreateDirectory(destinationDirectory);
            MovePath(source, destination, overwrite: false);
            var receipt = new QuarantineReceipt(
                receiptId,
                source,
                destination,
                "quarantined",
                clock(),
                null);
            WriteReceipt(receipt);
            return Success(
                ("action", "fs.quarantine"),
                ("path", source),
                ("receiptId", receiptId),
                ("quarantinePath", destination));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to quarantine path: {exception.Message}", "quarantine_failed");
        }
    }

    public object Restore(JsonElement request)
    {
        var receiptId = RequireIdentifier(request, "receiptId");
        var receipt = ReadReceipt(receiptId);
        if (receipt is null)
        {
            return Failure("Quarantine receipt not found.", "receipt_not_found");
        }

        if (!string.Equals(receipt.Status, "quarantined", StringComparison.Ordinal))
        {
            return Failure($"Receipt cannot be restored from status {receipt.Status}.", "invalid_receipt_state");
        }

        var destination = GetString(request, "destination") is { Length: > 0 } requested
            ? NormalizeAbsolutePath(requested)
            : receipt.OriginalPath;
        var overwrite = GetBoolean(request, "overwrite", false);
        try
        {
            MovePath(receipt.QuarantinePath, destination, overwrite);
            var updated = receipt with { Status = "restored", CompletedAt = clock() };
            WriteReceipt(updated);
            return Success(
                ("action", "fs.restore"),
                ("receiptId", receiptId),
                ("path", destination));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to restore path: {exception.Message}", "restore_failed");
        }
    }

    public object Purge(JsonElement request)
    {
        var receiptId = RequireIdentifier(request, "receiptId");
        var receipt = ReadReceipt(receiptId);
        if (receipt is null)
        {
            return Failure("Quarantine receipt not found.", "receipt_not_found");
        }

        if (!string.Equals(receipt.Status, "quarantined", StringComparison.Ordinal))
        {
            return Failure($"Receipt cannot be purged from status {receipt.Status}.", "invalid_receipt_state");
        }

        try
        {
            DeletePath(receipt.QuarantinePath);
            var parent = Path.GetDirectoryName(receipt.QuarantinePath);
            if (parent is not null && Directory.Exists(parent) && !Directory.EnumerateFileSystemEntries(parent).Any())
            {
                Directory.Delete(parent);
            }

            var updated = receipt with { Status = "purged", CompletedAt = clock() };
            WriteReceipt(updated);
            return Success(("action", "fs.purge"), ("receiptId", receiptId));
        }
        catch (Exception exception)
        {
            return Failure($"Unable to purge quarantined path: {exception.Message}", "purge_failed");
        }
    }

    private void RefuseProtectedRemoval(string path)
    {
        var root = Path.GetPathRoot(path);
        if (string.Equals(
                path.TrimEnd(Path.DirectorySeparatorChar),
                root?.TrimEnd(Path.DirectorySeparatorChar),
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Volume roots cannot be quarantined.");
        }

        if (IsWithin(options.StateRoot, path) || IsWithin(path, options.StateRoot))
        {
            throw new InvalidOperationException("Bridge state cannot be quarantined.");
        }
    }

    private static void CopyPath(string source, string destination, bool overwrite)
    {
        if (File.Exists(source))
        {
            var parent = Path.GetDirectoryName(destination);
            if (parent is not null)
            {
                Directory.CreateDirectory(parent);
            }
            File.Copy(source, destination, overwrite);
            return;
        }

        if (!Directory.Exists(source))
        {
            throw new FileNotFoundException("Source path not found.", source);
        }

        if (File.Exists(destination))
        {
            throw new IOException("Destination is a file.");
        }

        if (Directory.Exists(destination) && !overwrite)
        {
            throw new IOException("Destination exists; set overwrite=true to merge it.");
        }

        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.EnumerateDirectories(source, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Combine(destination, Path.GetRelativePath(source, directory)));
        }
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite);
        }
    }

    private static void MovePath(string source, string destination, bool overwrite)
    {
        if (!File.Exists(source) && !Directory.Exists(source))
        {
            throw new FileNotFoundException("Source path not found.", source);
        }

        if ((File.Exists(destination) || Directory.Exists(destination)) && !overwrite)
        {
            throw new IOException("Destination exists; set overwrite=true to replace it.");
        }

        if (overwrite)
        {
            DeletePath(destination);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        try
        {
            if (File.Exists(source))
            {
                File.Move(source, destination);
            }
            else
            {
                Directory.Move(source, destination);
            }
        }
        catch (IOException)
        {
            CopyPath(source, destination, overwrite: false);
            DeletePath(source);
        }
    }

    private static void DeletePath(string path)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
        else if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    private QuarantineReceipt? ReadReceipt(string receiptId)
    {
        var path = ReceiptPath(receiptId);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<QuarantineReceipt>(File.ReadAllText(path))
            : null;
    }

    private void WriteReceipt(QuarantineReceipt receipt)
    {
        Directory.CreateDirectory(quarantineReceiptsRoot);
        File.WriteAllText(ReceiptPath(receipt.ReceiptId), JsonSerializer.Serialize(receipt));
    }

    private string ReceiptPath(string receiptId) => Path.Combine(quarantineReceiptsRoot, receiptId + ".json");

    private object FinalizeTransfer(TransferReceipt receipt, bool duplicate)
    {
        if (!File.Exists(receipt.PartialPath)
            || new FileInfo(receipt.PartialPath).Length != receipt.TotalBytes)
        {
            return Failure(
                "Durable transfer bytes are incomplete.",
                "transfer_state_invalid");
        }
        var actualHash = Sha256File(receipt.PartialPath);
        if (!string.Equals(
            actualHash,
            receipt.FileSha256,
            StringComparison.OrdinalIgnoreCase))
        {
            return Failure("Completed transfer SHA-256 is invalid.", "file_hash_mismatch");
        }
        if ((File.Exists(receipt.Path) || Directory.Exists(receipt.Path)) && !receipt.Overwrite)
        {
            return Failure(
                "Target exists; transfer remains resumable until overwrite is approved.",
                "overwrite_required");
        }
        MovePath(receipt.PartialPath, receipt.Path, receipt.Overwrite);
        var completed = receipt with
        {
            Status = "completed",
            CompletedAt = clock()
        };
        WriteTransferReceipt(completed);
        return TransferSuccess(completed, duplicate);
    }

    private static object TransferSuccess(
        TransferReceipt receipt,
        bool duplicate,
        string action = "fs.writechunk") =>
        Success(
            ("action", action),
            ("transferId", receipt.TransferId),
            ("path", receipt.Path),
            ("receivedBytes", receipt.ReceivedBytes),
            ("totalBytes", receipt.TotalBytes),
            ("nextOffset", receipt.ReceivedBytes),
            ("fileSha256", receipt.FileSha256),
            ("status", receipt.Status),
            ("complete", string.Equals(receipt.Status, "completed", StringComparison.Ordinal)),
            ("duplicate", duplicate));

    private bool ChunkMatches(string path, long offset, byte[] expected)
    {
        if (!File.Exists(path) || offset + expected.Length > new FileInfo(path).Length)
        {
            return false;
        }
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        stream.Position = offset;
        var actual = new byte[expected.Length];
        try
        {
            var read = stream.Read(actual, 0, actual.Length);
            return read == expected.Length
                && CryptographicOperations.FixedTimeEquals(actual, expected);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(actual);
        }
    }

    private TransferReceipt? ReadTransferReceipt(string transferId)
    {
        var path = TransferReceiptPath(transferId);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<TransferReceipt>(File.ReadAllText(path))
            : null;
    }

    private void WriteTransferReceipt(TransferReceipt receipt)
    {
        Directory.CreateDirectory(transferReceiptsRoot);
        var path = TransferReceiptPath(receipt.TransferId);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(receipt));
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    private string TransferItemPath(string transferId) =>
        Path.Combine(transferItemsRoot, transferId + ".partial");

    private string TransferReceiptPath(string transferId) =>
        Path.Combine(transferReceiptsRoot, transferId + ".json");

    private static string RequireSha256(JsonElement request, string name)
    {
        var value = GetString(request, name)?.Trim().ToLowerInvariant();
        if (value is null || value.Length != 64 || !value.All(Uri.IsHexDigit))
        {
            throw new InvalidDataException($"Invalid {name}.");
        }
        return value;
    }

    private static string Sha256(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static string Sha256File(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    internal static string RequireAbsolutePath(JsonElement request, string name)
    {
        var value = GetString(request, name);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidDataException($"Missing {name}.");
        }
        return NormalizeAbsolutePath(value);
    }

    private static string NormalizeAbsolutePath(string value)
    {
        if (!Path.IsPathFullyQualified(value))
        {
            throw new InvalidDataException("Path must be absolute.");
        }
        return Path.GetFullPath(value);
    }

    private static string RequireIdentifier(JsonElement request, string name)
    {
        var value = GetString(request, name);
        if (string.IsNullOrWhiteSpace(value)
            || value.Length > 128
            || !value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_'))
        {
            throw new InvalidDataException($"Invalid {name}.");
        }
        return value;
    }

    internal static bool IsSuccess(object value) =>
        value is Dictionary<string, object?> map
        && map.TryGetValue("ok", out var ok)
        && ok is true;

    internal static Dictionary<string, object?> Success(params (string Key, object? Value)[] values)
    {
        var result = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["ok"] = true
        };
        foreach (var (key, value) in values)
        {
            result[key] = value;
        }
        return result;
    }

    internal static Dictionary<string, object?> Failure(string error, string code) => new(StringComparer.Ordinal)
    {
        ["ok"] = false,
        ["error"] = error,
        ["errorCode"] = code
    };

    internal static string? GetString(JsonElement request, string name) =>
        request.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

    internal static int GetInt(JsonElement request, string name, int fallback) =>
        request.TryGetProperty(name, out var property) && property.TryGetInt32(out var value)
            ? value
            : fallback;

    internal static long GetLong(JsonElement request, string name, long fallback) =>
        request.TryGetProperty(name, out var property) && property.TryGetInt64(out var value)
            ? value
            : fallback;

    internal static bool GetBoolean(JsonElement request, string name, bool fallback) =>
        request.TryGetProperty(name, out var property)
        && property.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? property.GetBoolean()
            : fallback;

    private static bool IsWithin(string parent, string child)
    {
        var normalizedParent = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var normalizedChild = Path.GetFullPath(child).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return normalizedChild.StartsWith(normalizedParent, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record QuarantineReceipt(
        string ReceiptId,
        string OriginalPath,
        string QuarantinePath,
        string Status,
        DateTimeOffset CreatedAt,
        DateTimeOffset? CompletedAt);

    private sealed record TransferReceipt(
        string TransferId,
        string Path,
        string PartialPath,
        long TotalBytes,
        long ReceivedBytes,
        string FileSha256,
        bool Overwrite,
        string Status,
        DateTimeOffset CreatedAt,
        DateTimeOffset? CompletedAt);
}
