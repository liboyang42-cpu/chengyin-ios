# Native safety and test-target closeout

This local, offline integration follows the remaining-native-client checkpoint. Three frozen owner manifests were verified before copying files. Shared files were reconciled narrowly; no earlier module, client, host, permission boundary, or test method was removed. No publication, remote CI, backend request, OS permission, capture, playback, upload, credential, provider, configuration or entitlement action was taken.

## Integrated changes

- App-hosted `QuestifyAppUnitTests`, its separate shared scheme and xcconfig, Debug testability and a bounded separate CI job now include every authored app-unit source. The original Questify UI scheme, six exhaustive UI shards, SwiftPM Core scope and iOS 17/macOS 14 baselines remain. The Credentials optionality correction preserves logout assertions; fake journal injection is additive.
- Five consent-first NPC samples now have scoped local capture/playback, per-sample reviewed source multipart uploads and the existing final enrollment review. Normal resource navigation visibly mounts a localized configuration-required gate even when resource reads are unavailable. No synthetic capture limits were put into production. The optional factory receives the existing resource coordinator and must share its journal and session owner; session invalidation supports sample coordinators. No normal provider is instantiated without attested configuration. Image/avatar scopes and cleanup remain intact.
- Voice upload defaults to the same disabled bounded streaming transport as retained image upload. Explicit fake transport injection remains supported. Image permissions cannot authorize voice upload; endpoint, ownership/consent, provider and current-scope checks remain independent.
- Metadata-only Keychain upload journals protect retained and IM upload owners across process death and epoch/draft changes. Pending/acknowledged outcomes stay locked. Same-process, same-scope successful local application records `locallyApplied`; this is not server publication or a claim that local drafts survive termination. No source status/receipt endpoint, automatic retry or manual unlock was invented.
- The reusable response-limited transport uses fresh ephemeral sessions, denies redirects/cookies/cache/credential-store reuse, and enforces advertised and per-chunk response bounds before accumulation. Retained hosts use it disabled; IM remains service-nil. All activation grants stay OFF.

## Exact reconciliation

Input manifests are `app-unit-packet-manifest.json`, `voice-packet-manifest.json`, and `image-packet-manifest.json`. They attest packet inputs, not subsequent integrated outputs.

- Voice host overlays matched preimages before copying; image's NPC-avatar Bool-return callback was applied as a narrow checked patch afterward.
- Image's fake durable journal setup and test-target Credentials optionality hunk both survive in `RetainedImageNormalHostTests`.
- The generator was copied only after verifying its preimage. Project output was regenerated against the complete combined source inventory instead of copying an old packet project.
- Voice catalog fragment entries were merged with exact collision checks, preserving the existing catalog.
- Integration adds a default bounded voice transport, visible normal-host configuration gate and five composition contracts. These intentionally differ from the frozen voice packet and are recorded in final hashes.

`before-hashes.json` is the immutable ownership checkpoint. `changed-files.json` contains exact before/after SHA-256 and sizes for every changed/additional file, excluding itself and Git/Python cache internals. No prior file was deleted. `changed-swift-files.json` contains all 26 changed Swift files.

## Verification

Run `python docs/native-closeout/run_checks.py` from the checkout. It records all 54 commands, working directories, raw outputs and explicit exit codes in `checks/results.json`. Runner exit 0 means no *unexpected* failures; it never changes the whole-parser FAIL to PASS.

- PASS exit 0: 414 Python source contracts, 24 tooling tests, 14 parser-advisory tests
- PASS exit 0: every prior module gate, voice/image source gates, deterministic generation/scaffold, exact localization fragment equality, app-unit inclusion and all six complete/disjoint UI shard dry-runs
- PASS exit 0: focused supplementary pinned Tree-sitter parsing, 26 Swift files, zero diagnostics; whitespace
- FAIL exit 1: full-tree parser, 804 Swift files, the same ten historical diagnostics across six files, unsuppressed. Exact lines remain in `checks/whole-parser.txt`; this batch does not touch those six files
- NOT_RUN: Swift typechecker/compiler, Core XCTest, app-hosted XCTest, Xcode build, XCUITest, simulator/device/accessibility, PhotosUI, Keychain persistence, AVFoundation, URLSession cancellation/memory and live backend/provider acceptance. Swift and xcodebuild availability commands exit 127

Authored inventory: 2,125 Core methods; 313 UI methods in 56 classes; 12 app-unit methods across three included sources; 281 App and 324 Core Swift files; 5,145 bilingual keys. Six UI shard counts are 52/52/52/52/53/52. Authored tests are not executed tests.

## Finite remaining gates

`remaining-gates.json` and the prior checkpoint's gate list distinguish implemented-but-OFF safety from absent implementation and unexecuted acceptance. The WeChat SDK authorization/callback adapter remains NOT_IMPLEMENTED_OFF. Voice limits, independent grants and Apple audio/temporary-file acceptance remain unresolved. Image manual/authoritative recovery remains unresolved without a source endpoint. Publisher/backend authority and all other existing permission/validation gates remain. The new app-unit target removes the target-wiring gap, not the Apple execution gap.
