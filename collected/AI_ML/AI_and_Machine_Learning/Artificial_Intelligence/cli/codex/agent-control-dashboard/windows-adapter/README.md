# Windows Adapter

The Node 24 adapter listens only on `127.0.0.1:17867`, durably stores Codex
hook events with the built-in SQLite module in
`%LOCALAPPDATA%\AgentControl\adapter.db`, and forwards them when the control
plane is reachable.

Configuration uses the API URL environment variable plus a DPAPI-protected
owner credential:

- `AgentControl__ApiUrl`
- `%LOCALAPPDATA%\AgentControl\owner-token.dpapi` stores the owner token with
  Windows CurrentUser DPAPI and exposes it only to the adapter process.

The hook wrapper always exits successfully so dashboard availability cannot
block a Codex session.
