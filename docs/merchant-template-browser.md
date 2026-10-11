# Merchant own-template paged browsing

## Baseline and independent scope

Actual upstream iOS: `94bced23ae734bcd8a5e236c8b992294bd15b14a`.
Exact incremental preimage: `586a19a33b545ea411c68501baa9002853888e15`.
Unsubmitted dependencies replayed onto 94: hints `ba3a202` → `8fe4896`; timeline `0fc771a` → `825873e`; categories `05cf3dc` → `586a19a`. Earlier metadata/preparation/rules are already in 94. This increment changes browsing, not the eight sealed authoring packages.

MASTER v10 W05, lines 399–427, provides the merchant authoring and human-review responsibility. The implementation is grounded in the existing Mini own-template management page; this is not a claim that all W05 requirements or publication controls are complete.

## Existing source events and contract

Pinned backend/Mini: `f1fe895f34c3664783aafd6145cf93e0de15878d`.

- `chengyinhub-xcx/subpackageMember/mytemplate/mytemplate.js`, SHA `163c38e49820ea442c3e318bd913fa0c3bad973a`: page size 10, `refreshList`, `loadMore`, `retryLoadMore`, `getList`, distinct first/append failure handling, and `onShow` source refresh. Exact form: POST `/api/template/my-list`, empty `is_quote`, `keyword`, `category_id`, plus `pageNum` and `pageSize`. Data is `{rows,total}`; unknown total falls back to page fullness.
- Its WXML, SHA `493ad3a3a9147d9595b73d193703bb4eccb6f4d9`: initial loading/error/empty, append-error retry, load-more, and exact-ID detail navigation. The page explicitly removed search. This implementation adds neither search nor unproven filters.
- `ApiTemplateController.myTemplateList`, lines 285–335, SHA `11a3ab9a9baa3ff6d09aedae860e6d29702127c5`: authenticated member, existing optional scope owner resolution, filters, `startPage`, `selectMemberTemplateList`, `getDataTable`, AjaxResult data wrapper.

Native's new paged service method reuses that existing read route and existing merchant-project access/me gate. Its session adapter returns both the decoded page and the access projection used for the read. Cancellation, account-scope fences and the unauthorized callback remain in the existing read wrapper. No write route, grant, new scope or endpoint approval is added.

Existing scope limitation, handed to root: current Mini and older native my-list calls omit `scope`, so the backend lists the current principal's templates. Its optional `scope=MERCHANT` owner resolution is real but this feature does not change that existing ownership behavior or claim manager-to-owner catalog coverage. Existing exact-ID detail authorization still decides whether a record is accessible. All backend remediation and production activation remain separate.

## Complete browsing flow

- The merchant template destination mounts a dedicated paged browser. It does not also run the old first-page/100-row document request. The old document adapter remains for compatibility; it is not the active list path.
- First response validates the rows object, positive unique IDs and optional nonnegative total. Missing/null total stays unknown. A successful empty response has its own create entry; a failed first response has retry, not false empty content.
- Load more requests only the next page and advances the page index only after validation. An append failure retains rows/count/page and exposes retry of the same next page. Repeated taps while busy cannot duplicate requests.
- Refresh replaces the accumulated pages only after a successful new first page. A refresh failure retains the prior snapshot with a visible stale-result explanation and blocks appending until refreshed. Refresh can supersede a pending append; a late append cannot join the newer snapshot.
- Duplicate overlap, an oversized response, a total below accumulated count, or an empty page claiming remaining rows fails atomically. Unknown totals use ten-row page fullness; known totals are server values. Offset pages have no source snapshot/version token, so this is not a transactional catalog snapshot guarantee. Inconsistencies require retry/refresh rather than invented records or silent deduplication.
- Access changes between pages, explicit denial, and authentication failure clear retained rows. Account changes immediately hide rows and totals; old requests cannot restore them. Leaving/backgrounding cancels the active flow, and return/foreground starts a fresh first-page read.
- Existing create and exact-ID editor destinations are retained. Returning from editing rereads source; the browser does not optimistically rewrite row titles or statuses. Existing template status labels are retained; this feature adds no new approval or marketplace action semantics.

There is no durable local catalog cache. The browser holds current-session source records only. No delete, marketplace review submission, publish-status toggle, payment or reward is performed.

## Verification and integration

- PASS: 89 focused source checks (12 new plus 77 related); pinned Tree-sitter parsing of 9 changed/new Swift files; whitespace, precise baseline bytes, allowlisted paths, forward/reverse patch checks, and prior-eight archive hash checks.
- Authored NOT RUN: 23 Core XCTest methods and 4 simulator UI flows. Core includes all 105 synthetic records, known/unknown totals, end detection, initial/append/refresh failures, overlapping/inconsistent pages, out-of-order refresh vs append, duplicate taps, cancellation, account/access change, exact request form and denied/unauthorized handling. UI includes initial retry, page-two detail/back refresh, edited-title source refresh, and genuine-empty create navigation.
- NOT RUN: Swift type checking, Xcode build/Core XCTest, simulator screenshots, accessibility/Dynamic Type, real backend acceptance. Required dot environment has no `swift` or `xcodebuild`; parser/source assertions are not native execution. No alternate environment was used.

Register `Core/MerchantTemplateBrowser.swift` and `App/MerchantTemplateBrowserView.swift`, new Core/UI test files, and 12 English/Simplified Chinese entries from `Resources/MerchantTemplateBrowserLocalizations.fragment.json`. Evidence `integration-fragment.json` lists paths, UI methods and interpolation keys. Central PBX/catalog/CI files are unchanged. Existing historical failures are not repaired or represented as this feature's passing acceptance.
