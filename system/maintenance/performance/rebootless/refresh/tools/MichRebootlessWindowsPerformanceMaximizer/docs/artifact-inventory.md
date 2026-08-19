# Artifact inventory

Copied from live production setup to avoid breaking the installed task/hotkey:

- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/UltimatePerformanceRefresh.exe -> app/MichRebootlessWindowsPerformanceMaximizer.exe
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/UltimatePerformanceRefreshProgress.cs -> src/UltimatePerformanceRefreshProgress.cs
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/UltimatePerformanceRefresh.ps1 -> scripts/UltimatePerformanceRefresh.ps1
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/Run-UltimatePerformanceRefresh.ps1 -> scripts/Run-UltimatePerformanceRefresh.ps1 when present
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/Run-UltimatePerformanceRefresh.cmd -> scripts/Run-UltimatePerformanceRefresh.cmd when present
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/compile_and_verify.ps1 -> scripts/compile_and_verify.ps1 when present
- /mnt/c/Users/micha/AppData/Local/HermesUltimateRefresh/*.log and verify-*.txt -> logs/ when present

Production files were copied, not moved, because moving them would break the installed Windows scheduled task and existing runnable production setup.
