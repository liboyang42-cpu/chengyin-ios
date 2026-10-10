# P045 club merchant discovery: local read-only slice

## Scope and source

- Native preimage: `34928c87f43a6b97bfc0b01f8bcc8dba0d9b1631`.
- Master v10: P045 club detail / PA09, `loadMerchants` and `onMerchantKeyword`.
- Actual Mini source: private `chengyinhub-xcx/pages/club/detail/index.js`, fixed commit `4f230354795772a35d71245578188ac1b31374d1`, Git blob `4a6545ae95e98d4a51ed1c3893bce08510d3d73b` (144316 bytes).
- Source lines 784–815: owner-only `POST /api/club/merchants`, JSON `{}`; filter the loaded directory by `name`, `merchantName`, `suitActivityTypes`, `address`, `city`, joined by one space. Trim and lowercase the query; lowercase the joined fields; use literal UTF-16 substring matching; retain response order and duplicates.
- Native gap verified in the exact preimage: `ClubDetailView` did not mount this directory/search. The existing `CoopFlowRead.merchants(name: nil)` and `CoopFlowReading.read(_:isCurrent:)` already provide the protected read route and cancellation gate.

## Behavior

The detail view now mounts a read-only merchant section through its existing `AppSession.cooperationFlowReader`. Only a configured, signed-in club owner whose club and cooperation account/epoch agree can activate it. A fresh guarded club-detail read verifies the same club and owner before each directory read. Search, clear and empty-query restore operate locally; no keyword is sent to a server. Source text fields remain unchanged for matching and display; absent/null fields are empty strings. Non-object rows or non-text search fields fail explicitly rather than fabricating an empty directory.

The filter uses an explicit ECMAScript whitespace set (BOM included, NEL excluded), locale-independent lowercase and UInt16 comparison. It does not normalize combining characters, fold accents/width, tokenize, sort or deduplicate. A query revision makes canonically equivalent but code-unit-different strings redraw reliably under Swift Observation.

Rendered context binding synchronously invalidates old permits without publishing during view construction. Context includes club ID, owner flag, both reader object identities, full cooperation session and club identity. Visibility permits reject delayed retry, keyboard and clear callbacks after leaving/reopening. Separate request generations reject overlapping refresh results. The existing readers receive the same `isCurrent` gate so stale unauthorized responses cannot expire the new session. Failure, denied-owner, genuine empty directory and filtered no-results have separate presentation paths.

## Bounds

- No changes to AppSession, PBX, shared localization catalog, endpoints, approval registry or production write grants.
- No invitation submission, profile navigation, images, sorting, pagination or cooperation mutation is introduced by this slice. The Mini merchant-profile action and the rest of P045 remain outside this increment.
- Nullable textual contract only. Unsupported field types are rejected; no claim of arbitrary JavaScript object/number coercion parity or lone-surrogate string support is made.
- Reader/owner changes become effective at the next actual context bind or guarded read; no new realtime ownership subscription is invented.

## Integration

Seven-path allowlist:

1. `App/ClubDetailView.swift`
2. `App/ClubMerchantDiscoveryView.swift`
3. `Core/ClubMerchantDiscovery.swift`
4. `Tests/CoreTests/ClubMerchantDiscoveryTests.swift`
5. `Tests/ContractChecks/test_club_merchant_discovery.py`
6. `Resources/ClubMerchantDiscoveryLocalizations.fragment.json`
7. `docs/club-merchant-discovery.md`

Apply only the exact-baseline patch. Merge all nine bilingual fragment keys into the shared catalog with conflict checking in the parent integration step. Run the existing project generator once after all packets are integrated; this packet does not edit generated PBX or the common locale. Until those steps and Apple checks run, the source packet is not an accepted app build.

## Verification

Run local structural checks:

`python3 -m unittest discover -s Tests/ContractChecks -p test_club_merchant_discovery.py -v`

For the exact private source oracle, set `CHENGYIN_CLUB_DETAIL_SOURCE` to a locally materialized file whose Git blob hash equals the value above. The test executes only the extracted filter in a Node VM against 19 vectors, including cross-field search, Unicode, null fields and duplicate ordering. A missing environment variable reports the oracle as SKIPPED / NOT_RUN; an explicitly wrong source fails. These are source semantics and structural evidence, not Swift runtime execution.

Apple gates, all NOT_RUN in the Linux packet environment: full `swift test` (including the new keyword and model XCTest suites), unsigned simulator/device builds, app-hosted SwiftUI tests, simulator UI/visual/VoiceOver tests and real device/backend acceptance. The parent must run Apple gates after localization and project integration. Include owner loss, reader replacement, same-account relogin, disappearing/reappearing during a read, delayed old retry and old unauthorized responses in UI acceptance.

Observed packet checks: the club-prefixed Python discovery ran 162 tests, with 160 passing and two existing external-Flutter parity checks explicitly skipped because `../app-audit` is absent. This includes all seven new checks and the 19-vector fixed Mini oracle. `check_club_coop_contextual.py` and `git diff --check` passed. There are 24 authored new XCTest methods; none ran in this environment. `check_scaffold.py` fails on expected source/PBX mismatch until parent integration adds the new files. The legacy `check_club_community.py` and `check_club_governance.py` scripts were attempted but are blocked by missing sibling Flutter source files; these are not passes.
