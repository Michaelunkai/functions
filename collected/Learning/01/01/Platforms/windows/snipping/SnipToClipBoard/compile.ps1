# Compile FullScreenSnip.cs
$csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
$source = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.cs"
$output = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe"

# Remove old exe
if (Test-Path $output) { Remove-Item $output -Force }

# Compile
& $csc /target:winexe /out:$output /r:System.Windows.Forms.dll /r:System.Drawing.dll $source

if (Test-Path $output) {
    Write-Host "COMPILED: $((Get-Item $output).Length) bytes"
} else {
    Write-Host "COMPILE FAILED"
    exit 1
}
