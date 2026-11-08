# Architecture

This document describes the current implementation. Historical plans are indexed in
[superpowers/README.md](superpowers/README.md); they are not current instructions.

## Components and dependency direction

```text
SwiftUI views → AppModel → PackageCoordinator → PackageManager adapters → CommandRunning
                             ↓                     ↓
                       PackageRecord         manager CLI / installation metadata
```

`Sources/Apps` depends on `AppsCore`. The core library does not import SwiftUI.
There are no external Swift package dependencies.

| Component | Responsibility | Entry points |
| --- | --- | --- |
| Native app | Window, lifecycle, source sidebar, package list, detail and settings sheets | `Sources/Apps/AppsApp.swift`, `ContentView.swift` |
| AppModel | UI selection, environment filter, saved additional runtime paths, background discovery | `Sources/Apps/AppModel.swift` |
| Coordinator | Concurrent inventory reads, runtime/source status, serialized changes, verification and session log | `Sources/AppsCore/PackageCoordinator.swift` |
| Models | Composite package identity, ownership restrictions, versions, installation metadata | `Sources/AppsCore/PackageRecord.swift` |
| Discovery | Executable lookup, nvm/Python choices, bounded project venv discovery | `ManagerDiscovery.swift`, `RuntimeDiscovery.swift` in `Sources/AppsCore` |
| Adapters | Manager-specific parsing, exact arguments, revalidation and supported operations | `*Manager.swift` in `Sources/AppsCore` |
| Command runner | POSIX process groups, cancellation, timeout, private output capture | `Sources/AppsCore/CommandRunner.swift` |

## Inventory and runtime identity

A `PackageRecord.ID` includes source, manager path, name, kind, and optional identity scope.
Go scopes identity to its binary; Cargo includes root and tracking package ID. Metadata
fingerprints and installation keys detect changes between listing and mutation.

A source may have multiple managers: npm and pip use every discovered or saved runtime.
The coordinator records runtime status separately from aggregated source status. A failed
runtime retains its inventory but loses previous update claims; healthy runtimes stay usable.
Mutation dispatch matches both source and manager path. Only the affected runtime is refreshed.

RuntimeDiscovery deduplicates equivalent executable paths while preserving distinct venv
roots whose interpreters symlink to a shared Python binary. Standard Python and Conda locations
are inspected along with a bounded set of development directories. Discovery does not scan
project `node_modules`, module caches, or the whole disk. Additional paths persist in UserDefaults.

## UI contract

The native window has three columns: source categories, package list, and selected package.
All packages is an optional sidebar category. npm/pip rows label their owning environment;
the dropdown above the list filters environment visibility without selecting an operation target.
Source changes reset that filter. Details expose the exact manager and installation location.

AppModel initializes without disk discovery. The view's initial reload dispatches discovery
through `Task.detached`; only publication occurs on the main actor. Filesystem access must not
block window creation. Additions in settings extend inventory rather than replacing an active
Node.js/Python selection. Cargo retains an explicit selected installation root.

The app uses a standard title bar and unified toolbar, with no custom close/minimize controls.
System capture/sharing indicators can cover the native traffic lights during screenshots.

## Adapter contracts

Each `PackageManager` provides `list`, `checkUpdates`, `upgrade`, and `uninstall`, with an
injected `CommandRunning` for fixture tests. Reads must distinguish missing/unsupported data
from a valid empty inventory. Mutation methods validate identity and restrictions again.

| Adapter | Contract and deliberate limits |
| --- | --- |
| Homebrew | JSON installed info; update checks use only the existing local catalog. Never run `brew update` as a check: migrations can change installations. Disabled autoremove and installed-dependent processing prevent unrelated work. |
| uv / pipx | Tools are managed environments, not individual distributions. uv uses the supported text format; pipx uses JSON. Separate version checks remain unsupported. |
| npm | Explicit global prefix, scoped names, exact newer SemVer target, and fresh inventory before changes. Links, aliases, and Git origins are not replaced by a registry lookup. Self-uninstall is restricted. |
| pip | Standard-library metadata probe on Python 3.8+; exact `python -m pip`. Protect system, external, Conda, foreign, and unknown ownership. Reject configuration that changes target scope, preserve registry settings, and constrain protected dependency versions during resolution. |
| Go | Go 1.25+ JSON build info for regular executable files in configured GOBIN/first GOPATH bin. Stage and verify one newer binary before atomic promotion. Trash only the revalidated owned file. Custom/development/replaced builds cannot auto-upgrade. |
| Cargo | Parse tracking metadata under explicit root; preserve source, bins, features, profile, and target. Only crates.io supports automatic upgrades; qualified package IDs address removal. Incomplete legacy records are view-only. |

A pip user-site removal may reveal another copy. The coordinator verifies disappearance of
the confirmed location/identity and reports that a different copy is now visible, clearing UI selection.
No manager is installed automatically and no adapter invokes `sudo` or forced ownership overrides.

## Execution, errors, and update semantics

CommandRunner uses `posix_spawn` with a separate process group. Cancellation or timeout sends
TERM and then KILL to that group, covering child installers. Default execution limit is 30 minutes.
Stdout and stderr go to private temporary files, limited to 32 MB per stream; the session log is
bounded and appears after completion. Errors shown in the UI contain a bounded output tail.

Go/Cargo update checks have a shared 60-second deadline. Pip checks have a 60-second deadline
per interpreter, with bounded individual network requests. Unknown results never become a claim
that the installed version is latest. Homebrew catalog freshness is unverified; incomplete pip
index responses remain unsupported. Upgrade actions may invoke the native manager even when
no independent check is available, subject to installation restrictions.

After every attempted mutation, reread that runtime. A zero exit code does not establish removal:
absence of the selected installation must be confirmed. On failed refresh, report uncertainty.
Manager commands can create their own lock files/caches and use their configured registries.
Timeout is not a transaction rollback.

## Verification and packaging

`Tests/AppsCoreTests/CheckSuite.swift` combines executable checks using fake managers/runners,
JSON/text fixtures, isolated files, and temporary environments. Full XCTest is not required.
`GoChecks.swift`, `CargoChecks.swift`, and `EnvironmentChecks.swift` are reference cases for
staged output, source-qualified mutations, and multiple runtimes of one source.

Use `scripts/test.sh`; compile through `scripts/swift-local.sh`. The wrapper keeps caches local
and supplies a VFS workaround for the development Command Line Tools mismatch. Packaging in
`scripts/build-app.sh` copies the executable through a temporary file and rename, builds the icon,
validates Info.plist, and ad hoc signs `dist/apps.app`. Verify the native app after restarting it;
a running process can still hold an older executable mapping.
