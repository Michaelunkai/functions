$__extractedFunctionName = 'ccc1'
$__extractedCommandName = 'ccc1'
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

function ccc1 {
    function Run-WithTimeout {
        param([string]$Name, [string]$Cmd, [int]$TimeoutSec = 120)
        Write-Host "[ccc1] Running: $Name..." -ForegroundColor Cyan
        $proc = Start-Process powershell -ArgumentList "-NoLogo","-NonInteractive","-ExecutionPolicy","Bypass","-Command",". '$PROFILE' -ErrorAction SilentlyContinue; $Cmd" -PassThru -WindowStyle Hidden
        if ($proc.WaitForExit($TimeoutSec * 1000)) {
            Write-Host "[ccc1] Done: $Name" -ForegroundColor Green
        } else {
            $proc.Kill()
            Write-Host "[ccc1] TIMEOUT: $Name (>${TimeoutSec}s) - skipped" -ForegroundColor Yellow
        }
    }

    siz
    mgr
    ccsizes
    cleanc
    dkill
    rmvol
    Run-WithTimeout 'wingup' 'wingup' 180
    ps527
    refresh-disk
    recc
    # Purge stale .openclaw-* temp dirs after recc update
    $npmGlobal = npm.cmd config get prefix 2>$null
    if ($npmGlobal) {
        Get-ChildItem (Join-Path $npmGlobal 'node_modules') -Directory -Filter '.openclaw-*' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[ccc1] Deleted stale: $($_.Name)" -ForegroundColor DarkGray
        }
    }
    dstop
    freram
    fixfixFIX
    Run-WithTimeout 'adw'   'adw'   120
    Run-WithTimeout 'scan1' 'scan1' 300
    siz
}

& $__extractedCommandName @__extractedArgs