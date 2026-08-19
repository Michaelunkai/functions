# FullScreenSnip - Fixed Version

This is the fixed version of FullScreenSnip that runs without console window popups.

## Problem
The original `FullScreenSnip.exe` was compiled as a **Console Application**, causing a terminal/console window to flash briefly every time the application started.

## Solution
The application has been recompiled as a **Windows Application** using:
- `/target:winexe` compiler flag
- Proper Windows Forms references

## Changes Made

### 1. Fixed Compilation
- Updated compilation to use `/target:winexe` instead of default console target
- Added proper DLL references: `System.Windows.Forms.dll`, `System.Drawing.dll`, `System.dll`

### 2. Added Build Scripts
- `compile.ps1` - PowerShell compilation script
- `compile.bat` - Batch file compilation script  
- `build.ps1` - MSBuild compilation script (for advanced builds)

### 3. Verification
- File type changed from `(console)` to `(GUI)` confirmed by `file` command
- Tested to run silently in system tray
- All hotkey functionality preserved

## How to Recompile

### Method 1: PowerShell (Recommended)
```powershell
.\compile.ps1
```

### Method 2: Batch File
```cmd
compile.bat
```

### Method 3: Manual CSC Command
```cmd
csc /target:winexe /out:FullScreenSnip.exe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.dll /platform:anycpu /optimize+ FullScreenSnip.cs
```

## Hotkeys
- **Ctrl+Alt+S** - Full screen PNG (saves to file)
- **Alt+S** - Free snip PNG (saves to file)  
- **Ctrl+Alt+Q** - Full screen image (clipboard)
- **Alt+Q** - Free snip image (clipboard)

## Features
- Runs silently in system tray
- No console/terminal window popups
- Configurable screenshot folder
- Run at startup option
- Balloon notifications for feedback

## Requirements
- .NET Framework 4.0 or later
- Windows 7/8/10/11

## File Verification
To verify the application type:
```bash
file FullScreenSnip.exe
```
Should show: `(GUI)` not `(console)`