# Uni validation record

Date: 2026-09-08

All bespoke Uni checks were run in isolated Windows PowerShell 5.1 child
processes so a test that calls `exit` cannot terminate the aggregate runner.

## Regression suite

- `Test-UniNoTarget.ps1`: exit 0, `UNI_NO_TARGET_TESTS_PASSED=38`
- `Test-UniRegistryParser.ps1`: exit 0, `UNI_REGISTRY_PARSER_TESTS_PASSED=27`
- `Test-UniFailures.ps1`: exit 0, `UNI_FAILURE_TESTS_PASSED=12`
- `Test-UniStartup.ps1`: exit 0
- `Test-Uni.ps1`: exit 0, `UNI_TESTS_PASSED=47`
- `Test-UniExactList.ps1`: exit 0, `UNI_EXACT_LIST_TESTS_PASSED=14`
- `Test-UniEarlyStop.ps1`: exit 0, `UNI_EARLY_STOP_TESTS_PASSED=10`
- `Test-UniTelegram.ps1`: exit 0, `UNI_TELEGRAM_TESTS_PASSED=32`

Aggregate result: `UNI_FINAL_REGRESSION_FAILURES=0`.

The aggregate was rerun after the bounded reconciliation change. The first
aggregate attempt had one transient startup-child capture failure; the
isolated rerun and the complete rerun both returned exit 0.

The current source extends final reconciliation to five bounded rounds, waits
for three consecutive quiet rounds, and rechecks authorized registry roots as
well as authorized filesystem/GMenu paths. PowerShell 5.1 and PowerShell 7
parsers both report zero syntax errors after this change.

## Concurrency

An eight-worker exact-list run held `Global\\UniOwnedCleanupV8` before launch,
then released it after all workers were waiting:

- workers: 8
- exit codes: `0,0,0,0,0,0,0,0`
- wait messages: 7 (the first worker acquired the queue immediately)
- fail-fast messages: 0
- exact owned path remaining: `False`
- harness result: exit 0

A fresh queue run against the updated source reproduced the same result:
eight workers, all exit 0, seven wait messages, zero fail-fast messages, zero
owned-path residue, and no worker stderr output.

## Profile/GMenu recreation proof

The live watcher removed the exact `.gmenu` tree, ran `uni gmenu` from a
no-profile child, and polled through completion. After the lazy GMenu/profile
fix, the result was `WATCH_EXIT=2;FINAL_EXISTS=False`. A normal
profile-enabled PowerShell smoke test also returned `PROFILE_GMENU_EXISTS=False`.
The exact normal profile wrapper route resolved `cfun uni` to the current
`F:\study\Platforms\windows\functions\uni.ps1` and returned exit 2 with
`PROFILE_ROUTE_KNOWN_REMAINING=0`.

A disposable file placed under `C:\Users\micha\.gmenu\Commands` was removed
by the real profile route. The proof returned `GMENU_PROOF_FILE_PRESENT=False`,
`GMENU_PROOF_ROOT_PRESENT=False`, and `GMENU_PROOF_UNI_EXIT=2`; the exit 2 was
the expected unavailable orphan-process scan, not a remaining authorized path.

The current exact GMenu authorization set was rescanned afterward:
`FINAL_GMENU_EXACT_REMAINING=0`.

An independent GMenu writer later recreated only
`C:\Users\micha\.gmenu\CommandHistory\ProfileSources`; this was not a
profile-import write and was not caused by Uni. After that writer was idle, a
fresh no-profile `uni.ps1 gmenu` reconciliation returned exit 0 and verified
`GMENU_FINAL_ROOT_IMMEDIATE=False` and `GMENU_FINAL_ROOT_AFTER_10S=False`.

A separate disposable writer recreated an authorized command at 45 seconds
while Uni was scanning. The race proof returned
`GMENU_RACE_WRITER_EXIT=0`, `GMENU_RACE_FILE_PRESENT=False`, and
`GMENU_RACE_ROOT_PRESENT=False` after Uni completed; Uni itself returned 2
only for the known unavailable orphan-process scan.

Final no-profile reconciliation after the external writer was idle returned
`LAST_GMENU_UNI_EXIT=2`, `LAST_GMENU_ROOT_IMMEDIATE=False`, and
`LAST_GMENU_ROOT_AFTER_10S=False`.

A fresh no-profile `uni.ps1 gmenu` run after the five-round change scanned 20
C: roots and approximately 2 million entries, matched zero exact-name C:
residuals, removed zero additional files/directories, and ended with
`UNI_GMENU_EXIT=2`; the only reported failure was the machine's unavailable
CIM process-command-line provider. The immediate live check remained
`GMENU_ROOT=False`.

A second live `uni.ps1 gmenu` run started with an empty `.gmenu` work tree
created by concurrent GMenu tooling. It completed all phases, removed one
temporary command file and two authorized directories (`.gmenu` and
`GMenuFallback`), and returned `UNI_LIVE_GMENU_EXIT=2` only for the same CIM
provider failure. Immediate and +10-second checks both reported the GMenu and
fallback roots absent.

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

A fresh live `driverbooster` run reached all 13 phases without a concurrency
abort. The verified IObit-owned C: roots were already absent; ten matching
paths were preserved as GameLibraryManager source/catalog assets, and one
shared Defender exclusion registry value remained protected. The run returned
exit 2 for protected/inaccessible state and unavailable CIM enumeration; this
is correctly reported as incomplete rather than falsely certified clean.

The orphan-process path now has a native Windows fallback (`NtQueryInformationProcess`)
when CIM fails. A direct Windows PowerShell probe loaded 471 process rows with
zero unresolved host processes after retrying transient PID races. The final
fresh no-profile `uni.ps1 gmenu` run used that fallback, matched zero exact-name
residuals, removed zero files/directories, and returned
`UNI_NATIVE_RETRY_GMENU_EXIT=0`; `.gmenu`, `GMenuFallback`, and the republisher
log were absent immediately and after ten seconds.

The final detached `driverbooster` route reached its terminal summary on the
current source: exit `2`, verified IObit-owned roots absent, and zero verified
file/directory removals because the remaining name matches were preserved
GameLibraryManager/evidence catalog assets. The only reported blockers were 19
registry scan errors/protected shared state and the documented inaccessible or
ambiguous coverage boundary; its stderr was empty.

The current-source eight-worker queue proof returned eight exit codes of `0`,
seven wait messages, zero fail-fast messages, zero worker stderr output, and no
remaining exact target path.
