param(
    [Parameter(Mandatory = $true)][string]$ProgressPath
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Repair Upgrade Progress'
$form.Width = 640
$form.Height = 220
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$label = New-Object System.Windows.Forms.Label
$label.Left = 16
$label.Top = 18
$label.Width = 590
$label.Height = 64
$label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Left = 16
$bar.Top = 92
$bar.Width = 590
$bar.Height = 28
$bar.Minimum = 0
$bar.Maximum = 100
$meta = New-Object System.Windows.Forms.Label
$meta.Left = 16
$meta.Top = 132
$meta.Width = 590
$meta.Height = 38
$meta.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$form.Controls.AddRange(@($label, $bar, $meta))
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    try {
        if (Test-Path -LiteralPath $ProgressPath) {
            $p = Get-Content -LiteralPath $ProgressPath -Raw | ConvertFrom-Json
            $percent = [int]([math]::Max(0, [math]::Min(100, $p.PercentComplete)))
            $bar.Value = $percent
            $label.Text = "$percent% - $($p.Status)"
            $meta.Text = "Updated: $($p.UpdatedAt)`r`nDeadline to start setup: $($p.LaunchDeadline)"
        } else {
            $label.Text = 'Waiting for repair-upgrade progress...'
            $meta.Text = $ProgressPath
        }
    } catch {
        $label.Text = "Progress monitor read error: $($_.Exception.Message)"
    }
})
$timer.Start()
[void]$form.ShowDialog()
