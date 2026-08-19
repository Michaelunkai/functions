
## 2026-04-09: AHK startup configuration

### Setup:
- **Method**: Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` key `MyMainAHK`
- **Value**: `"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "F:\study\Platforms\windows\autohotkey\mymainahk\current.ahk"`
- **No delay**: Registry Run fires immediately at logon
- **No duplicates**: `#SingleInstance Force` in script + only one startup entry
- **Tray icon**: Custom tray menu with Reload/Exit, tooltip "MyMainAHK"
- **Old disabled Task Scheduler entry `AHK_current`**: removed

### Lesson:
- Registry Run is simpler and more reliable than Task Scheduler for user-level startup
- Task Scheduler `Register-ScheduledTask` with `-RunLevel Limited` can fail with "parameter incorrect" on some Windows configs
- `#SingleInstance Force` + single startup entry = zero duplicate risk

## 2026-04-09: ppppp Paragon automation broken - venv Python PATH issue

### Root Cause:
- `ppppp` hotstring runs `paragon_complete.py` which needs `pyautogui` and `win32gui`
- The AHK script called bare `python` which resolved to `F:\backup\LocalAI\ollama\venv\Scripts\python.exe` (first in PATH)
- That venv has NO `pyautogui` or `win32gui` installed — only system Python (3.12) has them

### Fix:
1. Changed AHK to use explicit `C:\Users\micha\AppData\Local\Programs\Python\Python312\python.exe` instead of bare `python`
2. Added `ParagonPythonExe` global variable for the full path
3. Removed `"Hide"` flag from RunWait (pyautogui needs visible window context)

### LocalAI reorganization:
- Created `F:\study\AI_ML\LocalAI\` with README, launcher scripts, data pointers
- Updated `llocalai` AHK shortcut from `F:\backup\LocalAI` to `F:\study\AI_ML\LocalAI`
- Actual data (13GB models) stays at `F:\backup\LocalAI\ollama\`

### Lesson:
- Never use bare `python` in automation scripts — venvs in PATH can hijack the call
- Always use full path to the Python interpreter that has the required packages

## 2026-04-08: oll1-90 Full Rehaul

### Changes Made:
1. **All 90 oll functions now use `qwen3.5:latest`** - replaced qwen3:8b (oll21-30), qwen3:30b-a3b (oll69-82), qwen3-coder:latest (oll83-90)
2. **Added `--dangerously-skip-permissions`** to all 90 functions for full tool/PS/agentic access
3. **Added ollama serve dedup** - checks `Get-Process ollama` before starting, avoids duplicate serve processes
4. **Created `oll-scan` function** - run it to see a table of all 90 levels (context, GPU layers, overhead, parallel, KV cache, model)
5. **Fixed settings.json trailing comma** in UserPromptSubmit hooks array (invalid JSON causing hook errors)

### Root Causes Fixed:
- `deepseek-r1:32b does not support tools` → all models now qwen3.5:latest (tool-supporting)
- UserPromptSubmit hook error → trailing comma in JSON array removed
- Multiple ollama serve processes → dedup check added

## 2026-05-05: PowerShell nested command dollar escaping

### Root Cause:
- Calling `powershell.exe -Command "Get-StartApps | Where-Object { $_.Name ... }"` from an outer PowerShell session expanded `$_` too early, turning it into `.Name` and causing repeated `.Name is not recognized` errors.

### Fix:
- Use single quotes around the nested `-Command` payload, or escape `$` before passing scriptblocks that contain `$_` through an outer PowerShell command string.

## 2026-05-05: Codex Desktop AppsFolder launch dialog

### Root Cause:
- `cmd /c start shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App` can surface a Windows "cannot find shell:AppsFolder..." dialog for Codex Desktop instead of activating the app.
- `explorer.exe shell:AppsFolder\...` avoids the dialog but may focus File Explorer instead of Codex when Codex is already running.

### Fix:
- Use the registered Codex Desktop protocol (`codex://`) and then explicitly activate the `Codex ahk_exe Codex.exe` window from AHK.

## 2026-07-30: AHK monitor topology and stdin test harnesses

### Root Cause:
- `MonitorGetCount()` included the persistent MTT virtual display, so selecting the first non-primary monitor could target Moonlight instead of the connected physical secondary.
- Minimized windows can report a tiny taskbar-button rectangle, so the old size filter excluded them from bulk monitor moves.
- An incomplete stdin harness referenced a function it had not loaded, and AutoHotkey `#Warn` opened an interactive warning dialog.

### Fix:
- Classify active displays through `EnumDisplayDevicesW` and build the physical pair from device identity rather than AHK index.
- Keep minimized titled app windows during enumeration and use `MonitorFromWindow` for their monitor association.
- Run complete stdin harnesses with `/ErrorStdOut=UTF-8`; if a harness is interrupted, stop only the test `AutoHotkey64.exe` process whose command line does not reference `current.ahk`.
- For strict warning checks, route `#Warn All` to `StdOut`, initialize retained GUI handles at hotstring entry, and bind GUI methods directly instead of referencing outer locals from callback lambdas.
