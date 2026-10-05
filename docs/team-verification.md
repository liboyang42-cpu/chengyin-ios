# Team slice verification — 2026-10-01

## Authored inventory, not execution

- 47 new Swift core test methods: 18 domain contracts, six read-service tests and 23 coordinator/persistence tests
- 12 new synthetic UI methods in TeamFlowTests
- 74 English/zh-Hans localization entries
- Integrated inventory: 943 core methods, 149 UI methods in 23 classes, 1955 bilingual keys
- Exhaustive UI shards: 49 / 50 / 50; every existing class retained

## Available local checks

- PASS: 147 Python source/structure contract checks, including 13 new team checks
- PASS: 15 tooling checks and 14 advisory-parser self-tests
- PASS: exact team source audit against preserved Flutter, bilingual key parity, allowlisted read methods/routes, no live mutation/sharing/payment path, persist-before-submit/session guards
- PASS: deterministic project generation and structural scaffold verification (295 app/core/UI Swift source references, two catalogs)
- PASS: supplementary Tree-sitter parse of 16 new/edited Swift integration files, with no recovery diagnostics
- PASS: diff whitespace check
- Full-tree supplementary parser: 364 Swift files; retains ten diagnostics in six pre-existing files: AuthChannelView, MerchantHomeView, MessagingComponents, RegistrationSheetView, RegistrationUIForm and ParticipantCoordinatorTests. These are not compiler results and no file was omitted from that run

## NOT_RUN

Swift compiler/typechecking, SwiftPM XCTest, Xcode unsigned builds, simulator XCUITest/screenshots, real VoiceOver/Reduce Motion/Dynamic Type/device tests, live reads/mutations, provider/backend acceptance and distribution. This Linux workspace has neither swift nor xcodebuild. Source/syntax checks are not a substitute.

Fixtures and test transport are offline and synthetic. No remote publication, CI trigger, production configuration, login, invitation, membership, deletion, financial or backend operation was performed.

## Reproducible commands

python3 tools/generate_project.py
python3 tools/check_scaffold.py
python3 -m unittest discover -s Tests/ContractChecks -q
python3 -m unittest discover -s tools/tests -q
python3 tools/check_team_native.py --source ../app-audit -q
python3 tools/run_ui_shard.py --count 3 --shard 0 --dry-run
python3 tools/run_ui_shard.py --count 3 --shard 1 --dry-run
python3 tools/run_ui_shard.py --count 3 --shard 2 --dry-run

Run check_swift_syntax.py with the pinned advisory environment. Apple CI still needs swift test, unsigned build and all UI shards. Source-dependent Python tests explicitly report skipped if the preserved Flutter checkout is absent; the local audit here had that checkout and all 147 ran.

A cross-batch session audit also corrected profile-save account refresh to use the scoped CNAccountSessionService rather than the password-entry AuthService. Account/token/epoch/fresh.id guards are unchanged; a new source assertion covers phone-only CN refresh. Apple runtime verification remains NOT_RUN.
