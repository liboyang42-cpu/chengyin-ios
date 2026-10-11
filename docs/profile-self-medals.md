# P004/P108 own achievement medals

## Normal user flow

Account → Public profile → Achievements now reads the current owner's earned medals through the already configured `session.profileReader`. City and achievement rows appear together, with a count explicitly labelled **Medals loaded**. The user can refresh, retry a failure or partial response, and open the existing full badge wall. Existing badge-wall list/layout/detail behavior is reused, not rebuilt.

Other members and guests continue to see public statistics only. They cannot make an own-account medal read through this section, even if a caller mistakenly passes a private reader. The normal AccountView injection is included; no new operation grant or default-disabled write adapter exists.

## Exact Mini source

The sole master P004 and P108 delegate to `cy-profile`. Approved ref: `f859cd6e2618f618a53f5cd33949259828e86313`.

- `subpackageMember/components/cy/profile/index.js`, blob `99008cdb5c877c851f87f68fecac09f27c9eb46e`: `loadMedals` (1000–1026) reads `/api/medal/wall`; malformed/business/auth failures explicitly mark an error instead of saying the user has no medals. `reloadMedals` (1629) repeats the read. `goWall` (1740) navigates to the existing badge wall.
- `index.wxml`, blob `a955ea313225063e484fa09e937e0c9899b14ecb`: the Achievements self-only block (266–360) contains earned medal rows, empty/error/retry and the full-wall entry. The other-profile branch displays public aggregate counts.

Native already had a standalone badge wall and an approved `ProfileReading.profileBadges()` contract, but its own public-profile Achievements tab used the same public counts as visitors. The inline own-medal read/recovery/full-wall flow was absent.

## Existing contracts and differences

No service endpoint, authentication scope, privacy grant or runtime configuration is added. `ProfileService.badgeWall` still performs its established composite identity-wall + medal-wall read. This differs from Mini's medal-only call. A primary identity-wall failure can therefore fail this native read; a partial medal failure is never treated as an empty medal list. The existing model has no source total, so the UI labels the returned row count rather than inventing a total.

The new inline rows are text/system-symbol based and do not load medal images. The existing full wall receives no new media reader. This increment makes no new image-preview availability claim.

## Context and recovery

A read context binds positive viewed member ID, public-reader object, current public viewer identity/role/epoch/presentation revision, private-reader object and exact `ProfileReadIdentity`. Both current identities must match the viewed member and both readers must be configured. The parent-current predicate is checked before and after each read. Duplicate in-flight reads are suppressed.

A complete empty result replaces old medals. A generic or partial refresh failure keeps previously loaded rows with an explicit stale-data note and retry. Authentication failure clears old rows. Cancellation, changed identity/revision, a replaced reader or a retired presentation cannot publish a late result. Suspension keeps scoped rows only to preserve a pushed navigation link; mismatched contexts never render them.

The existing full wall is wrapped in a badge-only `ProfileSelfMedalsScopedReader`. It checks its captured owner both before dispatch and after success. A queued child task cannot read a replacement account before the old parent rerenders. Unrelated ProfileReading operations are not forwarded. The wrapper is retained as view state, avoiding reader replacement on body recomputation.

## Integration and verification

Base `41571fed5c27d4766d0bebb02e2800d798f1edbd`, with exact seventh → eighth → tenth afterimages overlaid. Shared AccountView and SocialPublicProfileView preimages are recorded. Merge their changes additively and preserve newer central edits. First-six editor code and central body split, AppSession, service contracts, existing badge-wall implementation, project/localization registration and all previous ten archives remain unchanged.

The package contains 12 changed paths, exact before/after images, reversible patch, manifests and source evidence. Registration/localization/DEBUG launch changes are delivered only as a fragment. 25 new source assertions, 72 dependency assertions, 16 source-mutation probes and 7 exact Mini synthetic cases pass. These are not Swift runtime tests.

20 Core + 7 app-unit + 6 UI tests are authored (33 total). Swift, swiftc and xcodebuild are absent: Apple compilation, actual iOS navigation, all native tests and real-account behavior are NOT_RUN. No real user profile/medal request, mutation, photo operation or permission action occurred.
