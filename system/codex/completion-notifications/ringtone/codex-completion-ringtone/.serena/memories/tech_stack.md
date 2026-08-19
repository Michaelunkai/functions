# Tech Stack

- Android: plain Java source, Android API 34 compile target, min SDK 23, manual PowerShell build pipeline.
- Build tools: local JDK/Android SDK under `F:\study\Dev_Toolchain\Android\michNvidiaApp-build-tools`; `build-apk.ps1` invokes `aapt2`, `javac`, `jar`, `d8`, `zipalign`, and `apksigner`. `C:\Users\micha\android-build-tools` is a zero-payload compatibility junction to that F-drive toolchain.
- Runtime: Python 3 script embedded into the APK as base64 and staged into Termux `$HOME/.codex/current`; command-name symlinks expose the `codex-*` surface.
- Windows companion: Windows PowerShell 5-compatible gateway with HMAC timestamp/nonce authentication and action allowlist.
- Android runtime services: foreground MissionGuardService, BootReceiver, RuntimeScheduleJobService, AutomationBrokerService, VaultBrokerService, TermuxUiAutomationService, CodexNotificationListenerService, and AndroidMediaController.
- Runtime version must match between `runtime/codex_runtime.py` and `CapabilityRuntime.VERSION`; current version is `1.3.0`.
- No Gradle project is used for the APK; `settings.gradle` is metadata only.
