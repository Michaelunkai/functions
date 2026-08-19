$ErrorActionPreference='SilentlyContinue'
$keys=@('HKLM:\SOFTWARE\AMD\RyzenMaster','HKLM:\SOFTWARE\WOW6432Node\AMD\RyzenMaster','HKCU:\SOFTWARE\AMD\RyzenMaster')
$r=foreach($k in $keys){ if(Test-Path $k){ $p=Get-ItemProperty $k; [pscustomobject]@{Key=$k; Exists=$true; Values=($p.PSObject.Properties | ?{$_.Name -notmatch '^PS'} | % { $_.Name+'='+$_.Value }) -join '; '} } else { [pscustomobject]@{Key=$k; Exists=$false; Values=''} } }
$r | ConvertTo-Json -Depth 3
