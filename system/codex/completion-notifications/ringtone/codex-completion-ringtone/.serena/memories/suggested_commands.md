# Windows Commands

- Build APK without touching device state: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-apk.ps1`.
- Run Python runtime tests: `py -3 tests\runtime_tests.py`.
- Run static contracts: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\static_contract_tests.ps1`.
- Run gateway integration: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\gateway_integration_tests.ps1`.
- Run the full suite: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`.
- Verify required/forbidden markers with the `rg` commands documented in `AGENTS.md` and `docs/FUTURE-SESSION-SAFETY.md`.
- Parse PowerShell scripts with `[System.Management.Automation.Language.Parser]::ParseFile(...)` before claiming installer safety.
- Install only on explicit request: `installers\Install-Android.ps1`, `installers\Install-ExactSetup.ps1`; these must not launch the app automatically.
- Use `git status --short --branch` and `git diff --stat` from `repo\`; the outer session directory is not the git root.