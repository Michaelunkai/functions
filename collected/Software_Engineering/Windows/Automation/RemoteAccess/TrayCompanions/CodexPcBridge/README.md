# Codex PC Bridge

Codex PC Bridge v2 separates machine authority from interactive desktop access
while shipping one executable:

- `CodexPcBridge.exe --service` is the Automatic-start LocalSystem service.
- `CodexPcBridge.exe` starts at sign-in as the tray gateway and interactive
  agent, connecting through an ACL-protected authenticated named pipe.
- The tray process supervises the on-demand `\CodexControlPlaneAgent`
  scheduled task at startup and every 30 seconds. The worker has no separate
  logon trigger, so the bridge remains the single startup owner.
- Protocol v2 uses enrolled P-256 identities, authenticated ECDH,
  HKDF-SHA256, AES-256-GCM, expiry, sequence, replay, and idempotency checks.
- The existing HMAC `POST /` contract remains available during migration.

A first MSI install starts in shadow mode on loopback/Tailscale port `18776`.
It does not claim the existing live bridge port `18767`. After relay, tray IPC,
and Android checks pass, an administrator can run
`Activate-CodexPcBridgeV2.ps1`; it records rollback metadata and restores the
shadow service plus legacy executable if the handoff fails.

After a relay preview is deployed, run
`Configure-CodexPcBridgeRelay.ps1 -RelayUrl https://...` from elevated
PowerShell 5.1. The service restarts on its current shadow port, embeds the
relay address in new enrollment challenges, and begins reconnect monitoring.
Live-port activation requires relay readiness and an Android health command
unless the operator explicitly supplies the corresponding skip switches.

The service dynamically exposes mounted filesystem volumes, guarded mutations,
resumable SHA-256-verified transfers, and durable process jobs. SYSTEM handles
machine resources; the tray agent handles current-user environment, mapped
drives, and GUI operations. Locked, offline, encrypted, or externally denied
resources return structured failures.

The service listens only on loopback and an authenticated Tailscale address.
The optional relay transports ciphertext only. No unauthenticated public
listener or firewall-wide bind is created.

## Current Installed F-Drive State

The authoritative installed executable is:

```text
F:\study\Software_Engineering\Windows\Automation\RemoteAccess\TrayCompanions\CodexPcBridge\release\windows\CodexPcBridge.exe
```

The self-contained single-file executable extracts five WPF native libraries
at runtime. On this machine, their physical cache lives at:

```text
F:\study\Software_Engineering\Windows\Automation\RemoteAccess\TrayCompanions\CodexPcBridge\runtime\state\BundleExtract\CodexPcBridge
```

`C:\Temp\.net\CodexPcBridge` is an NTFS junction to that F-drive directory.
Do not replace it with a physical C-drive cache. The current active bundle ID
is `SoxOQnwH-PQq`, with five files totaling `8,215,008` bytes. Ten obsolete
build-ID caches were removed after the service, tray, gateway, control agent,
and interactive bridge recovered from the F-backed cache.

Both machine Start Menu shortcuts target the authoritative F executable and
use its F directory as their working directory. Their pre-change shortcut
files are preserved under
`runtime\state\shortcut-backups\pre-f-target-20260730-0835`.

Build x64 and ARM64 release candidates:

```powershell
$env:CODEX_DOTNET = "F:\Downloads\.codex\tools\dotnet-sdk-10.0.301\dotnet.exe"
.\build.ps1 -RuntimeIdentifier all
```

Public release requires `-RequireSigning -CertificateThumbprint <thumbprint>`.
Unsigned development MSIs, checksums, SBOMs, and update manifests are written
under `release\windows\`.
