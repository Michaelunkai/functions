using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;

namespace CodexPcBridge.Core;

public enum AuthenticationResult
{
    Accepted,
    MissingHeaders,
    InvalidTimestamp,
    TimestampOutsideWindow,
    InvalidNonce,
    InvalidSignature,
    ReplayRejected
}

public sealed class GatewayAuthenticator
{
    private const int ReplayWindowSeconds = 300;
    private readonly byte[] secret;
    private readonly byte[]? legacyTextSecret;
    private readonly ConcurrentDictionary<string, long> nonces = new(StringComparer.Ordinal);

    public GatewayAuthenticator(byte[] secret)
        : this(secret, null)
    {
    }

    public GatewayAuthenticator(string secretBase64)
        : this(Convert.FromBase64String(secretBase64), Encoding.UTF8.GetBytes(secretBase64))
    {
    }

    private GatewayAuthenticator(byte[] secret, byte[]? legacyTextSecret)
    {
        if (secret.Length < 32)
        {
            throw new ArgumentException("Gateway secret must contain at least 32 bytes.", nameof(secret));
        }

        this.secret = secret.ToArray();
        this.legacyTextSecret = legacyTextSecret?.ToArray();
    }

    public AuthenticationResult Authenticate(IReadOnlyDictionary<string, string> headers, string body)
    {
        var timestamp = GetHeader(headers, "X-Codex-Timestamp");
        var nonce = GetHeader(headers, "X-Codex-Nonce");
        var signature = GetHeader(headers, "X-Codex-Signature");
        if (string.IsNullOrWhiteSpace(timestamp) || string.IsNullOrWhiteSpace(nonce) || string.IsNullOrWhiteSpace(signature))
        {
            return AuthenticationResult.MissingHeaders;
        }

        if (!long.TryParse(timestamp, out var epoch) || epoch <= 0)
        {
            return AuthenticationResult.InvalidTimestamp;
        }

        if (epoch > 9_999_999_999)
        {
            epoch /= 1000;
        }

        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        if (Math.Abs(now - epoch) > ReplayWindowSeconds)
        {
            return AuthenticationResult.TimestampOutsideWindow;
        }

        if (nonce.Length is < 16 or > 128 || !nonce.All(character => char.IsAsciiLetterOrDigit(character) || character is '_' or '-'))
        {
            return AuthenticationResult.InvalidNonce;
        }

        if (signature.Length != 64 || !signature.All(Uri.IsHexDigit))
        {
            return AuthenticationResult.InvalidSignature;
        }

        RemoveExpiredNonces(now);
        if (!nonces.TryAdd(nonce, now + ReplayWindowSeconds))
        {
            return AuthenticationResult.ReplayRejected;
        }

        var canonical = $"{timestamp}\n{nonce}\n{body}";
        var canonicalBytes = Encoding.UTF8.GetBytes(canonical);
        using var hmac = new HMACSHA256(secret);
        var expected = hmac.ComputeHash(canonicalBytes);
        var supplied = Convert.FromHexString(signature);
        var accepted = CryptographicOperations.FixedTimeEquals(expected, supplied);
        if (!accepted && legacyTextSecret is not null)
        {
            using var legacyHmac = new HMACSHA256(legacyTextSecret);
            accepted = CryptographicOperations.FixedTimeEquals(legacyHmac.ComputeHash(canonicalBytes), supplied);
        }

        if (!accepted)
        {
            nonces.TryRemove(nonce, out _);
            return AuthenticationResult.InvalidSignature;
        }

        return AuthenticationResult.Accepted;
    }

    private static string? GetHeader(IReadOnlyDictionary<string, string> headers, string name) =>
        headers.FirstOrDefault(pair => string.Equals(pair.Key, name, StringComparison.OrdinalIgnoreCase)).Value;

    private void RemoveExpiredNonces(long now)
    {
        foreach (var entry in nonces)
        {
            if (entry.Value < now)
            {
                nonces.TryRemove(entry.Key, out _);
            }
        }
    }
}
