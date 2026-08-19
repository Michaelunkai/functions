$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Path $PSCommandPath -Parent
$script = Join-Path $root 'UltimatePerformanceRefresh.ps1'
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script,'-NoPause') -WindowStyle Hidden
