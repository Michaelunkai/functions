$__extractedFunctionName = 'fixwmi'
$__extractedCommandName = 'fixwmi'
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

function fixwmi {
    [CmdletBinding()]
    param(
        [string]$OfflineSource
    )
    ############################################################
    # 0.  GUARANTEE ELEVATION
    ############################################################
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        Write-Error "Run this function in an elevated PowerShell session."
        return
    }
    # Helper   coloured instant output
    function _out([string]$msg,[string]$color="Gray"){Write-Host $msg -ForegroundColor $color}
    _out "=== Fix?WMI / WMIC repair script started @ $(Get-Date) ===" Cyan
    $wbemDir  = "$env:SystemRoot\System32\wbem"
    $wmicExe  = Join-Path $wbemDir 'wmic.exe'
    # DISM commands called directly (not via variable to avoid call operator issues)
    ############################################################
    # 1.  OPTIONAL FEATURE:  ENSURE  WMIC  CAPABILITY
    ############################################################
    _out "`n[1] Checking WMIC optional capability " Yellow
    $capName = "WMIC~~~~"
    $capState = (dism /online /Get-CapabilityInfo /CapabilityName:$capName 2>$null | Select-String "State :").ToString().Split(':')[-1].Trim()
    if ($capState -eq "Installed") {
        _out "    ? Capability already installed." Green
    } else {
        _out "    ? Capability missing ? installing " Yellow
        if ($OfflineSource) {
            $dismProc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /Add-Capability /CapabilityName:$capName /Source:`"$OfflineSource`" /NoRestart /Quiet" -Wait -PassThru -NoNewWindow
        } else {
            $dismProc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /Add-Capability /CapabilityName:$capName /NoRestart /Quiet" -Wait -PassThru -NoNewWindow
        }
        $rc = $dismProc.ExitCode
        if ($rc -eq 0) {
            _out "    ? WMIC capability installed successfully." Green
        } else {
            _out "    ? DISM failed (exit $rc) ? trying Add?WindowsCapability " Red
            try {
                $awcParams = @{Online=$true; Name=$capName}
                if ($OfflineSource) { $awcParams['Source']=$OfflineSource }
                Add-WindowsCapability @awcParams -ErrorAction Stop | Out-Null
                _out "    ? Add?WindowsCapability succeeded." Green
            } catch {
                _out "    ? Unable to install WMIC capability. Aborting." Red
                return
            }
        }
    }
    ############################################################
    # 2.  MAKE SURE WMIC.EXE EXISTS  (copy from WinSxS if needed)
    ############################################################
    if (-not (Test-Path $wmicExe)) {
        _out "`n[2] wmic.exe missing ? extracting from WinSxS " Yellow
        $sourceExe = Get-ChildItem "$env:SystemRoot\WinSxS" -Filter "wmic.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sourceExe) {
            Copy-Item $sourceExe.FullName $wmicExe -Force
            _out "    ? Copied $($sourceExe.FullName) to $wmicExe." Green
        } else {
            _out "    ? Could not locate wmic.exe in WinSxS. Aborting." Red
            return
        }
    } else {
        _out "`n[2] wmic.exe present at $wmicExe." Green
    }
    ############################################################
    # 3.  REPAIR / RESET WMI REPOSITORY & SERVICES
    ############################################################
    _out "`n[3] Resetting WMI services & repository " Yellow
    $serviceList = @("Winmgmt","WmiApSrv")
    foreach ($svc in $serviceList) {
        sc.exe config $svc start= auto | Out-Null
        try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {}
    }
    # Salvage & verify repository
    cmd.exe /c "winmgmt /salvagerepository"  | Out-Null
    cmd.exe /c "winmgmt /verifyrepository"   | Out-Null
    foreach ($svc in $serviceList) { Start-Service $svc -ErrorAction SilentlyContinue }
    _out "    ? WMI services restarted & repository verified." Green
    ############################################################
    # 4.  RE-REGISTER **ALL** WBEM MOF & MFL FILES
    ############################################################
    _out "`n[4] Recompiling every MOF/MFL in WBEM " Yellow
    Get-ChildItem $wbemDir -Include *.mof,*.mfl -Recurse | ForEach-Object {
        mofcomp $_.FullName 2>$null
    }
    _out "    ? MOF/MFL compilation complete." Green
    ############################################################
    # 5.  ADD WBEM TO SYSTEM PATH (if not there already)
    ############################################################
    _out "`n[5] Ensuring WBEM dir in system PATH " Yellow
    $machinePath = [Environment]::GetEnvironmentVariable("Path","Machine")
    if ($machinePath -notmatch [regex]::Escape($wbemDir)) {
        setx.exe PATH "$machinePath;$wbemDir" -m | Out-Null
        $env:Path = "$env:Path;$wbemDir"   # update current session
        _out "    ? Added WBEM directory to system PATH." Green
    } else {
        _out "    ? WBEM already in PATH." Green
    }
    ############################################################
    # 6.  HEALTH CHECK (DISM + SFC)
    ############################################################
    _out "`n[6] Running final health sweep (DISM /RestoreHealth ? SFC)  " Yellow
    Start-Process -FilePath "dism.exe" -ArgumentList "/online /Cleanup-Image /RestoreHealth /NoRestart /Quiet" -Wait -NoNewWindow | Out-Null
    sfc /scannow | Out-Null
    _out "    ? System image & component store repaired if required." Green
    ############################################################
    # 7.  VALIDATION
    ############################################################
    _out "`n[7] Validating WMI query + WMIC binary " Yellow
    if (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue) {
        _out "    ? WMI query succeeded." Green
    } else {
        _out "    ? WMI query failed   repository may still be corrupt." Red
    }
    try { wmic os get Caption,Version /value | Out-Null; _out "    ? WMIC executable verified." Green } catch { _out "    ? WMIC failed to run." Red }
    ############################################################
    _out "`n=== Fix?WMI completed @ $(Get-Date) ===`n" Cyan
}

& $__extractedCommandName @__extractedArgs