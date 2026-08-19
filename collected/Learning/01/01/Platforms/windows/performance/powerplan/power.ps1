# NUCLEAR POWER PLAN ENFORCER - SINGLE SCRIPT SOLUTION
# Run this ONCE on any new machine and it sets up PERMANENT enforcement
# Must run as Administrator

$POWER_GUID = "e7b3c3f6-7f35-4f4c-8b48-8f1ece9cd139"

# Self-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "=== NUCLEAR POWER ENFORCER ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check if power plan exists, if not create it
Write-Host "[1/5] Checking power plan..." -ForegroundColor Yellow
$planExists = powercfg /list | Select-String $POWER_GUID
if (-not $planExists) {
    Write-Host "  Creating Nuclear_Performance_v12 power plan..." -ForegroundColor Gray
    # Duplicate Ultimate Performance and customize
    $ultPerf = powercfg /list | Select-String "Ultimate Performance" | Select-Object -First 1
    if ($ultPerf -match "([a-f0-9-]{36})") {
        powercfg /duplicatescheme $matches[1] $POWER_GUID
        powercfg /changename $POWER_GUID "Nuclear_Performance_v12" "Maximum performance - no throttling"
    } else {
        # Create from High Performance
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c $POWER_GUID
        powercfg /changename $POWER_GUID "Nuclear_Performance_v12" "Maximum performance - no throttling"
    }
}
Write-Host "  OK: Power plan ready" -ForegroundColor Green

# 2. Set power plan NOW
Write-Host "[2/5] Activating power plan..." -ForegroundColor Yellow
powercfg /setactive $POWER_GUID
Write-Host "  OK: Nuclear_Performance_v12 active" -ForegroundColor Green

# 3. Create startup scheduled task
Write-Host "[3/5] Creating startup task..." -ForegroundColor Yellow
$taskName = "NuclearPowerStartup"
schtasks /delete /tn $taskName /f 2>$null

$action = New-ScheduledTaskAction -Execute "powercfg.exe" -Argument "/setactive $POWER_GUID"
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger1,$trigger2 -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "  OK: Startup task created" -ForegroundColor Green

# 4. Create periodic task (every 5 min)
Write-Host "[4/5] Creating periodic enforcement task..." -ForegroundColor Yellow
$taskName2 = "NuclearPowerPeriodic"
schtasks /delete /tn $taskName2 /f 2>$null

$trigger3 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $taskName2 -Action $action -Trigger $trigger3 -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "  OK: Periodic task created (every 5 min)" -ForegroundColor Green

# 5. Registry backup
Write-Host "[5/5] Setting registry run key..." -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name "NuclearPower" -Value "powercfg /setactive $POWER_GUID" -Type String -Force
Write-Host "  OK: Registry key set" -ForegroundColor Green

# Verify
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Write-Host ""

$currentPlan = powercfg /getactivescheme
Write-Host "Current plan: $currentPlan" -ForegroundColor White

$task1 = Get-ScheduledTask -TaskName "NuclearPowerStartup" -ErrorAction SilentlyContinue
$task2 = Get-ScheduledTask -TaskName "NuclearPowerPeriodic" -ErrorAction SilentlyContinue
$regKey = Get-ItemProperty -Path $regPath -Name "NuclearPower" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Startup Task:  $(if($task1){'INSTALLED'}else{'FAILED'})" -ForegroundColor $(if($task1){'Green'}else{'Red'})
Write-Host "Periodic Task: $(if($task2){'INSTALLED'}else{'FAILED'})" -ForegroundColor $(if($task2){'Green'}else{'Red'})
Write-Host "Registry Key:  $(if($regKey){'INSTALLED'}else{'FAILED'})" -ForegroundColor $(if($regKey){'Green'}else{'Red'})

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Write-Host "Nuclear_Performance_v12 will now ALWAYS run on startup!" -ForegroundColor Green
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
