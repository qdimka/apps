# Agent instructions

## Purpose and scope

apps is a native, local macOS application for inspecting installed CLI packages and
managing one installation at a time. Keep it usable without an account, server,
paid service, or third-party Swift dependency. Target macOS 14+ and Swift 6.

## Read the relevant context

- Before changing package discovery, models, adapters, or coordination, read
  `docs/architecture.md`, including the ownership and identity contracts.
- Before changing the window, navigation, or environment filters, read the UI and
  runtime sections of `docs/architecture.md` and the environment section in `README.md`.
- Before packaging or reporting release verification, read `docs/validation.md`;
  it records historical evidence, not a substitute for checks on your changes.
- When changing screenshots, read `docs/assets/README.md` before capturing new images.
- Read historical files under `docs/superpowers/` only when investigating a decision
  or explicitly continuing that plan. Start with its README to identify superseded work.
- These references are conditional reads, not automatically expanded instructions.
  `AGENTS.md` is the root instruction file for tools that support that convention.

## Repository map

- `Sources/Apps/`: SwiftUI views and the main-actor application model.
- `Sources/AppsCore/`: manager adapters, discovery, identities, command execution,
  and the observable coordinator. Keep this module independent of SwiftUI.
- `Tests/AppsCoreTests/`: executable check suite, fake runners, and fixture checks.
- `scripts/`: toolchain wrapper, checks, bundle packaging, and icon generation.
- `Resources/`: app metadata; `docs/assets/`: authentic documentation screenshots.
- `.build/` and `dist/` are generated output, not source files to commit.

## Build and verify

- Use `scripts/test.sh` for automated checks. The check target is `AppsCoreChecks`;
  do not replace it with `swift test` or assume XCTest is installed.
- Use `scripts/swift-local.sh build --product apps` for a development compile.
- Use `scripts/build-app.sh` for a release bundle, or add `debug` for a debug bundle.
  The wrapper handles the local Command Line Tools mismatch; do not patch the SDK.
- After packaging, run `codesign --verify --deep --strict dist/apps.app` and
  `plutil -lint dist/apps.app/Contents/Info.plist` before claiming a valid bundle.
- Run checks appropriate to the change. Documentation-only work needs link, asset,
  language, and diff checks; it does not require rebuilding unchanged application code.
- Record commands, results, code revision, and unverified limits when updating evidence.
  Never report a previous run as fresh verification of changed code.

## Architectural boundaries

- Put CLI parsing, argument construction, and installation validation in the adapter.
  Views request actions through AppModel and PackageCoordinator, not subprocesses.
- Pass executable URLs and separate arguments to CommandRunning. Never construct
  shell commands from package names, paths, or metadata, and never activate a venv.
- Preserve package identity across source, manager executable, name, kind, and any
  installation scope. Equal names in different runtimes must remain distinct.
- Keep source categories in the sidebar. npm/pip inventory aggregates environments;
  the top filter changes visibility only. Always label the row's environment.
- Dispatch changes to the exact row's manager, not a default or currently filtered runtime.
- Keep filesystem discovery off the main actor and out of application initialization.
  Window creation must not wait for directory access or a package manager.
- Keep reads independent, publish healthy runtimes despite failures elsewhere, and
  serialize changes. A failed check invalidates only that runtime's update statuses.

## Package and data handling

- Revalidate current installation identity and restrictions before changes. Enforce
  restrictions in adapters and the coordinator, not only through disabled buttons.
- Preserve npm prefix/origin, Python interpreter/ownership, Cargo root/source/build
  options, and Go binary identity. Do not broaden an action to a different installation.
- Keep Homebrew checks free of `brew update`; retain the environment flags that
  prevent unrelated autoremove and automatic installed-dependent processing.
- Unknown update availability stays unknown. Do not infer freshness from missing data.
- A successful exit alone does not prove removal; confirm against refreshed inventory.
- Preserve cancellation, whole-process-group termination, output limits, and concise
  error messages. Do not expose registry credentials in diagnostics or documentation.
- Exercise mutations with fakes or explicitly isolated disposable fixtures. Do not
  update or uninstall the user's installed tools merely to verify a code change.
- Publishing, pushing, changing system configuration, or changing real installations
  requires authorization for that action; a feature request does not authorize test mutations.

## Definition of done

- For behavior changes, add meaningful regression coverage and run the applicable suite.
- For UI changes, build and inspect the actual native window when accessible; preserve
  standard macOS controls and do not add duplicate custom traffic-light buttons.
- Keep all repository documentation in English. This does not implicitly request UI localization.
- Update the relevant contract documentation when behavior or commands change.
- Check `git diff --check` and local documentation links before finishing documentation work.
- State what changed, what was checked, and any remaining limitation. Do not claim
  a new-session instruction-loading audit unless one was actually performed.
