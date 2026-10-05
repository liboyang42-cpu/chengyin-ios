# Project editor verification — 2026-10-01 UTC

PASS local evidence:
- 14 new source/structure checks; full integrated source-contract suite: 107 checks
- 15 tooling checks and 14 parser self-tests (parser self-tests require the pinned swift-syntax-venv; running them with base Python initially failed because those dependencies are absent there, then passed in the correct environment)
- Deterministic generator/scaffold checks: 258 app/core/UI source entries, 1581 bilingual keys
- Supplementary parser: 17 authored/edited Swift files, zero recovery nodes
- Whitespace diff checks

AUTHORED, NOT_RUN:
- 31 new Core XCTest methods: validation, source decoding/payload mapping, merchant carry-over, block references/order, secure envelopes/namespace/revision, guest review without persistence, immutable/cancelled/session-stale confirmation, preflight races, quota, storage failure, unknown/completed receipts across coordinator recreation and rejection
- 9 new UI methods: edit/review/cancel, disabled service, validation, story-before-node prerequisite, whitelist, local restore, unknown-outcome/reopen, sign-out, explicit simulated receipt
- Integrated inventory: 802 core XCTest methods and 111 UI methods in 19 classes. Three exhaustive UI class shards: 37/38/36 methods; no case omitted

Swift, Xcode, simulator, screenshots, VoiceOver, device Reduce Motion, Keychain runtime, production service/account behavior and live backend acceptance: NOT_RUN. Neither swift nor xcodebuild is installed. Static/source assertions and Tree-sitter parsing are not compiler or runtime results. No remote publication, CI run, provider call, media upload, backend write or user-computer action was performed.

Run next on an authorized Apple environment:

```sh
python3 tools/generate_project.py
python3 tools/check_scaffold.py
swift test
xcodebuild -project Questify.xcodeproj -scheme Questify -configuration Debug \
  -destination 'platform=iOS Simulator,name=<available iPhone>' \
  -only-testing:QuestifyUITests/ProjectEditFlowTests CODE_SIGNING_ALLOWED=NO test
```

Keep the production-disabled gate unchanged during validation. Test both regional configurations and restart/Keychain recovery before considering any contract implementation.

## Fresh-detail ticket identity correction (2026-10-01 20:20 UTC)

Read-only review found that decoding the same edit-detail response twice assigned
new random ticket IDs. Whole-snapshot conflict checks consequently rejected an
unchanged source response containing tickets. Flutter `PublishApi.editDetail`
(`lib/data/api/publish_api.dart:167-184`, fixed source `a63e9e91`) keeps ticket list
order and does not require a stable ticket ID. The native decoder now uses an
explicit topic-ID + list-index local identity. Identical rows remain distinct;
the identity never becomes a server ID or a submitted payload field.

Four additional authored Swift tests check repeated-decoding equality, duplicate
row/topic separation and payload omission, genuinely fresh unchanged-preflight
acceptance, and rejection of changed ticket content even when revision text stays
the same. The test service decodes independent response bytes on every preflight,
so the former retained-fixture masking is removed. Existing conflict checks are
unchanged. These tests require Apple/Swift execution and are NOT_RUN here; only
source assertions, fixture JSON validation and advisory parsing are available.
