# CY-HANDOFF: IOS — I09 team return-read ownership

2026-10-15 UTC. **SOURCE_DELIVERED_UNVERIFIED; tests, build, App and CI NOT_RUN.**

## Baseline, scope and ownership

- Repository/branch: `liboyang42-cpu/chengyin-ios`, `migration/native-ios`.
- Exact published parent: `42d69919922ee5c07b97ded9a4a69741761526d7`, tree `140b290255c6f9bf2b46292a5e4d85ca7c1d542a`. All 5,083 snapshot file blobs were matched to that public tree before editing. This isolated candidate preserves the existing branch and cumulative work; the publication coordinator records its resulting commit separately.
- Protocol: `CY-COORD-20261015-v1`; I09, existing team-read contract / BK-EXISTING. B04 / BK-SCHEDULE was rechecked for the adjacent scheduling scope; this repair changes no scheduling contract.
- Exact changed paths: `App/TeamComponents.swift`, `App/TeamHomeView.swift`, `App/TeamCreateView.swift`, `Tests/AppUnitTests/TeamNoticePresentationTests.swift`, `docs/ios-current-status.md`, and this document. The existing registered test file contains the new `TeamScreenLifecycleTests` class; no project registration or localization change is needed.
- No backend source or shared control log is changed. Capabilities remain OFF, including normal release team-read lease issuance and all live team writes. No merge, deployment, signing, provider, payment or external communication.

## Fresh shared-backend evidence

The control branch was read at `6e7cd6d9666039aa49293ca71bc27e936ab4843c`: [IOS_START_PROMPT](https://github.com/liboyang42-cpu/hengyin/blob/6e7cd6d9666039aa49293ca71bc27e936ab4843c/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md), [IOS_HANDOFF](https://github.com/liboyang42-cpu/hengyin/blob/6e7cd6d9666039aa49293ca71bc27e936ab4843c/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/6e7cd6d9666039aa49293ca71bc27e936ab4843c/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md), OWNERSHIP, COORDINATION, TASKS and LONGRUN_CURRENT.

- The frozen candidate remains `1e403b135206844a34219753a36e2dee39c7dd59`; the control's latest recorded rolling source checkpoint is `7e5882addb7269373b2b95daa0a4ceeb4485fd10` / PR44. The latter is a recorded source checkpoint, not a verified deployed package or a claim about the moving branch head.
- [ApiPlayTeamController.java at that checkpoint](https://github.com/liboyang42-cpu/hengyin/blob/7e5882addb7269373b2b95daa0a4ceeb4485fd10/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiPlayTeamController.java), blob `c55319d052398b92e971d8cc07adb0a68e2fd468`, still exposes POST `/api/team/my` and POST `/api/team/info` in the existing AjaxResult envelope. The native bodies remain `{}` and either `{teamId}` or `{inviteCode}`.
- [PlayTeamServiceImpl.java](https://github.com/liboyang42-cpu/hengyin/blob/7e5882addb7269373b2b95daa0a4ceeb4485fd10/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/PlayTeamServiceImpl.java), blob `342120fe1e42e75760a481ed52c35cac07dbe399`, retains member-owned list reads, active membership for ID detail and invitation validity checks. Those two blobs match the earlier evidence recorded in [team-module](team-module.md). This client lifecycle repair needs no new DTO, pagination, action, permission, requestId or receipt API: **NO_API_CHANGE**.
- The [frozen B04 contract](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/docs/verification/mini-bug-arch-20261015/B04/CLAUDE_CONTRACT.md) and current `ClubEventOpsServiceImpl.java` were reread. The latter blob `3d1e4035f62351129a9700ddcb8ac037bbcc4108` matches frozen and rolling checkpoints: nullable common Shanghai HH:mm, retained-date times unchanged, added dates use the chosen time, update expectedVersion/CAS, and protected signup/waitlist/settlement history remain authoritative. The prior [I09 time repair](ios-i09-series-time-handoff.md) is unchanged.
- Current control records TEST_DEPLOYED=NO. Runtime HTTP, package/database binding, real account/device readback, merge and deployment are unverified. Historical backend test reports do not validate this native candidate. No CI was queried, started or rerun.

## Source-confirmed failure in the ordinary route

The normal route is Account → My teams (`AccountView`, `SessionTeamHomeView`, `AppSession.makeTeamCoordinator`) → retained `TeamHomeView` / `TeamScreenModel`. The factory still needs its existing explicitly supplied, revocable read lease; this is not a claim that release-default access is enabled.

Sanitized reproduction, traced through source rather than executed:

1. Read the owned list, then tap Refresh. The button starts an unstructured Task using `model.run { await coordinator.loadTeams() }`.
2. While read A is suspended, open invitation entry or an existing team. Both navigation links remain available. Disappearance calls `model.leave()`.
3. `TeamCoordinator.leaveScreen()` correctly invalidates its generation, clears loading/review, and retains any unresolved write journal. But the old screen wrapper kept `running=true` until A's await returned.
4. Go Back before A completes. The view's new `.task` requests read B, but the wrapper's `guard !running` drops it. No B request is made.
5. A later completes and the coordinator correctly discards its retired result. The wrapper then sets running=false, with no fresh return read scheduled. Cached rows remain stale; on an interrupted first load, an empty list can be presented as “No teams yet” even though no current successful read finished.
6. Only a later explicit Refresh recovers. Expected: returning can start B immediately, A cannot overwrite B or release B's loading/action guard, and B's own success or error controls the presentation.

The defect is a dropped fresh read, not proof of an old-response overwrite or an unauthorized team mutation. The inspected native team/player routes use one-shot/manual reads, not an automatic team polling loop; this repair adds no polling.

## Repair and complete recovery path

`TeamScreenModel` now assigns an independent UUID to each admitted run. Leaving retires that screen run and immediately releases its presentation-level `running` flag, while still invoking the unchanged coordinator leave operation. Only the run whose UUID remains current can clear loading on completion. An already-canceled caller cannot start a new run.

Every unstructured Refresh, Check outcome and Confirm gesture captures a presentation-generation permit synchronously before creating its Task. Leaving also retires that permit, so a previously queued Task cannot start a read or command after departure, even if it has not reached `run` yet or the screen has returned. Structured `.task` / refreshable entry retains its cancellation check. Confirmation dismisses only if its run completed while still current, and a queued confirmation first checks that its original review is still selected.

This supports both completion orders: A before B leaves B loading, and B before A preserves B's result or error. A fresh failure remains visible and permits an explicit retry; late success from A cannot erase that failure. Duplicate work within a live run remains suppressed, including after two rapid leave/return cycles.

The shared wrapper also serves ID/invitation detail, membership-required/read-only post-join continuation, creation-context reads and the review sheet. Their existing code paths are reused. Coordinator session/generation checks, current permission/registration preflight, immutable review consumption, retirement of acknowledged membership, and durable unknown-operation locks are unchanged. Leaving during preflight cannot dispatch the old review; leaving after dispatch keeps UNKNOWN and cannot resubmit it. A return list/detail read is never evidence that an earlier write succeeded.

## Authored acceptance and execution limits

Thirteen new AppUnit methods exercise the real wrapper with the existing synthetic coordinator/service and controlled suspended continuations:

1. Empty/cached owned list, immediate re-entry and both A/B completion orders.
2. Old failure while the fresh read remains suspended.
3. Current failure, later retired success, and explicit successful retry.
4. Detail, membership-required read-only continuation and creation-context re-entry.
5. Two rapid departures and three out-of-order reads.
6. Duplicate suppression within the current run, followed by a new allowed run.
7. Canceled caller rejected, then a new uncanceled caller admitted.
8. Account change on return, with old-account completion discarded.
9. Departure during write preflight, fresh detail recovery and zero submissions.
10. Departure after dispatch, successful return read, late write result, retained pending identity and no replay.
11. Queued Refresh before departure cannot start afterward or release a fresh loading guard.
12. Queued Confirm cannot consume or dismiss the new review after returning.
13. Queued outcome check cannot clear UNKNOWN; a new explicit, correlated check can still recover through the existing synthetic receipt path.

All fixtures are synthetic. These are authored source, **NOT_RUN**. Source inspection and file/patch identity checks are the only evidence for this delivery. No tests, source-contract suite, lint, typecheck, build, simulator, app, UI automation or CI was executed. Existing composition lease/401 tests and coordinator tests were inspected, not rerun.

Remaining acceptance: approved Apple-toolchain compilation/AppUnit execution; real hosted navigation through Refresh → invitation → Back with delayed read/error and account/lease changes; VoiceOver and device lifecycle checks; authorized backend deployment and independent real-account reads. This bounded I09 repair does not close the whole card or establish performance. The earlier time fix, full B04 protected-occurrence business acceptance, and player allowed-actions readback retain their separate evidence and limits.
