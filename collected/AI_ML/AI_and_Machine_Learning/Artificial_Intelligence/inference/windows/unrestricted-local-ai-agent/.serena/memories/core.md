# Core Project Map

- Source root: `repo/`; Android launcher source in `src/com/michaelovsky/codexapplauncher/`; embedded Termux runtime in `runtime/codex_runtime.py`.
- Canonical project identity and preservation rules: `AGENTS.md`, `docs/PROJECT-HANDOFF.md`, `docs/FUTURE-SESSION-SAFETY.md`.
- Existing compatibility contract: NVIDIA model `nvidia/nemotron-3-nano-30b-a3b`; Codex Web local port `5900`; WebAPK URL must retain `openProjectPath=/data/data/com.termux/files/home`; Termux package `com.termux`; Shizuku package `moe.shizuku.privileged.api`; Windows gateway `tools/CodexAutonomyGateway.ps1` on port `18765`.
- Do not launch, stop, force-stop, or probe installed Android apps during repository-only work. Runtime testing requires explicit user request.
- Preserve required `CODEXAPP_*` markers and forbidden-branch list in the handoff docs.
- Android broker is loopback-only on `127.0.0.1:18767`, authenticated by a separate Keystore token with durable idempotency receipts.
- Media actions are verified from media-session state plus an independent notification-listener or accessibility observation and a stability window.
- YouTube Music cold-start playback has an explicit `MEDIA_PLAY_FROM_SEARCH` fallback; `codex-media open` is routed as app launch.
- Durable action jobs are persisted before side effects and can emit verified state only through the evidence gate.
- Related details: `mem:tech_stack`, `mem:suggested_commands`, `mem:conventions`, `mem:task_completion`.