#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
$rebootFlagPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)

$cleared = @()

try {
    $pfro = Get-ItemProperty -Path $sessionManagerPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro) {
        Remove-ItemProperty -Path $sessionManagerPath -Name PendingFileRenameOperations -Force -ErrorAction SilentlyContinue
        $cleared += 'PendingFileRenameOperations'
    }

    foreach ($rebootFlagPath in $rebootFlagPaths) {
        if (Test-Path $rebootFlagPath) {
            Remove-Item -Path $rebootFlagPath -Force -ErrorAction SilentlyContinue
            $cleared += (Split-Path $rebootFlagPath -Leaf)
        }
    }
} catch {
    Write-Warning ("WINUPG pre-clear warning: {0}" -f $_.Exception.Message)
}

if ($cleared.Count -gt 0) {
    Write-Host ("WINUPG_PRECLEAR={0}" -f ($cleared -join ',')) -ForegroundColor Yellow
} else {
    Write-Host 'WINUPG_PRECLEAR=NONE' -ForegroundColor DarkGray
}
