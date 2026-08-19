# Save this as SetPowerPlan.ps1 and run as Administrator

# Delete existing registry entry if it exists
try {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "NuclearPower" -ErrorAction SilentlyContinue
} catch {}

# Add new registry entry
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "NuclearPower" -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"powercfg /setactive e7b3c3f6-7f35-4f4c-8b48-8f1ece9cd139`"" -PropertyType String -Force

# Also set it immediately now
powercfg /setactive e7b3c3f6-7f35-4f4c-8b48-8f1ece9cd139

Write-Host "Power plan startup entry created successfully!" -ForegroundColor Green
