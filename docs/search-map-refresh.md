# P101 same-query map refresh

## Source-backed gap

The ce61 mini-program preserves already loaded activity rows/pins while the same query refreshes and if that refresh fails. Native `SearchMapExplorerView.startLoad` cleared those results, selection and page continuation on every read. The new explicit **Refresh these results** action fills this gap without changing **Search this area**, which remains a fresh query.

Read-only sources in `liboyang42-cpu/chengyin`, immutable baseline `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/searchmap/index.js`, blob `eb6b2c97de1023b4b5407c51c5d49512639b4c36`: `runFreshQuery` clears changed-query state; `getList`, `setPageError`, `retryListPage` and `refreshMapResults` distinguish retained first-page refresh from page continuation. Existing `getMerchantNodes` independently loads the city-point layer.
- `chengyinhub-xcx/pages/searchmap/index.wxml`, blob `731e900ef0b7d3970d723ff95576c5bccd7377f5`: `listRefreshing`, `merchantNodesRefreshing`, `pageErrorIsRefresh` and the A-RPT-7 rule show the old result warning without hiding load-more after a refresh failure.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiActivityController.java`, blob `93d209b58f131693c06c5ea09f7e1231b5cba65c`: existing activity-list read contract; no new request fields or endpoints are introduced.

All three local evidence files were verified using Git blob hashes against the ce61 repository manifest before implementation. The master migration document maps P101 to the map explorer and PA04 requires weak-network recovery, coordinate/source and session-state checks. This is one source-backed P101 recovery feature, not a claim of complete W13–W15 parity or live acceptance.

## Behavior and ownership

- An explicit same-query refresh leaves its current activity cards, all accumulated activity pages, city points and selected object visible. A loading message explains that these are previously loaded results.
- A transient unavailable layer keeps only an earlier successful read of that same layer and shows its own retained-results warning. A successful layer replaces its old data, including an authoritative empty result. Successful activity refresh restarts page continuation from the returned first-page metadata.
- A failed refresh does not discard the existing activity next-page number or page failure. Users can retry the refresh or load/retry the next page separately. Neither control automatically dispatches retries. Refresh and load-more are mutually exclusive, including queued button actions.
- Unauthorized, invalid or unconfigured layers cannot retain their old rows. Current authenticated reader failures still use the existing session-expiry path; a fatal top-level failure clears the complete snapshot.
- The ticket is created at the button click and binds query, account/session scope and manual-area revision. Refresh does not reselect the manual area. The view and existing reader both reject stale results. Fresh search, changed filter/area/account/privacy scope, and dismissal retire pending work; A → B → A cannot restore a retired request.
- Dismissal can keep an already displayed same-scope read for returning to the screen, but cancels pending refresh and page work. A removed or now coordinate-less selected object is cleared after accepted refresh. Retained objects reuse the shared activity presentation, so activity detail and linked-topic routes remain separate.
- Only in-memory state is used. No location prompt, tiles activation, GPS/presence sharing, distance/rating/price fabrication, MapKit coordinate conversion, production grant, write route or backend behavior changes.

## Validation and integration

Authored: 14 Core XCTest cases and 4 app-hosted XCTest cases. Coverage includes repeated refresh, old success/failure after cancellation, layer-specific retention, authorization/configuration failures, successful empty and client-filtered pages, refresh/load-more interleavings, page failure versus refresh failure, exact request routes, area revision preservation and session/owner cancellation. XCTest execution is NOT_RUN because this executor has no Apple/Swift toolchain.

Local source validation: 10 new Python contracts; focused search-map discovery ran 39 cases with 38 passing and 1 optional-source skip. Full contract discovery ran 2,376 cases with 2,329 passing and 47 optional-source skips. Four changed/new Swift files passed supplementary Tree-sitter parsing. Source parsing and Python contracts are not Swift compilation or UI execution. An isolated integration dry-run merged the fragment and regenerated the project successfully; scaffold checks passed with 1,461 Swift files, 8,341 bilingual keys and 140 app-unit source files.

Integration must merge the 6 bilingual keys from `Resources/SearchMapRefreshLocalizations.fragment.json` into the main catalog and run the existing project generator. The candidate intentionally does not modify these shared integration files.

Apple acceptance remains NOT_RUN: compile Core and app targets, execute the 18 tests, then verify explicit refresh with full and partial failures, load-more before/after refresh, selected-object removal, quick repeated taps, Back/return, filter/area changes, logout/account changes and cancellation. Check English/Chinese, largest Dynamic Type, VoiceOver and retained-state messages above the map. No real production data, GPS prompt or write is needed for synthetic acceptance.
