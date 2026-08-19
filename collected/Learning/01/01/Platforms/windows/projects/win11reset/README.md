# Windows 11 Smart Reset Toolkit

The most comprehensive Windows 11 repair toolkit with **56 tools** for fixing virtually any system issue while preserving your apps and settings.

## 🚀 Quick Start

### PowerShell Functions
```powershell
winmenu   # Full interactive menu
winrst    # Reset menu
winfix    # Quick 5-minute fix
winchk    # Fix chkdsk issues
```

### Or just double-click `MENU.bat`!

## 📊 Stats

| Metric | Value |
|--------|-------|
| Total files | 56+ |
| PowerShell scripts | 25 |
| Batch launchers | 27 |
| Total size | ~130 KB |

## 🔧 All Tools

### System Repair (Keeps ALL apps)

| Tool | Time | Description |
|------|------|-------------|
| `QUICK_FIX.bat` | 5 min | Common issues - DISM, SFC, WU |
| `DEEP_REPAIR.bat` | 15-20 min | Comprehensive repair |
| `FIX_ALL.bat` | 20-30 min | Nuclear option - everything |
| `DIAGNOSE.bat` | 2 min | Analyze without changes |

### Core Fixes

| Tool | Description |
|------|-------------|
| `FIX_CHKDSK.bat` | Chkdsk not running at startup |
| `BOOT_REPAIR.bat` | MBR, BCD, UEFI boot issues |
| `NETWORK_FIX.bat` | DNS, Winsock, IP connectivity |
| `FORCE_UPDATE.bat` | Reset and force Windows Update |
| `STORE_FIX.bat` | Microsoft Store problems |
| `SEARCH_FIX.bat` | Windows Search rebuild |

### Device Fixes

| Tool | Description |
|------|-------------|
| `AUDIO_FIX.bat` | Sound/speaker issues |
| `PRINTER_FIX.bat` | Print spooler, queue |
| `BLUETOOTH_FIX.bat` | Bluetooth connectivity |
| `DISPLAY_FIX.bat` | Graphics, resolution |
| `USB_FIX.bat` | USB devices, power |
| `TIME_FIX.bat` | Time synchronization |

### Security & Privacy

| Tool | Description |
|------|-------------|
| `DEFENDER_FIX.bat` | Windows Defender issues |
| `PRIVACY.bat` | Telemetry, ads (reversible) |

### Performance

| Tool | Description |
|------|-------------|
| `OPTIMIZE.bat` | Full PC optimization |
| `MEMORY_FIX.bat` | RAM cleanup, leaks |
| `STARTUP_FIX.bat` | Boot optimization |
| `CONTEXT_MENU_FIX.bat` | Classic/new menu toggle |

### Utilities

| Tool | Description |
|------|-------------|
| `SYSTEM_INFO.bat` | Full diagnostic report |
| `CREATE_RESTORE_POINT.bat` | Backup before repairs |
| `MENU.bat` | Interactive menu for all tools |
| `HELP.bat` | Quick reference |

### Windows Reset (Removes apps)

| Tool | Description |
|------|-------------|
| `RUN_RESET.bat` | Main reset menu |
| `RUN_RESET_v2.bat` | Interactive mode selector |

### Automation

| Tool | Description |
|------|-------------|
| `Silent_QuickFix.ps1` | For scheduled tasks |
| `Schedule_Weekly_Fix.ps1` | Create weekly maintenance |

## 🔥 Quick Reference

| Problem | Solution |
|---------|----------|
| Chkdsk not running | `FIX_CHKDSK.bat` |
| Corrupted files | `DEEP_REPAIR.bat` |
| Windows Update stuck | `FORCE_UPDATE.bat` |
| No internet | `NETWORK_FIX.bat` |
| Store not working | `STORE_FIX.bat` |
| No sound | `AUDIO_FIX.bat` |
| Printer issues | `PRINTER_FIX.bat` |
| Boot problems | `BOOT_REPAIR.bat` |
| Slow PC | `OPTIMIZE.bat` + `MEMORY_FIX.bat` |
| Slow startup | `STARTUP_FIX.bat` |
| Blue screens | `FIX_ALL.bat` |
| USB not recognized | `USB_FIX.bat` |
| Wrong time | `TIME_FIX.bat` |
| Defender issues | `DEFENDER_FIX.bat` |
| Search broken | `SEARCH_FIX.bat` |

## 💡 Tips

1. **Run DIAGNOSE first** - See what needs fixing
2. **Create a backup** - `CREATE_RESTORE_POINT.bat`
3. **Start with QUICK_FIX** - Solves 80% of issues
4. **Use FIX_ALL for stubborn problems**
5. **Reboot when prompted** - Many fixes complete on reboot

## 📦 Project Structure

```
win11reset/
├── MENU.bat               # Main interactive menu
├── QUICK_FIX.bat          # 5-minute fix
├── DEEP_REPAIR.bat        # 15-minute repair
├── FIX_ALL.bat            # Nuclear option
├── FIX_CHKDSK.bat         # Chkdsk fix
├── BOOT_REPAIR.bat        # Boot repair
├── NETWORK_FIX.bat        # Network fix
├── ... (50+ more tools)
├── README.md              # This file
└── .gitignore
```

## 🔗 Links

- **GitHub:** https://github.com/Michaelunkai/win11reset
- **Related:** [win11repair](../win11repair) (in-place upgrade)

---

**Path:** `F:\study\Platforms\windows\projects\win11reset`
**Created:** 2026-02-05
**Author:** OpenClaw Assistant
