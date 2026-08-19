Set-StrictMode -Version 2.0

function Assert-PortAvailable {
    param([int]$Port = 8080, [switch]$SkipMutation)
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if (-not $listeners) { return $true }
    $projectRoot = Get-ProjectRoot
    foreach ($listener in $listeners) {
        $proc = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($proc -and $proc.Path -and $proc.Path.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
            if (-not $SkipMutation) { Stop-Process -Id $proc.Id -Force }
        } else {
            throw "Port $Port is already used by PID $($listener.OwningProcess). This project will not kill unrelated listeners."
        }
    }
    return $true
}

function Enable-LocalAIFirewallRule {
    param([int]$Port = 8080, [switch]$SkipMutation)
    $name = "LocalAI AutoDeployer TCP $Port"
    if ($SkipMutation) { return [pscustomobject]@{ RuleName = $name; Mutated = $false } }
    $netSecurityAvailable = $false
    try {
        $class = Get-CimClass -Namespace root/standardcimv2 -ClassName MSFT_NetFirewallRule -ErrorAction Stop
        $netSecurityAvailable = $null -ne $class
    } catch {
        $netSecurityAvailable = $false
    }
    if ($netSecurityAvailable) {
        try {
            $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
            if ($existing) { Remove-NetFirewallRule -DisplayName $name -ErrorAction Stop }
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Domain,Private,Public -ErrorAction Stop | Out-Null
            return [pscustomobject]@{ RuleName = $name; Mutated = $true; Port = $Port; Method = 'NetSecurity' }
        } catch {
            Write-Log -Level 'INFO' -Message ("Using netsh firewall path for {0} because NetSecurity was unavailable: {1}" -f $name, $_.Exception.Message)
        }
    }
    & netsh advfirewall firewall delete rule name="$name" protocol=TCP localport=$Port | Out-Null
    $output = & netsh advfirewall firewall add rule name="$name" dir=in action=allow protocol=TCP localport=$Port profile=domain,private,public enable=yes 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("netsh firewall rule creation failed for {0}: {1}" -f $name, ($output -join "`n"))
    }
    return [pscustomobject]@{ RuleName = $name; Mutated = $true; Port = $Port; Method = 'netsh' }
}

function Test-ExternalListener {
    param([int]$Port = 8080)
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    return [bool]($listeners | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::' })
}

Export-ModuleMember -Function *
