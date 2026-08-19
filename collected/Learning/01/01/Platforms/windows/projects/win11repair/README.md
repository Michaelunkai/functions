# Windows 11 Ultimate Repair v2.0

**Complete Windows repair in 8 fast phases** - fixes everything the original couldn't.

## Quick Start

```batch
RUN_REPAIR_v2.bat
```

Or PowerShell (admin):
```powershell
.\Win11RepairInstall_v2.ps1
```

## What It Does

| Phase | Action | Time |
|-------|--------|------|
| 1 | System Analysis | 2s |
| 2 | Stop Services | 1s |
| 3 | DISM RestoreHealth | 5-15min |
| 4 | SFC /scannow (background) | parallel |
| 5 | Windows Update Reset | 10s |
| 6 | Registry Cleanup | 1s |
| 7 | Restart Services | 1s |
| 8 | In-Place Upgrade | launches setup |

**Total pre-repair: ~15-20 minutes** (vs original: instant but incomplete)

## Why v2?

The original `Win11RepairInstall.ps1` only did ONE thing:
- Launch setup.exe with upgrade flags

That's like going to the doctor and only getting a bandage - it ignores the underlying issues.

**v2 does EVERYTHING:**
- ✅ Repairs Windows component store (DISM)
- ✅ Fixes corrupted system files (SFC)
- ✅ Resets Windows Update completely
- ✅ Cleans problematic registry keys
- ✅ Re-registers update DLLs
- ✅ Resets network stack
- ✅ THEN does the in-place upgrade

## Options

```powershell
# Test without making changes
.\Win11RepairInstall_v2.ps1 -DryRun

# Skip DISM/SFC (faster, less thorough)
.\Win11RepairInstall_v2.ps1 -SkipPreRepair

# Just repairs, no reinstall
.\Win11RepairInstall_v2.ps1 -SkipUpgrade

# Combine flags
.\Win11RepairInstall_v2.ps1 -DryRun -SkipPreRepair
```

## Requirements

- Windows 11 ISO at `E:\isos\Windows.iso`
- Administrator privileges
- PowerShell 5.1+ (comes with Windows)
- ~20GB free space on C:

## Files

| File | Purpose |
|------|---------|
| `Win11RepairInstall_v2.ps1` | Main repair script |
| `RUN_REPAIR_v2.bat` | Easy launcher |
| `repair_log_v2.txt` | Detailed log |
| `repair_report.txt` | Summary report |

## Speed Optimizations

v2 is optimized for speed:
1. **Skips redundant scans** - RestoreHealth does internal scan anyway
2. **SFC runs in background** - parallel with other repairs
3. **Only essential DLLs** - 6 vs 36 (saves 2-3 min)
4. **No unnecessary waits**
5. **Streamlined logging**

## Post-Repair

After the upgrade completes:
1. Check `C:\Windows\Temp\repair_verify.txt` for SFC verification
2. Run Windows Update to get latest patches
3. Restart once more for good measure

## Troubleshooting

**ISO not found?**
Edit `$isoPath` in the script to point to your Windows ISO.

**DISM fails?**
The script automatically tries the ISO as a repair source if Windows Update fails.

**Not enough space?**
Need at least 15GB free. Clean up with `cleanmgr` first.

---

*Created 2026-02-05 - PowerShell 5.1 compatible*
