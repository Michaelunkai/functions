# cleanc

Allowlist-driven root cleanup runner for direct children of `C:\` by default.

## Files

- Script: `Invoke-cleanc.ps1`
- Allowlist: `cleanc-allowlist.txt`
- Thin launcher source: `C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

## Behavior

- `cleanc` defaults to destructive execution.
- `cleanc -Run` performs the same destructive pass explicitly.
- `cleanc -Preview` is the non-destructive listing mode.
- The script only targets direct children of the selected root path.
- The allowlist accepts one exact root-item name or one exact rooted path per line.
- Blank lines and lines starting with `#` or `;` are ignored.

## Commands

```powershell
cleanc -SelfTest
cleanc
cleanc -Preview
cleanc -Run
cleanc -Preview -AllowlistPath 'F:\somewhere\cleanc-allowlist.txt'
cleanc -RootPath "$env:TEMP\cleanc-demo" -AllowlistPath "$env:TEMP\cleanc-demo-allowlist.txt"
```

## Notes

- The bundled allowlist starts conservative on purpose, so review it carefully before running against `C:\`.
- Destructive execution on `C:\` refuses to continue if critical Windows root items are not allowlisted.
- Real-time progress is streamed as high-frequency progress updates and `[PROGRESS]` lines while deletions are running.
