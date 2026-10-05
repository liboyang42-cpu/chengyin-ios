# Play experience: source-backed dormant runtime slice

## What this slice actually implements

- Classic node task dispatch and mode-2 scan → photo → merchant-verification state. Mode-2 photo evidence never locally marks a store completed
- Account/epoch/deployment namespace and exact activity-or-topic scope checks; frozen review and late-response rejection
- Branch `routeActionId` + `expectedRouteVersion`, structured 409 refresh, unresolved write lock, unchanged-readback lock and exact original-token replay. No client `outcomeCode`, target node or invented route decision
- Run start/pause/end clock, 7-day input bound, namespaced local storage interfaces, server save/read/clear, newer-snapshot merge and local/remote ended tombstones
- Legacy point-cost hints and progressive puzzle hints; ending empty-story state, exact server rewards, and completion-count leaderboard validation
- Team lead read + start/arrive/broadcast/unlock/settle/edit-time adapters; leader identity and all-arrived checks. JSON edit-time remains distinct from multipart other actions
- Advanced session/start/state/action/leaderboard adapters, source kind/action allowlist, exact payload unit conversions, role and turn commands, pending frozen idempotency replay and no inference of success from version advance
- PLAYER game projection, role/choice/text-evidence/hint/reveal commands, receipt identity validation and authoritative post-APPLIED projection readback
- Circle create/join/offers/card/record/answer adapters with offer and stage gates. Unknown writes reconcile only by source exact presence checks; no blind resend
- CLUB director domain projection/11-command/receipt adapter and coordinator. Dedicated director UI is the next isolated extension, not counted as present in this slice
- Native SwiftUI task/run/leader/reward/ending/ranking/player/circle/advanced views; local source stopwatch and stillness machines; device provider interfaces with dormant and injected synthetic implementations

## Source mapping

| Native file | Flutter source |
|---|---|
| PlayExperienceContracts / Service / Coordinator | data/api/play_api.dart; play_route_api.dart; feature/play/play_gap_logic.dart; play_session_page.dart; data/models/checkin_models.dart |
| PlayRunLifecycle | data/api/play_run_session_api.dart; data/models/play_run_session.dart; feature/play/play_run_session_store.dart |
| PlayAdvancedRuntime / View | data/api/advanced_play_api.dart; data/models/advanced_play.dart; feature/play/advanced/advanced_play_controller.dart; playkit_host.dart; fullscreen/playkit_fullscreen_payload.dart |
| PlayGameSessionRuntime / PlayerSessionView | data/api/game_session_api.dart; data/models/game_session.dart; feature/play/player_game_module_controller.dart; player_game_module_views.dart |
| PlayDirectorRuntime | data/api/game_session_api.dart; data/models/game_session.dart and club_director.dart |
| PlayCircleRuntime / CircleView | data/api/page_parity_api.dart; feature/play/circle_theme_play_page.dart; circle_write_readback.dart |
| PlayDeviceTasks / TaskViews | feature/play/stopwatch_game_page.dart; stillness_challenge_controller.dart; stillness_challenge_page.dart; app_sensor_challenge_placeholder.dart |
| Leader/ending/leaderboard | data/api/club_lead_api.dart; play_leaderboard_api.dart; data/models/club_lead.dart; play_ending.dart; play_leaderboard.dart |

## Integration

All files are additive. Existing PlaySessionView/read/basic-answer identity remains separate and unchanged. ActivityDetail gets a distinct runtime link when the AppSession can construct the current scoped coordinator. AppSession constructs PlayExperienceService with the empty capability default; real dispatch remains disabled. The injected synthetic `playExperience` module route exercises the actual decoders, request builders and coordinators using an in-memory transport only.

Core Observable coordinators require the Observation runtime: iOS 17/macOS 14. The app already targets iOS 17; the Swift Package test minimum must be macOS 14. There is no new third-party package.

Use one retained coordinator per namespace/account/activity-or-topic navigation context. Supply `PlayExperienceSession` from the existing session gate and `RegionalSessionStorageScope.service`, never from language. Every service capability remains opt-in; enabling any write requires backend/realm/role/UX acceptance. Enabling device/media requires its independent permission, consent and hardware/provider acceptance. Point spending, settlement and consent are not silently performed by navigation.

The currently injected completion and paused-run stores are memory fakes. Production must provide secure persistence with the exact namespace/account/scope key, and retain unresolved command journals across controller recreation/relaunch before enabling write capabilities. Advanced/player/director/circle pending state remains in their retained coordinator for this slice; durable pending-journal acceptance is still required. No tokens should be serialized, logged or copied into journals.

## Explicit remaining work / not parity claims

- Dedicated CLUB director UI and live prefab adapter are continuing in isolation. PrefabPreview is a separate local narrative identity, never live completion evidence
- Advanced adapter covers source action names; full per-kit widgets and payload-specific UI beyond draw/branch/coin/dice/daily-sign are not all migrated. Unsupported local-only kinds never dispatch invented actions
- Photo selection surface and upload/provider enablement are separate. Source media playback, filter camera and AR physical/provider behavior is not accepted; steps and audio-clip challenges stay unavailable where source lacks trustworthy native evidence
- Preference questionnaire/tiebreak/tag consent UI, journey-check dice/re-roll/settle UI, full operating-system summary/tag revocation UI, companion lines/eggs, NPC/free-explore story/card surfaces remain source work; endpoint presence alone does not count as a finished page
- Shanghai circle keyword-pair form and circle durable open-session recovery are still missing. No new session is blindly created after an ambiguous open
- Mode-2 exact merchant-scoped consent and dynamic verification-code display remain gated; no replacement proof or local completion
- Legacy hint and leader actions without a correlation receipt cannot be declared recovered by transport success or guessed reward. Unknown outcome locks are intentionally conservative
- Visual/VoiceOver/Dynamic Type/reduce-motion/device/build/runtime/backend acceptance is NOT_RUN, not passed
