# Map activity pagination

## Scope and visible result

The existing city-map screen now exposes **Load more activities** after the first activity read. It retains the existing 50-row request size and the separate, unpaged city-node read. Additional pages update the same activity list, pin collection, and selected-place detail. City POI IDs stay in their own domain.

A page failure leaves the current results and selected pin available and offers **Retry this page**. A raw full page that becomes empty after local date/price filtering still offers continuation. Double taps acquire only one ticket. Filter, sort, manual-area, session/account changes, refresh and dismissal fence old completions. Returning from detail preserves the same loaded read without issuing another page automatically.

This is one read-only mini-app-to-SwiftUI feature slice. It does not add map aggregation APIs, city-node pagination, location permission, location capture/sharing, a directions provider, attendance evidence, gameplay completion, or reward rules. W13 map-discovery behavior is the relevant master-document scope; W14/W15 ownership and already-delivered walking work remain unchanged.

## Verified source

Source repository revision: `ac16870a19218f68346d29a8c0d6b244b8b2a378`.

- [Mini-app search-map script](https://github.com/liboyang42-cpu/chengyin/blob/ac16870a19218f68346d29a8c0d6b244b8b2a378/chengyinhub-xcx/pages/searchmap/index.js#L206-L337): `getList` snapshots query/page state; raw row count determines fallback continuation before client filters. `setPageError`/`retryListPage` at lines 353–375 retain prior results and retry the failed page; `loadMoreResults` at lines 1203–1214 guards duplicate requests. Blob `eb6b2c97de1023b4b5407c51c5d49512639b4c36`.
- [Mini-app result layout](https://github.com/liboyang42-cpu/chengyin/blob/ac16870a19218f68346d29a8c0d6b244b8b2a378/chengyinhub-xcx/pages/searchmap/index.wxml#L95-L122): result cards, inline paging error, retained-map explanation and load-more button. Blob `5e076109348744fa8bcb21caaf65b302aa6deb44`.
- [Activity controller](https://github.com/liboyang42-cpu/chengyin/blob/ac16870a19218f68346d29a8c0d6b244b8b2a378/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiActivityController.java#L167-L344): existing `POST /api/activity/list`, `startPage()`, then `AjaxResult.success(getDataTable(list))` with public-row projection.
- [BaseController](https://github.com/liboyang42-cpu/chengyin/blob/ac16870a19218f68346d29a8c0d6b244b8b2a378/chengyinhub-common/src/main/java/com/chengyinhub/common/core/controller/BaseController.java#L95-L102) sets the page's `total` from `PageInfo.getTotal`; [TableDataInfo](https://github.com/liboyang42-cpu/chengyin/blob/ac16870a19218f68346d29a8c0d6b244b8b2a378/chengyinhub-common/src/main/java/com/chengyinhub/common/core/page/TableDataInfo.java#L13-L52) defines its long-valued total.

No private mini-app/backend source is added to the native repository. Existing native `ActivityListResponse` and existing `SearchMapTests` remain unchanged.

## Contract and state

The request is the existing multipart activity read: `is_my=0`, `pageNum`, `pageSize=50`, `longitude`, `latitude`, `sort_type`, optional `keyword`, optional `category_id`. Merchant `tag`/`cityRole` and date/price fields are not sent to this activity endpoint. Date and price matching remains local, with the existing missing-value rules.

`SearchMapActivityPage` separates filtered/deduplicated rows, raw response count, optional server total and requested page number. Present, valid total uses the raw page offset; absent total falls back to raw-count ≥ 50. An empty raw page stops even if a moving server total is stale. Negative/malformed totals fail rather than inventing a last page. No exact total is shown to users because local filters and a changing server list make that misleading.

`SearchMapPagination` acquires an identity-bound single-flight ticket before scheduling work. Rows append with first accepted ID occurrence retained. Duplicate/stale success cannot overwrite displayed fields or move an existing pin. Failure preserves rows and `nextPage`; retry creates a new ticket for that same page. Cancellation retires the ticket without losing the displayed read. Refresh replaces the complete snapshot. The SwiftUI adapter checks identity before dispatch and after completion; `SearchMapSessionReader` separately checks account, token context, epoch and manual-area revision, including late 401 responses.

The API exposes numbered pages, not an immutable snapshot cursor. Stable deduplication prevents duplicate cards; it cannot guarantee no omissions when the backend list changes between page requests. Refresh restarts at page 1. There is no background prefetch or claim of exhaustive results.

## Integration

Five existing files change: `Core/SearchMapContracts.swift`, `Core/SearchMapService.swift`, `Core/SearchMapReading.swift`, `App/SearchMapExplorerView.swift`, and `App/SearchMapFixtureSupport.swift`.

Add `Core/SearchMapPagination.swift`, its Core/AppUnit tests, the focused Python source-contract test, this document, and `Resources/SearchMapPaginationLocalizations.fragment.json` (7 English/Simplified-Chinese keys). The shared catalog and Xcode project are deliberately not edited in this isolated slice. The integrator must merge those additive keys and register the new Swift files through the existing project-generation workflow. Existing protocol adopters remain source-compatible through a default unavailable paging implementation and optional first-page metadata.

## Acceptance and evidence

Executed in the dot Linux workspace:

- 9 focused Python pagination source-contract checks: passed.
- Existing search-map contract suite: 10 passed, 1 explicitly skipped because the optional retained Flutter checkout is absent.
- Existing manual-map composition suite: 11 passed.
- Adjacent map/camera/density/visual checks: 19 passed; reference-map-layout checks: 9 passed; unchanged walking-preview request checks: 10 passed.
- Total Python unittest result: 68 passed, 1 explicitly skipped. Existing standalone search-map checker: 17 additional checks passed.
- All 8 changed/new Swift files parsed with tree-sitter Swift: passed.

Authored, not executed: 16 Core XCTest methods and 4 AppUnit XCTest methods. They cover optional totals, raw/filter separation, malformed metadata, exact wire fields, bounded page arithmetic, single-flight/retry, duplicate pin retention, first-page failure/legacy readers, identity changes, late success/401, cancellation and synthetic UI-facing fixtures.

Manual fixture entrances: `--uitesting-module searchMap --uitesting-search-map-entry city --uitesting-search-map-scenario pagination|pageFailure|pageDelayed|filteredPage`. Use the existing **Search this area** button first. Delayed mode adds an explicit synthetic-response release control. Fixture map tiles remain disabled by the existing offline path.

Apple Swift typechecking, SwiftPM XCTest, iOS app builds, AppUnit/XCUITest execution, screenshots, VoiceOver/Dynamic Type validation and live backend acceptance: **NOT_RUN**. No Swift/Xcode toolchain is installed here. Static parsing and source checks are not evidence that Swift compiled or that the UI ran. CI was not awaited and nothing was pushed.
