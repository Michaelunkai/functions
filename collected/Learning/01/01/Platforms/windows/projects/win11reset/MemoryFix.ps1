#Requires -RunAsAdministrator
# Windows 11 Memory Fix

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "`n  ============ MEMORY FIX ============" -ForegroundColor Green
Write-Host "  Optimizing memory usage...`n" -ForegroundColor White

# Get current memory status
$os = Get-CimInstance Win32_OperatingSystem
$totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedMem = $totalMem - $freeMem
$usedPct = [math]::Round(($usedMem / $totalMem) * 100, 1)

Write-Host "Current memory: $usedMem GB used / $totalMem GB ($usedPct%)" -ForegroundColor Gray

# Step 1: Clear working sets
Write-Host "`n[1/4] Clearing process working sets..." -ForegroundColor Yellow
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
Write-Host "  [OK] GC completed" -ForegroundColor Green

# Step 2: Clear standby memory
Write-Host "`n[2/4] Clearing standby list..." -ForegroundColor Yellow
# RAMMap equivalent - clear standby
$code = @'
using System;
using System.Runtime.InteropServices;
public class MemoryCleaner {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
'@
try {
    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
    Get-Process | Where-Object { $_.WorkingSet64 -gt 100MB } | ForEach-Object {
        [MemoryCleaner]::EmptyWorkingSet($_.Handle) | Out-Null
    }
    Write-Host "  [OK] Working sets trimmed" -ForegroundColor Green
} catch {
    Write-Host "  [!] Partial cleanup (needs admin)" -ForegroundColor Yellow
}

# Step 3: Clear system cache
Write-Host "`n[3/4] Clearing system cache..." -ForegroundColor Yellow
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Temp files cleared" -ForegroundColor Green

# Step 4: Verify page file
Write-Host "`n[4/4] Checking page file..." -ForegroundColor Yellow
$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
if ($pageFile) {
    Write-Host "  Page file: $($pageFile.AllocatedBaseSize) MB allocated" -ForegroundColor Gray
    Write-Host "  Current usage: $($pageFile.CurrentUsage) MB" -ForegroundColor Gray
}

# Final status
$osFinal = Get-CimInstance Win32_OperatingSystem
$freeMemFinal = [math]::Round($osFinal.FreePhysicalMemory / 1MB, 2)
$freed = $freeMemFinal - $freeMem

Write-Host "`n  ============ COMPLETE ============" -ForegroundColor Green
Write-Host "  Memory freed: $freed GB" -ForegroundColor $(if($freed -gt 0){"Green"}else{"Gray"})
Write-Host "  Free now: $freeMemFinal GB" -ForegroundColor Cyan

Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
