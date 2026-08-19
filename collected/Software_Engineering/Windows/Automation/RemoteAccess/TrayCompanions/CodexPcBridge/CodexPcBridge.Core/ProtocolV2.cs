using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace CodexPcBridge.Core;

public sealed record ProtocolPublicIdentity(
    string DeviceId,
    string SigningPublicKey,
    string AgreementPublicKey,
    string Fingerprint);

public sealed class ProtocolV2Identity : IDisposable
{
    private const int CurrentVersion = 1;
    private const string FileName = "protocol-v2-identity.json";
    private static readonly byte[] DpapiEntropy =
        SHA256.HashData(Encoding.UTF8.GetBytes("CodexPcBridge protocol v2 P-256 identity"));

    private readonly ECDsa signingKey;
    private readonly ECDiffieHellman agreementKey;
    private bool disposed;

    private ProtocolV2Identity(
        string deviceId,
        ECDsa signingKey,
        ECDiffieHellman agreementKey)
    {
        DeviceId = deviceId;
        this.signingKey = signingKey;
        this.agreementKey = agreementKey;
        PublicIdentity = CreatePublicIdentity(deviceId, signingKey, agreementKey);
    }

    public string DeviceId { get; }
    public ProtocolPublicIdentity PublicIdentity { get; }

    public static ProtocolV2Identity LoadOrCreate(string stateRoot, string deviceId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(stateRoot);
        ValidateIdentifier(deviceId, nameof(deviceId));
        var root = Path.GetFullPath(stateRoot);
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, FileName);
        if (File.Exists(path))
        {
            return Read(path, deviceId);
        }

        using var signing = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        using var agreement = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var payload = JsonSerializer.Serialize(
            new
            {
                version = CurrentVersion,
                deviceId,
                protectedSigningPrivateKey = Protect(signing.ExportPkcs8PrivateKey()),
                protectedAgreementPrivateKey = Protect(agreement.ExportPkcs8PrivateKey()),
                createdAt = DateTimeOffset.UtcNow
            },
            new JsonSerializerOptions { WriteIndented = true });
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, payload, new UTF8Encoding(false));
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
        return Read(path, deviceId);
    }

    public byte[] Sign(ReadOnlySpan<byte> data)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        return signingKey.SignData(
            data,
            HashAlgorithmName.SHA256,
            DSASignatureFormat.Rfc3279DerSequence);
    }

    internal byte[] SignRaw(ReadOnlySpan<byte> data)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        return signingKey.SignData(
            data,
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }

    public byte[] DeriveSharedSecret(string peerAgreementPublicKey)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        using var peer = ECDiffieHellman.Create();
        peer.ImportSubjectPublicKeyInfo(
            Convert.FromBase64String(peerAgreementPublicKey),
            out _);
        return agreementKey.DeriveRawSecretAgreement(peer.PublicKey);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        signingKey.Dispose();
        agreementKey.Dispose();
    }

    private static ProtocolV2Identity Read(string path, string expectedDeviceId)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.GetProperty("version").GetInt32() != CurrentVersion)
        {
            throw new InvalidDataException("Unsupported protocol-v2 identity version.");
        }
        var storedDeviceId = root.GetProperty("deviceId").GetString();
        if (!string.Equals(storedDeviceId, expectedDeviceId, StringComparison.Ordinal))
        {
            throw new InvalidDataException("Protocol-v2 identity belongs to another device id.");
        }

        var signingBytes = Unprotect(root.GetProperty("protectedSigningPrivateKey").GetString());
        var agreementBytes = Unprotect(root.GetProperty("protectedAgreementPrivateKey").GetString());
        try
        {
            var signing = ECDsa.Create();
            signing.ImportPkcs8PrivateKey(signingBytes, out _);
            var agreement = ECDiffieHellman.Create();
            agreement.ImportPkcs8PrivateKey(agreementBytes, out _);
            return new ProtocolV2Identity(expectedDeviceId, signing, agreement);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(signingBytes);
            CryptographicOperations.ZeroMemory(agreementBytes);
        }
    }

    private static ProtocolPublicIdentity CreatePublicIdentity(
        string deviceId,
        ECDsa signing,
        ECDiffieHellman agreement)
    {
        var signingPublicKey = signing.ExportSubjectPublicKeyInfo();
        var agreementPublicKey = agreement.ExportSubjectPublicKeyInfo();
        var fingerprintInput = new byte[signingPublicKey.Length + agreementPublicKey.Length];
        signingPublicKey.CopyTo(fingerprintInput, 0);
        agreementPublicKey.CopyTo(fingerprintInput, signingPublicKey.Length);
        var fingerprint = Convert.ToHexString(SHA256.HashData(fingerprintInput)).ToLowerInvariant();
        return new ProtocolPublicIdentity(
            deviceId,
            Convert.ToBase64String(signingPublicKey),
            Convert.ToBase64String(agreementPublicKey),
            fingerprint);
    }

    private static string Protect(byte[] value)
    {
        try
        {
            return Convert.ToBase64String(
                ProtectedData.Protect(value, DpapiEntropy, DataProtectionScope.LocalMachine));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(value);
        }
    }

    private static byte[] Unprotect(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidDataException("Protected protocol-v2 key is missing.");
        }
        try
        {
            return ProtectedData.Unprotect(
                Convert.FromBase64String(value),
                DpapiEntropy,
                DataProtectionScope.LocalMachine);
        }
        catch (Exception exception) when (exception is FormatException or CryptographicException)
        {
            throw new InvalidDataException(
                "Protocol-v2 key cannot be decrypted on this machine.",
                exception);
        }
    }

    internal static void ValidateIdentifier(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value)
            || value.Length > 128
            || !value.All(character =>
                char.IsAsciiLetterOrDigit(character) || character is '-' or '_'))
        {
            throw new InvalidDataException($"Invalid {name}.");
        }
    }
}

public sealed record ProtocolV2Envelope
{
    [JsonPropertyName("protocolVersion")]
    public int ProtocolVersion { get; init; } = 2;

    [JsonPropertyName("messageId")]
    public required string MessageId { get; init; }

    [JsonPropertyName("idempotencyKey")]
    public required string IdempotencyKey { get; init; }

    [JsonPropertyName("deviceId")]
    public required string DeviceId { get; init; }

    [JsonPropertyName("targetDeviceId")]
    public required string TargetDeviceId { get; init; }

    [JsonPropertyName("jobId")]
    public required string JobId { get; init; }

    [JsonPropertyName("capability")]
    public required string Capability { get; init; }

    [JsonPropertyName("sequence")]
    public long Sequence { get; init; }

    [JsonPropertyName("issuedAt")]
    public DateTimeOffset IssuedAt { get; init; }

    [JsonPropertyName("expiresAt")]
    public DateTimeOffset ExpiresAt { get; init; }

    [JsonPropertyName("nonce")]
    public required string Nonce { get; init; }

    [JsonPropertyName("encryptedPayload")]
    public required string EncryptedPayload { get; init; }

    [JsonPropertyName("tag")]
    public required string Tag { get; init; }

    [JsonPropertyName("signature")]
    public required string Signature { get; init; }

    [JsonPropertyName("senderKeyFingerprint")]
    public required string SenderKeyFingerprint { get; init; }
}

public sealed record ProtocolPeerState(
    ProtocolPublicIdentity Identity,
    string DisplayName,
    string GroupId,
    bool Revoked,
    long LastIncomingSequence,
    string? LastIncomingMessageId,
    long NextOutgoingSequence,
    DateTimeOffset EnrolledAt,
    DateTimeOffset? RevokedAt);

public sealed record ProtocolV2ConnectionProfile(
    int ProtocolVersion,
    string GroupId,
    string RelayAddress,
    ProtocolPublicIdentity PcIdentity,
    ProtocolPublicIdentity AndroidIdentity);

public sealed record ProtocolV2PeerCommandRequest
{
    [JsonPropertyName("targetDeviceId")]
    public string? TargetDeviceId { get; init; }

    [JsonPropertyName("action")]
    public required string Action { get; init; }

    [JsonPropertyName("jobId")]
    public required string JobId { get; init; }

    [JsonPropertyName("idempotencyKey")]
    public required string IdempotencyKey { get; init; }

    [JsonPropertyName("arguments")]
    public JsonElement Arguments { get; init; }
}

public sealed record ProtocolV2PeerCommandResult(
    bool Ok,
    string PeerDeviceId,
    ProtocolV2Envelope RequestEnvelope,
    ProtocolV2Envelope ResponseEnvelope,
    JsonElement Payload,
    bool Replayed);

public enum IncomingSequenceResult
{
    Accepted,
    DuplicateMessage,
    Rejected
}

public sealed class ProtocolPeerStore
{
    private readonly string root;
    private readonly object stateLock = new();

    public ProtocolPeerStore(string stateRoot)
    {
        root = Path.Combine(Path.GetFullPath(stateRoot), "protocol-v2-peers");
        Directory.CreateDirectory(root);
    }

    public ProtocolPeerState AddOrUpdate(
        ProtocolPublicIdentity identity,
        string displayName,
        string groupId,
        DateTimeOffset enrolledAt)
    {
        ValidatePublicIdentity(identity);
        ProtocolV2Identity.ValidateIdentifier(groupId, nameof(groupId));
        lock (stateLock)
        {
            var existing = TryRead(identity.DeviceId);
            var state = new ProtocolPeerState(
                identity,
                string.IsNullOrWhiteSpace(displayName) ? identity.DeviceId : displayName.Trim(),
                groupId,
                Revoked: false,
                existing?.LastIncomingSequence ?? -1,
                existing?.LastIncomingMessageId,
                existing?.NextOutgoingSequence ?? 0,
                existing?.EnrolledAt ?? enrolledAt,
                RevokedAt: null);
            Write(state);
            return state;
        }
    }

    public ProtocolPeerState GetRequired(string deviceId)
    {
        lock (stateLock)
        {
            var state = TryRead(deviceId)
                ?? throw new ProtocolV2Exception("unknown_device", "Device is not enrolled.");
            if (state.Revoked)
            {
                throw new ProtocolV2Exception("device_revoked", "Device enrollment is revoked.");
            }
            return state;
        }
    }

    public IncomingSequenceResult AcceptIncoming(
        string deviceId,
        long sequence,
        string messageId)
    {
        if (sequence < 0)
        {
            return IncomingSequenceResult.Rejected;
        }
        lock (stateLock)
        {
            var state = GetRequiredUnlocked(deviceId);
            if (sequence < state.LastIncomingSequence)
            {
                return IncomingSequenceResult.Rejected;
            }
            if (sequence == state.LastIncomingSequence)
            {
                return string.Equals(
                    messageId,
                    state.LastIncomingMessageId,
                    StringComparison.Ordinal)
                    ? IncomingSequenceResult.DuplicateMessage
                    : IncomingSequenceResult.Rejected;
            }

            Write(state with
            {
                LastIncomingSequence = sequence,
                LastIncomingMessageId = messageId
            });
            return IncomingSequenceResult.Accepted;
        }
    }

    public long NextOutgoingSequence(string deviceId)
    {
        lock (stateLock)
        {
            var state = GetRequiredUnlocked(deviceId);
            var next = checked(state.NextOutgoingSequence + 1);
            Write(state with { NextOutgoingSequence = next });
            return next;
        }
    }

    public void Revoke(string deviceId, DateTimeOffset revokedAt)
    {
        lock (stateLock)
        {
            var state = GetRequiredUnlocked(deviceId);
            Write(state with { Revoked = true, RevokedAt = revokedAt });
        }
    }

    private ProtocolPeerState GetRequiredUnlocked(string deviceId)
    {
        var state = TryRead(deviceId)
            ?? throw new ProtocolV2Exception("unknown_device", "Device is not enrolled.");
        if (state.Revoked)
        {
            throw new ProtocolV2Exception("device_revoked", "Device enrollment is revoked.");
        }
        return state;
    }

    private ProtocolPeerState? TryRead(string deviceId)
    {
        ProtocolV2Identity.ValidateIdentifier(deviceId, nameof(deviceId));
        var path = PathFor(deviceId);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<ProtocolPeerState>(File.ReadAllText(path))
            : null;
    }

    private void Write(ProtocolPeerState state)
    {
        var path = PathFor(state.Identity.DeviceId);
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state));
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

    private string PathFor(string deviceId) => Path.Combine(root, deviceId + ".json");

    internal static void ValidatePublicIdentity(ProtocolPublicIdentity identity)
    {
        ProtocolV2Identity.ValidateIdentifier(identity.DeviceId, nameof(identity.DeviceId));
        using var signing = ECDsa.Create();
        signing.ImportSubjectPublicKeyInfo(Convert.FromBase64String(identity.SigningPublicKey), out _);
        using var agreement = ECDiffieHellman.Create();
        agreement.ImportSubjectPublicKeyInfo(Convert.FromBase64String(identity.AgreementPublicKey), out _);
        var expected = ComputeFingerprint(identity.SigningPublicKey, identity.AgreementPublicKey);
        if (!string.Equals(expected, identity.Fingerprint, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Peer public-key fingerprint does not match.");
        }
    }

    internal static string ComputeFingerprint(
        string signingPublicKey,
        string agreementPublicKey)
    {
        var signing = Convert.FromBase64String(signingPublicKey);
        var agreement = Convert.FromBase64String(agreementPublicKey);
        var combined = new byte[signing.Length + agreement.Length];
        signing.CopyTo(combined, 0);
        agreement.CopyTo(combined, signing.Length);
        return Convert.ToHexString(SHA256.HashData(combined)).ToLowerInvariant();
    }
}

public sealed class ProtocolV2Exception : Exception
{
    public ProtocolV2Exception(string code, string message)
        : base(message)
    {
        Code = code;
    }

    public string Code { get; }
}

public static class ProtocolV2Crypto
{
    private const int NonceBytes = 12;
    private const int TagBytes = 16;
    private const int KeyBytes = 32;

    public static ProtocolV2Envelope Encrypt(
        ProtocolV2Identity sender,
        ProtocolPublicIdentity recipient,
        string messageId,
        string idempotencyKey,
        string jobId,
        string capability,
        long sequence,
        DateTimeOffset issuedAt,
        DateTimeOffset expiresAt,
        object payload)
    {
        ValidateMetadata(
            messageId,
            idempotencyKey,
            sender.DeviceId,
            recipient.DeviceId,
            jobId,
            capability,
            sequence,
            issuedAt,
            expiresAt);
        var nonce = RandomNumberGenerator.GetBytes(NonceBytes);
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(payload);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagBytes];
        var envelope = new ProtocolV2Envelope
        {
            MessageId = messageId,
            IdempotencyKey = idempotencyKey,
            DeviceId = sender.DeviceId,
            TargetDeviceId = recipient.DeviceId,
            JobId = jobId,
            Capability = capability,
            Sequence = sequence,
            IssuedAt = issuedAt,
            ExpiresAt = expiresAt,
            Nonce = Convert.ToBase64String(nonce),
            EncryptedPayload = string.Empty,
            Tag = string.Empty,
            Signature = string.Empty,
            SenderKeyFingerprint = sender.PublicIdentity.Fingerprint
        };
        var aad = CanonicalMetadata(envelope);
        var key = DeriveKey(sender, recipient);
        try
        {
            using var aes = new AesGcm(key, TagBytes);
            aes.Encrypt(nonce, plaintext, ciphertext, tag, aad);
            envelope = envelope with
            {
                EncryptedPayload = Convert.ToBase64String(ciphertext),
                Tag = Convert.ToBase64String(tag)
            };
            var signatureInput = SignatureInput(envelope, aad);
            envelope = envelope with
            {
                Signature = Convert.ToBase64String(sender.Sign(signatureInput))
            };
            return envelope;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public static JsonElement Decrypt(
        ProtocolV2Identity recipient,
        ProtocolPublicIdentity sender,
        ProtocolV2Envelope envelope,
        DateTimeOffset now)
    {
        if (envelope.ProtocolVersion != 2)
        {
            throw new ProtocolV2Exception("unsupported_protocol", "Unsupported protocol version.");
        }
        ValidateMetadata(
            envelope.MessageId,
            envelope.IdempotencyKey,
            envelope.DeviceId,
            envelope.TargetDeviceId,
            envelope.JobId,
            envelope.Capability,
            envelope.Sequence,
            envelope.IssuedAt,
            envelope.ExpiresAt);
        if (!string.Equals(envelope.DeviceId, sender.DeviceId, StringComparison.Ordinal)
            || !string.Equals(envelope.TargetDeviceId, recipient.DeviceId, StringComparison.Ordinal))
        {
            throw new ProtocolV2Exception("identity_mismatch", "Envelope device identity mismatch.");
        }
        if (!string.Equals(
                envelope.SenderKeyFingerprint,
                sender.Fingerprint,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ProtocolV2Exception("identity_mismatch", "Sender key fingerprint mismatch.");
        }
        if (envelope.ExpiresAt <= now)
        {
            throw new ProtocolV2Exception("request_expired", "Envelope has expired.");
        }
        if (envelope.IssuedAt > now.AddMinutes(5))
        {
            throw new ProtocolV2Exception("invalid_time", "Envelope issue time is in the future.");
        }

        byte[] nonce;
        byte[] ciphertext;
        byte[] tag;
        byte[] signature;
        try
        {
            nonce = Convert.FromBase64String(envelope.Nonce);
            ciphertext = Convert.FromBase64String(envelope.EncryptedPayload);
            tag = Convert.FromBase64String(envelope.Tag);
            signature = Convert.FromBase64String(envelope.Signature);
        }
        catch (FormatException exception)
        {
            throw new ProtocolV2Exception("invalid_encoding", exception.Message);
        }
        if (nonce.Length != NonceBytes || tag.Length != TagBytes)
        {
            throw new ProtocolV2Exception("invalid_envelope", "Invalid AES-GCM nonce or tag length.");
        }

        var aad = CanonicalMetadata(envelope);
        var signatureInput = SignatureInput(envelope, aad);
        using (var verifier = ECDsa.Create())
        {
            verifier.ImportSubjectPublicKeyInfo(
                Convert.FromBase64String(sender.SigningPublicKey),
                out _);
            if (!verifier.VerifyData(
                    signatureInput,
                    signature,
                    HashAlgorithmName.SHA256,
                    DSASignatureFormat.Rfc3279DerSequence))
            {
                throw new ProtocolV2Exception("signature_invalid", "Envelope signature is invalid.");
            }
        }

        var plaintext = new byte[ciphertext.Length];
        var key = DeriveKey(recipient, sender);
        try
        {
            using var aes = new AesGcm(key, TagBytes);
            try
            {
                aes.Decrypt(nonce, ciphertext, tag, plaintext, aad);
            }
            catch (AuthenticationTagMismatchException exception)
            {
                throw new ProtocolV2Exception("decryption_failed", exception.Message);
            }
            using var payload = JsonDocument.Parse(plaintext);
            return payload.RootElement.Clone();
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public static byte[] SignEnrollmentTranscript(
        ProtocolV2Identity identity,
        ReadOnlySpan<byte> transcript) =>
        identity.Sign(transcript);

    public static bool VerifyEnrollmentTranscript(
        ProtocolPublicIdentity identity,
        ReadOnlySpan<byte> transcript,
        string signature)
    {
        ProtocolPeerStore.ValidatePublicIdentity(identity);
        using var verifier = ECDsa.Create();
        verifier.ImportSubjectPublicKeyInfo(
            Convert.FromBase64String(identity.SigningPublicKey),
            out _);
        return verifier.VerifyData(
            transcript,
            Convert.FromBase64String(signature),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.Rfc3279DerSequence);
    }

    private static byte[] DeriveKey(
        ProtocolV2Identity identity,
        ProtocolPublicIdentity peer)
    {
        var sharedSecret = identity.DeriveSharedSecret(peer.AgreementPublicKey);
        try
        {
            var devicePair = new[] { identity.DeviceId, peer.DeviceId }
                .OrderBy(value => value, StringComparer.Ordinal);
            var salt = SHA256.HashData(
                Encoding.UTF8.GetBytes(string.Join("\n", devicePair)));
            return HkdfSha256(
                sharedSecret,
                salt,
                Encoding.UTF8.GetBytes("codex-pc-bridge/protocol-v2/aes-256-gcm"),
                KeyBytes);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(sharedSecret);
        }
    }

    private static byte[] HkdfSha256(
        byte[] inputKeyMaterial,
        byte[] salt,
        byte[] info,
        int length)
    {
        using var extract = new HMACSHA256(salt);
        var pseudorandomKey = extract.ComputeHash(inputKeyMaterial);
        try
        {
            var output = new byte[length];
            var previous = Array.Empty<byte>();
            var offset = 0;
            byte counter = 1;
            using var expand = new HMACSHA256(pseudorandomKey);
            while (offset < length)
            {
                var input = new byte[previous.Length + info.Length + 1];
                previous.CopyTo(input, 0);
                info.CopyTo(input, previous.Length);
                input[^1] = counter++;
                previous = expand.ComputeHash(input);
                var count = Math.Min(previous.Length, length - offset);
                previous.AsSpan(0, count).CopyTo(output.AsSpan(offset));
                offset += count;
            }
            CryptographicOperations.ZeroMemory(previous);
            return output;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(pseudorandomKey);
        }
    }

    private static byte[] CanonicalMetadata(ProtocolV2Envelope envelope) =>
        Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-pc-bridge-v2",
            envelope.MessageId,
            envelope.IdempotencyKey,
            envelope.DeviceId,
            envelope.TargetDeviceId,
            envelope.JobId,
            envelope.Capability,
            envelope.Sequence.ToString(System.Globalization.CultureInfo.InvariantCulture),
            envelope.IssuedAt.ToUnixTimeMilliseconds().ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            envelope.ExpiresAt.ToUnixTimeMilliseconds().ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            envelope.Nonce,
            envelope.SenderKeyFingerprint));

    private static byte[] SignatureInput(
        ProtocolV2Envelope envelope,
        byte[] aad)
    {
        var ciphertext = Convert.FromBase64String(envelope.EncryptedPayload);
        var tag = Convert.FromBase64String(envelope.Tag);
        var result = new byte[aad.Length + 1 + ciphertext.Length + tag.Length];
        aad.CopyTo(result, 0);
        result[aad.Length] = 0;
        ciphertext.CopyTo(result, aad.Length + 1);
        tag.CopyTo(result, aad.Length + 1 + ciphertext.Length);
        return result;
    }

    private static void ValidateMetadata(
        string messageId,
        string idempotencyKey,
        string deviceId,
        string targetDeviceId,
        string jobId,
        string capability,
        long sequence,
        DateTimeOffset issuedAt,
        DateTimeOffset expiresAt)
    {
        ProtocolV2Identity.ValidateIdentifier(messageId, nameof(messageId));
        ProtocolV2Identity.ValidateIdentifier(idempotencyKey, nameof(idempotencyKey));
        ProtocolV2Identity.ValidateIdentifier(deviceId, nameof(deviceId));
        ProtocolV2Identity.ValidateIdentifier(targetDeviceId, nameof(targetDeviceId));
        ProtocolV2Identity.ValidateIdentifier(jobId, nameof(jobId));
        if (string.IsNullOrWhiteSpace(capability)
            || capability.Length > 128
            || !capability.All(character =>
                char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.'))
        {
            throw new ProtocolV2Exception("invalid_metadata", "Invalid capability.");
        }
        if (sequence < 0 || issuedAt >= expiresAt)
        {
            throw new ProtocolV2Exception("invalid_metadata", "Invalid sequence or validity window.");
        }
    }
}

public sealed class ProtocolV2CommandProcessor : IAsyncDisposable
{
    private const int MaxCachedResponses = 256;
    private const int MaxOutgoingCommands = 512;
    private static readonly TimeSpan ResponseLifetime = TimeSpan.FromHours(23);
    private static readonly TimeSpan OutgoingRequestLifetime = TimeSpan.FromMinutes(2);
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web)
        {
            PropertyNameCaseInsensitive = true
        };

    private readonly string stateRoot;
    private readonly ProtocolV2Identity identity;
    private readonly ProtocolPeerStore peers;
    private readonly BridgeCommandDispatcher dispatcher;
    private readonly Func<DateTimeOffset> clock;
    private readonly bool ownsDispatcher;
    private readonly string responseRoot;
    private readonly string outgoingRoot;
    private readonly object responseLock = new();
    private readonly object outgoingLock = new();

    public ProtocolV2CommandProcessor(
        string stateRoot,
        string deviceId,
        BridgeRuntimeOptions runtimeOptions,
        IInteractiveAgent? interactiveAgent = null,
        Func<DateTimeOffset>? clock = null,
        BridgeCommandDispatcher? dispatcher = null)
    {
        this.stateRoot = Path.GetFullPath(stateRoot);
        responseRoot = Path.Combine(this.stateRoot, "protocol-v2-responses");
        outgoingRoot = Path.Combine(this.stateRoot, "protocol-v2-outgoing");
        Directory.CreateDirectory(responseRoot);
        Directory.CreateDirectory(outgoingRoot);
        identity = ProtocolV2Identity.LoadOrCreate(this.stateRoot, deviceId);
        peers = new ProtocolPeerStore(this.stateRoot);
        this.dispatcher = dispatcher ?? new BridgeCommandDispatcher(
            runtimeOptions,
            clock,
            interactiveAgent);
        ownsDispatcher = dispatcher is null;
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    public ProtocolPublicIdentity PublicIdentity => identity.PublicIdentity;
    public ProtocolPeerStore Peers => peers;

    public IReadOnlyList<ProtocolV2ConnectionProfile> ConnectionProfiles()
    {
        var result = new List<ProtocolV2ConnectionProfile>();
        foreach (var profile in ProtocolV2RelayRegistration.Load(stateRoot))
        {
            if (!string.Equals(
                    profile.PcDeviceId,
                    identity.DeviceId,
                    StringComparison.Ordinal))
            {
                continue;
            }
            try
            {
                var android = peers.GetRequired(profile.PeerDeviceId);
                result.Add(new ProtocolV2ConnectionProfile(
                    ProtocolVersion: 2,
                    GroupId: profile.GroupId,
                    RelayAddress: profile.RelayAddress,
                    PcIdentity: identity.PublicIdentity,
                    AndroidIdentity: android.Identity));
            }
            catch (ProtocolV2Exception)
            {
                // Revoked or missing peers are not advertised to browsers.
            }
        }
        return result;
    }

    public ProtocolV2PreparedPeerCommand PrepareOutgoing(
        ProtocolV2PeerCommandRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        ProtocolV2Identity.ValidateIdentifier(request.JobId, nameof(request.JobId));
        ProtocolV2Identity.ValidateIdentifier(
            request.IdempotencyKey,
            nameof(request.IdempotencyKey));
        ValidateCapability(request.Action);
        if (!string.IsNullOrWhiteSpace(request.TargetDeviceId))
        {
            ProtocolV2Identity.ValidateIdentifier(
                request.TargetDeviceId,
                nameof(request.TargetDeviceId));
        }
        if (request.Arguments.ValueKind is not (
            JsonValueKind.Undefined
                or JsonValueKind.Null
                or JsonValueKind.Object))
        {
            throw new ProtocolV2Exception(
                "invalid_payload",
                "Peer-command arguments must be a JSON object.");
        }

        var profiles = ConnectionProfiles()
            .Where(profile =>
                string.IsNullOrWhiteSpace(request.TargetDeviceId)
                || string.Equals(
                    profile.AndroidIdentity.DeviceId,
                    request.TargetDeviceId,
                    StringComparison.Ordinal))
            .ToArray();
        if (profiles.Length == 0)
        {
            throw new ProtocolV2Exception(
                "peer_unavailable",
                "No active Android peer matches the request.");
        }
        if (profiles.Length != 1)
        {
            throw new ProtocolV2Exception(
                "peer_ambiguous",
                "The Android peer must be selected explicitly.");
        }

        var profile = profiles[0];
        lock (outgoingLock)
        {
            var existing = ReadOutgoingRecord(
                profile.AndroidIdentity.DeviceId,
                request.Action,
                request.JobId,
                request.IdempotencyKey);
            if (existing is not null)
            {
                return new ProtocolV2PreparedPeerCommand(
                    profile,
                    existing.RequestEnvelope,
                    existing.ResponseEnvelope is null
                        || existing.ResponsePayload is null
                        ? null
                        : new ProtocolV2PeerCommandResult(
                            true,
                            existing.PeerDeviceId,
                            existing.RequestEnvelope,
                            existing.ResponseEnvelope,
                            existing.ResponsePayload.Value,
                            Replayed: true));
            }

            var now = clock();
            var arguments = request.Arguments.ValueKind is JsonValueKind.Undefined
                or JsonValueKind.Null
                ? JsonDocument.Parse("{}").RootElement.Clone()
                : request.Arguments.Clone();
            var peer = peers.GetRequired(profile.AndroidIdentity.DeviceId);
            var envelope = ProtocolV2Crypto.Encrypt(
                identity,
                peer.Identity,
                "message-" + Guid.NewGuid().ToString("N"),
                request.IdempotencyKey,
                request.JobId,
                request.Action,
                peers.NextOutgoingSequence(peer.Identity.DeviceId),
                now,
                now.Add(OutgoingRequestLifetime),
                new
                {
                    action = request.Action,
                    arguments
                });
            WriteOutgoingRecord(new OutgoingProtocolCommand(
                peer.Identity.DeviceId,
                request.Action,
                request.JobId,
                request.IdempotencyKey,
                envelope,
                ResponseEnvelope: null,
                ResponsePayload: null,
                CreatedAt: now,
                UpdatedAt: now));
            return new ProtocolV2PreparedPeerCommand(
                profile,
                envelope,
                CompletedResult: null);
        }
    }

    public ProtocolV2PeerCommandResult AcceptOutgoingResponse(
        ProtocolV2Envelope envelope)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        if (!envelope.Capability.EndsWith(".result", StringComparison.Ordinal)
            || envelope.Capability.Length <= ".result".Length)
        {
            throw new ProtocolV2Exception(
                "outgoing_response_invalid",
                "Envelope is not a peer-command result.");
        }
        var action = envelope.Capability[..^".result".Length];
        lock (outgoingLock)
        {
            var record = ReadOutgoingRecord(
                envelope.DeviceId,
                action,
                envelope.JobId,
                envelope.IdempotencyKey)
                ?? throw new ProtocolV2Exception(
                    "outgoing_response_unknown",
                    "No durable outbound request matches this response.");
            if (record.ResponseEnvelope is not null
                && record.ResponsePayload is not null)
            {
                if (!string.Equals(
                        record.ResponseEnvelope.MessageId,
                        envelope.MessageId,
                        StringComparison.Ordinal))
                {
                    throw new ProtocolV2Exception(
                        "outgoing_response_conflict",
                        "A different response is already committed for this request.");
                }
                return new ProtocolV2PeerCommandResult(
                    true,
                    record.PeerDeviceId,
                    record.RequestEnvelope,
                    record.ResponseEnvelope,
                    record.ResponsePayload.Value,
                    Replayed: true);
            }

            var peer = peers.GetRequired(envelope.DeviceId);
            var payload = ProtocolV2Crypto.Decrypt(
                identity,
                peer.Identity,
                envelope,
                clock());
            var sequence = peers.AcceptIncoming(
                envelope.DeviceId,
                envelope.Sequence,
                envelope.MessageId);
            if (sequence == IncomingSequenceResult.Rejected)
            {
                throw new ProtocolV2Exception(
                    "replay_rejected",
                    "Peer-command response sequence was already used.");
            }
            if (!payload.TryGetProperty("acknowledgement", out var acknowledgement)
                || !acknowledgement.TryGetProperty("messageId", out var acknowledged)
                || !string.Equals(
                    acknowledged.GetString(),
                    record.RequestEnvelope.MessageId,
                    StringComparison.Ordinal))
            {
                throw new ProtocolV2Exception(
                    "outgoing_response_mismatch",
                    "Peer-command response does not acknowledge the durable request.");
            }

            var completed = record with
            {
                ResponseEnvelope = envelope,
                ResponsePayload = payload.Clone(),
                UpdatedAt = clock()
            };
            WriteOutgoingRecord(completed);
            return new ProtocolV2PeerCommandResult(
                true,
                completed.PeerDeviceId,
                completed.RequestEnvelope,
                envelope,
                payload.Clone(),
                Replayed: sequence == IncomingSequenceResult.DuplicateMessage);
        }
    }

    public async Task<ProtocolV2Envelope> ExecuteAsync(
        ProtocolV2Envelope envelope,
        CancellationToken cancellationToken)
    {
        var peer = peers.GetRequired(envelope.DeviceId);
        var payload = ProtocolV2Crypto.Decrypt(
            identity,
            peer.Identity,
            envelope,
            clock());
        var sequence = peers.AcceptIncoming(
            envelope.DeviceId,
            envelope.Sequence,
            envelope.MessageId);
        if (sequence == IncomingSequenceResult.Rejected)
        {
            throw new ProtocolV2Exception("replay_rejected", "Envelope sequence was already used.");
        }
        var requestHash = HashEnvelope(envelope);
        if (sequence == IncomingSequenceResult.DuplicateMessage)
        {
            var cached = ReadCachedResponse(envelope.DeviceId, envelope.MessageId);
            if (cached is not null)
            {
                if (!string.Equals(
                        cached.RequestHash,
                        requestHash,
                        StringComparison.Ordinal))
                {
                    throw new ProtocolV2Exception(
                        "replay_rejected",
                        "Duplicate envelope content does not match the accepted request.");
                }
                return cached.Response;
            }
        }

        var request = JsonNode.Parse(payload.GetRawText()) as JsonObject
            ?? throw new ProtocolV2Exception("invalid_payload", "Encrypted payload must be a JSON object.");
        request["protocolVersion"] = 2;
        request["messageId"] = envelope.MessageId;
        request["idempotencyKey"] = envelope.IdempotencyKey;
        request["deviceId"] = envelope.DeviceId;
        request["jobId"] = envelope.JobId;
        request["capability"] = envelope.Capability;
        request["sequence"] = envelope.Sequence;
        request["issuedAt"] = envelope.IssuedAt;
        request["expiresAt"] = envelope.ExpiresAt;

        using var requestDocument = JsonDocument.Parse(request.ToJsonString());
        var result = string.Equals(
                envelope.Capability,
                "bridge.peer.approve",
                StringComparison.Ordinal)
            ? AuthorizeBrowserPeer(peer, request)
            : await dispatcher.ExecuteAsync(
                requestDocument.RootElement,
                cancellationToken);
        var resultJson = JsonSerializer.SerializeToUtf8Bytes(result.Body);
        var now = clock();
        var responsePayload = new
        {
            acknowledgement = new
            {
                messageId = envelope.MessageId,
                duplicate = sequence == IncomingSequenceResult.DuplicateMessage
            },
            finalStatus = result.StatusCode is >= 200 and < 300 ? "completed" : "failed",
            result = result.Body,
            resultHash = Convert.ToHexString(SHA256.HashData(resultJson)).ToLowerInvariant(),
            completedAt = now
        };
        var response = ProtocolV2Crypto.Encrypt(
            identity,
            peer.Identity,
            "response-" + Guid.NewGuid().ToString("N"),
            envelope.IdempotencyKey,
            envelope.JobId,
            envelope.Capability + ".result",
            peers.NextOutgoingSequence(peer.Identity.DeviceId),
            now,
            now.Add(ResponseLifetime),
            responsePayload);
        WriteCachedResponse(
            envelope.DeviceId,
            envelope.MessageId,
            new CachedProtocolResponse(requestHash, response, now));
        return response;
    }

    private BridgeDispatchResult AuthorizeBrowserPeer(
        ProtocolPeerState approver,
        JsonObject request)
    {
        if (!string.Equals(
                request["action"]?.GetValue<string>(),
                "bridge.peer.approve",
                StringComparison.Ordinal))
        {
            throw new ProtocolV2Exception(
                "invalid_payload",
                "Browser peer approval action is missing.");
        }
        var groupId = request["groupId"]?.GetValue<string>() ?? string.Empty;
        var authorizedProfile = ProtocolV2RelayRegistration.Load(stateRoot)
            .Any(profile =>
                string.Equals(profile.PcDeviceId, identity.DeviceId, StringComparison.Ordinal)
                && string.Equals(profile.PeerDeviceId, approver.Identity.DeviceId, StringComparison.Ordinal)
                && string.Equals(profile.GroupId, approver.GroupId, StringComparison.Ordinal)
                && string.Equals(profile.GroupId, groupId, StringComparison.Ordinal));
        if (!authorizedProfile)
        {
            throw new ProtocolV2Exception(
                "peer_approval_forbidden",
                "Only the Android device bound to this relay group can approve browsers.");
        }

        var browserNode = request["browserIdentity"]
            ?? throw new ProtocolV2Exception(
                "invalid_payload",
                "Browser public identity is missing.");
        ProtocolPublicIdentity browser;
        try
        {
            browser = browserNode.Deserialize<ProtocolPublicIdentity>(JsonOptions)
                ?? throw new JsonException("Browser public identity is missing.");
            ProtocolPeerStore.ValidatePublicIdentity(browser);
        }
        catch (Exception exception) when (
            exception is JsonException
                or InvalidDataException
                or FormatException
                or CryptographicException)
        {
            throw new ProtocolV2Exception(
                "invalid_identity",
                "Browser public identity is invalid.");
        }
        if (!browser.DeviceId.StartsWith("browser-", StringComparison.Ordinal)
            || string.Equals(browser.DeviceId, identity.DeviceId, StringComparison.Ordinal)
            || string.Equals(
                browser.DeviceId,
                approver.Identity.DeviceId,
                StringComparison.Ordinal))
        {
            throw new ProtocolV2Exception(
                "invalid_identity",
                "Browser device identity is invalid.");
        }
        var displayName = request["displayName"]?.GetValue<string>()?.Trim();
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Length > 128)
        {
            throw new ProtocolV2Exception(
                "invalid_payload",
                "Browser display name is invalid.");
        }

        peers.AddOrUpdate(browser, displayName, groupId, clock());
        return new BridgeDispatchResult(200, new
        {
            ok = true,
            action = "bridge.peer.approve",
            authorizedDeviceId = browser.DeviceId,
            groupId,
            fingerprint = browser.Fingerprint
        });
    }

    public ValueTask DisposeAsync()
    {
        identity.Dispose();
        return ownsDispatcher ? dispatcher.DisposeAsync() : ValueTask.CompletedTask;
    }

    private CachedProtocolResponse? ReadCachedResponse(
        string deviceId,
        string messageId)
    {
        lock (responseLock)
        {
            var path = ResponsePath(deviceId, messageId);
            if (!File.Exists(path))
            {
                return null;
            }
            try
            {
                return JsonSerializer.Deserialize<CachedProtocolResponse>(
                    File.ReadAllText(path),
                    JsonOptions);
            }
            catch (JsonException)
            {
                File.Delete(path);
                return null;
            }
        }
    }

    private void WriteCachedResponse(
        string deviceId,
        string messageId,
        CachedProtocolResponse response)
    {
        lock (responseLock)
        {
            var path = ResponsePath(deviceId, messageId);
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(
                    temporary,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    4096,
                    FileOptions.WriteThrough))
                {
                    JsonSerializer.Serialize(stream, response, JsonOptions);
                    stream.Flush(flushToDisk: true);
                }
                File.Move(temporary, path, overwrite: true);
            }
            finally
            {
                if (File.Exists(temporary))
                {
                    File.Delete(temporary);
                }
            }
            foreach (var stale in Directory
                .EnumerateFiles(responseRoot, "*.json")
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .Skip(MaxCachedResponses))
            {
                File.Delete(stale);
            }
        }
    }

    private string ResponsePath(string deviceId, string messageId)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(
            deviceId + "\n" + messageId));
        return Path.Combine(
            responseRoot,
            Convert.ToHexString(digest).ToLowerInvariant() + ".json");
    }

    private OutgoingProtocolCommand? ReadOutgoingRecord(
        string peerDeviceId,
        string action,
        string jobId,
        string idempotencyKey)
    {
        var path = OutgoingPath(peerDeviceId, action, jobId, idempotencyKey);
        if (!File.Exists(path))
        {
            return null;
        }
        try
        {
            return JsonSerializer.Deserialize<OutgoingProtocolCommand>(
                File.ReadAllText(path),
                JsonOptions);
        }
        catch (JsonException)
        {
            File.Delete(path);
            return null;
        }
    }

    private void WriteOutgoingRecord(OutgoingProtocolCommand record)
    {
        var path = OutgoingPath(
            record.PeerDeviceId,
            record.Action,
            record.JobId,
            record.IdempotencyKey);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, record, JsonOptions);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
        foreach (var stale in Directory
            .EnumerateFiles(outgoingRoot, "*.json")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Skip(MaxOutgoingCommands))
        {
            File.Delete(stale);
        }
    }

    private string OutgoingPath(
        string peerDeviceId,
        string action,
        string jobId,
        string idempotencyKey)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join(
            "\n",
            peerDeviceId,
            action,
            jobId,
            idempotencyKey)));
        return Path.Combine(
            outgoingRoot,
            Convert.ToHexString(digest).ToLowerInvariant() + ".json");
    }

    private static void ValidateCapability(string capability)
    {
        if (string.IsNullOrWhiteSpace(capability)
            || capability.Length > 128
            || !capability.All(character =>
                char.IsAsciiLetterOrDigit(character)
                || character is '-' or '_' or '.'))
        {
            throw new ProtocolV2Exception(
                "invalid_metadata",
                "Invalid capability.");
        }
    }

    private static string HashEnvelope(ProtocolV2Envelope envelope) =>
        Convert.ToHexString(SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(envelope, JsonOptions)))
        .ToLowerInvariant();

    private sealed record CachedProtocolResponse(
        string RequestHash,
        ProtocolV2Envelope Response,
        DateTimeOffset CreatedAt);

    private sealed record OutgoingProtocolCommand(
        string PeerDeviceId,
        string Action,
        string JobId,
        string IdempotencyKey,
        ProtocolV2Envelope RequestEnvelope,
        ProtocolV2Envelope? ResponseEnvelope,
        JsonElement? ResponsePayload,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt);
}

public sealed record ProtocolV2PreparedPeerCommand(
    ProtocolV2ConnectionProfile Profile,
    ProtocolV2Envelope RequestEnvelope,
    ProtocolV2PeerCommandResult? CompletedResult);
