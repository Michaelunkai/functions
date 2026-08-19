# Codebase Conventions

- Keep changes additive and compatible with the handoff docs; do not resurrect forbidden WebView, default-workspace, recursive-command, or pre-health WebAPK branches.
- Use structured JSON results with `ok`, status/error fields, evidence buckets, and timestamps. Natural-language claims, exit codes, installer visibility, and screenshots alone are not completion evidence.
- Persist side effects atomically; use job-scoped idempotency keys and retain receipts/evidence. Manual stop is authoritative and must suppress automatic resume.
- Broker actions are primary actions. Verification must read back real Android state through a distinct observation path and a stability recheck.
- Keep package provenance explicit: official package versus user-installed alias. Never bypass licensing, payment, DRM, account security, or package signer integrity.
- `codex-media open` must use `app.open`; media controls use `media.control`; search playback uses `media.search_play`.
- YouTube Music selectors and package aliases belong in the versioned adapter in `runtime/codex_runtime.py`; do not hard-code screen coordinates as the primary route.
- Preserve the existing Termux command generation and marker strings when extending `TermuxCommand.java`.