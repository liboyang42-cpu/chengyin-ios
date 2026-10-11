# P108 own public profile → personal editor → refreshed public profile

## Delivered user chain

The ordinary Account → Public profile → About screen now exposes **Edit personal introduction** for the current account's own profile, with a live existing profile editor. It opens the existing full `ProfileEditView`. The user can locally edit/review, use the established save flow, or cancel/discard through the existing confirmation. Returning requests a new public-profile read. Failed reads use the existing `SocialReadScreen` retry. A draft is never copied into public data, and returning never means a save succeeded.

AccountView actually supplies its existing `profileEditCoordinator`, session revision and category reader. This is not a newly default-disabled mutation adapter or an unconnected fixture-only button. Existing editor configuration and save gates still apply. Other public-profile callers, guests and mismatched accounts receive no editor entry. No new endpoint, approval, credential or production factory is needed.

## Exact source and gap

The sole master P108 delegates the personal/public page to `cy-profile`. At pinned Mini ref `f859cd6e2618f618a53f5cd33949259828e86313`:

- `subpackageMember/components/cy/profile/index.wxml`, blob `a955ea313225063e484fa09e937e0c9899b14ecb`, lines 485–493 exposes `goEditIntro` only under `isSelf` in About.
- `index.js`, blob `99008cdb5c877c851f87f68fecac09f27c9eb46e`, line 1709 sends `goEditIntro` to `/pages/gerenziliao/gerenziliao`, even when the viewer has a merchant role. It does not send this personal introduction to shop decoration.
- `pageLifetimes.show`, lines 473–499 rechecks viewer/self identity and refreshes own data on return; other profiles use the public read path.

The native About section previously only displayed introduction/interests/images. The ordinary account had a separate editor route, but the source-backed direct About → editor → return/read chain was absent. This addition reuses that editor instead of reimplementing any of the previous six local-editor increments.

## Identity and navigation safety

The navigation context contains positive viewed member ID, Social reader instance/identity/role/epoch/presentation revision, existing coordinator instance and Profile editor identity/revision. Both current accounts must exactly match the viewed member. Configured readers/editors and the existing parent-current predicate are required. These are navigation checks, not new authorization.

Opening captures a unique ticket; repeated taps cannot replace it. The pushed destination verifies the ticket and full current context before creating the existing editor. A stale context shows an explicit expired-screen message with Close. The editor retains its own cancel/discard, readback and unknown-write rules unchanged.

A pop consumes only the matching presentation ticket. A delayed pop from a previous editor cannot close a newly opened editor. Only a same-context return replaces the public read's request UUID. An account/reader/coordinator/revision change cannot request a return refresh for its predecessor. Existing `SocialReadScreen` fences the actual read and retries; no endpoint is added or duplicated here. Normal backgrounding does not silently pop/discard an unsaved editor.

## Merge and verification

Git base: `41571fed5c27d4766d0bebb02e2800d798f1edbd`.

Beforeimages include the exact seventh author-refresh and eighth local-cover afterimages. AccountView and SocialPublicProfileView must be additively merged from these recorded preimages; retain any newer central additions. All nine earlier sealed packages remain byte-identical. `ProfileEditView`, its coordinator/service, AppSession, central project/localization and existing fixture repairs are untouched. The registration fragment contains only source/test registration, two translations and the dedicated DEBUG fixture launch route.

23 focused source checks, 14 source-mutation probes and 8 exact Mini synthetic cases pass. These are source checks and synthetic Mini execution, not Swift runtime verification. 17 Core, 8 app-unit and 6 UI tests are authored (31 total). The app-unit and UI fixture use the existing real editor against a synthetic shared profile store. No real user profile read/write, user photo or permission action occurred.

Swift, swiftc and xcodebuild are absent. Apple compilation, actual iOS push/pop, device UI tests and production save/read behavior are NOT_RUN. Source registration and the fragment must be integrated centrally before an Apple build.
