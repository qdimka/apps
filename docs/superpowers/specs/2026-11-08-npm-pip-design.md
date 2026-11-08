# apps: npm and pip design

**Status:** Historical 0.2 design. The single-active-runtime approach below was superseded by
[environment inventory](2026-11-08-environment-inventory-design.md). Ownership and mutation safeguards remain.

## Intent and approach

Extend native local apps with global npm packages and Python distributions, including main Python
installations and project venvs. Reuse PackageManager and CommandRunning. The initial approach selected
one active npm and Python runtime, with discovered and manually added choices. Scanning all runtimes
was deferred then because it required separate runtime states and project discovery; it was subsequently
implemented after user clarification. A system-only pip source would not meet the requested venv scope.

npm inventory includes scoped global names and nvm installations, but not project node_modules.
Python inventory uses standard-library importlib.metadata on Python 3.8+ without installing libraries.
Mutations run the exact selected `python -m pip`, without shell activation.

## Behavior and safeguards

- Add npm/pip sidebar categories and native file/interpreter/venv selection. Persist additional paths;
  never silently substitute another runtime for a saved missing one.
- Probe prefix/base_prefix, pip availability, EXTERNALLY-MANAGED state, distribution ownership,
  location, commands, description, and dependencies. Normalize names to avoid duplicate distributions.
- Show Conda/foreign/system distributions with restrictions. Apply ownership protections in adapters
  as well as UI. Do not use sudo or --break-system-packages.
- Do not silently replace npm links, aliases/Git origins, or Python direct-URL/editable installs with
  unrelated registry packages. Restrict npm/pip self-uninstall.
- Accept npm outdated's normal exit code 1 with useful JSON. Malformed/error replies must not look
  like a successful check. Checks are explicit and use configured registries; no startup network checks.
- Revalidate runtime, environment, version, and restrictions immediately before changes.
- Confirm removal against refreshed inventory. Distinguish global npm, one Python distribution,
  and a uv/pipx tool environment. Pip removal does not remove the entire venv or unrelated dependencies.

## Verification and limits

Use fixtures, fake runners, temporary files, and isolated environments for scoped names, exit codes,
old Python, ownership, exact commands, symlink identity, and changed contexts. Real installed packages
are read-only during verification. Run the suite, release packaging/signature checks, native UI QA,
and independent review. Shipped as 0.2.0 without new dependencies, bulk operations, Conda management,
or automatic installation of Python/Node/pip. Later review added configuration-scope guards,
protected dependency constraints, newer-version comparison, and a shared pip-check deadline.
