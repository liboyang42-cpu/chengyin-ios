# I01: Play location measurement fidelity

CY-HANDOFF: IOS. Protocol CY-COORD-20261015-v1. LOCAL_SOURCE_READY_FOR_REVIEW / NOT_PUSHED, 2026-10-15. Production remains OFF; native/device acceptance NOT_RUN.

## Freeze and source binding

- iOS base: migration/native-ios at `b6720951db29054496b4c7f04af7248d045aceee`, tree `4435430618411c1986db73b5d6410439405d31ca`. This bounded candidate retains the published callback repair, I09 and unified docs; it does not import unpublished coordinator readback changes.
- Prior proposal was held at control `7cda068a98f463d453b94378e41ffbbd6b3acb26` because BK-GPS was DRAFT. The later `f9823c6` execution section froze GPS. Freshly read [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/ab377921bbcb0277f3df3563040cd93f114fa40d/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md) and [OWNERSHIP](https://github.com/liboyang42-cpu/hengyin/blob/ab377921bbcb0277f3df3563040cd93f114fa40d/docs/plans/mini-codex-cloud-20261015/OWNERSHIP.md) now report SOURCE_READY for the backend CI scope at `69c281af1ecc3493db5614b74e494b91c7bb0656`, with all TEST_DEPLOYED NO. These are backend coordinator reports, not this iOS worker's native or deployment results. Historical callback handoff remains unchanged.
- Actual current business candidate `1e403b135206844a34219753a36e2dee39c7dd59`, [ApiPlayProgressController.java](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiPlayProgressController.java), blob `44efd3af40e6f1ae425229ec38a9ae476e602c3a`, was read again before adaptation. POST /api/play/arrive accepts optional accuracy in meters: blank remains legacy-compatible; supplied negative/nonfinite values fail; values >80 fail only within its coordinate-validation path. No timestamp wire parameter is defined. Method, authentication, node/scope and route action/version semantics are unchanged.
- Contract freeze removes the earlier source-adaptation blocker only. PR18 remains unmerged and no server deployment, real GPS acceptance, production entitlement or feature enablement follows from it. Only iOS source/tests and this handoff/index are changed; shared backend controls remain read-only.

## Source behavior

Measured accuracy and sample time now survive native capture, the existing authorized runtime projection, device review, prefab arrival evidence, and persisted completion evidence. New measured evidence must contain both metadata fields, finite nonnegative accuracy and a finite sample time aged 0 through 30 seconds. Invalid measurements are rejected, never changed into missing accuracy.

Only `accuracy` is serialized to the arrive request. Sample time remains local evidence because the frozen backend contract does not define a timestamp field. Values 80 and 81 are both transmitted faithfully; the server contract's 80-meter rule is not installed as a new global client policy. The existing Roam projection's quality policy is unchanged.

CoreLocation output remains WGS84. The existing runtime conversion is reused without changing its authorization or global threshold; WGS84 evidence still cannot pass the GCJ02 arrive request guard by relabeling.

New direct completion and new coordinator submission validate freshness before dispatch or creating a pending intent. Encoding an existing UNKNOWN attempt validates metadata integrity but does not reevaluate sample age, acquire a new sample, or change its identity/body. Legacy stored location evidence missing both fields remains readable and emits the same legacy multipart body. Partial metadata is invalid.

The previously published native authorization, success and error callbacks are restricted to the exact active CLLocationManager. Accepted completion and cancellation clear the continuation and detach/stop that manager. Task-cancellation cleanup is generation-scoped so a delayed cancellation cannot stop a successor.

Capabilities, default empty grants, production configuration, OS permissions and deployment approvals are unchanged. QR/check-in has no new accuracy or timestamp parameters.

## Validation inventory

Authored genuine Swift cases cover invalid/negative/nonfinite/incomplete metadata, freshness boundaries and future times, 80/81 fidelity, projection metadata, legacy evidence and a fixed pre-change UNKNOWN journal with literal legacy multipart bytes, stable replay identity/body, stale new submission without pending state/POST, QR/default-OFF behavior, late old-manager callbacks, duplicate completion, explicit cancel, Task cancellation and no-grant behavior.

Actual offline checks:

- Focused Python source checks: 7 passed. Supplemental structural evidence only.
- Existing Play contract checks: 15 passed, 5 skipped because external Flutter source is absent.
- Project/scaffold structural checks: passed; no generated project changes were needed.
- Patch whitespace validation: passed.

**NOT RUN:** Swift/Core XCTest, AppUnit, XCUITest, Xcode build, simulator, physical-device/provider tests, real-account/backend integration, deployed 80/81 response validation and release/signing. Swift and Xcode are unavailable in the execution environment; nothing was installed and no CI was requested. Authored tests and source checks do not establish these acceptance layers.

## Prefab pre-dispatch boundary correction

Root source review found that the old prefab ordering saved pending arrival before the newly added freshness validation, potentially recording UNKNOWN without a POST. The corrected bounded path prepares the immutable request first and retains all existing capability, protected-transport, lifetime and cancellation checks. Immediately before entering transport, a synchronous preparation callback validates freshness once and persists pending arrival; there is no second freshness check after persistence. Rejected/invalid measurements and known preparation failures therefore do not create a false arrival intent. Real transport uncertainty retains the pending journal. This does not grant prefab a new network dispatch capability.

New authored Core regressions cover stale/negative/incomplete prefab measurements with no pending state or POST, a clock crossing during journal persistence without a second freshness rejection, unknown transport retention, persistence failure with no dispatch, and unchanged disabled/protected-transport gates. These additions and the correction have NOT_RUN status. Earlier offline check counts above apply to the pre-correction snapshot only; no tests or CI were rerun after the latest instruction to write code and push.
