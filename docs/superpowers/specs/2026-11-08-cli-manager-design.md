# apps: initial macOS CLI manager design

**Status:** Historical 0.1 specification. Later specifications extend source coverage;
[architecture.md](../../architecture.md) describes the current implementation.

## Purpose and chosen approach

A free local app for a Mac owner who installs many command-line tools with agents. Combine
installed inventory, explicit update checks, individual upgrades, and removal for personal use.
The user chose native SwiftUI. Tauri was considered for portability but added a stack without
benefiting this macOS-only scope. Reuse existing Homebrew, uv, and pipx rather than building a manager.

## Initial scope

- Discover Homebrew, uv tools, and pipx; read installed packages independently.
- Combined inventory, source/search/update filters, and a selected package detail.
- Show source, installed version, available version where known, installation path, commands,
  and dependencies when supplied by the manager.
- Check versions only on explicit request; upgrade or uninstall one selected package.
- Confirm removal with name, source, and version; show progress, results, and a session log.

Equal names in different sources remain separate: identity includes source, manager installation,
and package name. Inventory comes from manager registries, not just command presence in PATH.
Missing managers have an explanation and do not break the rest of the app.

## Native interface

A standard macOS window with source sidebar, package list, and detail panel. Use native SwiftUI
controls, system typography/colors, and system light/dark appearance. Search and refresh/check
controls live in the toolbar; details expose upgrade, removal, and the log. Source failures remain local.

## Architecture and operations

Separate UI state from manager adapters and package records. The original proposal used Foundation
Process; the delivered runner evolved to POSIX process groups for reliable cancellation. Commands
receive separate arguments without shell concatenation; output must not block the interface.
Serialize changes and reread the affected registry even after failure. Report nonzero exits clearly.

Discovery covers PATH, standard Apple Silicon/Intel Homebrew locations, and user tool directories.
Show the actual manager path. Run as the current user without sudo; interactive/admin requirements
are reported for handling in Terminal. Use machine-readable data where supported. Unknown metadata
must not block inspection; unsupported checks stay unknown rather than claiming freshness.

The package list is not a separate database of truth. Store preferences in UserDefaults and keep
logs in the current session. Registry configuration belongs to the installed manager.

## Deferred from the initial version

Arbitrary pip/venv/Conda environments, manual binaries, new-package installation, bulk changes,
scheduled updates, rollback, cleanup, services, public distribution, notarization, and self-update.
Later specifications added pip/venv support. No account, cloud server, analytics, or mandatory paid service.

## Verification and acceptance

Target macOS 14 with Swift Package Manager and a local app-bundle script. Test parsers and exact
arguments with fixtures; inspect the native window, empty lists, and source errors where accessible.
Do not mutate real user tools for verification. A local bundle must launch, inventory/filter independently,
show source/version, serialize changes, confirm removal, and refresh with accurate results.
The user selected the name apps; exact icons, sizing, colors, and CLI flags were implementation choices.
