Set-StrictMode -Version 2.0

function Start-LocalAIServerProcess {
    param([Parameter(Mandatory=$true)]$RuntimeConfig)
    $root = Get-ProjectRoot
    $stdout = Join-Path $root 'logs\server.stdout.log'
    $stderr = Join-Path $root 'logs\server.stderr.log'
    $argLine = ($RuntimeConfig.Args | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' '
    return Start-Process -FilePath $RuntimeConfig.BackendExe -ArgumentList $argLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
}

function Wait-LocalAIHealth {
    param([int]$Port = 8080, [int]$TimeoutSec = 120, $Process)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        if ($Process) {
            try { $Process.Refresh() } catch {}
            if ($Process.HasExited) {
                throw "Local AI server exited before becoming healthy. ExitCode=$($Process.ExitCode)"
            }
        }
        try {
            $models = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/v1/models" -f $Port) -UseBasicParsing -TimeoutSec 5
            return $models
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)
    throw "Local AI server did not become healthy on 127.0.0.1:$Port within $TimeoutSec seconds."
}

function Invoke-LocalAIValidation {
    param(
        [Parameter(Mandatory=$true)]$RuntimeConfig,
        [switch]$DoNotStart
    )
    $root = Get-ProjectRoot
    $proc = $null
    if (-not $DoNotStart) {
        $proc = Start-LocalAIServerProcess -RuntimeConfig $RuntimeConfig
    }
    try {
        $health = Wait-LocalAIHealth -Port $RuntimeConfig.Port -Process $proc
        $payload = @{
            model = 'local'
            messages = @(
                @{ role = 'system'; content = 'Return concise, valid plain text.' },
                @{ role = 'user'; content = 'Write exactly one sentence confirming local inference is running.' }
            )
            max_tokens = 64
            temperature = 0.1
            stream = $false
        } | ConvertTo-Json -Depth 8
        $start = Get-Date
        $response = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/v1/chat/completions" -f $RuntimeConfig.Port) -Method Post -Body $payload -ContentType 'application/json' -UseBasicParsing -TimeoutSec 120
        $elapsed = ((Get-Date) - $start).TotalSeconds
        $text = ''
        if ($response.choices -and $response.choices[0].message.content) { $text = [string]$response.choices[0].message.content }
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Validation payload returned empty content.' }
        $report = [pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            Healthy = $true
            ListenerGlobal = Test-ExternalListener -Port $RuntimeConfig.Port
            Seconds = [math]::Round($elapsed, 3)
            OutputPreview = $text
            Health = $health
        }
        Save-Json -InputObject $report -Path (Join-Path $root 'reports\validation-latest.json')
        return $report
    } finally {
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
}

Export-ModuleMember -Function *
