# Merchant operations verification

Verified locally in the 2026-10-01 integration:

- 10 new Python source/structure tests PASS; aggregate 133 contract checks PASS
- 15 tooling tests PASS
- 14 supplementary-parser self-tests PASS using the existing pinned `swift-syntax-venv`
- Deterministic project regeneration/scaffold PASS: 285 app/core/UI Swift project references, 1,881 bilingual keys
- 13 clean new/edited Swift files passed supplementary Tree-sitter with zero diagnostics (ten new module/test files plus AppSession, AccountView, QuestifyApp)
- Full-tree parser: 352 files, same ten recovery diagnostics in six pre-existing files. The inherited MerchantHome diagnostic moves to line 203 after the additive operations entry; no new diagnostic family appears. Other files: AuthChannelView, MessagingComponents, RegistrationSheetView, RegistrationUIForm, ParticipantCoordinatorTests. This is not a Swift compiler result
- Authored inventory: 896 core methods (+43), 137 UI methods (+5) across 22 classes; exhaustive shard dry runs 47/45/45, all classes included
- git diff whitespace check PASS

NOT_RUN: Swift/SwiftPM/XCTest execution, SwiftUI/Apple SDK typechecking, unsigned CN/US Xcode builds, simulator/UI/screenshots, device tests, VoiceOver/Dynamic Type, provider permissions, live backend/data and business acceptance. Swift and xcodebuild are absent. No remote publication or CI run was initiated.

The default Python environment lacked the pinned parser packages; self-tests were rerun successfully with the already installed parser virtual environment. An initial scaffold check caught the new helper's SF Symbol string as a localization key; changing that helper to the equivalent rectangle-grid symbol resolved it. These corrected checks are not runtime evidence.

Run on an approved Apple toolchain after publication:
1. `swift test`
2. Unsigned Debug simulator and Release CN/US device builds using the repository CI configuration
3. All three `tools/run_ui_shard.py` groups, including MerchantOperationsFlowTests
4. English/Chinese + accessibility text sizes; card scrim/placeholder contrast; form focus/keyboard, picker labels, interrupted confirmation/back/reload, dirty reset-to-original, denied grants, signout/account replacement during every await, private template answers and unsupported raw statuses
5. Independently accepted backend/role/identity contract and production mutation gates before any live enablement proposal
