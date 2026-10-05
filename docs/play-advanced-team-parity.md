# Advanced team controls and distinct game leaderboard

Source-only local parity slice. Depends on accepted CARD tree a64adcf7372d9496fc93e640ba2d421e01b8c2c7. No mini/backend writes, capability activation, new publisher or remote CI.

## Current contract, not historical aliases

chengyin@4b0248cbc00e9e943eba8b43819afb623a87b942:
- AdvancedGameRuntimeServiceImpl publicMultiplayer returns members, completedUnitIds, turnIndex, leaderMemberId and myRole. Only the leader receives roleAssignments.
- publicRuntimeConfig includes roles (id/label/min/max) only for the leader. assignment is AUTO/LEADER, not MANUAL. turnOrder/next role is intentionally not public. The UI must not infer whose turn it is.
- ASSIGN_ROLE requires team ownership, LEADER assignment, actual leader, active target member, existing role and remaining capacity. COMPLETE_UNIT requires the actor's role to match the server's current turn and a unique unitId.
- Advanced leaderboard uses /api/play/advanced/leaderboard with activityId/topicId/nodeId. Server chooses ACTIVITY/TOPIC scope and returns only completed runs; metric is ELAPSED_TIME/SCORE/COMPLETED_UNITS. This is not /api/play/leaderboard.

## Connected source

PlayAdvancedView now hosts team controls and a separate advanced leaderboard section. Team projection is ownerType=2, member/role bounded, ignores roleAssignments/roles for nonleaders even if unexpectedly included. Frozen reviews bind owner, session, node, version and screen lifetime. Duplicate taps cannot dispatch while submitting; no local score or completion mutation. Required turn count and deadline are read back; exact eligibility remains server owned. Unknown writes retain existing recovery/read-before-exact-retry semantics.

Leaderboard state is independent (loading/empty/failure/retry), clears on read start and state changes, and binds owner/session/version/metric plus surface and request generations. Leaving/backgrounding invalidates pending review/read lifetime. Rendering never displays backend owner IDs. A late submitted write may still update its existing owner-bound coordinator from an authoritative response; it never navigates or applies optimistic progress.

## Checks and limits

17 new Core XCTest methods cover leader/nonleader data, auto roles, capacity, missing owner type, frozen review/exit/version, duplicate clicks, wire payload, unknown exact retry, expiry, distinct leaderboard query, empty/failure, and late exit/account responses. They are authored but NOT_RUN because Swift/Xcode is absent.

Python source/tooling, deterministic scaffold, parser and clean replay evidence live in the packet. These do not establish compilation, camera/device, simulator UI, rendered bilingual/accessibility, real team permission changes or backend acceptance. The 25 affected merchant seed combinations are a source impact set, not 25 completed end-to-end tests.

Review r2: current-session leaderboard401 follows coordinator failure, closes team interactions and clears sensitive projections; old epoch late401 is discarded. Repeated active notifications are idempotent; background end invalidates pending reads before foreground reload. Dedicated XCTest regressions authored, UNRUN.

Inline parity: ChapterStoryGameHost mounts PlayAdvancedInlineTeamHost outside the optional kit selection, so pure multiplayer/board combinations also expose shared mechanics. Both normal hosts use distinct surface IDs; an old inline disappearance cannot cancel a newer fallback screen. No kit is invented for multiplayer.

Review r3: retained offscreen hosts cannot reclaim the surface on foreground; both hosts gate active handling on visibility. Obsolete owner/surface reviews are silently discarded instead of setting an error on the new host.
