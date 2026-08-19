using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace CodexPcBridge.Core;

internal sealed class BridgeProcessManager : IAsyncDisposable
{
    private readonly BridgeRuntimeOptions options;
    private readonly Func<DateTimeOffset> clock;
    private readonly string jobsRoot;
    private readonly ConcurrentDictionary<string, RunningJob> running = new(StringComparer.Ordinal);

    public BridgeProcessManager(BridgeRuntimeOptions options, Func<DateTimeOffset> clock)
    {
        this.options = options;
        this.clock = clock;
        jobsRoot = Path.Combine(options.StateRoot, "jobs");
        Directory.CreateDirectory(jobsRoot);
        MarkInterruptedJobs();
    }

    public async Task<object> ExecuteAsync(JsonElement request, CancellationToken cancellationToken, bool powerShellAlias = false)
    {
        ProcessSpecification specification;
        try
        {
            specification = ParseSpecification(request, powerShellAlias);
        }
        catch (Exception exception)
        {
            return BridgeFileSystem.Failure(exception.Message, "invalid_process_request");
        }

        var timeoutSeconds = Math.Clamp(
            BridgeFileSystem.GetInt(request, "timeoutSeconds", 300),
            1,
            24 * 60 * 60);
        var result = await RunAsync(specification, timeoutSeconds, cancellationToken);
        return BridgeFileSystem.Success(
            ("action", powerShellAlias ? "shell" : "process.exec"),
            ("exitCode", result.ExitCode),
            ("timedOut", result.TimedOut),
            ("cancelled", result.Cancelled),
            ("stdout", result.StandardOutput),
            ("stderr", result.StandardError),
            ("stdoutTruncated", result.StandardOutputTruncated),
            ("stderrTruncated", result.StandardErrorTruncated),
            ("ok", result.ExitCode == 0 && !result.TimedOut && !result.Cancelled));
    }

    public Task<object> StartAsync(JsonElement request, CancellationToken cancellationToken, string? existingJobId = null)
    {
        ProcessSpecification specification;
        try
        {
            specification = ParseSpecification(request, powerShellAlias: false);
        }
        catch (Exception exception)
        {
            return Task.FromResult<object>(BridgeFileSystem.Failure(exception.Message, "invalid_process_request"));
        }

        var jobId = existingJobId ?? BridgeFileSystem.GetString(request, "jobId") ?? Guid.NewGuid().ToString("N");
        if (!IsIdentifier(jobId))
        {
            return Task.FromResult<object>(BridgeFileSystem.Failure("Invalid jobId.", "invalid_job_id"));
        }
        if (running.ContainsKey(jobId))
        {
            return Task.FromResult<object>(BridgeFileSystem.Failure("Job is already running.", "job_running"));
        }

        try
        {
            var startInfo = CreateStartInfo(specification);
            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            if (!process.Start())
            {
                process.Dispose();
                return Task.FromResult<object>(BridgeFileSystem.Failure("Process did not start.", "process_start_failed"));
            }

            var outputTask = ReadBoundedAsync(process.StandardOutput, options.MaxOutputBytes, CancellationToken.None);
            var errorTask = ReadBoundedAsync(process.StandardError, options.MaxOutputBytes, CancellationToken.None);
            var definition = new PersistedJob(
                jobId,
                "running",
                specification,
                process.Id,
                null,
                false,
                false,
                null,
                null,
                false,
                false,
                clock(),
                null,
                1);
            WriteJob(definition);
            var job = new RunningJob(process, definition, outputTask, errorTask);
            if (!running.TryAdd(jobId, job))
            {
                process.Kill(entireProcessTree: true);
                process.Dispose();
                return Task.FromResult<object>(BridgeFileSystem.Failure("Job is already running.", "job_running"));
            }

            _ = MonitorAsync(jobId, job);
            return Task.FromResult<object>(BridgeFileSystem.Success(
                ("action", "process.start"),
                ("jobId", jobId),
                ("pid", process.Id),
                ("status", "running")));
        }
        catch (Exception exception)
        {
            return Task.FromResult<object>(BridgeFileSystem.Failure(
                $"Unable to start process: {exception.Message}",
                "process_start_failed"));
        }
    }

    public object Status(JsonElement request)
    {
        var jobId = BridgeFileSystem.GetString(request, "jobId");
        if (!IsIdentifier(jobId))
        {
            return BridgeFileSystem.Failure("Invalid jobId.", "invalid_job_id");
        }

        var job = ReadJob(jobId!);
        return job is null
            ? BridgeFileSystem.Failure("Job not found.", "job_not_found")
            : BridgeFileSystem.Success(
                ("action", "process.status"),
                ("job", job));
    }

    public object Cancel(JsonElement request)
    {
        var jobId = BridgeFileSystem.GetString(request, "jobId");
        if (!IsIdentifier(jobId))
        {
            return BridgeFileSystem.Failure("Invalid jobId.", "invalid_job_id");
        }
        if (!running.TryGetValue(jobId!, out var job))
        {
            var persisted = ReadJob(jobId!);
            return persisted is null
                ? BridgeFileSystem.Failure("Job not found.", "job_not_found")
                : BridgeFileSystem.Failure($"Job is not running; current status is {persisted.Status}.", "job_not_running");
        }

        try
        {
            job.Cancelled = true;
            if (!job.Process.HasExited)
            {
                job.Process.Kill(entireProcessTree: true);
            }
            return BridgeFileSystem.Success(
                ("action", "process.cancel"),
                ("jobId", jobId),
                ("status", "cancelling"));
        }
        catch (Exception exception)
        {
            return BridgeFileSystem.Failure($"Unable to cancel job: {exception.Message}", "cancel_failed");
        }
    }

    public async Task<object> ResumeAsync(JsonElement request, CancellationToken cancellationToken)
    {
        var jobId = BridgeFileSystem.GetString(request, "jobId");
        if (!IsIdentifier(jobId))
        {
            return BridgeFileSystem.Failure("Invalid jobId.", "invalid_job_id");
        }
        var persisted = ReadJob(jobId!);
        if (persisted is null)
        {
            return BridgeFileSystem.Failure("Job not found.", "job_not_found");
        }
        if (persisted.Status is not ("interrupted" or "failed" or "cancelled" or "timed_out"))
        {
            return BridgeFileSystem.Failure($"Job cannot be resumed from status {persisted.Status}.", "invalid_job_state");
        }

        using var definition = JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            action = "process.start",
            executable = persisted.Specification.Executable,
            arguments = persisted.Specification.Arguments,
            workingDirectory = persisted.Specification.WorkingDirectory,
            environment = persisted.Specification.Environment
        }));
        return await StartAsync(definition.RootElement, cancellationToken, jobId);
    }

    public async ValueTask DisposeAsync()
    {
        foreach (var job in running.Values)
        {
            try
            {
                if (!job.Process.HasExited)
                {
                    job.Process.Kill(entireProcessTree: true);
                }
                await job.Process.WaitForExitAsync();
            }
            catch
            {
            }
            job.Process.Dispose();
        }
        running.Clear();
    }

    private ProcessSpecification ParseSpecification(JsonElement request, bool powerShellAlias)
    {
        if (powerShellAlias)
        {
            var command = BridgeFileSystem.GetString(request, "command")
                ?? BridgeFileSystem.GetString(request, "script");
            if (string.IsNullOrWhiteSpace(command))
            {
                throw new InvalidDataException("Missing command.");
            }
            var requestedShell = BridgeFileSystem.GetString(request, "shell")?.ToLowerInvariant();
            var executable = requestedShell == "pwsh"
                ? options.PowerShell7Path ?? throw new InvalidDataException("PowerShell 7 path is not configured.")
                : options.PowerShell5Path;
            if (!File.Exists(executable))
            {
                throw new FileNotFoundException("PowerShell executable not found.", executable);
            }
            var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
            return new ProcessSpecification(
                executable,
                ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
                ParseWorkingDirectory(request),
                ParseEnvironment(request),
                command.Length);
        }

        var executablePath = BridgeFileSystem.GetString(request, "executable")
            ?? BridgeFileSystem.GetString(request, "fileName")
            ?? BridgeFileSystem.GetString(request, "target");
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            throw new InvalidDataException("Missing executable.");
        }
        var arguments = ParseArguments(request);
        return new ProcessSpecification(
            executablePath,
            arguments,
            ParseWorkingDirectory(request),
            ParseEnvironment(request),
            null);
    }

    private static IReadOnlyList<string> ParseArguments(JsonElement request)
    {
        if (!request.TryGetProperty("arguments", out var property))
        {
            return [];
        }
        if (property.ValueKind == JsonValueKind.Array)
        {
            return property.EnumerateArray()
                .Select(value => value.ValueKind == JsonValueKind.String
                    ? value.GetString()!
                    : throw new InvalidDataException("arguments must contain only strings."))
                .ToArray();
        }
        if (property.ValueKind == JsonValueKind.String)
        {
            return [property.GetString()!];
        }
        throw new InvalidDataException("arguments must be a string array.");
    }

    private static string? ParseWorkingDirectory(JsonElement request)
    {
        var workingDirectory = BridgeFileSystem.GetString(request, "workingDirectory");
        if (string.IsNullOrWhiteSpace(workingDirectory))
        {
            return null;
        }
        if (!Path.IsPathFullyQualified(workingDirectory) || !Directory.Exists(workingDirectory))
        {
            throw new InvalidDataException("workingDirectory must be an existing absolute directory.");
        }
        return Path.GetFullPath(workingDirectory);
    }

    private static IReadOnlyDictionary<string, string> ParseEnvironment(JsonElement request)
    {
        if (!request.TryGetProperty("environment", out var property))
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }
        if (property.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("environment must be an object.");
        }
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in property.EnumerateObject())
        {
            if (item.Value.ValueKind != JsonValueKind.String)
            {
                throw new InvalidDataException("environment values must be strings.");
            }
            result[item.Name] = item.Value.GetString()!;
        }
        return result;
    }

    private static ProcessStartInfo CreateStartInfo(ProcessSpecification specification)
    {
        var startInfo = new ProcessStartInfo(specification.Executable)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (var argument in specification.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        if (specification.WorkingDirectory is not null)
        {
            startInfo.WorkingDirectory = specification.WorkingDirectory;
        }
        foreach (var pair in specification.Environment)
        {
            startInfo.Environment[pair.Key] = pair.Value;
        }
        return startInfo;
    }

    private async Task<ProcessExecutionResult> RunAsync(
        ProcessSpecification specification,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        using var process = new Process { StartInfo = CreateStartInfo(specification) };
        process.Start();
        var outputTask = ReadBoundedAsync(process.StandardOutput, options.MaxOutputBytes, cancellationToken);
        var errorTask = ReadBoundedAsync(process.StandardError, options.MaxOutputBytes, cancellationToken);
        var exitTask = process.WaitForExitAsync(cancellationToken);
        var timeoutTask = Task.Delay(TimeSpan.FromSeconds(timeoutSeconds), cancellationToken);
        var completed = await Task.WhenAny(exitTask, timeoutTask);
        var timedOut = completed != exitTask && !cancellationToken.IsCancellationRequested;
        var cancelled = cancellationToken.IsCancellationRequested;
        if ((timedOut || cancelled) && !process.HasExited)
        {
            process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
        }
        else
        {
            await exitTask;
        }
        var output = await outputTask;
        var error = await errorTask;
        return new ProcessExecutionResult(
            process.HasExited ? process.ExitCode : -1,
            timedOut,
            cancelled,
            output.Text,
            error.Text,
            output.Truncated,
            error.Truncated);
    }

    private async Task MonitorAsync(string jobId, RunningJob job)
    {
        try
        {
            await job.Process.WaitForExitAsync();
            var output = await job.Output;
            var error = await job.Error;
            var status = job.Cancelled
                ? "cancelled"
                : job.Process.ExitCode == 0 ? "completed" : "failed";
            var updated = job.Definition with
            {
                Status = status,
                ExitCode = job.Process.ExitCode,
                Cancelled = job.Cancelled,
                StandardOutput = output.Text,
                StandardError = error.Text,
                StandardOutputTruncated = output.Truncated,
                StandardErrorTruncated = error.Truncated,
                CompletedAt = clock()
            };
            WriteJob(updated);
        }
        catch (Exception exception)
        {
            WriteJob(job.Definition with
            {
                Status = "failed",
                StandardError = exception.Message,
                CompletedAt = clock()
            });
        }
        finally
        {
            running.TryRemove(jobId, out _);
            job.Process.Dispose();
        }
    }

    private static async Task<BoundedText> ReadBoundedAsync(
        StreamReader reader,
        int maxBytes,
        CancellationToken cancellationToken)
    {
        var builder = new StringBuilder();
        var buffer = new char[4096];
        var truncated = false;
        while (true)
        {
            var read = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
            if (read == 0)
            {
                break;
            }
            var candidate = new string(buffer, 0, read);
            var currentBytes = Encoding.UTF8.GetByteCount(builder.ToString());
            var remaining = maxBytes - currentBytes;
            if (remaining <= 0)
            {
                truncated = true;
                continue;
            }
            if (Encoding.UTF8.GetByteCount(candidate) <= remaining)
            {
                builder.Append(candidate);
                continue;
            }
            foreach (var character in candidate)
            {
                if (Encoding.UTF8.GetByteCount(builder.ToString() + character) > maxBytes)
                {
                    truncated = true;
                    break;
                }
                builder.Append(character);
            }
        }
        return new BoundedText(builder.ToString(), truncated);
    }

    private void MarkInterruptedJobs()
    {
        foreach (var path in Directory.EnumerateFiles(jobsRoot, "*.json"))
        {
            try
            {
                var job = JsonSerializer.Deserialize<PersistedJob>(File.ReadAllText(path));
                if (job?.Status == "running")
                {
                    WriteJob(job with { Status = "interrupted", Pid = null, CompletedAt = clock() });
                }
            }
            catch
            {
            }
        }
    }

    private PersistedJob? ReadJob(string jobId)
    {
        var path = JobPath(jobId);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<PersistedJob>(File.ReadAllText(path))
            : null;
    }

    private void WriteJob(PersistedJob job)
    {
        Directory.CreateDirectory(jobsRoot);
        var path = JobPath(job.JobId);
        var temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temp, JsonSerializer.Serialize(job));
        File.Move(temp, path, overwrite: true);
    }

    private string JobPath(string jobId) => Path.Combine(jobsRoot, jobId + ".json");

    private static bool IsIdentifier(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Length <= 128
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');

    private sealed record RunningJob(
        Process Process,
        PersistedJob Definition,
        Task<BoundedText> Output,
        Task<BoundedText> Error)
    {
        public bool Cancelled { get; set; }
    }

    private sealed record BoundedText(string Text, bool Truncated);
    private sealed record ProcessExecutionResult(
        int ExitCode,
        bool TimedOut,
        bool Cancelled,
        string StandardOutput,
        string StandardError,
        bool StandardOutputTruncated,
        bool StandardErrorTruncated);
    private sealed record ProcessSpecification(
        string Executable,
        IReadOnlyList<string> Arguments,
        string? WorkingDirectory,
        IReadOnlyDictionary<string, string> Environment,
        int? SensitiveCommandLength);
    private sealed record PersistedJob(
        string JobId,
        string Status,
        ProcessSpecification Specification,
        int? Pid,
        int? ExitCode,
        bool TimedOut,
        bool Cancelled,
        string? StandardOutput,
        string? StandardError,
        bool StandardOutputTruncated,
        bool StandardErrorTruncated,
        DateTimeOffset CreatedAt,
        DateTimeOffset? CompletedAt,
        int Attempt);
}
