using System.Text.Json;

namespace CodexPcBridge.Core;

public sealed class GatewayActionRequest : EventArgs
{
    public GatewayActionRequest(string action, string summary)
    {
        Action = action;
        Summary = summary;
    }

    public string Action { get; }
    public string Summary { get; }

    public static GatewayActionRequest FromJson(JsonElement request)
    {
        var action = GetString(request, "action")?.Trim().ToLowerInvariant() ?? "status";
        var summary = action switch
        {
            "shell" or "powershell" => SummarizeCommand(GetString(request, "command") ?? GetString(request, "script")),
            "run" => SummarizeRun(GetString(request, "fileName") ?? GetString(request, "target")),
            "open" => SummarizeOpen(GetString(request, "target")),
            "diagnostics" => "Read-only companion diagnostics",
            "status" => "Read-only companion status",
            _ => $"Unsupported action: {action}"
        };

        return new GatewayActionRequest(action, summary);
    }

    public bool RequiresInteractiveApproval => Action is "shell" or "powershell" or "run" or "open";

    private static string SummarizeCommand(string? command) =>
        string.IsNullOrWhiteSpace(command)
            ? "PowerShell command (missing command)"
            : $"PowerShell command ({command.Trim().Length} characters)";

    private static string SummarizeRun(string? target) =>
        string.IsNullOrWhiteSpace(target)
            ? "Start process (missing target)"
            : $"Start process: {target.Trim()}";

    private static string SummarizeOpen(string? target) =>
        string.IsNullOrWhiteSpace(target)
            ? "Open target (missing target)"
            : $"Open target: {target.Trim()}";

    private static string? GetString(JsonElement request, string name) =>
        request.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
}
