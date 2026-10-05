# Play director and live prefab extension

This is an additive extension to the first Play slice. It has not been accepted on an Apple runtime or real backend/device.

## CLUB director

`PlayDirectorView(model:)` consumes the source CLUB projection for a concrete activity ID. It exposes PREPARE, START, FINISH, ASSIGN_ROLES, TAKEOVER_ROLE, BROADCAST, UNLOCK_CHAPTER, SET_LEADERBOARD_VISIBILITY, CLUB_STATION_PAUSE, CLUB_STATION_RESUME and CLUB_REJECT_SUBMISSION only when the server projection supplies the action. START also requires the source readiness conjunction. Candidate team/member/role/station/chapter/submission IDs are taken from the current projection; role takeover requires a confirmed source role and an unassigned target in the same team. Each command is reviewed, freezes revision/request ID/payload, and remains locked after unknown outcomes. Terminal APPLIED receipts require fresh, matching-session projection readback.

The club cannot approve merchant evidence. Its submission surface contains source status/reason metadata and only the source rejection operation. No player evidence media or private evidence body is exposed. Recap copy uses `PlayDirectorRecap.normalizeExport`, not raw JSON: exact schemas, IDs, timestamps, count fields, duplicate checks and the source privacy allowlist are validated before copying. Extra phone/memberId/evidence fields are stripped.

New UI entry: `PlayDirectorView(model: PlayDirectorCoordinator)`.
Factory: `PlayDirectorCoordinator(activityID: Int, service: PlayExperienceService, currentSession: () -> PlayExperienceSession?)`.
Production service requires separate `.directorCommands` acceptance; the default remains empty. A read-only CLUB projection is not permission to dispatch commands.

## Live prefab bridge, separate from preview

`PlayPrefabRuntimeCoordinator(scope:service:provider:store:currentSession:)` reuses `PrefabPreviewState` and source scene IDs, but it NEVER reads `PrefabPreviewStore`. `PlayPrefabRuntimeStore(storage:)` accepts the existing `TemplateAuthoringStorage` interface and writes only `prefab-runtime.v1.<namespaced-owner-and-exact-scope>`. Its owner binds account and deployment namespace. `PlayPrefabRuntimeRecord` strips supplied preview photos/avatar/synced flags; load always discards the locally saved synced flag until a fresh source read confirms it. Narrative edits cannot mutate these server/device facts.

The exact source live chain is implemented:
1. Read `/api/play/nodes` with exactly activityId or topicId and use the actual first node
2. Require the source prefab topic identity and playable/current registration state; source prefab has no branch-token forwarding, so branch runtime is blocked rather than guessed
3. Explicit hall action obtains injected GCJ-02 location, submits `/api/play/arrive`, validates returned node ID, then captures a photo through the injected provider
4. Explicit capture/upload uses multipart `/api/common/uploadOSS` with field `file`, at most 10 MiB, and a top-level returned HTTPS `url`. No fake local file path is sent as an image URL
5. At flow, submit that uploaded hall URL to `/api/play/photo`; only a fresh first-node read reporting done or a nonempty source imgUrl marks synced

Separate pending arrival/photo/upload markers are saved before dispatch. Unchanged reads do not clear them. An ambiguous upload has no source receipt or lookup contract, so it remains blocked rather than re-uploading or inventing an idempotency key. No preview URL, local elapsed time, local story choice or random die proves server completion.

App entry: `PlayPrefabRuntimeView(model:dice:)`. It has the source register/boot/walk/hall/birth/dream/learning/career/work/flow interactions, using the shared story-state engine and injected dice. Boot uses the exact “hello world”, ten-second window and six-second precision bonus; multi-character paste cannot bypass source key entry. Walk preserves the source 50/74 checkpoints on restoration. Birth/dream timing, quiz answers, teacher checks/timeouts, source jobs and boss checks are mapped from prefab_life_page.dart. The native timed-button alternative supports assistive input and cancels on backgrounding; it is local story interaction, never motion proof. Original delayed visual transitions are simplified and are not claimed as pixel parity.

The source ending descriptions are shown as an explicit static story guide, not an inferred personal ending, reward or live population statistic. Map sticker x/y values are source board-space coordinates, never GPS.

## Stillness correction

`PlayMotionSampleProviding.samples(context:)` and `PlayStillnessCoordinator` provide a genuine continuous injectable stream. The native challenge consumes samples until authoritative local sensor completion or failure; it does not require users to manually tap one sample at a time. The pure five-sample/250ms-gap state machine is retained. The default provider is disabled and never requests OS permissions. The earlier single-sample diagnostic view is replaced by `PlayStillnessStreamView`.

## Existing-slice hardening included

- Unknown circle creation cannot be duplicated by refreshing offers; a known returned session ID is used for card recovery
- Advanced business rejection has a source authoritative refresh path; no invented restart after unknown start
- Unknown legacy/progressive hints remain scoped across same-account relogin and clear only on returned hint facts
- Branch replay is offered only when the original token/payload and current branch identity/version are eligible
- Topic nodes reads reject a returned different topic ID
- Local coordinator phases have English/Chinese labels

## Remaining acceptance and source boundaries

- The source has 36 WebP assets in `app-audit/assets/prefab`; no license/provenance metadata was found in the audit snapshot. They are not copied into the public native tree pending redistribution confirmation. Text/timing interaction is implemented; artwork/map collage and source decorative/audio fidelity are not accepted
- Hardware GPS/camera/motion, upload provider, raw media playback, real accounts/backend and permissions are NOT_RUN. Synthetic providers/transport are the only ones used
- Production pending journals for all classic/advanced/player/director/circle operations must be secure and persistent before activation; the first slice keeps retained coordinators/memory test stores. The prefab runtime journal itself is injectable through the existing secure storage abstraction
- Preference/tiebreak/tag UI, journey-check dice API UI, operating-system summary UI, full media/filter/AR and per-kit forms beyond migrated surfaces remain explicitly open in the larger play_all audit. This extension does not claim the whole original gameplay area is finished
- Shared AppSession/navigation/catalog/project files must only be changed in the parent-granted integration window. No remote publication is performed by this worker

## Checks

Authored extension tests cover director readiness/role transfer/receipt identities, privacy-filtered recap, upload contract/size/default-off gate, preview/runtime separation, namespace isolation, unknown photo readback, boot timing/paste, walk restore, interrupted hold, source quiz/career/dream mechanics, unknown circle-open locking and continuous stillness. Swift/Xcode/XCTest/device runs are NOT_RUN; Python source checks and Tree-sitter parsing are supplementary only.

## Preference and operating-summary continuation

The extension also includes PlayPreferenceRuntime/PlayPreferenceViews and PlayOperatingSummary. These map play_api.dart's source preference steps (`single`/`discard`), exact option IDs, inherited-tag reuse, server tiebreaks, evaluation/progress, and confirm/correct tag operations. The routeActionId is retained through a source-requested tiebreak; the client never computes outcomeCode or targetNodeId. Final completion is re-read from nodes. Unknown branch submissions permit only the frozen correlated request, while uncorrelated unknown tag writes remain locked pending matching readback. Tag confirmation/correction requires the source recipient/purpose disclosure and source allowed tag values.

The private operating-summary view shows result cards, tags, known map-anchor names, and seven/thirty-day actions. Tag revocation requires explicit review, an ID-matching REVOKED receipt and a summary readback that no longer contains an active tag. Missing coordinates are not silently converted to zero.

`SessionPlayRuntimeView` observes AppSession directly and uses its sessionRevision as the view identity. Integrators should replace the first slice's raw activity runtime destination with this observed wrapper, then insert the small AppSession factory snippet in `docs/app-session-play-extension.snippet.swift.txt` without replacing other workers' additions. Every supplied service remains capability-empty and hardware providers remain dormant. Add DEBUG module routes `playDirector`, `playPrefab`, and `playPrefabBoot` to the synthetic extension host, preserving all existing fixture cases and six UI shards.
