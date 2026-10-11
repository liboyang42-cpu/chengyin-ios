# P045 post reference opens topic details

## Evidence and exact preimage

- Real baseline: `51d3e24de92427a777f8690f847cec39971b041a`.
- This fifth slice is applied after the sealed calendar, image-preview and author-profile slices; its composite preimage tree is `acdea4ecd5dcf2c7f5cddb1cb8eae72817ce5a5f`. Earlier slices are unchanged. The member-report slice is independent.
- Master P045 (lines 1652–1655): `onPostReference`. P059 (1708–1711) identifies the existing topic-detail surface.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- `pages/club/detail/index.js:2483–2487` opens `/pages/topic/index/index?id=` using the post's `sportTopicId`. If the post or that ID is absent it calls the existing comments action. `index.wxml:149` binds `playdetail` to this handler.
- Adjacent source comments explicitly separate detail from `onPostReferencePlay`; this patch does not conflate the two.

The original native tile had a conditional `onTopic` callback. Production `AppSession.clubCommunityContext` did not supply it, so the reference title was static. The existing governance context already carries the real `SessionTopicDetailView` destination.

## Implementation

Club home and club detail pass their existing `clubCustomerTopics` environment context. The reference title calls that existing destination using the exact positive safe `sportTopicId`; `refId` (which can name an activity/template), post ID and author ID are not substitutes. Both template references and activity result cards preserve this rule.

A missing, zero, negative or unsafe topic ID opens the already-existing comments destination when its exact club is available. A stale/removed/duplicate post cannot trigger either action. No new empty destination or default-disabled service is introduced. Explicit callback hosts remain supported.

Topic details open in a large native sheet with Close; source feed pagination stays mounted. The selected destination is fenced by the accepted post and version, club, account/guest epoch, read scope and composition viewer revision. Changing those values or removing the destination retires the selection; reopening creates a new presentation identity. Existing topic sign-in, configuration, error, privacy and action gates remain in the unchanged destination.

## Known source-feed dependency

As explicitly assigned to the composition owner, the pre-existing `AppSession` community source service is still fixed to `disabled.invalid`/`CommunityDormantHTTPTransport`. That prevents production from obtaining posts at this baseline. This patch completes the reference interaction for accepted posts with the existing composed topic destination; it does not claim production end-to-end acceptance or change that transport. No backend write, self-play launch, route permission or approval grant is added.

## Focused verification

Executed on the current computer:

- Twelve focused source/static assertions passed.
- Four exact Mini action cases (valid topic, missing ID, zero ID, absent post) passed with navigation/comments stubbed; details and play remain distinct.
- Pinned Tree-sitter parsed six changed/new Swift files with zero recovery diagnostics.
- Patch whitespace and complete composite-before-to-after hash reconstruction passed.

Eight Core tests are authored: exact IDs, missing/invalid ID comments, template/activity references, absent card/club, unique accepted post, account/epoch/scope/revision, post replacement/removal and guest/reopen behavior.

NOT RUN: Swift typechecking/compilation, the eight Core tests, simulator/device/UI/VoiceOver or real backend acceptance. Swift and Xcode are unavailable here. Source/static checks are not native tests.

## Integration and remaining adjacent action

Use the registration fragment for the two new sources and Core tests. Existing localized keys are reused. No PBX, aggregate catalog, CI, shared fixture, `AppSession`, governance/public-profile destination or topic-host implementation is modified.

The remaining directly observed adjacent gap is the separate template-card `onPostReferencePlay` button (Mini lines 2476–2481). It must use the actual self-play entry and its existing gates, not silently reuse topic-detail navigation. It is outside this fifth slice.
