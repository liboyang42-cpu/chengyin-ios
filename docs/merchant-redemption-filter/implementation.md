# Merchant redemption status filter parity

The existing redemption list now offers the four source-backed server filters: All (`all`), Pending (`pending`), Processed (`handled`), and No cash settlement (`no_cash`). The prior picker sent `settled`, which the source server does not recognize and therefore matches no rows. The processed label does not imply that every record was paid: the source group also includes adjustments and reversals before settlement.

Only an explicit change to a recognized choice resets the existing query to page 1 and uses the existing reload. Selecting the current value is a no-op. A loaded legacy or unknown raw filter remains selected under an unrecognized-filter label; it is never silently mapped to another request. The user can explicitly choose one of the four valid options. Existing initial-load behavior remains unchanged.

The new Core enum describes presentation choices only. It neither classifies returned records nor changes the request builder, service, permissions, paging, summaries, access/scope fences, mutation review, grants, journals or production-write behavior. Server summary amounts are never summed or relabeled by this change. This remains the existing redemption-only list; the mini-program's combined refund timeline is not added.

## Exact source evidence

Repository `liboyang42-cpu/chengyin`, pinned ref `ce61c0bbace743ff835cb297ef41c89b52181636`, verified with read-only connector reads and retained Git tree blob IDs:

- `chengyinhub-xcx/pages/merchant/ledger/index.js`, blob `181f127cdd02b184e4235be60574198b301feb36`: `redemptionTabs` defines all/pending/handled/no_cash, and `loadRedemptions` sends the selected filter to the existing finance-redemptions route.
- `chengyinhub-xcx/pages/merchant/ledger/index.wxml`, blob `1135ba2e453c8c1fc92f9988d033addae8d7f7db`: finance-authorized redemption tabs use those source options.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantFinanceQueryService.java`, blob `b6ff358286d6b6df3855b8ef0a72bdacca924eb1`, lines 439–445, `matchesRedemptionFilter`: pending includes PENDING_SETTLEMENT, ADJUSTMENT_PENDING and LEDGER_ERROR; handled includes SETTLED, ADJUSTED and REVERSED_BEFORE_SETTLEMENT; no_cash matches NO_CASH_SETTLEMENT. There is no settled wire alias.

No private implementation was copied into native product code. The outer source-manifest records verified URLs, blob hashes and the root baseline receipt.

## Allowed scope and integration

Exact frozen root base: `6a3b946469ad8b2bf2c83ff5136b39f9cac309a1` from batch14. Two product paths: one narrow redemption-picker hunk in `App/MerchantBusinessViews.swift`, plus new `Core/MerchantRedemptionFilter.swift`. The focused inverse assertion restores the exact original view SHA-256, preserving all prior note, datepicker, customer, aftercare and review changes.

Merge the six bilingual fragment entries and run the existing project generator only in the integration owner's copy. The shared catalog/project, frozen batch14 and earlier merchant packets remain untouched here. Tests accept either the independent fragment or an exact complete catalog merge.

## Evidence and limits

Actually run: five focused Python contracts; three supplementary Swift syntax parses; whitespace and exact shared-view inverse checks; protected-path hashes and exact-base patch replay. Six Core XCTest methods are authored but unrun: source choice values/order, processed-versus-settled distinction, wire route/body/permissions, pagination, unknown/raw preservation, and unchanged server rows/summary. Swift and Xcode are unavailable. No compiler, Core runtime, simulator/UI/accessibility, broad aggregate or live API result is claimed. No remote writes, commits, credential access, financial actions or production mutations occurred.
