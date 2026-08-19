$ErrorActionPreference='SilentlyContinue'
Write-Host '=== Time ==='
Get-Date -Format o
Write-Host '=== Xbox/HID/Bluetooth devices ==='
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'Xbox|Controller|Gamepad|Bluetooth XINPUT|XINPUT|HID-compliant game controller|Xbox Wireless' -or $_.Class -match 'Bluetooth|HIDClass|MEDIA' } | Sort-Object Class,FriendlyName | Select-Object Class,Status,FriendlyName,InstanceId | Format-List
Write-Host '=== Services ==='
'GameInputSvc','BthAvctpSvc','bthserv','XboxGipSvc','GamingServices','GamingServicesNet','XblAuthManager','XblGameSave','XboxNetApiSvc' | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType,ServiceType } | Format-Table -AutoSize
Write-Host '=== XInput live probe (2 seconds) ==='
$code = @"
using System;
using System.Runtime.InteropServices;
public class XI {
  [StructLayout(LayoutKind.Sequential)] public struct State { public UInt32 dwPacketNumber; public Gamepad Gamepad; }
  [StructLayout(LayoutKind.Sequential)] public struct Gamepad { public UInt16 wButtons; public byte bLeftTrigger; public byte bRightTrigger; public Int16 sThumbLX; public Int16 sThumbLY; public Int16 sThumbRX; public Int16 sThumbRY; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] public static extern UInt32 XInputGetState(UInt32 dwUserIndex, out State pState);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
for($i=0; $i -lt 4; $i++){
  for($slot=0; $slot -lt 4; $slot++){
    $st = New-Object XI+State
    $r = [XI]::XInputGetState([uint32]$slot, [ref]$st)
    if($r -eq 0){
      $rb = (($st.Gamepad.wButtons -band 0x0200) -ne 0)
      $lb = (($st.Gamepad.wButtons -band 0x0100) -ne 0)
      $a = (($st.Gamepad.wButtons -band 0x1000) -ne 0)
      Write-Host ("slot={0} packet={1} buttons=0x{2:X4} RB={3} LB={4} A={5} LT={6} RT={7}" -f $slot,$st.dwPacketNumber,$st.Gamepad.wButtons,$rb,$lb,$a,$st.Gamepad.bLeftTrigger,$st.Gamepad.bRightTrigger)
    }
  }
  Start-Sleep -Milliseconds 500
}
Write-Host '=== Recent GameInput/Bluetooth/System event hints ==='
Get-WinEvent -LogName System -MaxEvents 120 | Where-Object { $_.ProviderName -match 'GameInput|BTH|Bluetooth|Hid|XINPUT|BTHUSB|HidBth' -or $_.Message -match 'GameInput|Bluetooth|Xbox|Controller|HID' } | Select-Object -First 12 TimeCreated,ProviderName,Id,LevelDisplayName,Message | Format-List
