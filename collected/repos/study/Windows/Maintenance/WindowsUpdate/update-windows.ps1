#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update script - installs all updates except KB2267602 (Defender definitions).
    No automatic reboot. Prints list of KBs requiring reboot at end.
.NOTES
    PS v5 syntax. Run as Administrator.
#>

param()

Write-Host "=== Windows Update Script ===" -ForegroundColor Cyan
Write-Host "No automatic reboot. Excluding KB2267602 (Defender definitions)." -ForegroundColor Yellow

# --- Update Windows Defender signatures first ---
Write-Host "`n[Defender] Attempting Windows Defender signature update..." -ForegroundColor Cyan
try {
    $mpCmdPath = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (Test-Path $mpCmdPath) {
        $defenderResult = & $mpCmdPath -SignatureUpdate 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[Defender] Signature update succeeded." -ForegroundColor Green
        } else {
            Write-Host "[Defender] Signature update returned exit code $LASTEXITCODE (may already be current)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[Defender] MpCmdRun.exe not found at $mpCmdPath - skipping." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[Defender] Signature update error: $($_.Exception.Message)" -ForegroundColor Red
}

# --- Install-Module guard for PSWindowsUpdate ---
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "PSWindowsUpdate module not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "PSWindowsUpdate installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try manually: Install-Module PSWindowsUpdate -Force -Scope AllUsers" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "PSWindowsUpdate module found." -ForegroundColor Green
}

try {
    Import-Module PSWindowsUpdate -ErrorAction Stop
    Write-Host "PSWindowsUpdate module loaded." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to import PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Outer retry loop: keep installing until 0 updates remain (max 10 rounds) ---
$round = 0
$maxRounds = 10
$remainingCount = -1
$allRebootKBs = @()
$allInstalledKBs = @()
$allFailedKBs = @()
$allInstalledByRound = @{}
$installError = $null

do {
    $round++

    # Check how many updates are pending this round
    Write-Host "`nChecking for available updates (round $round)..." -ForegroundColor Cyan
    $availableUpdates = Get-WindowsUpdate -NotKBArticleID KB2267602
    $remainingCount = $availableUpdates.Count

    Write-Host "=== Round $round/$maxRounds - $remainingCount updates pending ===" -ForegroundColor Cyan

    if ($remainingCount -eq 0) {
        Write-Host "No updates remaining. Exiting loop." -ForegroundColor Green
        break
    }

    Write-Host "Available updates ($remainingCount):" -ForegroundColor Cyan
    $availableUpdates | Format-Table -AutoSize KBArticleIDs, Title, Size

    # --- Per-update progress before install ---
    Write-Host "`nUpdates queued for install:" -ForegroundColor Cyan
    $idx = 0
    $availableUpdates | ForEach-Object {
        $idx++
        $kbId = if ($_.KBArticleIDs) { $_.KBArticleIDs -join ',' } elseif ($_.KB) { $_.KB } else { 'N/A' }
        Write-Host "  [$idx/$remainingCount] KB$kbId - $($_.Title)" -ForegroundColor White
    }

    # --- Install updates (no auto-reboot) ---
    Write-Host "`nInstalling updates (round $round)..." -ForegroundColor Cyan
    $installResults = $null
    $installError = $null
    try {
        $installResults = Install-WindowsUpdate -NotKBArticleID KB2267602 -AcceptAll -IgnoreReboot -Verbose
    } catch {
        $installError = $_.Exception.Message
        Write-Host "ERROR during Install-WindowsUpdate (round $round): $installError" -ForegroundColor Red
    }

    # --- Collect results for this round ---
    Write-Host "`nCollecting results (round $round)..." -ForegroundColor Cyan
    $rebootKBs   = @()
    $installedKBs = @()
    $failedKBs   = @()

    if ($installResults) {
        $rebootKBs   = @($installResults | Where-Object { $_.RebootRequired -eq $true })
        $installedKBs = @($installResults | Where-Object { $_.RebootRequired -ne $true -and $_.Result -ne 'Failed' })
        $failedKBs   = @($installResults | Where-Object { $_.Result -eq 'Failed' })
        # Deduplicate by KB ID to avoid retrying the same KB multiple times
        $failedKBs = @($failedKBs | Sort-Object -Property @{E={if($_.KBArticleIDs){$_.KBArticleIDs[0]}elseif($_.KB){$_.KB}else{'N/A'}}} -Unique)
    }

    # Accumulate across rounds
    $allRebootKBs   += $rebootKBs
    $allInstalledKBs += $installedKBs
    $allFailedKBs   += $failedKBs
    $allInstalledByRound[$round] = $installedKBs

    # --- Per-KB retry logic for failed updates ---
    if ($failedKBs.Count -gt 0) {
        Write-Host "`n[Retry] Failed KBs detected: $($failedKBs.Count). Attempting per-KB retry..." -ForegroundColor Yellow
        $persistentFails = @()

        foreach ($failedKB in $failedKBs) {
            $kbId = if ($failedKB.KBArticleIDs) { $failedKB.KBArticleIDs[0] } elseif ($failedKB.KB) { $failedKB.KB } else { 'N/A' }
            Write-Host "`n[Retry] KB$kbId - $($failedKB.Title)" -ForegroundColor Cyan

            $retrySuccess = $false
            # Try up to 3 times with 5s sleep between
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                Write-Host "  [Attempt $attempt/3]" -ForegroundColor Gray
                try {
                    $retryResult = Install-WindowsUpdate -KBArticleID $kbId -AcceptAll -IgnoreReboot -ErrorAction Stop
                    if ($retryResult -and $retryResult.Result -ne 'Failed') {
                        Write-Host "  [Attempt $attempt] SUCCESS" -ForegroundColor Green
                        $retrySuccess = $true
                        break
                    }
                } catch {
                    Write-Host "  [Attempt $attempt] Error: $($_.Exception.Message)" -ForegroundColor Red
                }
                if ($attempt -lt 3) {
                    Start-Sleep -Seconds 5
                }
            }

            # If all 3 retries failed, trigger WUA scans and retry once more
            if (-not $retrySuccess) {
                Write-Host "  [Retry] All 3 attempts failed. Triggering WUA scans..." -ForegroundColor Yellow
                try {
                    Start-Process wuauclt -ArgumentList '/detectnow' -Wait -ErrorAction Stop
                    Write-Host "  [WUA] wuauclt /detectnow completed" -ForegroundColor Gray
                } catch {
                    Write-Host "  [WUA] wuauclt error: $($_.Exception.Message)" -ForegroundColor Red
                }
                try {
                    Start-Process usoclient -ArgumentList 'StartScan' -Wait -ErrorAction Stop
                    Write-Host "  [WUA] usoclient StartScan completed" -ForegroundColor Gray
                } catch {
                    Write-Host "  [WUA] usoclient error: $($_.Exception.Message)" -ForegroundColor Red
                }
                Start-Sleep -Seconds 15

                # One final retry after WUA scans
                Write-Host "  [Retry] Final attempt after WUA scan..." -ForegroundColor Cyan
                try {
                    $finalRetry = Install-WindowsUpdate -KBArticleID $kbId -AcceptAll -IgnoreReboot -ErrorAction Stop
                    if ($finalRetry -and $finalRetry.Result -ne 'Failed') {
                        Write-Host "  [Final] SUCCESS" -ForegroundColor Green
                        $retrySuccess = $true
                    }
                } catch {
                    Write-Host "  [Final] Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # Track persistent failures
            if (-not $retrySuccess) {
                $persistentFails += $failedKB
                Write-Host "  [Status] PERSISTENT FAIL - added to persistent failures list" -ForegroundColor Red
            }
        }

        # Store persistent fails for later use (COM fallback, reporting)
        if (-not (Get-Variable -Name allPersistentFails -ErrorAction SilentlyContinue)) {
            $allPersistentFails = @()
        }
        $allPersistentFails += $persistentFails
        Write-Host "`n[Retry] Round ${round}: $($persistentFails.Count) persistent failures tracked" -ForegroundColor Magenta

        # --- COM-object WUA fallback for stubborn updates ---
        if ($persistentFails.Count -gt 0) {
            Write-Host "`n[COM] Attempting COM-object WUA fallback for $($persistentFails.Count) stubborn update(s)..." -ForegroundColor Cyan
            try {
                $wuaSession    = New-Object -ComObject Microsoft.Update.Session
                $wuaSearcher   = $wuaSession.CreateUpdateSearcher()
                $wuaResults    = $wuaSearcher.Search('IsInstalled=0 and IsHidden=0')
                $wuaUpdates    = $wuaResults.Updates

                if ($wuaUpdates.Count -gt 0) {
                    Write-Host "[COM] Found $($wuaUpdates.Count) update(s) via WUA COM searcher." -ForegroundColor Cyan

                    $wuaDownloader         = $wuaSession.CreateUpdateDownloader()
                    $wuaDownloader.Updates = $wuaUpdates
                    Write-Host "[COM] Downloading updates via WUA COM..." -ForegroundColor Gray
                    $dlResult = $wuaDownloader.Download()
                    Write-Host "[COM] Download result code: $($dlResult.ResultCode)" -ForegroundColor Gray

                    $wuaInstaller         = $wuaSession.CreateUpdateInstaller()
                    $wuaInstaller.Updates = $wuaUpdates
                    Write-Host "[COM] Installing updates via WUA COM..." -ForegroundColor Gray
                    $wuaInstallResult = $wuaInstaller.Install()

                    # ResultCode: 0=NotStarted 1=InProgress 2=Succeeded 3=SucceededWithErrors 4=Failed 5=Aborted
                    if ($wuaInstallResult.ResultCode -eq 2 -or $wuaInstallResult.ResultCode -eq 3) {
                        Write-Host "[COM] WUA COM install succeeded (ResultCode=$($wuaInstallResult.ResultCode))." -ForegroundColor Green
                    } else {
                        Write-Host "[COM] WUA COM install finished with ResultCode=$($wuaInstallResult.ResultCode) (4=Failed 5=Aborted)." -ForegroundColor Yellow
                    }
                    if ($wuaInstallResult.RebootRequired) {
                        Write-Host "[COM] Reboot required after COM install." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[COM] WUA COM searcher found no pending updates." -ForegroundColor Green
                }
            } catch {
                Write-Host "[COM] WUA COM fallback error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    # Round summary
    Write-Host "`n--- Round $round summary: installed=$($installedKBs.Count) reboot=$($rebootKBs.Count) failed=$($failedKBs.Count) ---" -ForegroundColor Magenta

    # Re-check remaining after this round
    $afterCheck = Get-WindowsUpdate -NotKBArticleID KB2267602
    $remainingCount = $afterCheck.Count
    Write-Host "Remaining after round ${round}: $remainingCount" -ForegroundColor Cyan

    # If nothing was installed this round and updates still remain, avoid infinite loop
    if ($installedKBs.Count -eq 0 -and $rebootKBs.Count -eq 0 -and $remainingCount -gt 0) {
        Write-Host "No progress this round ($remainingCount still pending). Breaking to avoid loop." -ForegroundColor Yellow
        break
    }

} while ($remainingCount -gt 0 -and $round -lt $maxRounds)

# --- Task Scheduler auto-resume if reboot required ---
if ($allRebootKBs.Count -gt 0) {
    Write-Host "`n[Scheduler] Reboot-pending KBs detected ($($allRebootKBs.Count)). Registering auto-resume task..." -ForegroundColor Yellow
    try {
        $taskAction  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"F:\study\Windows\Maintenance\WindowsUpdate\update-windows.ps1`""
        $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
        Register-ScheduledTask -TaskName 'WindowsUpdateResume' -Action $taskAction -Trigger $taskTrigger -RunLevel Highest -Force | Out-Null
        Write-Host "[Scheduler] REBOOT REQUIRED - auto-resume scheduled at next logon (task: WindowsUpdateResume)" -ForegroundColor Yellow
        Write-Host "[Scheduler] Reboot-pending KBs:" -ForegroundColor Yellow
        $allRebootKBs | ForEach-Object {
            $kbId = if ($_.KB) { $_.KB } elseif ($_.KBArticleIDs) { $_.KBArticleIDs -join ',' } else { 'N/A' }
            Write-Host "  [REBOOT] KB$kbId - $($_.Title)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[Scheduler] Failed to register auto-resume task: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    # Remove any leftover resume task if no reboot needed
    try {
        Unregister-ScheduledTask -TaskName 'WindowsUpdateResume' -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

# --- Final Get-WindowsUpdate check to confirm 0 remaining ---
Write-Host "`n[Final Check] Running Get-WindowsUpdate to confirm 0 remaining..." -ForegroundColor Cyan
$finalCheck = Get-WindowsUpdate -NotKBArticleID KB2267602
$finalCount = $finalCheck.Count
$finalColor = if ($finalCount -eq 0) { 'Green' } else { 'Yellow' }
Write-Host "[Final Check] Remaining updates: $finalCount" -ForegroundColor $finalColor

# --- Print final summary ---
Write-Host "`n========================================" -ForegroundColor Magenta

if ($finalCount -eq 0 -and $allRebootKBs.Count -eq 0) {
    Write-Host "  ALL UPDATES INSTALLED - 0 REMAINING  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Magenta
} elseif ($finalCount -eq 0) {
    Write-Host "  ALL UPDATES INSTALLED - 0 REMAINING  " -ForegroundColor Green
    Write-Host "  (Reboot required to complete some KBs)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Magenta
} else {
    Write-Host "  $finalCount UPDATE(S) STILL PENDING  " -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Magenta
}

# --- KBs installed grouped by round ---
if ($allInstalledKBs.Count -gt 0) {
    Write-Host "`nInstalled KBs by round ($($allInstalledKBs.Count) total across $round round(s)):" -ForegroundColor Green
    foreach ($r in ($allInstalledByRound.Keys | Sort-Object)) {
        $rKBs = $allInstalledByRound[$r]
        if ($rKBs -and $rKBs.Count -gt 0) {
            Write-Host "  Round $r ($($rKBs.Count) KB(s)):" -ForegroundColor Cyan
            $rKBs | ForEach-Object {
                $kbId = if ($_.KB) { $_.KB } elseif ($_.KBArticleIDs) { $_.KBArticleIDs -join ',' } else { 'N/A' }
                Write-Host "    [OK] KB$kbId - $($_.Title)" -ForegroundColor Green
            }
        }
    }
}

if ($allRebootKBs.Count -gt 0) {
    Write-Host "`nRESTART REQUIRED to complete:" -ForegroundColor Red
    $allRebootKBs | ForEach-Object {
        $kbId = if ($_.KB) { $_.KB } elseif ($_.KBArticleIDs) { $_.KBArticleIDs -join ',' } else { 'N/A' }
        Write-Host "  [REBOOT] KB$kbId - $($_.Title)" -ForegroundColor Red
    }
} elseif ($allInstalledKBs.Count -gt 0) {
    Write-Host "`nNO REBOOT REQUIRED." -ForegroundColor Green
}

if ($allFailedKBs.Count -gt 0) {
    Write-Host "`nFAILED ($($allFailedKBs.Count) updates):" -ForegroundColor Red
    $allFailedKBs | ForEach-Object {
        $kbId = if ($_.KB) { $_.KB } elseif ($_.KBArticleIDs) { $_.KBArticleIDs -join ',' } else { 'N/A' }
        Write-Host "  [FAIL] KB$kbId - $($_.Title)" -ForegroundColor Red
    }
}

if ($installError) {
    Write-Host "`nLast install error: $installError" -ForegroundColor Red
}

if ($allInstalledKBs.Count -eq 0 -and $allRebootKBs.Count -eq 0 -and $allFailedKBs.Count -eq 0 -and -not $installError) {
    Write-Host "`nNo updates were installed this run." -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "Update script complete ($round round(s) run). No automatic reboot was performed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Magenta

# --- ACTION REQUIRED instruction block ---
Write-Host "`n ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "  Open Settings > Windows Update and verify 'You are up to date' is shown." -ForegroundColor White
Write-Host "  If updates still appear, run update-windows.ps1 again." -ForegroundColor White
Write-Host ""
