# Uni validation gaps

- No standard PowerShell line-coverage provider or coverage configuration is
  present in this workspace, so line coverage is unavailable.
- The live C: route cannot certify every filesystem/registry object while
  Windows denies 18 filesystem reads and 19 registry reads or while an object
  is shared/ambiguous. Uni preserves those objects by design.
- The eight-worker proof covers Uni-owned concurrent runs. It does not prove
  that an unrelated external process cannot recreate an app artifact after
  Uni exits; the stale fast-profile GMenu writer was fixed and then verified
  absent, but arbitrary third-party writers remain outside Uni's authority.
- Source/catalog assets such as Codex worktrees and GameLibraryManager images
  were not deleted merely because their names contained an app token; they are
  not proven to be owned leftovers.
