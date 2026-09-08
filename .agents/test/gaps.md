# Uni validation gaps

- No standard PowerShell line-coverage provider or coverage configuration is
  present in this workspace, so line coverage is unavailable.
- The live C: route cannot certify every filesystem/registry object while
  Windows denies 18 filesystem reads and 19 registry reads or while an object
  is shared/ambiguous. Uni preserves those objects by design.
- The bounded post-final reconciliation currently rechecks the authorized
  filesystem roots/files, explicit GMenu scope, and authorized registry roots.
  It does not claim a universal recheck of every possible service, task,
  firewall, shared registry, or third-party-created artifact after Uni exits.
- The current live machine's CIM provider fails every `Win32_Process` query
  with "A general error occurred". Uni therefore returns incomplete rather
  than claiming it closed unknown script-hosted targets; direct verified
  executable processes remain handled by the normal process path.
- A separate explicit GMenu publish/profile-writer can recreate `.gmenu` after
  Uni releases its mutex. Uni cannot prevent an unrelated writer that does not
  participate in the Uni queue; the final proof therefore includes a delayed
  post-exit check and records this race as an external-writer boundary.
- The eight-worker proof covers Uni-owned concurrent runs. It does not prove
  that an unrelated external process cannot recreate an app artifact after
  Uni exits; the stale fast-profile GMenu writer was fixed and then verified
  absent, but arbitrary third-party writers remain outside Uni's authority.
- Source/catalog assets such as Codex worktrees and GameLibraryManager images
  were not deleted merely because their names contained an app token; they are
not proven to be owned leftovers.

- The current `C:\Temp\glm-debug-*` directory is a 2,039-file,
  approximately 230 MB GameLibraryManager catalog snapshot containing many
  unrelated assets plus `driverbooster.png`; it is intentionally preserved
  because filename matching cannot establish Driver Booster ownership.
- The live direct `uni gmenu` run removed the authorized `.gmenu` and
  `GMenuFallback` roots and verified both absent immediately and after ten
  seconds, but still returned incomplete because CIM cannot enumerate
  `Win32_Process` command lines on this machine.
- CIM itself remains broken, but Uni now falls back to native Windows process
  command-line inspection, retries transient PIDs, and fails closed only when
  a still-running script host remains genuinely uninspectable. The final live
GMenu route completed with exit 0 under that fallback.
- The final `driverbooster` route still returns incomplete for 19 protected or
  inaccessible registry conditions and shared/catalog matches. That is an
  ownership/permissions boundary, not evidence that the preserved catalog
  images belong to Driver Booster.
