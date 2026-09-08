param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(Position = 1)][scriptblock]$Body,
    [switch]$SelfTest
)

. 'F:\study\Learning\01\01\Shells\powershell\profile-functions\Invoke-ProfileFunctionMutation.ps1'
if ($SelfTest) {
    Invoke-ProfileFunctionMutation -Operation Add -Name '__ProfileMutationSelfTest' -Body { $null } -SelfTest
    return
}
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host 'addfunc <Name> { function body }' -ForegroundColor Cyan
    return
}
Invoke-ProfileFunctionMutation -Operation Add -Name $Name -Body $Body -SelfTest:$SelfTest
