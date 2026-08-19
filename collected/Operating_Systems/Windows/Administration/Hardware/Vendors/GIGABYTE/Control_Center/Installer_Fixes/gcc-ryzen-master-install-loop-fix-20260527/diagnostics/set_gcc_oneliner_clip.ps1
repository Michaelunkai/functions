$s=Get-Content 'C:\Temp\gcc_install_loop_clip_source.ps1' -Raw
$b=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s))
$one='powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$b
Set-Clipboard -Value $one
'len='+$one.Length
'prefix='+$one.Substring(0,[Math]::Min(90,$one.Length))
'clipok='+((Get-Clipboard) -eq $one)
$one | Set-Content 'C:\Temp\gcc_install_loop_fix_oneliner.txt' -Encoding ASCII
