$__extractedFunctionName = 'getdirectx'
$__extractedCommandName = 'getdirectx'
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

function getdirectx {
    # Install DirectX End-User Runtime (legacy d3dx9/10/11, xinput, xaudio for older games)
    # Uses full offline installer + silent mode - no popups, no errors
    param([switch]$Force, [switch]$CheckOnly)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $requiredDlls = @(
        'd3dx9_24.dll','d3dx9_25.dll','d3dx9_26.dll','d3dx9_27.dll','d3dx9_28.dll',
        'd3dx9_29.dll','d3dx9_30.dll','d3dx9_31.dll','d3dx9_32.dll','d3dx9_33.dll',
        'd3dx9_34.dll','d3dx9_35.dll','d3dx9_36.dll','d3dx9_37.dll','d3dx9_38.dll',
        'd3dx9_39.dll','d3dx9_40.dll','d3dx9_41.dll','d3dx9_42.dll','d3dx9_43.dll',
        'd3dx10_33.dll','d3dx10_34.dll','d3dx10_35.dll','d3dx10_36.dll','d3dx10_37.dll',
        'd3dx10_38.dll','d3dx10_39.dll','d3dx10_40.dll','d3dx10_41.dll','d3dx10_42.dll','d3dx10_43.dll',
        'd3dx11_42.dll','d3dx11_43.dll',
        'xinput1_3.dll','x3daudio1_7.dll','xaudio2_7.dll','xactengine3_7.dll',
        'd3dcompiler_43.dll','d3dcsx_43.dll'
    )

    function local:Test-DXInstalled {
        $m = @()
        foreach ($d in $requiredDlls) {
            if (-not (Test-Path "$env:SystemRoot\System32\$d") -and -not (Test-Path "$env:SystemRoot\SysWOW64\$d")) { $m += $d }
        }
        return $m
    }

    Write-Host "`n=== DirectX Legacy Runtime ===" -ForegroundColor Cyan
    $missing = local:Test-DXInstalled

    if ($CheckOnly) {
        if ($missing.Count -eq 0) { Write-Host "  All $($requiredDlls.Count) legacy DLLs present." -ForegroundColor Green }
        else { Write-Host "  Missing $($missing.Count): $($missing -join ', ')" -ForegroundColor Yellow }
        return
    }

    if ($missing.Count -eq 0 -and -not $Force) {
        Write-Host "  All $($requiredDlls.Count) legacy DirectX DLLs already installed!" -ForegroundColor Green
        Write-Host "  DirectX 12 built into Windows 11. Use -Force to reinstall." -ForegroundColor Gray
        return
    }

    if ($missing.Count -gt 0) { Write-Host "  Missing $($missing.Count) DLLs - installing..." -ForegroundColor Yellow }
    else { Write-Host "  Force reinstall..." -ForegroundColor Yellow }

    $url = "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
    $dl = "$env:TEMP\directx_Jun2010_redist.exe"
    $ex = "$env:TEMP\directx_extract"

    if (Test-Path $dl) { if ((Get-Item $dl).Length -lt 90000000) { Remove-Item $dl -Force } }
    if (-not (Test-Path $dl)) {
        Write-Host "  Downloading ~96MB offline installer..." -ForegroundColor Cyan
        try { Invoke-WebRequest -Uri $url -OutFile $dl -UseBasicParsing }
        catch { Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red; return }
    } else { Write-Host "  Using cached download." -ForegroundColor Green }

    Write-Host "  Extracting..." -ForegroundColor Cyan
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    New-Item -ItemType Directory -Path $ex -Force | Out-Null
    $p = Start-Process $dl -ArgumentList "/Q /T:`"$ex`"" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Write-Host "  Extract failed ($($p.ExitCode))" -ForegroundColor Red; return }

    Write-Host "  Installing silently (no popups)..." -ForegroundColor Cyan
    $p = Start-Process "$ex\DXSETUP.exe" -ArgumentList "/silent" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Write-Host "  DXSETUP warning: exit code $($p.ExitCode)" -ForegroundColor Yellow }

    Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue

    $missing = local:Test-DXInstalled
    if ($missing.Count -eq 0) { Write-Host "  SUCCESS: All DLLs verified!" -ForegroundColor Green }
    else { Write-Host "  Still missing: $($missing -join ', ')" -ForegroundColor Yellow }
    Write-Host ""
}

& $__extractedCommandName @__extractedArgs