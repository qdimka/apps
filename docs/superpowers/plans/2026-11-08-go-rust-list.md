# Go and Cargo implementation plan

**Status:** Adapter tasks completed in 0.3. The original source-dropdown/no-sidebar task was superseded
by [environment inventory](2026-11-08-environment-inventory.md).
**Design:** [Go/Rust specification](../specs/2026-11-08-go-rust-list-design.md).

**Goal:** Add Go-installed CLI binaries and Cargo binary crates using existing PackageManager adapters.
**Stack:** Swift 6, macOS 14+, Foundation, existing Go/Cargo, no new dependencies.

## Constraints and review focus

Do not change user tools during verification. Use separate arguments without shell or --force.
Preserve exact Go target and Cargo root/source/options. Prevent symlinks/names from broadening deletion;
never replace a Go binary before verified staged output and fresh identity checks. Distinguish empty,
legacy, and corrupt Cargo tracking data. Retain native window controls without duplicates.

## Completed task 1: Go

Files: Sources/AppsCore/{GoManager,ManagedFiles,PackageRecord,ManagerDiscovery}.swift and
Tests/AppsCoreTests/GoChecks.swift. Add scoped identity, packageReference/modulePath/buildOptions,
FileTrashing injection, build-info parsing, exact-target validation, newer-version checks,
private staged build/promotion, and Trash removal. Verify foreign/devel/replaced builds, symlinks,
stale fingerprints, failed output, and successful temporary-file promotion with fake commands.

## Completed task 2: Cargo

Files: Sources/AppsCore/CargoManager.swift and Tests/AppsCoreTests/CargoChecks.swift. Parse
.crates2.json with root/package identity; preserve bins/features/profile/target; qualify uninstall
and restrict unsupported origins. Check registry/Git/path, no downgrade, malformed/empty/legacy data,
and changed metadata. Validate actual schema and qualified uninstall using a dependency-free,
offline disposable local crate in a private root. Read the user's registry without mutations.

Tasks 1–2 shared enum/discovery changes and shipped together in ad3c6d2. Final review added shared
60-second cancellable update-check deadlines. No Critical findings remained.

## Superseded task 3: Source dropdown

The original task removed the sidebar and retained one active npm/Python. The user clarified that
source categories must remain, all environments must be inventoried, and the dropdown filters
Node/Python environments. Do not execute the superseded design. The correction shipped in 9e274cf;
see the environment plan and [validation evidence](../../validation.md).
