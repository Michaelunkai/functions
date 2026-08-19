$__extractedFunctionName = 'SafeBoot'
$__extractedCommandName = 'SafeBoot'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Function = $__extractedFunctionName
        Command = $__extractedCommandName
        Script = $__extractedScriptPath
        Exists = [bool](Test-Path -LiteralPath $__extractedScriptPath)
        Mode = 'SelfTest'
    } | ConvertTo-Json -Compress
    return
}

function SafeBoot {
    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet("Minimal", "Network", "AlternateShell")]
        [string]$Mode = "Minimal",
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        [Parameter(Mandatory=$false)]
        [int]$Timeout = 10
    )
    # Requires admin privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "ERROR: This function requires Administrator privileges. Please restart PowerShell as Administrator."
        return
    }
    try {
        # Verify bcdedit is available
        $bcdeditTest = bcdedit /enum | Out-String
        if (-not $?) {
            Write-Error "ERROR: Cannot access bcdedit. Make sure you're running as Administrator."
            return
        }
        # Configure boot settings with explicit output for debugging
        Write-Output "Configuring Safe Mode boot entry..." -ForegroundColor Cyan
        # Set up safe boot parameters
        switch ($Mode) {
            "Minimal" {
                $result = bcdedit /set '{current}' safeboot minimal
                Write-Output "bcdedit output: $result"
                Write-Output "Configured for Safe Mode (Minimal)" -ForegroundColor Green
            }
            "Network" {
                $result = bcdedit /set '{current}' safeboot network
                Write-Output "bcdedit output: $result"
                Write-Output "Configured for Safe Mode with Networking" -ForegroundColor Green
            }
            "AlternateShell" {
                $result1 = bcdedit /set '{current}' safeboot minimal
                $result2 = bcdedit /set '{current}' safebootalternateshell yes
                Write-Output "bcdedit output: $result1, $result2"
                Write-Output "Configured for Safe Mode with Command Prompt" -ForegroundColor Green
            }
        }
        # Verify the settings were applied
        Write-Output "Verifying boot configuration..." -ForegroundColor Cyan
        $verifyConfig = bcdedit /enum | Out-String
        if ($verifyConfig -match "safeboot\s+(\w+)") {
            Write-Output "Safe Boot configuration verified: $($Matches[1])" -ForegroundColor Green
            # Prompt for reboot
            if ($Force) {
                # Force restart without confirmation
                Write-Output "System will restart in $Timeout seconds..." -ForegroundColor Yellow
                Write-Output "WARNING: Your computer will boot into Safe Mode on the next restart." -ForegroundColor Red
                Start-Sleep -Seconds $Timeout
                shutdown.exe /r /t 0 /f
            } else {
                $confirm = Read-Host "System will restart into Safe Mode. Continue? (Y/N)"
                if ($confirm -eq "Y" -or $confirm -eq "y") {
                    Write-Output "Restarting system in 5 seconds..." -ForegroundColor Yellow
                    Write-Output "WARNING: Your computer will boot into Safe Mode on the next restart." -ForegroundColor Red
                    Start-Sleep -Seconds 5
                    shutdown.exe /r /t 0
                } else {
                    # Revert safe boot settings if user cancels
                    Write-Output "Reverting Safe Mode boot configuration..." -ForegroundColor Cyan
                    bcdedit /deletevalue '{current}' safeboot > $null
                    bcdedit /deletevalue '{current}' safebootalternateshell 2>$null > $null
                    Write-Output "Safe Mode boot configuration has been canceled and reverted." -ForegroundColor Yellow
                }
            }
        } else {
            Write-Error "ERROR: Failed to verify Safe Mode configuration. Safe Mode might not be properly configured."
            return
        }
    } catch {
        Write-Error "ERROR: An error occurred: $_"
        # Attempt to revert changes on error
        Write-Output "Attempting to revert boot configuration..." -ForegroundColor Yellow
        bcdedit /deletevalue '{current}' safeboot 2>$null > $null
        bcdedit /deletevalue '{current}' safebootalternateshell 2>$null > $null
    }
}

& $__extractedCommandName @__extractedArgs