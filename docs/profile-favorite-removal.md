# P109 saved-post removal: contract and injectable chain

## Current source-only continuation

Status: **SOURCE-ONLY / NOT ENABLED**. [Profile and Settings favorites flow](ios-profile-settings-favorites-flow.md) is the current continuation: the normal Account/Settings routes now propagate an optional exact revocable controller, and the complete supported saved-post flow includes review/cancel, verified result, missing-row read-only UNKNOWN recovery, scoped session expiry, and one refresh on Done/Close/swipe.

The selector remains default-empty with no production grant. Saved TOPIC removal is NOT IMPLEMENTED. All tests/builds/App/device/CI for that continuation are NOT_RUN. Its dedicated Settings favorites source, tests and resource are registered; the historical evidence below describes the earlier injectable adapter only and does not become current runtime evidence.

## Verified source

The sole master P109 lists `postUnlike` on `pages/mylike/mylike`. All private source evidence is pinned to `f859cd6e2618f618a53f5cd33949259828e86313`:

- Mini `pages/mylike/mylike.js`, blob `ae7bdee4a6189bf8bb16d00f46a7a16fa728522b`: `postUnlike` posts `id`, `bookmark: 0`, `request_id` to `/api/creativesquare/bookmark`. It blocks concurrent requests per ID and removes the row by ID only on code 200.
- `ApiCreativeSquareController.java`, blob `a1f092982b1e783a8db3c747873d37188d829b3f`, lines 1012–1042: validates the authenticated principal, positive post ID, explicit 0/1 state and request ID. bookmark=0 calls `communityPostService.unact(memberId, postId, "BOOKMARK", request_id)`.
- The same controller's `/info` (955–1005) checks exact target visibility then calls `enrichCreativeSquareList`. Own bookmark enrichment (175–209) explicitly initializes `isBookmarked` to 0 and sets 1 for currently bookmarked IDs.
- `CommunityPostServiceImpl.java`, blob `23970f7bb136362ee7f6c5c2e642226a77a07ed8`, lines 429–442: transactional unact requires principal/request ID, deletes the member action, records the command receipt and returns detail.

The endpoint internally uses the community action service; the native source collection remains legacy-qualified. This package uses the exact legacy compatibility endpoint, never relabels the collection's IDs as community-v1 routes, and never uses `/api/topic/like`, whose toggle semantics are different. Absence from a first page is not removal evidence.

Native adds explicit review, stricter readback and durable unknown handling. It intentionally does not copy Mini's willingness to release the in-flight flag after an ambiguous response and allow another request.

## Safety and lifecycle

An immutable approval binds exact endpoint base URL, namespace, account, identity/role/epoch, post ID, expiry and precisely two paths (`api/creativesquare/info`, `api/creativesquare/bookmark`). Runtime use additionally requires CN market, current collection scope, a legacy post, exactly one matching approval and an unchanged ephemeral session/token. A base URL, ordinary reader or member-follow grant cannot authorize this feature.

Review is consumed before the first confirmation await. Fresh target state and the durable pending record are checked again immediately before dispatch. `request_id` is the immutable review UUID. A pending record is written before send. The record owner excludes ephemeral login epoch/token, so reopening or signing back into the same account does not unlock an uncertain write. No token or post body is persisted in the journal.

Known removal requires explicit `isBookmarked == 0` on the exact ID through authenticated `/info`. Missing state, a wrong ID, malformed acknowledgement, timeout, cancellation after dispatch or failed readback never produces success. The record is cleared only after successful exact readback. Unknown reconciliation performs only a detail read; it never invokes confirm or resends the write. All non-successful responses after dispatch conservatively remain uncertain.

Each UI presentation has a UUID; an old sheet dismissal cannot retire a newer review. Scope/background/disappearance retire pending presentation state. A late callback cannot write before dispatch or publish after retirement; a dispatched uncertain write retains its journal lock. Done is delivered once, only for the current presentation's known removal, then invokes the existing collection refresh. Existing topic tabs, detail generation, list pagination and gallery entry stay intact.

## Required production integration

Only after an independent permission review, central composition must supply:

1. A `ProfileFavoriteRemovalApproval` for the exact CN deployment, local namespace, authenticated identity, post ID and expiry, with only the two audited paths.
2. The existing ephemeral current session/token provider, bound to the same AccountCollection reader scope.
3. The existing approved no-redirect transport and durable `OperationPendingJournal`.
4. The resulting optional controller through `AccountCollectionAccountLinks.favoriteRemoval`; its propagation into the post list is included here.

No production grant is manufactured in the new code, fixture or fragment. Central registration and localization merging are separate from enabling production authority.

## Verification and package

Base: `41571fed5c27d4766d0bebb02e2800d798f1edbd`. This increment is independent of all eight earlier profile packages; none were overlaid or modified. Only 11 allowed paths changed, with exact before/after images, forward/reverse patch replay, checksums and protected central files verified.

28 focused source checks and 6 exact Mini synthetic scenarios pass. 17 static mutation probes test rejection of removed source guards. These are source-seam checks, not Swift execution. 20 Core + 7 app-unit + 5 UI tests are authored (32 total), using synthetic transport and data. Swift, swiftc and xcodebuild are absent: compilation, all native tests, actual device navigation and real production behavior are NOT_RUN. No real favorite/profile mutation or user operation occurred.
