# Current employee and invitation roster

## Source-backed gap

The mini-program's existing team page presents active employees and pending invitations separately, with counts and an explicit no-employees state. The native team page previously displayed every returned employee and invitation in generic sections, mixing current and historical records and showing no employee-specific empty state when invitations existed.

The native page now projects the current loaded team document into four groups: ACTIVE employees, PENDING invitations, REVOKED employees, and ACCEPTED / EXPIRED / REVOKED invitations. The two current groups have independent loaded-record counts and empty states. Historical rows remain accessible through clearly labeled disclosures. Counts describe only the latest loaded response, never a global or complete lifetime total.

Every original record, field, ID, version and within-group source order is preserved. The same existing row renderer and guarded action callbacks are supplied by the owning page. No role permissions or write payloads are derived by the projection. Invitation expiry is not inferred from the phone clock: the server's exact status remains authoritative.

## Pinned evidence

Source: `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`.

- [Mini team loading](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/team/index.js), lines 417–442: validates the response and filters ACTIVE / PENDING. Blob `46ad9d5a9c90a87c24e634317a17cbbf7e6dd730`.
- [Mini team layout](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/merchant/team/index.wxml): separate member/invitation counts and employee empty state. Blob `98f720912868aa6333f19fdfc452f5f13cc8d4d4`.
- [Operator controller](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantOperatorController.java): existing team-list route. Blob `1ca5a7d91456dc94ffb71de5952ceddcec1246c7`.
- [Operator service](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantOperatorServiceImpl.java), lines 59–76: owner-scoped team response and authoritative pending-to-expired presentation. Blob `7b719e47eb3fe8777d2312318a787c879dc1f319`.

All four fetched source blobs were verified against the pinned repository-tree manifest. The new native presentation intentionally retains existing historical rows rather than dropping them to match the mini-program's current-only layout.

## Integration and safety

Base native tree: `3eb25aa37ff73a9ad13f0d8dd8a908bad36449cb`.

Merge the 12 additive keys in `Resources/MerchantOperatorRosterLocalizations.fragment.json` into the string catalog and regenerate the Xcode project with `python3 tools/generate_project.py`. Those shared integration files are not part of the isolated candidate patch.

Only two presentation hunks change `App/MerchantBusinessViews.swift`. Its strict inverse test restores the exact prior customer-detail version before applying the unchanged customer, settlement, aftercare and Home checks. The only other existing-file edit is the additive inverse layer in that test.

The roster renders only inside the existing current snapshot. It retains no roster state, launches no reads, and makes no network or persistence calls. The existing access, scope/authorization invalidation, frozen review and unknown-result journal are untouched. History cannot gain edit/remove/revoke buttons because the original exact ACTIVE / PENDING action guards remain unchanged. No invitation sharing, acceptance, permission change, refund, payment, reward or production request was performed or enabled.

## Verification scope

- 10 Python contracts check wiring, exact status inventory, original-record preservation declarations, loaded-count scope, independent empty states, accessible disclosures, bilingual strings and absence of new transport/persistence/actions.
- Two added inverse tests verify the exact two-hunk restoration and reject missing, duplicate, changed or unrelated edits while preserving all older layers.
- 12 Swift Core tests are authored for every status, history-only and empty states, source order, exact fields/versions, same numeric IDs in different domains, no clock-derived expiry, refresh replacement, malformed status variants and unchanged mutation requests.
- Supplementary Tree-sitter parsing is separate from Swift compilation.
- Swift/XCTest, Apple builds, AppUnit/UI execution, Dynamic Type, VoiceOver and real backend acceptance remain **NOT_RUN** in the Linux executor.

On Apple infrastructure, check mixed and history-only rosters, zero employees with a pending invitation, count updates after refresh, disclosure expansion, existing role/removal/revocation reviews, cancellation and return, account/authorization change, both languages and accessibility text sizes. Keep all tests synthetic; no real team changes are needed.
