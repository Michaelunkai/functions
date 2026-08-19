using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed record ProtocolV2RelayProfile(
    string RelayAddress,
    string GroupId,
    string PcDeviceId,
    string PeerDeviceId,
    DateTimeOffset EnrolledAt);

internal static class ProtocolV2RelayRegistration
{
    private const string DirectoryName = "protocol-v2-relay";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    public static void Register(
        string relayAddress,
        string groupId,
        ProtocolV2Identity owner,
        ProtocolPublicIdentity member,
        string displayName)
    {
        var relay = ValidateRelayAddress(relayAddress);
        ProtocolV2Identity.ValidateIdentifier(groupId, nameof(groupId));
        var timestamp = DateTimeOffset.UtcNow.ToString("O");
        var createNonce = "nonce-" + Guid.NewGuid().ToString("N");
        var createTranscript = Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-relay-create-v1",
            groupId,
            owner.DeviceId,
            owner.PublicIdentity.Fingerprint,
            timestamp,
            createNonce));
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        using var createResponse = client.PostAsJsonAsync(
            Endpoint(relay, groupId, "create"),
            new
            {
                owner = owner.PublicIdentity,
                displayName = Environment.MachineName,
                timestamp,
                nonce = createNonce,
                signature = Convert.ToBase64String(owner.SignRaw(createTranscript))
            },
            JsonOptions).GetAwaiter().GetResult();
        RequireSuccess(createResponse, "Relay group creation");

        timestamp = DateTimeOffset.UtcNow.ToString("O");
        var approvalNonce = "nonce-" + Guid.NewGuid().ToString("N");
        var approvalTranscript = Encoding.UTF8.GetBytes(string.Join(
            "\n",
            "codex-relay-member-approve-v2",
            groupId,
            owner.DeviceId,
            member.DeviceId,
            member.Fingerprint,
            "android",
            timestamp,
            approvalNonce));
        using var approvalResponse = client.PostAsJsonAsync(
            Endpoint(relay, groupId, "members"),
            new
            {
                member,
                displayName,
                role = "android",
                approvedBy = owner.DeviceId,
                timestamp,
                nonce = approvalNonce,
                signature = Convert.ToBase64String(owner.SignRaw(approvalTranscript))
            },
            JsonOptions).GetAwaiter().GetResult();
        RequireSuccess(approvalResponse, "Relay member approval");
    }

    public static void Save(string stateRoot, ProtocolV2RelayProfile profile)
    {
        var root = Path.Combine(Path.GetFullPath(stateRoot), DirectoryName);
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, profile.GroupId + ".json");
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(
                temporary,
                JsonSerializer.Serialize(profile, JsonOptions),
                new UTF8Encoding(false));
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

    public static IReadOnlyList<ProtocolV2RelayProfile> Load(string stateRoot)
    {
        var root = Path.Combine(Path.GetFullPath(stateRoot), DirectoryName);
        if (!Directory.Exists(root))
        {
            return [];
        }
        var profiles = new List<ProtocolV2RelayProfile>();
        foreach (var path in Directory.EnumerateFiles(root, "*.json"))
        {
            try
            {
                var profile = JsonSerializer.Deserialize<ProtocolV2RelayProfile>(
                    File.ReadAllText(path),
                    JsonOptions);
                if (profile is not null)
                {
                    profiles.Add(profile);
                }
            }
            catch (JsonException)
            {
                // A corrupt profile cannot authorize a connection.
            }
        }
        return profiles;
    }

    private static Uri ValidateRelayAddress(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || uri.UserInfo.Length > 0
            || !string.IsNullOrEmpty(uri.Fragment)
            || (uri.Scheme != Uri.UriSchemeHttps
                && !(uri.Scheme == Uri.UriSchemeHttp
                    && IPAddress.TryParse(uri.Host, out var address)
                    && IPAddress.IsLoopback(address))))
        {
            throw new ProtocolV2Exception(
                "relay_address_invalid",
                "Relay address must use HTTPS, except for loopback development.");
        }
        return uri;
    }

    private static Uri Endpoint(Uri relay, string groupId, string operation) =>
        new(relay, $"/v2/groups/{groupId}/{operation}");

    private static void RequireSuccess(HttpResponseMessage response, string operation)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }
        var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        throw new ProtocolV2Exception(
            "relay_registration_failed",
            $"{operation} failed with HTTP {(int)response.StatusCode}: {Bound(body)}");
    }

    private static string Bound(string value) =>
        value.Length <= 512 ? value : value[..512];
}
