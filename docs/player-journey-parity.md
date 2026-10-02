# Player journey and chapter story native slices

## Current authority and separate business destinations

Participation, saved participant contacts, order history and completed play history are separate business sources. Participation uses POST `api/registration/my-joined`, details POST `api/registration/info` with form `id`, and completed play history POST `api/play/my-completed` with no guessed payload. The normal account destination mounts all read implementations; grants stay off by default.

Source inspection (read-only, 2026-10-02): mini `subpackageMember/mycanyu/mycanyu.js:6–10,68–88,99–146,166–174`; `subpackageMember/components/scene-member-participation-detail/index.js:124–143,204–216,244–323,418–450`; profile `subpackageMember/components/cy/profile/index.js:970–990`; Flutter `participation_api.dart:22–61`, `play_api.dart:694–710`, `completed_play.dart`.

Current mini detail lines 315–323 supersede Flutter's obsolete three-day cancellation rule: pending orders or a not-started/in-progress order summary show self-service cancellation. Paid selection is `paymentStatus == 2`, preserving cancel-refund rather than cancel. Existing order lifecycle review/disabled adapters remain the cancellation outlet. Missing counts remain unknown rather than invented zero.

Participation preserves registrationId when entering gameplay and exposes the exact ticket-detail reader from that route. The current mini still forwards a needs-modification player ID to merchantapply, but backend tables prove that cross-link is unsafe: player info reads CmsRegistration; merchant info requires PROJECT_MANAGE and reads CmsRegistrationMerchant through ViewRegistrationMerchant. Native does not reproduce this numeric-ID conflation. Player modification, direct verification scan, contact support and the scope=my template action are not completed by this packet; scope=my requires api/template/myinfo, so the public template reader must not be substituted. No provider/contact information is fabricated and no live financial action is enabled.

## Chapter gameplay body

The chapter entry is mounted in the normal play runtime using the same current authorized nodes snapshot. It is not public topic detail. Source chapters use `name` and comma-separated `imgArr`; the first image is preserved as cover. Blocks retain source order, text variables, image/audio, voice, reveal, dream, mood/odd metadata, known thoughts, earned node notes, and an actual game host.

The renderer stops at the first incomplete, locked, unknown or cross-chapter node. It does not append the legacy description when blocks already exist, and never exposes an unearned thought name. This client spoiler guard is independent of server projection; backend `ApiPlayProgressController.java:806–838` now calls `ChapterBlockReadSupport.projectForPlayer`.

Variables are read from nodes `data.vars` and advanced session `vars`, merged by key as those accepted sources update, without empty maps erasing existing keys. Tokens follow current mini's bounded ASCII grammar; missing or empty values retain the authored token unless a nonempty fallback exists. Objects are not stringified into private/debug text. Authorized route readback supplies current earned thoughts.

The server's advanced `present` chooses presentation. Inline gameplay uses the real PlayKitInlineHost without a nested scrolling/navigation container. Other presentations navigate to the existing scoped node/game surface. No gameplay result, reward or completion is synthesized. Active inline games remain present during same-chapter authoritative completion readback.

Source proof: mini `pages/play/index.js:2934–3052,5317–5324,5382–5402,5462–5467`; `pages/play/utils/playkit-view.js:221–239`; Flutter `chapter_story_page.dart:545–584,600–637` and `checkin_models.dart:1239–1253`. Current mini block flow has advanced beyond Flutter's legacy description-only projection.

## Native presentation and lifetime

Native navigation/scrolling, Dynamic Type text and explicit disclosures replace Flutter scroll-triggered particles/reveal chrome. Back is standard until a game has unsent input, then explicit Back/Discard/Keep editing protects it. The shared PlayKit host owns frozen submission review and pending/unknown results. Leaving discards transient input and stops device work; it does not erase pending action recovery.

Audio uses explicit narration/guide/passage selection with one mounted playback host, rather than starting sound automatically. Images use injected bounded no-redirect media reads, with no origin grant by default. These are product presentation choices and must be visually/device-reviewed, not described as proven acceptance.

Thought auto-claim, bespoke mood/odd visual effects, chapter autoplay and media provider activation are not included. Existing gameplay network/device/recovery acceptance limits still apply.

## Evidence

PASS: project regeneration and structural catalog/reference checks; check_player_journey_screens.py; existing check_play_runtime_hosts.py, check_journey_content.py and check_platform_consumers.py.

AUTHORED: 7 participation/history domain tests and 8 chapter projection tests. These cover exact POST/body contracts, default-off dispatch, cancellation state precedence, invalid response IDs/shape, same-account stale 401, actual cover wire key, bounded variable substitution, incomplete/unknown/locked barriers, earned note/thought projection and mixed media blocks.

NOT_RUN: Swift tests, Apple compile, simulator, visual/interaction screenshots, VoiceOver/Dynamic Type runtime, hardware and live services. The cloud executor has no Swift/Xcode toolchain. No real accounts, backend calls or mutations were performed.

### Player/merchant ID-domain review

Mini participation detail `index.js:469–472` forwards the player id into `pages/topic/merchantapply?mode=1`. The target's `index.js:244–246` then calls POST api/registration/merchant/info. Backend `ApiRegistrationController.java:403–425` reads CmsRegistration and checks player ownership. `ApiRegistrationMerchantController.java:181–202` requires PROJECT_MANAGE and `MerchantRegistrationDetailReadServiceImpl.java:55–66` reads ViewRegistrationMerchant/CmsRegistrationMerchant. These are distinct ID domains, and the current CmsRegistration schema has no displayStatus field. A matching number or stale UI condition cannot establish the required relation. No approved player-edit contract was found; this is a source-contract gap, not an external-authentication blocker.
