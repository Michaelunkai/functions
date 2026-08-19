@echo off
echo Compiling FullScreenSnip as Windows Application (no console window)...

set CSC_PATH=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC_PATH%" (
    echo Error: C# compiler not found at %CSC_PATH%
    pause
    exit /b 1
)

"%CSC_PATH%" /target:winexe /out:FullScreenSnip.exe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.dll /platform:anycpu /optimize+ /debug- FullScreenSnip.cs

if errorlevel 1 (
    echo Compilation failed!
    pause
    exit /b 1
)

echo.
echo Compilation successful!
echo FullScreenSnip.exe has been compiled as a Windows Application.
echo.
echo Press any key to exit...
pause >nul