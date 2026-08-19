# GoPhish Local Ready Automation

PowerShell 5 compatible automation for a localhost-only GoPhish setup.

## Scripts

- `setup-gophish.ps1` downloads GoPhish `v0.12.1`, verifies the release SHA256, configures localhost-only admin and phishing listeners, starts GoPhish, opens a dedicated Chrome profile, logs in automatically, completes the forced first-login password reset, and leaves the dashboard open.
- `cleanup-gophish.ps1` stops only the workspace-owned GoPhish and browser-profile processes, then removes the runtime tree created by the setup script.

## Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-gophish.ps1
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\cleanup-gophish.ps1
```

The setup script stores generated local credentials under `.gophish-runtime\state\admin-credentials.txt`.
The default admin UI is localhost-only and normally opens at `https://127.0.0.1:3333/`.

## Verification

This package was copied from the live Codex workspace after the source setup script had successfully:

- verified the GoPhish release SHA256,
- started GoPhish,
- opened Chrome with a dedicated local profile,
- completed the forced password reset,
- left the live browser tab on `Dashboard - Gophish`,
- verified admin and phishing TCP ports were reachable.

The copied scripts should be syntax-checked with Windows PowerShell 5 before handoff.
