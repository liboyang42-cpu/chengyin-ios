# Publisher fresh-authority integration

Prepared in isolation. The main checkout was read-only to this worker. No remote writes or API requests were made; GitHub repository-name search was read-only and returned no backend repository. No source backend file was available, so ownership statements below are traced to the retained Flutter source, not claimed as independently backend-audited.

## Copy and narrow merge

Add `Core/PublisherAuthoritySource.swift`, `Core/PublisherSourceAuthorityReader.swift`, `App/PublisherAuthorityHost.swift`, and `Tests/CoreTests/PublisherSourceAuthorityTests.swift` to the corresponding targets using the existing generator. Apply `docs/reader-projections.patch` only, or manually merge its six additive lines. The `Projections/` files are review copies, not replacement instructions. The existing display defaults, reader protocols, endpoints and transports are unchanged.

In the existing `PublisherLifecycleHostContext` initializer supply:

```swift
freshAuthority: { [weak self] resource, captured in
    guard let self else { throw PublisherLifecycleError.unavailable }
    return try await self.freshPublisherAuthority(resource, session: captured)
}
```

Keep the original `.dormant` client and no journal in normal host. This change creates no endpoint grant, mutation grant, upload, credential or endpoint. Existing host lifetime fencing on logout, token/role/region/namespace change, background and navigation cancellation still applies. The helper is stateless and re-creates cheap composition on every call; it does not cache authority.

## Exact source ownership and eligibility

- Topic route remains `TopicSessionReader.topicDetail` → `POST /api/topic/info-to-user`. `TopicService` verifies exact returned ID. The additional same-response projection preserves strict explicit `isOwner` (numeric 0/1 or Boolean) and numeric `betaFlag` 0/1. Source `app-audit/lib/data/models/topic.dart:297–308` and `feature/topic/topic_detail_page.dart:562–565` explicitly say server `isOwner` is computed as topic `memberId == current viewer`; it is never obtained from a stored UI Boolean. The helper maps an explicitly true result to the independently captured, still-current account ID. It does not invent a topic `memberId` field.
- Activity route remains `AppSession.activityDetail` → `POST /api/activity/info`. The helper checks exact `detail.summary.id`, strict positive same-response `memberId`, the host's decoded `hostMemberID`, and captured account. Gate-only responses, missing owner, missing status/publishStatus and incomplete ticket projection block. Source `data/models/activity.dart:385–445` explicitly identifies `memberId` as creator and warns that `ownerId` means activity identity in ticket records.
- Transfer picker source remains `/api/club/my` (`feature/topic/transfer_to_club_sheet.dart:22–25,113`). Every call fetches the owned list using `ClubSessionReader.clubOwned()`, then fetches every listed ID's `/api/club/detail`. Only exact matching returned ID with fresh `isOwner == true` becomes eligible. `viewerIsAdmin`, `canGovern`, local account role, public directory rows, an arbitrary selected number and stale `/my` row `isOwner` never grant eligibility. Duplicate list IDs or failed/mismatched detail reads block instead of producing false proof. The source also allows an approved cooperation invitation (`data/api/topic_api.dart:328–330`), but this packet conservatively does not infer that path from labels or unrelated cooperation records.
- The source account and both reader scopes are checked before/after every awaited topic/club read. Full PublishingSession equality includes account, epoch, role, region and namespace. A change fails before any authority is returned.

## Stable fingerprint coverage and limitations

The revision field is canonical sorted-key JSON bytes encoded in base64, not a server-generated revision or a cryptographic authorization token. The nested whitelist preserves absent versus explicit null and array ordering, and is collision-free for its source facts. It retains only audited detail fields:

- Exact resource and owner proof; topic beta/product/lifecycle/self-play/price; complete visible chapter/node/template content and merchant identity/business facts; names, descriptions, images/audio, scheduled dates/times, category and collaborator facts
- Ticket IDs, prices, descriptions, refund rules, meeting points, scheduled start/end and total stock (where the source exposes them)
- Activity owner/status/publishStatus/cancellation reason and cancellation time, topic/club identity, team rules and source task summaries
- Fresh eligible club IDs and names, sorted by ID so `/my` reordering alone does not invalidate review

View/like/rating/registration counters, audit `createTime`/`updateTime`, comments, registrants and remaining sale inventory are not fingerprinted. Scheduled dates and cancellation time are business state, so they remain. Structural chapter count and configured total stock remain because they change the reviewed content/capacity. `paidPlayers` and pricing floor/lineup/settlement terms are independently reread and compared by the existing lifecycle coordinator; they are not replaced with display signup counts or club labels.

A topic with missing explicit owner/beta/product, missing chapters/tickets/count, locked story, or a chapter-count/unlocked-count mismatch cannot establish complete visible evidence and blocks. Normal browsing still works because an incomplete added projection becomes nil without altering display decoding. Optional source fields remain missing/null and are never defaulted into authorization.

No version/revision/ETag is exposed by the retained topic/activity detail or Club detail model. The version parameters in `club_api.dart:490–513` belong to separate club-maintenance operations, not these authority read responses, and are not repurposed.

This is complete for the operation-relevant facts exposed by the audited read contracts, not an assertion that an unseen backend has no other fields. The retained detail source does not provide an atomic server version or every hidden editor field. No claim of atomic check-and-write or new backend freshness guarantee is made. Production grants remain OFF; any future activation must independently audit deployed authorization/concurrency and ensure the read contract covers every consequential field for that operation. Do not authorize a hidden-field transfer from a partial public response. No invented version/receipt endpoint or automatic retries were added.

## Verification

- Dry-run `git apply --check` of the two-reader patch against the integration checkout: PASS at preparation
- Pinned Tree-sitter supplementary parsing: PASS for 6 Swift files (including projection review copies)
- Source-key and boundary check in `tools/check_publisher_authority.py`: see final check output
- Ten XCTest methods authored covering source presence, strict owner/beta, incomplete story, exact resource, no local-role permission, mandatory fresh reads, my-list plus current leadership, failure/stale session fencing, volatile-versus-business fingerprint fields, deterministic club ordering, and exact activity ownership/cancellation state
- Swift compiler/typechecking, XCTest execution, Apple SDK/Xcode build, simulator/device and live deployed backend acceptance: NOT_RUN because this executor has no Swift compiler/Apple SDK
