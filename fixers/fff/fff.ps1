# fff.ps1 - one-shot DISM + SFC system repair via fixfixfix.
# Thin passthrough: forwards every switch (-Full, -SelfTest, ...) so fff -Full
# forces the full repair and fff -SelfTest stays cheap. Success/failure is
# judged by $LASTEXITCODE (fixfixfix never throws), so a failed step shows as
# FFF_FAILED with the exit code set - no exception spam.
function fff {
    [CmdletBinding()]
    param(
        [switch]$SelfTest,
        [switch]$Full,
        [int]$NativeTimeoutSeconds = 2700,
        [int]$InactivityTimeoutSeconds = 300,
        [int]$StatusIntervalSeconds = 15
    )

    $repairScript = 'F:\study\repos\shells\powershell\fixfixfix.ps1'

    if ($SelfTest) {
        & $repairScript -SelfTest -NativeTimeoutSeconds $NativeTimeoutSeconds -InactivityTimeoutSeconds $InactivityTimeoutSeconds -StatusIntervalSeconds $StatusIntervalSeconds
        Write-Output 'FFF_SELFTEST_OK destructiveVssStep=false'
        return
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # -Full:$Full is safe here: the profile's fixfixfix wrapper now
        # declares its switches, so '-Full:$false' binds (never becomes a
        # positional 'False').
        & $repairScript -Full:$Full -NativeTimeoutSeconds $NativeTimeoutSeconds -InactivityTimeoutSeconds $InactivityTimeoutSeconds -StatusIntervalSeconds $StatusIntervalSeconds
        if ($LASTEXITCODE -ne 0) { throw 'fff: fixfixfix reported failure.' }
        $watch.Stop()
        $global:LASTEXITCODE = 0
        Write-Host ("FFF_OK elapsed_ms={0} destructiveVssStep=false" -f $watch.ElapsedMilliseconds) -ForegroundColor Green
    } catch {
        $watch.Stop()
        $global:LASTEXITCODE = 1
        Write-Host ("FFF_FAILED elapsed_ms={0} message=[{1}]" -f $watch.ElapsedMilliseconds, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'fff' @args
}
