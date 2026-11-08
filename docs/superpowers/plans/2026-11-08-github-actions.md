# GitHub Actions and release configuration

**Scope:** Prepare local configuration only. The user will add the GitHub repository later;
no remote, push, tag, or release is created during this task.

## Design

Reuse the same native checks and packaging for CI and releases. CI runs on branch pushes,
pull requests, and manual dispatch. A reusable workflow builds Apple Silicon and Intel
bundles on standard macOS runners. A version tag calls that build and publishes both ZIPs
plus SHA256SUMS only after both architectures pass. Require tag/Info.plist agreement.
Use ad hoc signing without Apple credentials or notarization; explain that distribution limit.
Keep build permissions read-only and grant contents:write only to the publication job.

## Implementation and verification

- [x] Add shared CI matrix and tag-triggered release workflow, with no hardcoded owner/repository.
- [x] Add locally usable ZIP packaging/version checks, preserving executable bits and bundle metadata.
- [x] Make tests accept an explicit Python interpreter so CI can supply Python with pip reliably.
- [x] Verify invalid/mismatched tags fail before builds; verify ZIP extraction, executable, plist,
  signature, and checksum on the local architecture; run the full suite.
- [x] Validate workflow syntax with actionlint, document triggers/assets/permissions/setup, and record
  that actual GitHub execution and Intel compilation remain unverified until a remote is added.
