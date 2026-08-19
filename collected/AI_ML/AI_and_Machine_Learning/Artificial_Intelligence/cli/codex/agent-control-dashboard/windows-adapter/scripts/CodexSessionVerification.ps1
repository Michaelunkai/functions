function Get-CodexTopLevelSetting {
    param([Parameter(Mandatory = $true)][string]$Name)

    $configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }
    foreach ($line in Get-Content -LiteralPath $configPath -ErrorAction Stop) {
        if ($line -match '^\s*\[') { break }
        if ($line -match ('^\s*' + [Regex]::Escape($Name) + '\s*=\s*"([^"]+)"\s*(?:#.*)?$')) {
            return $Matches[1].Trim().ToLowerInvariant()
        }
    }
    return $null
}

function Set-CodexTopLevelSetting {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $text = [System.IO.File]::ReadAllText($ConfigPath)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($text -split "`r?`n")
    $sectionIndex = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[') {
            $sectionIndex = $index
            break
        }
    }
    $found = $false
    for ($index = 0; $index -lt $sectionIndex; $index++) {
        if ($lines[$index] -match "^\s*$([regex]::Escape($Name))\s*=") {
            $lines[$index] = "$Name = `"$Value`""
            $found = $true
            break
        }
    }
    if (-not $found) {
        throw "Codex root setting '$Name' was not found in $ConfigPath."
    }
    $temporary = "$ConfigPath.agent-control.$PID.tmp"
    [System.IO.File]::WriteAllText(
        $temporary,
        ($lines -join $newline),
        [System.Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporary -Destination $ConfigPath -Force
}

function Resolve-RequestedSessionSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Selection,
        [Parameter(Mandatory = $true)][string]$ConfigName
    )

    $normalized = $Selection.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Agent Control requires a durable $ConfigName selection before dispatch."
    }
    if ($normalized -ne 'default') { return $normalized }

    $resolved = Get-CodexTopLevelSetting -Name $ConfigName
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw "Agent Control selection 'default' could not resolve top-level Codex setting '$ConfigName'."
    }
    return $resolved
}

function Confirm-RequestedSessionSettings {
    param(
        [Parameter(Mandatory = $true)][string]$SessionPath,
        [Parameter(Mandatory = $true)][string]$ExpectedModel,
        [Parameter(Mandatory = $true)][string]$ExpectedEffort
    )

    $context = Get-Content -LiteralPath $SessionPath -ErrorAction Stop |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object {
            $null -ne $_ -and $_.type -eq 'turn_context' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.payload.model) -and
            -not [string]::IsNullOrWhiteSpace([string]$_.payload.effort)
        } |
        Select-Object -Last 1

    if ($null -eq $context) { return $null }

    $actualModel = ([string]$context.payload.model).Trim().ToLowerInvariant()
    $actualEffort = ([string]$context.payload.effort).Trim().ToLowerInvariant()
    $mismatches = @()
    if ($actualModel -ne $ExpectedModel.Trim().ToLowerInvariant()) {
        $mismatches += "model mismatch (expected '$ExpectedModel', recorded '$actualModel')"
    }
    if ($actualEffort -ne $ExpectedEffort.Trim().ToLowerInvariant()) {
        $mismatches += "reasoning effort mismatch (expected '$ExpectedEffort', recorded '$actualEffort')"
    }
    if ($mismatches.Count -gt 0) {
        throw "Codex session settings did not match the requested model/effort: $($mismatches -join '; ')"
    }

    return [pscustomobject]@{ model = $actualModel; effort = $actualEffort }
}
