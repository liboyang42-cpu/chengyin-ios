# Nearby-team executable write repair

## Confirmed gap and corrected coverage

The first integrated nearby packet had all six wire descriptors, executable scoped reads, source state/error/expiry behavior and fake-only mutation simulation. It did **not** have an injectable HTTPTransport mutation adapter. That was a completeness gap; the previous fake-only implementation is not full dormant-write coverage.

This isolated repair adds exact executable dormant HTTP writes for:

- POST `/api/team/apply` `{teamId}`; only server `data.applyExpireTime` is copied when provided
- POST `/api/team/withdraw` `{teamId}`; response data is ignored as in source
- POST `/api/team/handle` `{teamId, memberId, approved}`; distinct team/applicant identity, true JSON boolean

There is no join-mode setter, invitation/join/quit/kick/disband duplication, retired hangout, idempotency header, retry key, operation-receipt endpoint or invented reconciliation API.

## Execution model

`NearbyTeamHTTPWriteAdapter` takes a verified APIConfiguration, injected HTTPTransport, optional OperationEndpointApproval (nil by default), persistent journal, current-session/token closures, and a mandatory async fresh-evidence loader. The evidence loader must perform independently authorized source reads for the exact account/team/applicant. It must not blindly echo the review. The typed evidence must equal the immutable review and satisfy ticket/pending/leader/applicant/expiry rules before sending.

`NearbyTeamService` now accepts an optional `NearbyTeamWriting` adapter, default nil. Fake transport still reports `.simulated`; valid HTTP success reports `.acknowledged`; explicit non-200 business envelope reports `.rejected(errorCode:message:)`; known preflight failure is `.notSent`; transport/cancellation/malformed/uncertain persistence or post-send session change is `.unknown`. The live path requires the matching review, so a standalone action descriptor is not sufficient authority. Coordinator passes its already-checked immutable review and shows a distinct acknowledgment message, without fabricated roster increments or membership receipt IDs.

Default AppSession factory callers pass no write grant or evidence loader. The additive host helper extends only `makeNearbyTeamCoordinator` to accept optional write approval and fresh evidence. No default endpoint, role, token, grant or live capability is changed. The ordinary screen remains disabled for writes. The preexisting fake fixture still uses its own synthetic service.

## Durable replay rules

The adapter journal stores only deployment/region/namespace/account scope, target/operation identifiers, operation UUID and prepared/dispatched/acknowledged phase. It stores no credentials, names, messages, coordinates or expiry values. The target lock for handle does not include `approved`, preventing approve/reject races for the same applicant.

Fresh evidence is awaited before dispatch. The adapter rechecks the journal **after** that await, then persists and verifies the dispatched marker before the first HTTP send. This prevents separate adapter instances from replaying the same review even across epochs. Existing prepared/dispatched/acknowledged records fail closed. Valid business rejection clears its exact record; acknowledgment remains durable and cannot be replayed. Unknown outcomes preserve the existing coordinator's account-scoped lock and adapter's target journal. No automatic retry or lookup endpoint exists. A future authorized integration needs an independently verified resolution policy before clearing acknowledged/unknown locks; this repair does not invent one.

## Ready integration files

Copy the following from this packet to the same relative locations in the current main checkout, after shared ownership is granted:

Replacements:
- `Core/NearbyTeamService.swift`
- `Core/NearbyTeamCoordinator.swift`
- `Core/NearbyTeamHTTPReadTransport.swift` (comment clarifies separate writer ownership)
- `App/NearbyTeamViews.swift`
- `tools/check_nearby_team_module.py` (replaces obsolete fake-only source assertion)

New files:
- `Core/NearbyTeamHTTPWriteAdapter.swift`
- `Tests/CoreTests/NearbyTeamHTTPWriteTests.swift`
- `Tests/ContractChecks/test_nearby_write_adapter.py`
- `tools/check_nearby_write_repair.py`
- `Resources/NearbyTeamWriteLocalizations.fragment.json`
- this document and verification JSON

Then run the additive helper from the isolated packet:

```
python native-nearby-write-repair/tools/apply_nearby_write_host_patch.py --root chengyin-ios
```

The helper reads the current AppSession, replaces only the existing nearby factory, refuses repeat application, and preserves all surrounding modules. It was tested only against a temporary copy; no shared AppSession was modified during isolated work. Copying an old whole AppSession snapshot is unnecessary and unsafe while PublishModes/Wallet integrate.

Merge the four fragment `strings` into the current `Localizable.xcstrings`; do not replace the whole catalog. Also merge those four keys into `NearbyTeamLocalizations.fragment.json` if it remains a cumulative module catalog. Keep six UI shards; this repair adds no UI methods. Regenerate the project and inventory, rerun aggregate gates, and append a PROGRESS correction explicitly superseding the earlier fake-only mutation limitation. Do not use the old packet or its obsolete fake-only source checker afterward.

The existing `docs/nearby-team-source-map.md` and `docs/nearby-team-verification.json` should be updated after integration to reference this repair. Existing numerical totals are historical; recompute after other workers' changes rather than overwriting their totals.

## Verification in isolation

- New fake HTTPTransport XCTest methods authored: 22
- New supplemental repair source checks: 12 PASS
- Existing nearby supplemental source checks with replacement checker: 13 PASS in a staged copy
- Staged parser: 13 Swift files PASS, including the patched AppSession copy, baseline nearby code and new/replacement files
- Repair-only parser: 6 Swift files PASS after final comment-only read transport update
- New bilingual keys: 4 (en/zh-Hans)
- New UI tests: 0 (existing 3 remain)
- Combined nearby authored core tests after integration: 44 (18 domain + 4 HTTP reads + 22 HTTP writes)
- Swift compiler/XCTest, Xcode, simulator/UI/accessibility, device persistence and backend acceptance: NOT_RUN; Swift/Xcode toolchain is absent
- Actual network/backend/location/membership/remote operations during repair: 0

The Python checks validate source boundaries and fixture coverage; they do not execute Swift or prove runtime correctness.
