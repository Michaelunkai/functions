$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'HermesControllerMaximizer'
$latest=Get-ChildItem (Join-Path $root 'logs') -Filter 'controller-max-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(-not $latest){ throw 'No log found' }
Write-Host "LOG=$($latest.FullName)"
$lines=Get-Content -LiteralPath $latest.FullName
$changed=$lines | Where-Object { $_ -match 'POWERSAVE (set|disabled) .* path=' }
Write-Host "changedLines=$($changed.Count)"
foreach($line in $changed){
  if($line -match ' path=(HKLM:.+)$'){
    $rp=$Matches[1]
    # Keep actual Xbox/HID controller paths only; revert broad accidental device-controller matches.
    $isXbox = ($rp -match 'VID_045E|PID_0B05|00001124|BTHENUM.*14CB658953BD')
    if(-not $isXbox -and (Test-Path -LiteralPath $rp)){
      if($line -match 'POWERSAVE set (\w+)=0 path='){
        $name=$Matches[1]
        Remove-ItemProperty -LiteralPath $rp -Name $name -ErrorAction SilentlyContinue
        Write-Host "REVERT remove $name path=$rp"
      } elseif($line -match 'POWERSAVE disabled (\w+) old=([^ ]+) path='){
        $name=$Matches[1]; $old=[int]$Matches[2]
        Set-ItemProperty -LiteralPath $rp -Name $name -Type DWord -Value $old -ErrorAction SilentlyContinue
        Write-Host "REVERT restore $name=$old path=$rp"
      }
    }
  }
}
# Patch script: narrow target selection to Microsoft Xbox/Bluetooth XINPUT/HID game controller only.
$main=Join-Path $root 'Invoke-ControllerMaximizer.ps1'
$text=[IO.File]::ReadAllText($main)
$old=@'
  $targets=Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Xbox|Controller|Bluetooth XINPUT|HID-compliant game controller' -or $_.InstanceId -match 'VID_045E|PID_0B05|00001124' }
'@
$new=@'
  $targets=Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_045E|PID_0B05|00001124|14CB658953BD' -or $_.FriendlyName -match '^Xbox |Xbox Elite|Xbox Wireless|Bluetooth XINPUT-compatible input device|^HID-compliant game controller$' }
'@
if($text -notlike "*$old*"){ throw 'Target selection block not found' }
$text=$text.Replace($old,$new)
[IO.File]::WriteAllText($main,$text,[Text.Encoding]::UTF8)
Write-Host 'PATCHED narrow target selector'
