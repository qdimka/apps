# English interface and release implementation

> Use executing-plans inline; one independent final review covers the feature.

1. Add failing checks for English default, Russian catalog lookup, interpolation, fallback,
   complete catalog coverage, and standalone resource presence.
2. Add AppsCore localization resources/helper, translate UI/core strings, add saved language selector,
   and embed catalogs during packaging. Keep external metadata/output unmodified.
3. Run the suite and package extraction/resource/signature checks; inspect English default and Russian
   switching in the native app. Refresh README screenshots and English documentation.
4. Commit/push 0.4.0, verify both CI architectures, then push v0.4.0 and follow the release run until
   both archives and SHA256SUMS are visibly present in GitHub Releases. Do not substitute artifact links.
