# CDriveDeleteAudit

Read-only C: drive delete-candidate audit for Windows PowerShell 5. The script uses the Everything command-line client (`bin\es.exe`) to rank conservative cleanup candidates, write CSV/JSON/text reports, and generate a separate force-delete one-liner for the exact files listed.

Normal execution does not delete files. Deletion only happens when `-ForceDeleteListed` is explicitly supplied with a manifest.

## Files

- `Invoke-CDriveDeleteAudit.ps1` - main audit script.
- `bin\es.exe` - Everything CLI client used by the script.
- `bin\es.zip` - original bundled Everything CLI zip from the source directory.
- `tests\Invoke-SmokeTest.ps1` - PowerShell 5 parse check and safe read-only audit smoke test.

## Usage

Run a read-only audit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-CDriveDeleteAudit.ps1 -Top 10 -OutputRoot C:\Temp\CDriveDeleteAudit -NoColor
```

Run the smoke test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SmokeTest.ps1
```

Open the report folder after a read-only audit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-CDriveDeleteAudit.ps1 -Top 100 -OpenReportFolder
```

Delete only from a previously generated manifest:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-CDriveDeleteAudit.ps1 -ForceDeleteListed -DeleteManifest C:\Temp\CDriveDeleteAudit\<run>\top-delete-candidates.csv
```

## Safety Model

The default mode is audit-only. It excludes protected operating system paths, Program Files, most ProgramData app state, personal folders, browser identity/profile data, Python/Docker/container paths, Hermes/Codex state, and ambiguous app state.

The generated one-liner is written as a separate artifact so the operator can inspect the CSV first. Do not run `-ForceDeleteListed` without reviewing the manifest.

## Source

Packaged from:

```text
C:\ProgramData\Hermes\CDriveDeleteAudit\Invoke-CDriveDeleteAudit.ps1
```

