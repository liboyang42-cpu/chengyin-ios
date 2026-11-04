# L12 business time slice — partial delivery, not launch acceptance

Owner: L12 business-time agent, issue #138. Branch: `codex/l12-business-time-20261104`.

## Baseline and collision check

- Public iOS `integration/launch-20261204`: `eec839502b11f1119a6ede212c768bb3f2de4f29` (checked before implementation).
- Frozen backend contract: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Read public launch plan sections 2 and 4 and #138. Issue had zero comments/assignees and no remote `codex/l12*` branch at claim time. Claim is recorded here because the task prohibits public comments.
- Existing `BeijingServerTime`, `MapCoordinateObservation`, and `SeasonRef.timezone` were checked. The season type explicitly says contract only, no I/O; it is not evidence of a working entry. No private repository or pre-existing workspace backend source was read.

## Exact whitelist

- `Core/MarketBusinessTime.swift`
- `Core/BeijingBusinessTime.swift`
- `Tests/CoreTests/MarketBusinessTimeTests.swift`
- `Tests/CoreTests/BeijingBusinessTimeTests.swift`
- `docs/app-composition/l12-business-time.diff`
- `docs/launch/l12-business-time-20261104.md`

## Implemented

The existing Beijing parser now delegates to the shared market parser, retaining the public API used by the deregistration display and existing server-clock deadline hints. Bare legacy values remain Shanghai wall time. The new parser requires a declared IANA business zone, preserves explicit-offset instants, keeps date-only values as calendar dates, rejects invalid calendar/offset values, and returns unknown for DST gaps and folds instead of selecting an arbitrary instant. Display derives the phone time from the same instant and supplies the business time when offsets differ. It does not choose a default US zone, infer business time from a device, authorize an operation, or change server decisions.

The existing Beijing path benefits from strict explicit-offset validation: impossible dates such as February 30 remain unknown/unverified instead of becoming a deadline fact. Existing server-anchor reconnect/reboot behavior is regression-tested.

## Integration handoff

L1 must apply `docs/app-composition/l12-business-time.diff` with `git apply --unidiff-zero` to add the new source to the Xcode app target. `git apply --unidiff-zero --check docs/app-composition/l12-business-time.diff` passes on this base. No shared AppSession, Composition, Runtime, project, CI, manifest or authentication file was edited. SwiftPM discovers the new source and tests automatically. L1 must refresh its CI manifest after integration per the plan. Until the project diff is applied, the Xcode target cannot resolve the new parser.

## Validation

Linux Swift 6.0.3, official `swift:6.0-jammy` image digest `sha256:95f6ef898992dc840b35517e780f6f6db9661432775ab0b33cc0a531ea749bdb`. The container uses `--network none`.

An isolated SwiftPM package copies the two production files and both test files byte-for-byte, without stubs, implementation edits or dependency additions. It exercises US summer offset, CN device display, spring gaps, autumn folds, half-hour DST folds, explicit offset disambiguation, missing zones, calendar dates, malformed inputs, and all existing Beijing deadline/clock regression tests.

Reproduce the focused checks with a temporary package:

```sh
mkdir -p /tmp/l12-check/Sources/QuestifyCore /tmp/l12-check/Tests/QuestifyCoreTests
cp Core/MarketBusinessTime.swift Core/BeijingBusinessTime.swift /tmp/l12-check/Sources/QuestifyCore/
cp Tests/CoreTests/MarketBusinessTimeTests.swift Tests/CoreTests/BeijingBusinessTimeTests.swift /tmp/l12-check/Tests/QuestifyCoreTests/
cat > /tmp/l12-check/Package.swift <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "L12TimeChecks", targets: [
    .target(name: "QuestifyCore"),
    .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])
])
SWIFT
(cd /tmp/l12-check && swift test -j 2)
git diff --check
git apply --unidiff-zero --check docs/app-composition/l12-business-time.diff
```

Result: **17 tests passed, 0 failures**, including 10 Beijing tests and 7 market tests. Test copies were compared byte-for-byte with the repository sources after the run. `git diff --check` and the handoff patch applicability check passed.

These focused checks are not a full repository Core suite or an Xcode build. Neither simulator/device tests nor a real backend session, restart journey or CN/US release build was run. CI was not dispatched. No business request or transaction was sent.

## Remaining gaps / acceptance boundary

This delivers only a time-parsing/display slice. L12 and J15 remain incomplete. There is no claim of normal-entry US login/browse/order acceptance, an original writer/readback flow, or mutation UNKNOWN recovery. Existing Beijing unknown parsing is read-only and is not a transaction receipt.

- Apple sign-in, E.164/SMS/email authentication, StoreKit/payment channel selection and permission changes require explicit owner authorization under the current task; they were not changed. No new app dependency was added.
- No verified real city/theme business-zone read contract was connected at the frozen backend head. `SeasonRef.timezone` is not a production entry. Backend business-zone semantics and normal entry wiring remain to be implemented and tested by their owners; no speculative payload field was added.
- The public frozen `ApiOrientController` shows `/api/orient/geo/normalize` is a publisher `topicId`/`coordSys`/`apply` operation, not a generic device-coordinate normalization endpoint. It was not called, and L5 map ownership was not duplicated.
- Currency/tax, market gating, security/review pages, privacy manifest/permission strings, bilingual backend errors and the UI Chinese-copy sweep are not delivered by this slice.
- Actual test-backend readback, restart and UNKNOWN mutation recovery, mini-program regression, device display in English/Chinese, and CN/US login/browse/order journeys still require evidence. #138 must stay open. No issue comment, PR, CI dispatch, production change or real transaction is authorized by this delivery.

## First batch receipt

Code/test commit `2a129a8561c8e1610b45ea2d6919884e914d7892` was pushed to the independent branch, fetched back, and all four changed file blobs matched local bytes (SHA-256 checked). The second batch adds this report and the un-applied shared project diff.
