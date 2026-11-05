# Native owner/target identifier false-positive audit

Date: 2026-11-05 (UTC)
Base: 26c846a81145e391e4dd1e9aeff652a374fa9bf5
Finding commit: 7691588efe5f66c32af5001ebcb6bd3b3de49d05

GitHub run https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/41979777841
Job https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/41979777841/job/127095889910
Gitleaks 8.24.3 full-history scan reported exactly four generic-api-key findings. The current diff scan reported no leaks. The findings were inspected at their original commit, not inferred from current source.

- App/NativeFriendRemovalView.swift:155: Synthetic fixture owner identity; not an authentication key.
- Core/ParticipantFileJournal.swift:62: Validation of ownerKey presence and length followed by the fixed target identifier profile.participants; no credential literal.
- Tests/AppUnitTests/NativeFriendDirectoryNavigationHostingTests.swift:62: Synthetic owner identity passed to the test metadata flow.
- Tests/AppUnitTests/NativeFriendDirectoryNavigationHostingTests.swift:65: Same synthetic owner identity passed to the test removal flow.

The sole scanner configuration change appends these four exact commit/path/rule/line fingerprints to .gitleaksignore, following its existing historical-finding convention. No wildcard, path exclusion, rule disablement, scanner version change, workflow edit or history rewrite is included. No original ignore entry is removed or modified. Future commits and adjacent lines remain scanned.

Validation: exact four-entry append verified against the original file; original prefix and unique commit-bound fingerprint syntax verified. The remote changed-file list must be exactly .gitleaksignore and this audit. Full-history Gitleaks and Xcode have not been rerun for this candidate; GitHub CI remains required. The legacy test_gitleaks_configuration.py contains an old 92-entry count and obsolete workflow step names already inconsistent with the base; it is not represented as passing or changed to weaken assertions.
