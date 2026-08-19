$__extractedFunctionName = 'rmvol'
$__extractedCommandName = 'rmvol'
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

function rmvol {
    $ErrorActionPreference = 'SilentlyContinue'

    # Phase 1: Purge VSS shadows and permanently disable System Protection
    Write-Host "[1/5] Purging VSS shadows and System Protection..." -ForegroundColor Cyan
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | Select-Object -ExpandProperty Root
    & vssadmin delete shadows /all /quiet 2>$null | Out-Null
    foreach ($drive in $drives) {
        & powershell.exe -NoProfile -Command "Disable-ComputerRestore -Drive '$drive' -ErrorAction SilentlyContinue" 2>$null
    }
    try {
        $csp = Get-WmiObject -Namespace 'root\default' -Class SystemRestoreConfig -ErrorAction SilentlyContinue
        if ($csp) { $csp.RPSessionInterval = 0; $csp.Put() | Out-Null }
    } catch {}
    $srReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore"
    if (-not (Test-Path $srReg)) { New-Item -Path $srReg -Force | Out-Null }
    Set-ItemProperty -Path $srReg -Name "DisableSR" -Value 1 -Type DWord
    Set-ItemProperty -Path $srReg -Name "DisableConfig" -Value 1 -Type DWord
    Write-Host "  System Restore permanently disabled" -ForegroundColor Green

    # Phase 2: Permanently disable ALL services that write to SVI
    Write-Host "[2/5] Disabling all SVI-writing services permanently..." -ForegroundColor Cyan
    foreach ($svc in @('VSS','swprv','wbengine','SDRSVC','WSearch','TrkWks','StorSvc','MacriumService')) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        & sc.exe config $svc start= disabled 2>$null | Out-Null
    }
    Stop-Process -Name "ReflectUI","ReflectMonitor" -Force -ErrorAction SilentlyContinue
    & sc.exe config mrigflt start= disabled 2>$null | Out-Null
    $migReg = "HKLM:\SOFTWARE\Macrium\reflect\MIG"
    if (Test-Path $migReg) { Set-ItemProperty -Path $migReg -Name "Enabled" -Value 0 }
    Unregister-ScheduledTask -TaskName "RestoreMrigflt" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  All services disabled (VSS, Macrium, TrkWks, StorSvc, mrigflt)" -ForegroundColor Green

    # Phase 3: Force-delete SVI on every drive
    Write-Host "[3/5] Removing System Volume Information folders..." -ForegroundColor Cyan
    $emptyDir = Join-Path $env:TEMP "rmvol_empty_$(Get-Random)"
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    $pendingPaths = [System.Collections.Generic.List[string]]::new()

    foreach ($drive in $drives) {
        $svi = Join-Path $drive "System Volume Information"
        if (-not (Test-Path $svi)) { continue }
        Write-Host "  Processing: $svi" -ForegroundColor Yellow

        & takeown /f "$svi" /r /d y 2>$null | Out-Null
        & icacls "$svi" /grant "Administrators:(OI)(CI)F" /t /c /q 2>$null | Out-Null

        # Delete individual files first (most will delete, only kernel-locked ones won't)
        Get-ChildItem -Path $svi -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object { Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }

        # Try removing the now-empty folder
        & cmd /c "rd /s /q `"$svi`"" 2>$null
        if (Test-Path $svi) {
            & robocopy "$emptyDir" "$svi" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /nc /ns /np 2>$null | Out-Null
            & cmd /c "rd /s /q `"$svi`"" 2>$null
        }
        if (Test-Path $svi) {
            try { [System.IO.Directory]::Delete($svi, $true) } catch {}
        }

        if (Test-Path $svi) {
            $locked = @(Get-ChildItem -Path $svi -Recurse -Force -ErrorAction SilentlyContinue)
            if ($locked) {
                Write-Host "  Kernel-locked ($($locked.Count) files by PID 4): $svi" -ForegroundColor Yellow
                $locked | Sort-Object FullName -Descending | ForEach-Object { $pendingPaths.Add($_.FullName) }
            }
            $pendingPaths.Add($svi)
        } else {
            Write-Host "  Removed: $svi" -ForegroundColor Green
        }
    }
    Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue

    # Phase 4: Queue reboot-delete for kernel-locked paths (PID 4 NTFS)
    if ($pendingPaths.Count -gt 0) {
        Write-Host "[4/5] Queuing PendingFileRename for kernel-locked files..." -ForegroundColor Yellow
        $smssRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        # Deduplicate: clear old SVI entries, keep non-SVI entries
        $existing = @((Get-ItemProperty -Path $smssRegPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $ops = [System.Collections.Generic.List[string]]::new()
        if ($existing) {
            for ($i = 0; $i -lt $existing.Count; $i += 2) {
                if ($existing[$i] -notlike '*System Volume*') { $ops.Add($existing[$i]); $ops.Add($existing[$i+1]) }
            }
        }
        foreach ($p in $pendingPaths) {
            $ops.Add("\??\" + $p)
            $ops.Add("")
        }
        Set-ItemProperty -Path $smssRegPath -Name PendingFileRenameOperations -Value $ops.ToArray() -Type MultiString
        Write-Host "  $($pendingPaths.Count) paths queued (deduplicated)" -ForegroundColor Magenta
    }

    # Phase 5: Final status
    Write-Host "[5/5] Status:" -ForegroundColor Cyan
    $allClean = $true
    foreach ($drive in $drives) {
        $svi = Join-Path $drive "System Volume Information"
        $dl = $drive.TrimEnd('\')
        if (-not (Test-Path $svi)) {
            Write-Host "  $dl CLEAN" -ForegroundColor Green
        } else {
            $files = @(Get-ChildItem $svi -Force -ErrorAction SilentlyContinue)
            if ($files) { Write-Host "  $dl PENDING REBOOT ($($files.Name -join ', '))" -ForegroundColor Magenta; $allClean = $false }
            else { & cmd /c "rd /s /q `"$svi`"" 2>$null; Write-Host "  $dl CLEAN" -ForegroundColor Green }
        }
    }

    if ($allClean) { Write-Host "rmvol complete. All drives clean." -ForegroundColor Green }
    else { Write-Host "rmvol complete. Kernel-locked files will delete on reboot. Nothing restored." -ForegroundColor Green }
}

& $__extractedCommandName @__extractedArgs
