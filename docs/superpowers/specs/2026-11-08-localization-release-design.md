# English-first interface and published release

The user requested downloadable app archives in GitHub Releases and an English interface by default.
Keep Russian available through a saved in-app language preference in the existing settings sheet.
Use bundled English/Russian string catalogs shared by UI and core messages; English is the fallback
for missing/invalid preferences and missing translations. Preserve source/runtime behavior and native controls.
Translate application labels, statuses, confirmations, restrictions, and errors; manager-provided descriptions
and subprocess output remain unchanged. Interpolated package/path values must not be translated as keys.
Package localization resources inside the standalone app so downloads do not depend on the build directory.

Ship as 0.4.0 after checks, native UI inspection, and successful Apple Silicon/Intel CI. Push the matching
v0.4.0 tag to invoke the existing draft/upload/publish release workflow. Verify both release ZIPs and checksums
are attached to the published release, not merely retained as Actions artifacts.
