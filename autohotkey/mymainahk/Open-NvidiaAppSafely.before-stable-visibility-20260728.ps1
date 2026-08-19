param(
    [int]$WaitSeconds = 5
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
    param([int]$Seconds)

    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if ((Get-VisibleNvidiaWindow).Count -gt 0) {
            return $true
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return $false
}

Start-NvidiaUi
if (Wait-ForVisibleNvidiaWindow -Seconds $WaitSeconds) {
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
if (-not (Wait-ForVisibleNvidiaWindow -Seconds $WaitSeconds)) {
    throw 'NVIDIA App did not create a visible window after a UI-only restart.'
}
