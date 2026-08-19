param(
    [int]$WaitSeconds = 8,
    [int]$StableMilliseconds = 3000
)

$ErrorActionPreference = 'Stop'
$appPath = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe'

if (-not (Test-Path -LiteralPath $appPath)) {
    throw "NVIDIA App executable was not found: $appPath"
}

function Get-VisibleNvidiaWindow {
    @(
        Get-Process -Name 'NVIDIA App' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.Responding }
    )
}

function Start-NvidiaUi {
    Start-Process -FilePath $appPath -WorkingDirectory (Split-Path -Parent $appPath)
}

function Wait-ForVisibleNvidiaWindow {
    param(
        [int]$Seconds,
        [int]$RequiredStableMilliseconds
    )

    $deadline = (Get-Date).AddSeconds($Seconds)
    $visibleSince = $null
    do {
        if ((Get-VisibleNvidiaWindow).Count -gt 0) {
            if ($null -eq $visibleSince) {
                $visibleSince = Get-Date
            }
            if (((Get-Date) - $visibleSince).TotalMilliseconds -ge $RequiredStableMilliseconds) {
                return $true
            }
        } else {
            $visibleSince = $null
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return $false
}

Start-NvidiaUi
if (Wait-ForVisibleNvidiaWindow -Seconds $WaitSeconds -RequiredStableMilliseconds $StableMilliseconds) {
    exit 0
}

# The NVIDIA backend services are deliberately left alone.  Only a UI process
# that failed to create any visible window is restarted.
$orphanedUi = @(Get-Process -Name 'NVIDIA App' -ErrorAction SilentlyContinue)
if ($orphanedUi.Count -gt 0) {
    Stop-Process -Id $orphanedUi.Id -Force -ErrorAction Stop
}

Start-Sleep -Milliseconds 500
Start-NvidiaUi
if (-not (Wait-ForVisibleNvidiaWindow -Seconds $WaitSeconds -RequiredStableMilliseconds $StableMilliseconds)) {
    throw 'NVIDIA App did not keep a visible window after a UI-only restart.'
}
