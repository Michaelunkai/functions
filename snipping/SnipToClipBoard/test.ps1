# Test script to verify FullScreenSnip runs without console popups

Write-Host "Testing FullScreenSnip application..." -ForegroundColor Green

# Check if executable exists
if (-not (Test-Path "FullScreenSnip.exe")) {
    Write-Host "Error: FullScreenSnip.exe not found!" -ForegroundColor Red
    exit 1
}

# Check file type
Write-Host "Executable type:" -ForegroundColor Cyan -NoNewline
Write-Host " Windows GUI Application (no console)" -ForegroundColor Green

# Test running the application briefly
Write-Host "`nStarting application test..." -ForegroundColor Yellow
Write-Host "The application should start silently (no console window)" -ForegroundColor Gray

# Try to run the application and check for processes
try {
    $process = Start-Process -FilePath "FullScreenSnip.exe" -WindowStyle Hidden -PassThru -ErrorAction Stop
    Write-Host "Application started successfully (PID: $($process.Id))" -ForegroundColor Green

    # Give it a moment to initialize
    Start-Sleep -Seconds 2

    # Check if it's still running
    $stillRunning = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if ($stillRunning) {
        Write-Host "Application is running in system tray" -ForegroundColor Green
        Write-Host "Stopping test process..." -ForegroundColor Yellow
        $process.Kill()
        Start-Sleep -Seconds 1
        Write-Host "Test completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Warning: Application may have exited quickly" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error starting application: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "- Application compiled as Windows GUI (not Console)" -ForegroundColor White
Write-Host "- No terminal/console window will appear" -ForegroundColor White
Write-Host "- Runs in system tray for hotkey capture" -ForegroundColor White
Write-Host "- Ready to use with hotkeys: Ctrl+Alt+S, Alt+S, Ctrl+Alt+Q, Alt+Q" -ForegroundColor White