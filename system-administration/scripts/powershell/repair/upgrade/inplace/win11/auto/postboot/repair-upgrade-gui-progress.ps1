param(
    [int]$SetupProcessId = 0,
    [string]$WindowTitle = 'Windows repair upgrade progress'
)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-SetupSnapshot {
    $candidateLogs = @(
        'C:\$WINDOWS.~BT\Sources\Panther\setupact.log',
        'C:\$WINDOWS.~BT\Sources\Rollback\setupact.log'
    )
    $logPath = $candidateLogs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $progress = $null
    $activity = 'Waiting for Windows Setup...'
    $lastWrite = $null
    if ($logPath) {
        $item = Get-Item -LiteralPath $logPath -Force
        $lastWrite = $item.LastWriteTime
        $tail = @(Get-Content -LiteralPath $logPath -Tail 150)
        [array]::Reverse($tail)
        foreach ($line in $tail) {
            if ($null -eq $progress -and $line -match 'Overall progress: \[(\d+)%\]|Action progress: \[(\d+)%\]|Progress percentage \[(\d+)\]|Progress:\s*(\d+)') {
                foreach ($group in $Matches.Values) {
                    if ($group -match '^\d+$') {
                        $progress = [int]$group
                        break
                    }
                }
            }
            if ($activity -eq 'Waiting for Windows Setup...' -and $line.Trim()) {
                $activity = $line.Trim()
            }
            if ($null -ne $progress -and $activity -ne 'Waiting for Windows Setup...') { break }
        }
    }

    $setup = $null
    if ($SetupProcessId -gt 0) {
        $setup = Get-Process -Id $SetupProcessId -ErrorAction SilentlyContinue
    }
    if (-not $setup) {
        $setup = Get-Process setup,setupprep,SetupHost -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    $readyToReboot = $false
    $readySignals = @(
        'reboot is required',
        'will reboot',
        'ready to reboot',
        'setup platform requested reboot',
        'Initiating reboot',
        'shutdown',
        'MOUPG.*reboot',
        'SP.*reboot'
    )
    if (-not $setup -and $lastWrite) {
        $readyToReboot = $true
    }
    foreach ($signal in $readySignals) {
        if ($activity -match $signal) {
            $readyToReboot = $true
            break
        }
    }

    [pscustomobject]@{
        Progress = $progress
        Activity = $activity
        LogPath = $logPath
        LastWrite = $lastWrite
        Process = $setup
        ReadyToReboot = $readyToReboot
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $WindowTitle
$form.Width = 660
$form.Height = 260
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#003399')
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.ControlBox = $true

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Left = 24
$titleLabel.Top = 16
$titleLabel.Width = 600
$titleLabel.Height = 32
$titleLabel.Text = 'Windows Setup'
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($titleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Left = 24
$statusLabel.Top = 56
$statusLabel.Width = 600
$statusLabel.Height = 40
$statusLabel.Text = 'Checking upgrade prerequisites...'
$statusLabel.ForeColor = [System.Drawing.Color]::White
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$form.Controls.Add($statusLabel)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Left = 24
$bar.Top = 108
$bar.Width = 600
$bar.Height = 24
$bar.Style = 'Marquee'
$bar.MarqueeAnimationSpeed = 30
$form.Controls.Add($bar)

$percentLabel = New-Object System.Windows.Forms.Label
$percentLabel.Left = 24
$percentLabel.Top = 142
$percentLabel.Width = 600
$percentLabel.Height = 24
$percentLabel.Text = ''
$percentLabel.ForeColor = [System.Drawing.Color]::White
$percentLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.Controls.Add($percentLabel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Left = 24
$detailLabel.Top = 172
$detailLabel.Width = 600
$detailLabel.Height = 60
$detailLabel.ForeColor = [System.Drawing.Color]::LightGray
$detailLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$detailLabel.Text = 'Monitoring C:\`$WINDOWS.~BT\Sources\Panther\setupact.log'
$form.Controls.Add($detailLabel)

$readyToRebootShown = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    $snapshot = Get-SetupSnapshot

    if ($snapshot.ReadyToReboot -and -not $readyToRebootShown) {
        $readyToRebootShown = $true
        $bar.Style = 'Continuous'
        $bar.MarqueeAnimationSpeed = 0
        $bar.Value = 100
        $titleLabel.Text = 'Ready to restart'
        $statusLabel.Text = 'Windows Setup has completed. Your PC will restart shortly.'
        $percentLabel.Text = '100% complete'
        $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#006600')
        $titleLabel.ForeColor = [System.Drawing.Color]::White
        $statusLabel.ForeColor = [System.Drawing.Color]::White
        $percentLabel.ForeColor = [System.Drawing.Color]::White
        $detailLabel.ForeColor = [System.Drawing.Color]::LightGreen
        $detailLabel.Text = "Setup handoff detected.`r`nDo not turn off your PC."
        return
    }

    if ($null -ne $snapshot.Progress) {
        $bar.Style = 'Continuous'
        $bar.MarqueeAnimationSpeed = 0
        $bar.Value = [Math]::Min(100, [Math]::Max(0, $snapshot.Progress))
        $titleLabel.Text = 'Installing Windows'
        $statusLabel.Text = $snapshot.Activity
        $percentLabel.Text = "$($bar.Value)% complete"
    } elseif ($snapshot.Process) {
        $bar.Style = 'Marquee'
        $bar.MarqueeAnimationSpeed = 30
        $titleLabel.Text = 'Windows Setup'
        $statusLabel.Text = 'Windows Setup is working...'
        $percentLabel.Text = ''
    } else {
        $bar.Style = 'Marquee'
        $bar.MarqueeAnimationSpeed = 30
        $titleLabel.Text = 'Windows Setup'
        $statusLabel.Text = 'Waiting for Windows Setup...'
        $percentLabel.Text = ''
    }

    $processText = if ($snapshot.Process) { "Process: $($snapshot.Process.ProcessName) PID $($snapshot.Process.Id)" } else { 'Process: no setup process active' }
    $logText = if ($snapshot.LastWrite) { "Log: $($snapshot.LogPath) | updated $($snapshot.LastWrite)" } else { 'Log: waiting for setup log' }
    $detailLabel.Text = "$processText`r`n$logText`r`n$($snapshot.Activity)"
})
$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosing({ $timer.Stop() })
[void]$form.ShowDialog()
