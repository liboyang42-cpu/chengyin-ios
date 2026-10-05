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

## Authentication foundation and form compile

- PR #3 fixed head `f5a3084eec6dffa2d0a5cda2ff0866266e8919a4`, run https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36835198574: 16 Swift tests and unsigned simulator/device builds passed, secrets passed
- The first #3 run caught CRLF token validation: Swift grapheme matching did not catch the combined CRLF sequence. Header validation now checks printable ASCII bytes and regression cases cover CRLF, CR, LF, tab, NUL, blank and non-ASCII values
- PR #4 head `71c0d3febbcb25ed2418a47d55df4493d62b9cf5`, run https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36835397728: native compile/test checks passed
- Main merge head `921d7dc109294d00322fd2b47113eb239d403db4` also passed run https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36834319545

Three native UI scenarios are now defined for identity entry/dismissal/repetition, disabled unconfigured login, and bilingual preference persistence. Their first execution is pending at this revision. No UI success is inferred from compilation. Tests use fixture text only and do not configure a service URL.
