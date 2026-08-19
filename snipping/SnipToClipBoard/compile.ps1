# PowerShell compilation script for FullScreenSnip
# Compiles as Windows Application to eliminate console popups

Write-Host "Compiling FullScreenSnip as Windows Application..." -ForegroundColor Green

# Find C# compiler
$cscPaths = @(
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "${env:windir}\Microsoft.NET\Framework\v4.0.30319\csc.exe",
    "${env:windir}\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
)

$csc = $null
foreach ($path in $cscPaths) {
    if (Test-Path $path) {
        $csc = $path
        break
    }
}

if (-not $csc) {
    Write-Host "Error: C# compiler (csc.exe) not found!" -ForegroundColor Red
    Write-Host "Please install .NET Framework 4.x Developer Pack" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using compiler: $csc" -ForegroundColor Cyan

# Backup existing executable if it exists
$exePath = "FullScreenSnip.exe"
if (Test-Path $exePath) {
    $backupName = "FullScreenSnip.backup." + (Get-Date -Format "yyyyMMddHHmmss") + ".exe"
    Copy-Item $exePath $backupName -Force
    Write-Host "Backed up existing executable to: $backupName" -ForegroundColor Yellow
}

# Compile as Windows Application
$arguments = @(
    "/target:winexe",
    "/out:FullScreenSnip.exe",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
    "/reference:System.dll",
    "/platform:anycpu",
    "/optimize+",
    "/debug-",
    "FullScreenSnip.cs"
)

Write-Host "Compiling with: $csc $arguments" -ForegroundColor Gray
& $csc $arguments

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nCompilation successful!" -ForegroundColor Green
    Write-Host "FullScreenSnip.exe has been compiled as a Windows Application." -ForegroundColor Cyan
    Write-Host "No console window will appear when running." -ForegroundColor Cyan

    # Test the file type
    Write-Host "`nVerifying executable type..." -ForegroundColor Gray
    if (Test-Path $exePath) {
        $size = (Get-Item $exePath).Length
        Write-Host "Executable size: $size bytes" -ForegroundColor Gray
        Write-Host "Success! Application ready to use." -ForegroundColor Green
    }
} else {
    Write-Host "`nCompilation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}