# CI and GitHub releases

The workflows are active in [qdimka/apps](https://github.com/qdimka/apps).
Pushing source code runs CI; creating a matching version tag separately triggers release publication.

## Workflows

| Workflow | Trigger | Result |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Branch push, pull request, manual dispatch, or reusable call | Checks and ad hoc signed app ZIP for Apple Silicon and Intel |
| `.github/workflows/release.yml` | Push of a tag beginning with `v` | Calls CI, then publishes both ZIPs and SHA256SUMS after both builds succeed |

CI uses standard GitHub-hosted `macos-15` (arm64) and `macos-15-intel` (x86_64) runners. It asserts
the actual architecture before compiling. Python 3.12 with pip is provided to isolated checks through
`APPS_TEST_PYTHON`; no packages are installed into a user's Python or system interpreter.

Build jobs have `contents: read`, and checkout does not retain credentials. Only the publication job
has `contents: write`. It uses GitHub's built-in token; no personal token, Apple certificate, or
repository-specific secret is required. There is no privileged `pull_request_target` build.

Standard hosted runners are free for public repositories. Private repositories consume the account's
included minutes and can incur charges beyond its allowance. See [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Adding the repository later

1. Add the intended GitHub remote and push the branch containing `.github/workflows/`.
2. Confirm Actions is enabled and repository/organization policy permits the official actions used.
3. Inspect the CI run. Both architectures must pass before using a version tag for release.
4. Keep `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` up to date.
   Commit the version change before tagging it.
5. Push a tag matching the app version, for example:

   ```sh
   git tag v0.3.0
   git push origin v0.3.0
   ```

Only stable tags of the form `vMAJOR.MINOR.PATCH` are accepted; leading zeros, prerelease suffixes,
and mismatches with Info.plist fail before packaging. CI is branch-name independent, so the project
does not need to rename its branch to main before adoption. Manual CI runs do not publish releases.

## Release contents

For `v0.3.0`, the release contains:

```text
apps-v0.3.0-macos-arm64.zip
apps-v0.3.0-macos-x86_64.zip
SHA256SUMS
```

Each archive contains `apps.app` at its root and retains executable bits and bundle metadata.
The publish job verifies the expected two archive names and generates checksums from downloaded
build artifacts. Release notes combine installation/signing information with GitHub-generated notes.

Publication creates a draft first, uploads all assets, then publishes it. An existing release or draft
is never overwritten. If upload or publication fails, inspect the draft before retrying; explicitly
remove the incomplete draft if you want a fresh run, or finish it manually. Do not move an already
published version tag to different code. The workflows do not grant permission to overwrite releases.

To verify downloaded archives on a Mac, place both ZIPs beside SHA256SUMS and run:

```sh
shasum -a 256 -c SHA256SUMS
```

Unzip the archive for the Mac's architecture and move `apps.app` to Applications. These bundles use
ad hoc signatures, not Developer ID signing or Apple notarization. Gatekeeper can require explicit
approval in Privacy & Security; the workflow does not promise a seamless trusted-download experience.
Adding notarization is a separate change requiring Apple Developer credentials.

## Local packaging and checks

```sh
Tests/ReleaseChecks.sh
scripts/test.sh
scripts/package-release.sh v0.3.0
```

The packaging script validates the version, builds the release app for the native host architecture,
checks the executable architecture/signature/plist, creates a fresh ZIP with ditto, and tests the ZIP.
Set `APPS_EXPECTED_ARCH` to require a particular native architecture; it does not cross-compile.
`Tests/ReleaseChecks.sh` uses a disposable repository fixture to prove invalid tags, mismatched
versions, and unsupported architectures cannot invoke a build.

CI archives are available as Actions artifacts for 14 days, including branch/PR builds. Download the
inner app ZIP rather than treating the Actions artifact wrapper as an application bundle. The app ZIP
preserves permissions regardless of artifact-service file handling.

## Verification limits

Local checks can validate workflow syntax, native packaging, and checksums. An actual GitHub run,
remote permissions, the Intel build, and publication remain unverified until a repository is added.
The workflow uses the [official checkout action](https://github.com/actions/checkout),
[setup-python](https://github.com/actions/setup-python),
[upload-artifact](https://github.com/actions/upload-artifact),
[download-artifact](https://github.com/actions/download-artifact), and
[GitHub CLI release commands](https://cli.github.com/manual/gh_release_create).
