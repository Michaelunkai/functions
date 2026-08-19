$ErrorActionPreference='SilentlyContinue'
$targets = @('Kingdom Come Deliverance II v1.1-v1.4 Plus 41 Trainer.exe','KingdomCome.exe','gs_mngr_3.exe','setup.exe','setup.tmp')
Get-CimInstance Win32_Process | Where-Object { $targets -contains $_.Name } | Select-Object ProcessId,Name,ExecutablePath,CommandLine | Format-List
