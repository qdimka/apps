# Verification evidence

This is a historical evidence record, not a claim that checks have run against every later change.
Use [AGENTS.md](../AGENTS.md) for current verification requirements. Counts depend on installed tools.

## apps 0.3.0

**Code:** `9e274cf`, including Go/Cargo from `ad3c6d2` and the environment-inventory correction.
**Date:** November 8, 2026.

| Check | Observed result |
| --- | --- |
| `scripts/test.sh` | 92 checks, 0 failures |
| `scripts/build-app.sh` | Release arm64 bundle built and ad hoc signed |
| `codesign --verify --deep --strict dist/apps.app` | Passed |
| `plutil -lint dist/apps.app/Contents/Info.plist` | Passed |
| Read-only real inventory | Homebrew 63, Go 9, Cargo 0; npm 14 across three Node installations; pip 492 across four environments |
| Native UI | Sidebar categories, environment row labels, Node v24 filter (3 entries), project venv filter (2 entries), exact manager details |

Inventory breakdown: npm nvm v22.19.0 (8), v24.11.1 (3), v22.21.1 (3); Python Anaconda (471),
system (18), Homebrew (1), and a project .venv (2). uv tools was empty and pipx absent.
These are observations, not required counts or fixed fixtures.

Go Trash and staged replacement were tested with fake commands and temporary files. Cargo's real
tracking schema and qualified path uninstall were checked with a dependency-free, offline local
fixture and a separate temporary root. The agent did not update or uninstall user-installed tools.

Independent review found no Critical issues. An Important shared-deadline finding was fixed with
cancellable Go/Cargo checks and regression cases; a Minor npm label finding was fixed by showing
the Node installation rather than only a possibly shared global prefix. Multi-runtime tests cover
independent failures, exact mutation dispatch, filtering, and venv symlink identity.

A native launch initially blocked on synchronous project-directory discovery before SwiftUI startup.
A sampled stack identified AppModel initialization → projectPythons → directory access. Discovery
was moved into Task.detached after the window appears, and the corrected bundle launched successfully.
Native close/minimize/fullscreen controls exist without custom duplicates; macOS capture can replace
their visual area with a sharing indicator.

## apps 0.2.0 history

**Code:** npm/pip work through `d8c1636`.

- 69 automated checks passed, covering scopes/prefixes, JSON/exit codes, stale contexts, distribution
  ownership, restrictions, registry uncertainty, nvm defaults, venv symlinks, and review regressions.
- A real temporary venv created with --without-pip verified standard-library metadata probing on
  Python 3.9. No package downloads or user-environment changes were needed.
- Observed inventory included Homebrew 63, npm 8, Anaconda pip 471, uv 0, and no pipx. Later native
  verification used the saved Node v24 installation with 3 globals after local installation changes.
- Inspected scoped npm details, protected Conda-owned Python packages, runtime settings, system Python
  with 18 distributions, and return to Anaconda. Actual upgrade/uninstall operations were not used for QA.
- At this release one active npm/Python runtime was selected. That behavior is historical and was
  superseded in 0.3 by simultaneous multi-environment inventory.
- The final release bundle's plist/signature and launch were checked after the Mac was unlocked.

Review fixes included rejecting pip configuration that changes interpreter/destination/target scope,
canonical distribution operands, protected dependency constraints, uncertain index results, a shared
pip-check deadline, npm SemVer/no-downgrade rules, origin restrictions, and exact pip removal identity.
The pip guard reads the installed pip Configuration API; incompatible versions fail closed while
registry settings remain available. Its overall check deadline is 60 seconds per interpreter.

## apps 0.1.0 history

- 33 checks passed after review fixes; release packaging, signature, and plist validation succeeded.
- Real inventory read Homebrew 63 and uv 0; pipx was absent.
- Inspected native launch, ripgrep search/details, paths, empty/error behavior, and dark appearance.
  Light appearance uses semantic system colors but was not separately inspected.
- Duplicate sidebar window controls were removed following user feedback. Only native controls remain.
- Update checks read Homebrew metadata. Positive upgrade/uninstall cases used fake managers.

Review removed brew update from checks because migrations can change installed packages. It also
prevented unrelated Homebrew autoremove/dependent processing, confirmed removals after refresh,
reset stale update statuses on failed checks, bounded errors, terminated child process groups,
and published independent source reads without waiting for a slow source.

## Known limits and deferred findings

- npm outdated exit 1 with an empty JSON object is not separately rejected as contradictory.
  Mutation still independently checks its target version.
- A Homebrew revision-only update can show a target version without the `_N` suffix; Homebrew itself
  still handles the revision during upgrade.
- uv parsing targets the supported text format; unexpected formats produce a source error.
- Manager output is available after command completion, not streamed live. Timeouts do not roll back
  partial package-manager changes. Registry caches/lock files may be created by inventory commands.
- Homebrew catalog freshness is not verified. One Homebrew/uv/pipx installation is discovered per source.
- Full XCTest is absent on the development Command Line Tools installation. Use the executable check
  target and repository toolchain wrapper instead of changing system SDK files.
- Work was performed in the shared feature checkout; no merge, push, notarization, or public release
  was performed. The bundle is intended for local use.

## Documentation and screenshots

The English documentation refresh changes no executable code. Three genuine app-window captures
were saved under docs/assets and inspected: npm environments, a project venv, and Go tool details.
The UI remains Russian; no screenshots were edited to imply an English interface. Documentation
verification checks local Markdown targets, image signatures/dimensions, English prose, and whitespace.
Automatic instruction loading in a new host session was not exercised in this documentation-only change.

## GitHub Actions configuration verification

**Code state:** base `3e83130` plus the local CI/release workflows, packaging script, release
preflight checks, and explicit test-Python injection prepared in this change. No remote was connected.

- `scripts/test.sh`: 92 checks, 0 failures with the default interpreter.
- `APPS_TEST_PYTHON=/opt/anaconda3/bin/python scripts/test.sh`: 92 checks, 0 failures with an explicit interpreter.
- `Tests/ReleaseChecks.sh`: 4 preflight checks passed, proving rejected tags/versions/architecture
  do not invoke the app build in a disposable fixture. Initial RED was the absent packaging script.
- actionlint v1.7.12: both workflows validated with no diagnostics. Tool installed only in a temporary directory.
- `bash -n scripts/package-release.sh Tests/ReleaseChecks.sh`: passed.
- `scripts/package-release.sh v0.3.0`: local arm64 archive built and ZIP integrity passed.
- Extracted ZIP: Info.plist version, executable permission, arm64 architecture, and strict signature
  verification passed. SHA-256 was computed for the archive.
- Independent read-only review found no Critical, Important, or Minor findings in the workflows,
  packaging, permission boundaries, tag checks, or draft/upload/publish sequence.
- Actual GitHub execution, Intel compilation, remote policy, and release publication remain unverified
  until the intended repository is added. No tags, pushes, or releases were created.

## First remote CI execution

After the repository was created and source was pushed, the first run exposed a system Bash 3.2
empty-array/nounset failure in the toolchain wrapper. A clean-toolchain fixture reproduced the
failure; an always-populated argument array fixed it, with two system-Bash regression checks.
The next run reached the suite and exposed pip 26.3's source-grouped Configuration.items format.
The old guard silently skipped nested options. A temporary pip 26.3 environment and mocked
flat/grouped schemas reproduced the failure; normalization now supports both and rejects unknown
shapes. Local suites pass 93 checks on pip 26.3 and on the legacy system pip. No user-installed
packages were changed; pip compatibility installs used a disposable temporary environment.
Remote runs and build artifacts are available in [Actions](https://github.com/qdimka/apps/actions).
