$ErrorActionPreference='Stop'
$un=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | ? { $_.DisplayName -eq 'AMD Ryzen Master' } | Sort-Object {[version]($_.DisplayVersion -replace '[^0-9\.]','')} -Descending | Select-Object -First 1
if(-not $un){ throw 'AMD Ryzen Master uninstall record not found' }
$key='HKLM:\SOFTWARE\AMD\RyzenMaster'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name 'VersionNumber' -Value $un.DisplayVersion -PropertyType String -Force | Out-Null
$cache='C:\Program Files\GIGABYTE\Control Center\GCCUpdate.txt'
if(Test-Path $cache){ Copy-Item $cache "$cache.bak.$(Get-Date -Format yyyyMMddHHmmss)" -Force; Remove-Item $cache -Force }
[pscustomobject]@{RyzenMasterInstalled=$un.DisplayVersion; GCCExpectedKey=$key; VersionNumber=(Get-ItemProperty $key).VersionNumber; GCCUpdateCacheCleared=(-not(Test-Path $cache))} | ConvertTo-Json -Compress
