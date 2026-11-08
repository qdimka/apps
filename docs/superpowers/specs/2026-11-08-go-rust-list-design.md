# apps 0.3: Go, Rust, and package inventory

**Status:** Go/Cargo adapter design shipped. The original two-column/source-dropdown UI interpretation
was rejected by user clarification; use [environment inventory](2026-11-08-environment-inventory-design.md)
for navigation and filtering. Do not remove the source sidebar based on this historical design.

## Original UI proposal, superseded

A combined package list and details, a source dropdown above the list, and persistent source badges.
The proposal retained one active npm/Python in settings and added Cargo root selection. The final
implementation instead keeps source categories and combines all npm/Python runtime inventories.

## Go

Inspect regular executable files in GOBIN or the first GOPATH/bin with `go version -m -json`;
Go 1.25+ is required. Do not scan module caches or arbitrary PATH entries. Do not modify symlinks
or foreign-owned files; unrecognized files are not presented as Go tools. Show command, module,
version, file, and dependencies. Local/development/replaced/custom builds cannot auto-upgrade.

Check `go list -m -json module@latest` under a shared deadline. Install only a newer SemVer target.
Build into a private temporary GOBIN inside the original directory, clear GOFLAGS, and preserve
recorded platform/CGO options. Verify output package/module/version and original-file identity
before atomically replacing one binary. Removal sends the revalidated owned file to Trash.

## Rust / Cargo

Read installed binary crates from .crates2.json under an explicit root. Identity includes root
and tracking package ID. Empty metadata is a valid empty inventory; corrupt JSON is an error.
Legacy entries can be read through cargo install --list with view-only restrictions.

For crates.io, use exact-name cargo search and SemVer comparison under a shared deadline. Install
a concrete newer version into the same --root with recorded bins/features/profile/target and --locked,
without --force. Never turn Git/path/alternative-registry installs into crates.io packages. Uninstall
uses a qualified package ID and root, leaving rustup toolchains/projects untouched. Root defaults to
CARGO_INSTALL_ROOT/CARGO_HOME/~/.cargo; custom install.root is selected manually.

## Boundaries and verification

No manager installation, bulk updates, rustup management, or project dependency inventory.
Pass separate arguments without shell evaluation. Verify with fixtures, fake runners, temporary files,
full checks, release/signature checks, native UI QA, and independent review. Do not change real user
packages as a test. No external Swift dependencies.
