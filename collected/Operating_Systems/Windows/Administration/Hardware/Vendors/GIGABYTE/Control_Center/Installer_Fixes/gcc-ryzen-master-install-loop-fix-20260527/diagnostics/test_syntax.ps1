$ErrorActionPreference='Stop'
$p='F:\study\Operating_Systems\Windows\Administration\Hardware\Vendors\GIGABYTE\Control_Center\Installer_Fixes\gcc-ryzen-master-install-loop-fix-20260527\scripts\Fix-GCCInstallLoop.ps1'
[scriptblock]::Create((Get-Content -LiteralPath $p -Raw)) | Out-Null
'exists='+[string](Test-Path -LiteralPath $p)
'syntax-ok'
