using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed record EnrollmentChallenge(
    int ProtocolVersion,
    string ChallengeId,
    DateTimeOffset IssuedAt,
    DateTimeOffset ExpiresAt,
    string Nonce,
    string? RelayAddress,
    IReadOnlyList<string> DirectAddresses,
    ProtocolPublicIdentity PcIdentity);

public sealed record EnrollmentResponse(
    int ProtocolVersion,
    string ChallengeId,
    string Nonce,
    ProtocolPublicIdentity DeviceIdentity,
    string DisplayName,
    string Signature);

public sealed record EnrollmentReceipt(
    int ProtocolVersion,
    string GroupId,
    string PcDeviceId,
    string DeviceId,
    DateTimeOffset EnrolledAt,
    string ReceiptPayload,
    string PcSignature);

public sealed class ProtocolV2EnrollmentManager : IDisposable
{
    private static readonly TimeSpan ChallengeLifetime = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan ChallengeRetention = TimeSpan.FromHours(24);
    private const int MaxChallengeRecords = 128;
    private readonly string stateRoot;
    private readonly string challengeRoot;
    private readonly ProtocolV2Identity identity;
    private readonly ProtocolPeerStore peers;
    private readonly Func<DateTimeOffset> clock;
    private readonly object challengeLock = new();

    public ProtocolV2EnrollmentManager(
        string stateRoot,
        string deviceId,
        Func<DateTimeOffset>? clock = null)
    {
        var root = Path.GetFullPath(stateRoot);
        this.stateRoot = root;
        challengeRoot = Path.Combine(root, "protocol-v2-enrollment");
        Directory.CreateDirectory(challengeRoot);
        identity = ProtocolV2Identity.LoadOrCreate(root, deviceId);
        peers = new ProtocolPeerStore(root);
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    public ProtocolPublicIdentity PublicIdentity => identity.PublicIdentity;

    public EnrollmentChallenge CreateChallenge(
        string? relayAddress,
        IEnumerable<string>? directAddresses = null)
    {
        var now = clock();
        lock (challengeLock)
        {
            PruneChallenges(now);
            if (Directory.EnumerateFiles(challengeRoot, "*.json").Take(
                    MaxChallengeRecords).Count() >= MaxChallengeRecords)
            {
                throw new ProtocolV2Exception(
                    "challenge_limit_reached",
                    "Too many enrollment challenges are retained.");
            }
        }
        var validatedDirectAddresses = (directAddresses ?? [])
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim().TrimEnd('/'))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var challenge = new EnrollmentChallenge(
            ProtocolVersion: 2,
            ChallengeId: "challenge-" + Guid.NewGuid().ToString("N"),
            IssuedAt: now,
            ExpiresAt: now.Add(ChallengeLifetime),
            Nonce: Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)),
            RelayAddress: string.IsNullOrWhiteSpace(relayAddress) ? null : relayAddress.Trim(),
            DirectAddresses: validatedDirectAddresses,
            PcIdentity: identity.PublicIdentity);
        lock (challengeLock)
        {
            WriteChallenge(new StoredChallenge(challenge, Used: false, UsedAt: null));
        }
        return challenge;
    }

    public EnrollmentReceipt Complete(EnrollmentResponse response)
        => CompleteCore(response, null);

    public EnrollmentReceipt CompleteWithRelayRegistration(
        EnrollmentResponse response,
        string relayAddress)
        => CompleteCore(response, relayAddress);

    private EnrollmentReceipt CompleteCore(
        EnrollmentResponse response,
        string? relayAddress)
    {
        if (response.ProtocolVersion != 2)
        {
            throw new ProtocolV2Exception("unsupported_protocol", "Unsupported enrollment protocol.");
        }
        ProtocolV2Identity.ValidateIdentifier(response.ChallengeId, nameof(response.ChallengeId));
        ProtocolPeerStore.ValidatePublicIdentity(response.DeviceIdentity);

        lock (challengeLock)
        {
            var stored = ReadChallenge(response.ChallengeId)
                ?? throw new ProtocolV2Exception("challenge_not_found", "Enrollment challenge was not found.");
            var now = clock();
            if (stored.Used)
            {
                throw new ProtocolV2Exception("challenge_used", "Enrollment challenge was already used.");
            }
            if (stored.Challenge.ExpiresAt <= now)
            {
                throw new ProtocolV2Exception("challenge_expired", "Enrollment challenge has expired.");
            }
            if (!string.Equals(
                    stored.Challenge.Nonce,
                    response.Nonce,
                    StringComparison.Ordinal))
            {
                throw new ProtocolV2Exception("challenge_mismatch", "Enrollment challenge nonce mismatch.");
            }
            var transcript = CreateTranscript(stored.Challenge, response);
            bool signatureValid;
            try
            {
                signatureValid = ProtocolV2Crypto.VerifyEnrollmentTranscript(
                    response.DeviceIdentity,
                    transcript,
                    response.Signature);
            }
            catch (Exception exception) when (exception is FormatException or CryptographicException)
            {
                throw new ProtocolV2Exception("signature_invalid", "Enrollment signature is invalid.");
            }
            if (!signatureValid)
            {
                throw new ProtocolV2Exception("signature_invalid", "Enrollment signature is invalid.");
            }

            var groupId = stored.GroupId
                ?? CreateDeterministicGroupId(stored.Challenge.ChallengeId);
            if (stored.GroupId is null)
            {
                stored = stored with { GroupId = groupId };
                WriteChallenge(stored);
            }
            if (!string.IsNullOrWhiteSpace(relayAddress))
            {
                ProtocolV2RelayRegistration.Register(
                    relayAddress,
                    groupId,
                    identity,
                    response.DeviceIdentity,
                    response.DisplayName);
            }
            peers.AddOrUpdate(
                response.DeviceIdentity,
                response.DisplayName,
                groupId,
                now);
            WriteChallenge(stored with
            {
                Used = true,
                UsedAt = now,
                GroupId = groupId
            });
            if (!string.IsNullOrWhiteSpace(relayAddress))
            {
                ProtocolV2RelayRegistration.Save(
                    stateRoot,
                    new ProtocolV2RelayProfile(
                        relayAddress.Trim().TrimEnd('/'),
                        groupId,
                        identity.DeviceId,
                        response.DeviceIdentity.DeviceId,
                        now));
            }
            var unsignedReceipt = new
            {
                protocolVersion = 2,
                groupId,
                pcDeviceId = identity.DeviceId,
                deviceId = response.DeviceIdentity.DeviceId,
                enrolledAt = now
            };
            var receiptBytes = JsonSerializer.SerializeToUtf8Bytes(unsignedReceipt);
            return new EnrollmentReceipt(
                ProtocolVersion: 2,
                GroupId: groupId,
                PcDeviceId: identity.DeviceId,
                DeviceId: response.DeviceIdentity.DeviceId,
                EnrolledAt: now,
                ReceiptPayload: Convert.ToBase64String(receiptBytes),
                PcSignature: Convert.ToBase64String(identity.Sign(receiptBytes)));
        }
    }

    public static EnrollmentResponse CreateResponse(
        EnrollmentChallenge challenge,
        ProtocolV2Identity joiningIdentity,
        string displayName)
    {
        if (challenge.ProtocolVersion != 2)
        {
            throw new ProtocolV2Exception("unsupported_protocol", "Unsupported enrollment protocol.");
        }
        var unsigned = new EnrollmentResponse(
            ProtocolVersion: 2,
            ChallengeId: challenge.ChallengeId,
            Nonce: challenge.Nonce,
            DeviceIdentity: joiningIdentity.PublicIdentity,
            DisplayName: string.IsNullOrWhiteSpace(displayName)
                ? joiningIdentity.DeviceId
                : displayName.Trim(),
            Signature: string.Empty);
        var transcript = CreateTranscript(challenge, unsigned);
        return unsigned with
        {
            Signature = Convert.ToBase64String(
                ProtocolV2Crypto.SignEnrollmentTranscript(joiningIdentity, transcript))
        };
    }

    public void Dispose() => identity.Dispose();

    private static byte[] CreateTranscript(
        EnrollmentChallenge challenge,
        EnrollmentResponse response) =>
        Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-pc-bridge-enrollment-v2",
            challenge.ChallengeId,
            challenge.Nonce,
            challenge.ExpiresAt.ToUnixTimeMilliseconds().ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            challenge.PcIdentity.DeviceId,
            challenge.PcIdentity.Fingerprint,
            response.DeviceIdentity.DeviceId,
            response.DeviceIdentity.Fingerprint,
            response.DisplayName));

    private StoredChallenge? ReadChallenge(string challengeId)
    {
        var path = ChallengePath(challengeId);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<StoredChallenge>(File.ReadAllText(path))
            : null;
    }

    private void WriteChallenge(StoredChallenge challenge)
    {
        var path = ChallengePath(challenge.Challenge.ChallengeId);
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, challenge);
                stream.Flush(flushToDisk: true);
            }
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

    private string ChallengePath(string challengeId) =>
        Path.Combine(challengeRoot, challengeId + ".json");

    private string CreateDeterministicGroupId(string challengeId)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-pc-bridge-relay-group-v2",
            identity.DeviceId,
            challengeId)));
        return "group-" + Convert.ToHexString(digest).ToLowerInvariant();
    }

    private void PruneChallenges(DateTimeOffset now)
    {
        var retained = new List<(string Path, DateTime LastWrite)>();
        foreach (var path in Directory.EnumerateFiles(challengeRoot, "*.json"))
        {
            try
            {
                var challenge = JsonSerializer.Deserialize<StoredChallenge>(
                    File.ReadAllText(path));
                if (challenge is null
                    || (challenge.Used && challenge.UsedAt <= now - ChallengeRetention)
                    || (!challenge.Used
                        && challenge.Challenge.ExpiresAt <= now - ChallengeRetention))
                {
                    File.Delete(path);
                    continue;
                }
            }
            catch (JsonException)
            {
                File.Delete(path);
                continue;
            }
            retained.Add((path, File.GetLastWriteTimeUtc(path)));
        }
        foreach (var item in retained
            .OrderBy(value => value.LastWrite)
            .Take(Math.Max(0, retained.Count - MaxChallengeRecords + 1)))
        {
            var challenge = JsonSerializer.Deserialize<StoredChallenge>(
                File.ReadAllText(item.Path));
            if (challenge is { Used: true }
                || challenge?.Challenge.ExpiresAt <= now)
            {
                File.Delete(item.Path);
            }
        }
    }

    private sealed record StoredChallenge(
        EnrollmentChallenge Challenge,
        bool Used,
        DateTimeOffset? UsedAt,
        string? GroupId = null);
}
