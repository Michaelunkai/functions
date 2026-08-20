# proxy-watchdog.ps1 — Ensures NVIDIA proxy v11 is always running
# Called by nvioc.ps1 before every OpenCode launch
# If proxy is down, starts it. If proxy is alive, hot-reloads keys.

$proxyScript = Join-Path $env:USERPROFILE '.config\opencode\nvidia-proxy.cjs'
$proxyKeysFile = 'F:\backup\windowsapps\credentials\nvidia\api-keys.txt'
$proxyPort = 3456

function Get-ProxyHealth {
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$proxyPort/health" `
            -Method Get -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { return ($resp.Content | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Start-Proxy {
    if (-not (Test-Path -LiteralPath $proxyScript -PathType Leaf)) {
        Write-Host "OC_PROGRESS stage=watchdog-proxy-missing path=$proxyScript"
        return $false
    }

    # Find node.exe
    $nodeExe = $null
    $nodeCandidates = @(
        (Join-Path ${env:ProgramFiles} 'nodejs\node.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe')
    )
    foreach ($nodePath in $nodeCandidates) {
        if ($nodePath -and (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
            $nodeExe = $nodePath
            break
        }
    }
    if (-not $nodeExe) {
        foreach ($c in (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($c.Source -notmatch 'WindowsApps') { $nodeExe = $c.Source; break }
        }
    }
    if (-not $nodeExe) { $nodeExe = 'node' }

    Write-Host "OC_PROGRESS stage=watchdog-starting-proxy"
    Start-Process -FilePath $nodeExe -ArgumentList "`"$proxyScript`" --port $proxyPort --keys `"$proxyKeysFile`"" `
        -WindowStyle Hidden -ErrorAction Stop | Out-Null

    # Wait for it to come up (max 8s)
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $h = Get-ProxyHealth
        if ($h) {
            Write-Host "OC_PROGRESS stage=watchdog-proxy-started keys=$($h.keys) running=$($h.running)"
            return $true
        }
    }
    Write-Host "OC_PROGRESS stage=watchdog-proxy-timeout"
    return $false
}

# === MAIN ===
$health = Get-ProxyHealth
if ($health) {
    # Proxy is alive — hot-reload keys
    try { $null = Invoke-WebRequest -Uri "http://127.0.0.1:$proxyPort/_reload" -Method Get -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue } catch { }
    Write-Host "OC_PROGRESS stage=watchdog-already-running v=$($health.v) keys=$($health.keys) free=$($health.free) running=$($health.running) queued=$($health.queued)"
} else {
    # Proxy is down — start it
    Write-Host "OC_PROGRESS stage=watchdog-proxy-down"
    $started = Start-Proxy
    if ($started) {
        Write-Host "OC_PROGRESS stage=watchdog-proxy-recovered"
    } else {
        Write-Host "OC_PROGRESS stage=watchdog-proxy-failed"
    }
}
