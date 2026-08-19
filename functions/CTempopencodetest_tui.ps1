$ErrorActionPreference = 'SilentlyContinue'
$env:NVIDIA_API_KEY = (Get-Content 'F:\backup\windowsapps\credentials\nvidia\api.txt' -Raw).Trim()

$exe = 'C:\Users\micha\AppData\Local\npm-global\node_modules\opencode-ai\node_modules\opencode-windows-x64\bin\opencode.exe'

# Try to capture the crash from the TUI by running it briefly
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $exe
$pinfo.Arguments = '-m nvidia/thinkingmachines/inkling'
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($pinfo)
Start-Sleep -Seconds 8

if ($proc.HasExited -eq $false) {
    $proc.Kill()
    Write-Host "Process was killed after timeout"
} else {
    Write-Host "Process exited with code: $($proc.ExitCode)"
}

$stderr = $proc.StandardError.ReadToEnd()
$stdout = $proc.StandardOutput.ReadToEnd()

Write-Host "=== STDERR ($($stderr.Length) chars) ==="
Write-Host $stderr
Write-Host "=== STDOUT ($($stdout.Length) chars) ==="
Write-Host $stdout
