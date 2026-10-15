# CY-HANDOFF: IOS — native location callback isolation

2026-10-15 · **NO_API_CHANGE** · Source repair; native execution not yet verified.

## Baseline and coordination

- iOS branch: `migration/native-ios`; source baseline `f0df08598adbd73cdd85089ce4d1e0965e0e070c`.
- Coordination: CY-COORD-20261015-v1, `liboyang42-cpu/hengyin` at `7cda068a98f463d453b94378e41ffbbd6b3acb26`.
- Related backend dependency: BK-GPS. Backend contracts remain **DRAFT**, with no **CONTRACT_FROZEN** approval. The separate accuracy/timestamp wire adaptation is blocked and is not part of this change.
- Earlier handoff was read at `bcf992184a401fcf348e10ebad03f396a2fcb0ee`. BK-GPS [PR12](https://github.com/liboyang42-cpu/hengyin/pull/12), head `a5af41f57fa3771a151f8f662241e432b9233944`, was an unmerged draft. Deployment: **NOT_VERIFIED**. No deployment or permission readiness is inferred.

## Independent native defect

Expected: after a location capture is cancelled or finishes, callbacks from its CLLocationManager cannot authorize, complete or fail a later capture.

Actual source behavior before this repair: authorization callbacks checked only whether any continuation existed; success/error callbacks cleared the shared continuation without checking which manager owned it. A queued callback from a cancelled manager could therefore consume its successor's continuation.

The repair checks exact active-manager identity before taking a continuation, then clears it and detaches/stops that manager. Explicit cancellation uses the same terminal path. Task cancellation is scoped to the capture generation; it cannot clean up a newer capture. A pre-cancelled task is rejected before manager creation. The manager factory is injectable for hardware-free unit tests.

The three-argument location output, WGS84 label, existing measurement validation, GCJ02 requirement, projection policy, API request bodies, stored evidence schema and all capability/default-grant settings remain unchanged. No OS permission or production capability is enabled.

## Tests and remaining acceptance

Three genuine AppUnit XCTest cases are authored in `RuntimeDependencyAppTests.swift`:

- Cancel twice, start a successor, deliver old authorization/error/location callbacks, finish the successor and deliver duplicate callbacks; verify detach/stop and original WGS84 output.
- Cancel the capture Task, start a successor and verify a stale callback cannot fail it.
- No location grant must not construct a manager or request permission.

Actual offline validation: focused source/lifecycle checks and project/scaffold structural checks passed; patch whitespace and baseline preservation passed. These checks do not compile or execute Swift.

**NOT RUN:** Swift/Core XCTest, AppUnit, XCUITest, Xcode build, simulator, physical-device/provider tests, real-account/backend integration, deployment and signing/release. Swift and Xcode are unavailable in this environment; no toolchain was installed and no CI was requested.

Backend handoff request for BK-GPS: freeze the accuracy field contract and compatibility/error behavior with an exact source SHA and approved deployment evidence before publishing the separate measurement adaptation. No backend source or shared coordination files are changed here.
