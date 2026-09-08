# Uni validation record

Date: 2026-09-08

All bespoke Uni checks were run in isolated Windows PowerShell 5.1 child
processes so a test that calls `exit` cannot terminate the aggregate runner.

## Regression suite

- `Test-UniNoTarget.ps1`: exit 0, `UNI_NO_TARGET_TESTS_PASSED=37`
- `Test-UniRegistryParser.ps1`: exit 0, `UNI_REGISTRY_PARSER_TESTS_PASSED=27`
- `Test-UniFailures.ps1`: exit 0, `UNI_FAILURE_TESTS_PASSED=12`
- `Test-UniStartup.ps1`: exit 0
- `Test-Uni.ps1`: exit 0, `UNI_TESTS_PASSED=47`
- `Test-UniExactList.ps1`: exit 0, `UNI_EXACT_LIST_TESTS_PASSED=14`
- `Test-UniEarlyStop.ps1`: exit 0, `UNI_EARLY_STOP_TESTS_PASSED=10`
- `Test-UniTelegram.ps1`: exit 0, `UNI_TELEGRAM_TESTS_PASSED=32`

Aggregate result: `UNI_FINAL_REGRESSION_FAILURES=0`.

## Concurrency

An eight-worker exact-list run held `Global\\UniOwnedCleanupV8` before launch,
then released it after all workers were waiting:

- workers: 8
- exit codes: `0,0,0,0,0,0,0,0`
- wait messages: 8
- fail-fast messages: 0
- exact fixture remaining: `False`

## Profile/GMenu recreation proof

The live watcher removed the exact `.gmenu` tree, ran `uni gmenu` from a
no-profile child, and polled through completion. After the lazy GMenu/profile
fix, the result was `WATCH_EXIT=2;FINAL_EXISTS=False`. A normal
profile-enabled PowerShell smoke test also returned `PROFILE_GMENU_EXISTS=False`.
The exact normal profile wrapper route returned `WRAPPER_EXIT=2;FINAL_EXISTS=False`.

## Live user route

The requested multi-name route (`driverbooster`, `driver booster`, `ccleaner`,
`iobit`, `ccleanercrashreporting`, `kvrt`, `chris`) reached phase 13 without
the previous concurrency abort. Its exit was 2 because this machine still
reported 18 filesystem and 19 registry access/shared-value conditions; that is
an incomplete/unverified result, not a zero-leftover certification.

The pasted 169-path audit now finds 17 existing paths, all classified as
Windows Photos debug files or Codex worktree/source text. It finds no remaining
GMenu state path; source/catalog paths were preserved because their ownership is
not proven by an app-name substring.
