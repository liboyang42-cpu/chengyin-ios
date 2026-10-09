# Merchant review loaded-page parity

## Source and exact integration baseline

The mini-program at private source commit `ce61c0bbace743ff835cb297ef41c89b52181636` appends validated review pages before applying its pending/low/photo predicates. Its managed-review request remains POST `api/merchant/reviews/manage?pageNum=N&pageSize=20`.

Verified source references (the private source bytes are not included in this public candidate):
- `chengyinhub-xcx/pages/merchant/reviews/index.js`, blob `ff2dd31dc1d1973ce634ad7b2449542d636258a4`, lines 166–178, 198–205 and 528–533
- `chengyinhub-xcx/pages/merchant/reviews/view-model.js`, blob `e5ec2266c33c968c29f06f357ad5f3ab0aedae5e`, strict page/review shaping

This candidate uses the actual fifth-batch integrated postimage over published commit `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865` / tree `82e9abd1afa6180815ef7ea5ea314d6eb692e036`. The exact preimage of `App/MerchantBusinessViews.swift` is SHA-256 `9591a8fd9cebf903e7bf4b10c914e6fa3aa907b3823d48c737c89521a94e3b05`, including the already integrated staff roster. Do not apply the candidate as though the published commit alone were its preimage.

## Behavior

- The new **Load more reviews** path accumulates consecutive pages from page one. Pending, low-rating and photo filters now retain earlier matching reviews across loaded pages.
- Existing Previous/Next page replacement remains available before accumulation. Its protected UI acceptance source is unchanged. The scope description explains the different controls. After accumulation, further pages use Load more and refresh replaces the retained list from page one.
- Server summary values remain from the exact latest server snapshot. The client does not recompute totals, reply rates or permission flags from retained rows.
- Duplicate row IDs update in place using the latest validated fields, with their source-page reference updated. Nonconsecutive, repeated or post-terminal append operations fail closed.
- Refresh, failed replacement/append, cancellation, dismissal, account/session/realm change, merchant/access change and authorization generation changes clear or reject the old accumulation. Newer loads fence late responses.

## Separate display and mutation authority

`MerchantReviewLoadedPages` is an ephemeral read-only projection. It never replaces the coordinator snapshot, creates an authorization ticket, executes a mutation, or reserves/completes the journal.

Only a row equal to a row in the current exact coordinator snapshot can expose the original review actions. Earlier retained rows offer a separate **Reload original page to manage** destination. The destination binds account/epoch/realm, authorization generation, full merchant access, original page and target review ID. It opens a new page with a new coordinator and performs the existing exact source-page read. It displays only the requested review from that new response. If the target moved off that page, the user is told to close and refresh; no target search or fabricated detail endpoint is added.

The source-page host checks its bound context while rendering and again on editor review/dismissal callbacks. It cannot turn a retained row into a mutation baseline. The unchanged coordinator still validates the mutation against the exact fresh page, re-reads that page before confirmation, requires complete baseline equality, and preserves its dispatch authorization and durable journal fences. All production grants/default factories and mutation implementation files remain byte-identical. Unknown operations remain locked after navigation, refresh and independent source-page reads.

## Verification and limits

- 8 new Core XCTest methods and 11 new app-unit methods are authored. Their Apple execution is **NOT_RUN** in this Linux executor.
- Focused structural checks, full native contract checks, exact whole-file inverse preservation checks and advisory Swift syntax parsing are recorded in the candidate verification directory.
- The new inverse layer proves preservation of the older roster/customer/settlement/aftercare/Home code. It is not evidence that new Swift behavior has executed. New negative/race tests separately cover the added boundary.
- Existing `MerchantBusinessFlowTests.swift` remains byte-identical. No UI class, method, shard cost, planning budget or fixture launch default changes. The new load-more/source-page UI path still requires Apple runtime acceptance.
- The legacy merchant source checker requires an external Flutter `app-audit` source checkout; that optional source input is absent here. This is reported separately from successful native-local checks.
- No backend changes, requests to production, permission grants, payment/reward operations, publication or push occur.

## Integration

Apply only the candidate `delta.patch` after exact preimage validation. Merge the five bilingual entries from the separate `localization-delta.json` into the central catalog; do not replace the catalog. Regenerate the Xcode project using the normal generator to discover the new Core/test sources. Generated project/catalog files inside the isolated verification checkout are not publication artifacts.
