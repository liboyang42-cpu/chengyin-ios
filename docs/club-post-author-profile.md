# P045 post author public profile

## Exact scope and preimage

This slice implements the missing `onPostUser` action, not a replacement public-profile page.

- Real native base: `51d3e24de92427a777f8690f847cec39971b041a`.
- Composite preimage: base plus the sealed calendar and post-image-preview patches, tree `cd18ac50747907e4ee9a6d246e938a927e952749`.
- Calendar is preserved in `ClubDetailView`; image preview and its read scope are preserved in `ClubCommunityViews`. Neither earlier patch is rewritten. The member-report patch is not a dependency.
- Master document: P045 `onPostUser`, lines 1652–1655; P108 public profile, lines 1904–1907.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- `pages/club/detail/index.js:2490–2493`: navigate to public user info using the event's member ID. Line 412 projects `authorMemberId` to that event member ID. `index.wxml:148` binds the post-card user event.

Before this slice, a callback slot existed but `AppSession.clubCommunityContext` never supplied it. Authors therefore had no native default route even when a host supplied accepted posts.

## Implemented interaction

The club detail community entry and club home community feed carry the existing `ClubEnrollmentProfileContext`. An accepted post's author name opens the existing `SocialPublicProfileView` with the exact positive, safe `authorMemberId`. Post IDs, generic `memberId`, names and the viewer's account are never substitutes. Existing explicit callback hosts remain compatible.

A large native sheet has an explicit close action and keeps the underlying feed mounted, avoiding a new navigation push that would reset its existing page task. Closing and reopening creates independent presentation identity. The exact accepted post, club, viewer account/epoch, read scope, profile role/revision/reader identity and square scope/reader identity fence opening and presentation. Refresh, removal, a replaced post or a changed reader/session retires the route. Public-profile privacy, errors, sign-in and existing action permissions remain owned by the unchanged destination.

No URL is guessed, new transport invented or backend write performed. No write grant is expanded.

## Existing production dependency

The route implementation is complete for an accepted post and configured existing public-profile reader. It is **not claimed production-usable end to end** at this baseline: `AppSession.swift:124` fixes the community service to `disabled.invalid` and `CommunityDormantHTTPTransport`, whose `send` always throws `APIError.notConfigured`. Thus production cannot currently obtain the source posts. The composition/transport owner is handling this pre-existing blocker; this patch intentionally leaves `AppSession`, transport policy and service contracts unchanged.

The existing authorized composition is `AppSession` initialization at lines 2789–2822: reviewed regional API configuration, storage scope and `compositionTransport`, which already construct `SocialAccountService`, `ClubService` and `ClubGovernanceService`. `runtimeHTTPTransport` is that same guarded transport, not an independent URLSession. `ClubCommunityService(baseURL:transport:)` already supports reads while setting `allowsInjectedWrites=false`. Its exact read cases and session checks are in `Core/ClubCommunityContracts.swift:67–76` and `Core/ClubCommunityService.swift:22–54`. Native list fields currently include `clubId/pageNum/pageSize`; Mini detail list at lines 1574–1585 uses `id/clubId` and expects an array. The owner must retain the reviewed route allowlist and confirm the accepted current contract rather than assume a base URL is permission.

## Focused verification

Executed on the current computer:

- 14 narrow source/static assertions passed.
- Four exact Mini `onPostUser` cases plus its author projection passed with navigation stubbed; no external navigation or profile request occurred.
- Pinned Tree-sitter parsed all six changed/new Swift files with zero recovery diagnostics.
- `git diff --check` and reconstruction of the complete after-files from the composite before-files passed.

Authored: eight Core tests covering exact IDs, invalid IDs, same-club/unique accepted posts, self and guest public contexts, stale viewer, role/reader/read-scope replacement, changed/removed post and reopen identity.

NOT RUN: Swift compile/typecheck, the eight Core tests, simulator/device/UI/VoiceOver execution or real backend acceptance. Swift and Xcode are unavailable on this computer; source and syntax checks do not replace native tests.

## Integration and next missing action

The registration fragment lists only new sources and tests. Existing localization keys are reused. No PBX, aggregate catalog, CI, fixture host, governance view or public-profile view is changed.

Next observed P045 gap: `onPostReference` and `onPostReferencePlay` use the post's `sportTopicId` to open topic details and self-play (Mini lines 2476–2487). The native optional `onTopic` callback is also absent from production composition, and no distinct self-play action exists. This is outside the current patch.
