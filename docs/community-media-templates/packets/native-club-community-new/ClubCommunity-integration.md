# ClubCommunity additive package

## Delivered

Executable typed reads for club list, joined-club feed, comment pages and public revision history; source-specific post/comment actions through a concrete injected JSON HTTP adapter; immutable exact-target reviews and fresh role/content/version revalidation; native feed/tile/composer/comments/history/review views; default-off synthetic-only image seam; English and Simplified Chinese catalog; canned transport fixtures and authored core/UI tests.

No membership, member management, governance workspace or administrative collection UI is duplicated.

## Parent-owned integration

1. Copy `Core/ClubCommunity*.swift`, `App/ClubCommunity*.swift`, tests and checker additively into matching native directories. Merge the 47 `club.community.*` catalog entries into the app catalog rather than replacing it. Register new files with the existing project generator.
2. Add optional `community: ClubCommunityContext? = nil` to `ClubDetailView`. Inside its List add `if let community { ClubCommunityEntry(clubID: id, identity: reader.clubIdentity, context: community) }`. It is a public posts destination; do not nest under governance/member-management conditions.
3. Add optional context through the existing club host/navigation owner. Joined-club feed destination is `ClubCommunityFeedView(context: context, identity: reader.clubIdentity)` with no clubID. It preserves `clubCount == 0` join-first state instead of mislabelling it an empty club.
4. Read-only context can use `ClubCommunityService(baseURL:configuration.baseURL, transport:transport)` and nil coordinator. Wire `currentSession` to the existing account/epoch/token lifecycle; retain one coordinator per app lifetime, not per view. Guest scope uses the same `ClubReadIdentity` epoch. Never synthesize a signed-in member from an unrelated Square identity.
5. `evidence` must freshly read membership and exact post/comment under that identity. Obtain membership from the existing ClubReading detail flow. Populate joined/owner/admin from server-returned flags, and post/comment from community lists using exact IDs. Keep public feed `viewerCanManage` as returned; no role inference from menu selection. Reject missing, mismatched or stale targets. `refreshEvidence` must repeat those reads, not echo input outside fixture mode. Unknown locks survive same-account epoch changes as long as the coordinator is retained; they have no reconciliation/reset endpoint and are intentionally not cleared by count/content guesses. No persistence across process termination is provided, so production writes remain disabled.
6. The optional fixture convenience initializer `ClubCommunityService(offlineBaseURL:transport:)` takes a canned `ClubCommunityOfflineTransport` for offline mutation QA. The ordinary initializer refuses mutations. The concrete dormant initializer `ClubCommunityService(dormantBaseURL:transport:grant:)` accepts any injected HTTPTransport and defaults its grant to `.disabled`; `.reviewedInjection` enables exact HTTP execution after the same review/authority checks. No shipped factory supplies that grant. Tests inject a plain HTTPTransport with the explicit grant, exercising serialization, response and error paths without network. Uploads remain `ClubCommunityDisabledImages()` by default. `ClubCommunitySyntheticImages` returns fixture.invalid URLs without OS/network access.
7. Under `#if DEBUG`, mount `NavigationStack { ClubCommunityFeedView(context: try ClubCommunityFixture.context(), identity: ClubCommunityFixture.identity, clubID: 10) }` only for `--club-community-fixture`. The parent owns the shared launch-argument fixture switch. The fixture is a canned response adapter, not a simulated real backend or evidence that writes persisted.

## Exact source mapping

- `app-audit/lib/data/api/club_api.dart:360–427`: comment list/create/delete/report; delete permits author/owner/admin, reports queue review
- `:430–464`: per-club list and toggle-like, no desired-state parameter, no retry
- `:471–517`: create images optional semicolon string; update always includes semicolon images, version and requestId; pin uses id/pinned/version/requestId
- `:520–574`: public history; delete/report id only; feed rows + clubCount
- `lib/data/models/club_post.dart`: authorMemberId, isPinned bool/1, public revision fields, image delimiters, type==2 announcements and source reference-card rules
- `lib/data/models/club_comment.dart`: comment memberId; author/owner/admin deletion distinction
- `lib/feature/club/club_feed_page.dart:136–185`: author edit/delete, announcement-manager edit/pin, public history
- `lib/feature/club/club_posts_section.dart:181–218`: 300-character / nine-image composer and image-only post support
- `lib/feature/club/club_detail_page.dart:245–247`: public posts tab and joined/owner compose intent

## Safety and remaining runtime gates

No live network, posting, commenting, likes, moderation, image upload, OS permissions or remote writes were performed. Mutation success means server acknowledgment requiring fresh reads; report means moderation queued, never deletion. Transport ambiguity, malformed responses and post-send session changes preserve a locked unknown result. Legacy endpoints receive neither invented idempotency IDs nor receipt routes. The coordinator serializes a target through send and consumes a review exactly once, including duplicate confirms that race during fresh-evidence awaits. Versioned changes reject changed source post snapshots before submission.

Authored tests cover request bodies, delimiter handling, roles/target mismatches, row variants, default-off transport, ambiguous-toggle lock, queued reports, duplicate confirm, epoch changes and image seam. UI authored cases cover feed/comments/history, review/cancel and Chinese labels. They require the host fixture hook above.

Validation: source checker PASS; supplementary Tree-sitter parsing PASS, 6 Swift files, no recovery. Swift compiler/typecheck, XCTest, simulator/UI/accessibility runtime, physical-device behavior and Apple signing: NOT_RUN (Swift/Apple toolchain absent). Tree-sitter is not compilation. Before activation, run the existing Xcode build/core tests/UI tests, verify sheet dismissal, repeated confirms, account-change invalidation and large Dynamic Type/VoiceOver. Production mutation activation and live upload are intentionally outside this package.
