# P045 separate Try action for referenced topics

## Source and exact dependencies

- Real baseline: `96d727404a966cd3b3d2437c79449046beda560f`.
- That baseline already includes the calendar slice. This sixth slice applies after the unchanged image-preview, author-profile and reference-topic patches. Composite preimage tree: `9865cc8dc5fb7b6be2f7fc7cf5cd5449f3a3927e`. The member-report slice is independent; all five earlier output packages remain unchanged.
- Master P045 (1652–1655) names `onPostReferencePlay`; P011 (1516–1519) maps `pages/play/index` to the existing native gameplay experience.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- Detail JS 2476–2481 sends the accepted post's `sportTopicId` to `/pages/play/index?topicId=…`, with the existing comments action as the missing-ID fallback. WXML 149 binds this separately from reference details.
- `normalizeClubPost` at JS 405–424 derives the shared card variant from `refType` and forces completion for that projection. Exact helper blob `4977db342838e6349c9512ca1b3f8c3ea726cd50` and post-card WXML blob `3c4836ea314be738cee6fa2db1ca6e2bf912c188` show Try on named cover cards that are not completed activity references. Feed-play-card WXML blob `ad4542c21e332dcc1ce65f200f3027de076bddb3` makes Try independent of `isTopicTemplate`; that flag only changes the remix action.

This slice uses the existing club projection's `sportName` and `sportCover`; the Mini post-card comment explicitly notes that club posts provide `sportCover`. It does not invent or load a new media field.

## Behavior

The reference card now has a distinct localized Try button. It resolves only the current accepted `sportTopicId` into `PlaySessionScope.topic`, then opens the existing `SessionPlayRuntimeView` with `.journey(scope)`. The existing scope encodes only `topicId`. It never substitutes `refId`, an activity ID, post ID, author ID or current account.

This is actual gameplay navigation, not topic-details navigation, template remix, a new run manufactured locally, or `SessionTopicSelfPlayView` (the separate purchase flow). Missing/invalid/unsafe topic IDs retain the source's comments fallback when the exact club is available. Completed activity cards, missing names and missing covers do not gain Try. Ordinary covered topic cards remain eligible even when they are not marked remixable templates.

Club detail and home provide the existing `AppSession` host through an optional typed environment value. The host observes the same account/epoch and composition viewer revision used by the application. It supplies the real existing gameplay destination; no disabled replacement runtime, new transport, feature approval or backend write grant is created. Existing server availability and runtime read/write gates remain authoritative.

A large sheet provides Close and preserves the source feed's normal page state. Gameplay keeps its existing navigation and lifecycle. Guest users receive the existing play sign-in state plus the existing login flow. A successful sign-in changes the owner, retires the old selection and returns to the source; it never silently replays the guest's old action under the new account.

The route is bound to the exact unique accepted post, post content/version, club, read scope, host object, viewer revision and account/epoch. Opening rechecks the captured rendered route. The nested host observes the actual session, so account/role/epoch changes retire even nested gameplay or login. Refresh, source replacement/removal and host replacement also retire the route. Reopening has independent presentation identity.

## Existing integration limits

The community source service at this baseline is still the separately owned dormant `AppSession` composition. This slice does not change it or claim production end-to-end acceptance before its owner repairs that read path.

Gameplay uses the existing reviewed play-read approval and current server state. Unavailable play permissions, sign-in, locked content and other authoritative gates are preserved. No actual network gameplay, payment, answer submission, reward claim or run write was executed during development.

## Focused checks

Executed on the current computer:

- Fifteen narrow source/static assertions passed.
- Four exact Mini action cases plus six exact shared-helper visibility cases passed in Node. Navigation and comments were stubbed; no external action occurred.
- All four locally retained Mini helper/component sources match their exact Git blob SHA-1 values.
- Pinned Tree-sitter parsed six Swift files with zero recovery diagnostics.
- Whitespace, exact preimage patch application and complete after-file hash reconstruction passed.
- The five earlier sealed patch SHA-256 values were rechecked unchanged.

Authored: ten Core tests covering exact topic-versus-activity wire scope, missing/invalid IDs, remix flag independence, visibility, unique same-club accepted post, account/epoch/role revision/host/read retirement, post replacement, guest-to-login isolation and independent reopening.

NOT RUN: Swift compilation/typechecking, the ten Core tests, simulator/device/UI/VoiceOver or real backend acceptance. This computer has neither Swift nor Xcode. The source/static evidence is not native runtime acceptance.

## Registration and native acceptance

The adjacent registration fragment lists the two new sources, one test file and two-key English/Simplified Chinese localization fragment. Central integration owns registration; no PBX, aggregate catalog, CI, existing fixture, `AppSession`, gameplay implementation or earlier sealed package was edited.

Native acceptance should verify: named cover card → Try → actual gameplay for the exact topic; different result from View details; missing topic → existing comments; explicit close and nested back → source page; guest sign-in retires the old route; logout/role/account/refresh invalidation; large text and VoiceOver. Run `swift test --filter ClubPostPlayRouteTests` before native UI acceptance.
