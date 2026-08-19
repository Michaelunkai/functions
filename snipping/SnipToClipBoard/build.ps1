# Build script for FullScreenSnip
# This compiles as a Windows Application to avoid console window popups

$ErrorActionPreference = "Stop"

# Check for .NET Framework build tools
$msbuildPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $msbuildPath)) {
    $msbuildPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
}
if (-not (Test-Path $msbuildPath)) {
    $msbuildPath = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
}
if (-not (Test-Path $msbuildPath)) {
    Write-Host "MSBuild not found. Attempting to use dotnet build..." -ForegroundColor Yellow
    dotnet build -c Release
    exit $LASTEXITCODE
}

Write-Host "Building FullScreenSnip as Windows Application..." -ForegroundColor Green
& $msbuildPath "FullScreenSnip.csproj" /p:Configuration=Release /p:Platform="Any CPU" /p:OutputPath=".\bin\Release" /verbosity:m

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!" -ForegroundColor Green
    Write-Host "Output: bin\Release\FullScreenSnip.exe" -ForegroundColor Cyan
} else {
    Write-Host "Build failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}