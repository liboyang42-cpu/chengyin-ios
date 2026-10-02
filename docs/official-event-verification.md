# Verification record

Date: 2026-10-01 (UTC)

- PASS: isolated Python source assertions, 10 checks; integrated official contract checks, 12 checks within the 93-test full source-contract suite
- PASS: integrated project generation and deterministic structural verification, 246 app/core/UI source entries, 1453 bilingual keys
- PASS: 15 tooling tests and 14 advisory-parser self-tests
- Authored integrated inventory: 771 core XCTest methods, 102 UI methods across 18 classes; three exhaustive class shards contain 34/34/34 methods
- PASS: supplemental Tree-sitter parse on all 11 authored Swift files and four edited integration files, zero recovery diagnostics, tree-sitter 0.26.0 + tree-sitter-swift 0.7.3
- Aggregate parser: 309 Swift files inspected; same ten recovery diagnostics in six pre-existing untouched files (AuthChannelView, MerchantHomeView, MessagingComponents, RegistrationSheetView, RegistrationUIForm, ParticipantCoordinatorTests). Not a compiler result
- PASS: English/zh-Hans catalog coverage, 101 official-event keys, source-only assertions
- PASS: 5 synthetic JSON fixture payloads parsed locally
- AUTHORED / NOT_RUN: 21 Core XCTest methods, covering exact GET routes, source response shapes, business/HTTP denial handling, state/filter/reward fields, credential validation, guest private-read blocking, account/epoch/token transitions, guest epoch round-trip, cancellation and current/stale 401
- AUTHORED / NOT_RUN: 10 XCUITest methods covering native navigation/reopen, status filters, search/Joined behavior, public guest/private login, publisher denial, broadcast stats, guest/account isolation, retry, unknown facts, language and synthetic accessibility settings
- NOT_RUN: Swift typechecking, compiler/build, simulator runtime, screenshots, VoiceOver, real accessibility validation, physical device, real backend/account behavior, live assets, CN/US live region acceptance. `command -v swift` and `command -v xcodebuild` found neither tool
- NOT_PERFORMED: remote CI (only local shard inventory regenerated), deployment, publishing, remote CI, user-computer access, backend writes, account creation, financial actions, schema/migration changes

Commands executed from the shared workspace:

```sh
python3 native-official-events-new/tools/check_official_module.py
swift-syntax-venv/bin/python chengyin-ios/tools/check_swift_syntax.py \
  --root native-official-events-new \
  $(find native-official-events-new -name '*.swift' -printf '%P ')
```

The Python checks inspect source structure and fixture JSON. They do not execute Swift or independently establish behavioral correctness. The Tree-sitter check is supplemental parsing only, not Swift compiler/API verification.

After authorized integration on an Apple-capable environment:

```sh
python3 tools/generate_project.py
python3 tools/check_scaffold.py
swift test
xcodebuild -project Questify.xcodeproj -scheme Questify \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
# Select an available iPhone simulator, then:
xcodebuild test -project Questify.xcodeproj -scheme Questify \
  -destination 'platform=iOS Simulator,name=<available iPhone>' \
  -only-testing:QuestifyUITests/OfficialEventFlowTests \
  CODE_SIGNING_ALLOWED=NO
```

The local source-check script belongs to this isolated delivery directory. Do not copy its `Config`-absence assertion into the main repository's production aggregate checks unchanged.
