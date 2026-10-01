# Verification evidence

2026-10-01, Linux development workspace.

PASS: Python project generation; independent generated-project reference/file parser; scheme target reference; deterministic regeneration; 18 English/Chinese localization entries; source-file inclusion; credential file extension exclusion; placeholder Bundle ID and no ATS relaxation in build config. Python scripts compile to bytecode.

NOT RUN: Swift compiler, Swift package tests, Xcode project opening/build, SwiftUI previews, simulator, real device, VoiceOver, business/backend tests, signing, TestFlight, store release. Neither `swift` nor `xcodebuild` is installed in the current workspace.

These static checks establish scaffold consistency only. They do not prove successful app compilation or runtime correctness. No CI has been configured or triggered for this new project.

## First hosted macOS run

2026-10-01: https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36833152589

PR #1 head: `5a027cb9e1640cd3a9d6e3cb3063534c0a6cb83b`. Xcode 26.6 / Apple Swift 6.3.3. Four pure Swift tests passed. Both unsigned simulator Debug and device Release builds succeeded. Gitleaks succeeded. These results supersede the initial NOT RUN build/test status above for that revision only. AppIntents metadata extraction emitted a warning because there is no AppIntents dependency.

UI interactions, previews, accessibility, real-device installation, live backend, signing and distribution remain NOT RUN. This is an unsigned build, not an installable distribution IPA.

Migration importer: six offline Python tests passed; 14 selected literal auth strings became review candidates, with no app resource overwritten. Their wording and UI use remain to be reviewed.
