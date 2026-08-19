# Completion Checks

1. Run `py -3 -m py_compile runtime\codex_runtime.py`.
2. Run `py -3 tests\runtime_tests.py`.
3. Run `tests\static_contract_tests.ps1`.
4. Run `tests\gateway_integration_tests.ps1`.
5. Run `build-apk.ps1` and confirm APK signing verification succeeds.
6. Re-run required-marker and forbidden-branch searches from the handoff docs.
7. Verify `runtime/codex_runtime.py` version equals `CapabilityRuntime.VERSION`.
8. Inspect `git diff --stat` and `git status --short --branch`; do not revert unrelated existing changes.
9. Update tracked release APK/hash only after a successful build and only if the task changes packaged behavior.
10. Do not perform live Android launch/install/probe unless the user explicitly requests runtime testing in that turn.
11. Before final response, report only checks actually run and distinguish repository verification from unperformed device verification.