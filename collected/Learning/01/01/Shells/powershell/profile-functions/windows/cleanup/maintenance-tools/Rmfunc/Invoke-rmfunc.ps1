[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(ValueFromRemainingArguments)][object[]]$Remaining,
    [switch]$Force
)

$__mutationLibrary = @(
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\legacy-safe-functions\Invoke-ProfileFunctionMutation.ps1')
    'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Invoke-ProfileFunctionMutation.ps1'
    'F:\study\Windows\collected\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\Invoke-ProfileFunctionMutation.ps1'
    'F:\study\Platforms\windows\collected\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\Invoke-ProfileFunctionMutation.ps1'
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
if (-not $__mutationLibrary) {
    throw 'rmfunc could not locate Invoke-ProfileFunctionMutation.ps1 in any known profile location. Reinstall the ps5-profile-portable legacy-safe-functions folder.'
}
. $__mutationLibrary[0]

$__extraNames = @($Remaining | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
if ([string]::IsNullOrWhiteSpace($Name) -and $__extraNames.Count -eq 0) {
    Write-Host 'rmfunc - remove saved profile functions' -ForegroundColor Cyan
    Write-Host '  rmfunc <Name> [Name2 ...] [-Force]'
    return
}

$names = @($Name) + $__extraNames
Invoke-ProfileFunctionRemove -Name $names -Force:$Force
