# P108 author-post refresh and recovery

## Delivered user operation

From My → Public profile → Posts, Refresh posts re-reads the first author page through the existing `SquareReading.squareFeed(query: .init(authorID: memberID), cursor: nil)` operation. Previously loaded cards stay visible with an explicit retained-results label while refreshing and after a transient failure. Retry repeats the failed operation: a failed refresh requests the first page; failed continuation requests the same saved cursor. A successful refresh atomically replaces all prior pages, including a successful empty result. Load more continues from the replacement page's cursor. Detail routes retain the existing post ID and content generation.

No new service, URL, token, capability, account grant or image reader is introduced. The native adapter was already the versioned community author feed; Mini's delegate reads its legacy creative-square endpoint. This increment preserves the existing native adapter rather than silently changing that contract or claiming identical wire protocols.

## Source and confirmed gap

The only master is `MASTER-v10-extracted-text.txt`, P004 and P108. P108 delegates to `cy-profile`. Approved Mini ref: `f859cd6e2618f618a53f5cd33949259828e86313`, `chengyinhub-xcx/subpackageMember/components/cy/profile/index.js`, blob `99008cdb5c877c851f87f68fecac09f27c9eb46e`. The exact methods are `getCreativesquareList` (1558–1605), `reloadFeed` (1630–1633), and `onFeedReachBottom` (1635–1639). Its WXML invokes `reloadFeed` from the feed-error retry and pagination from scroll-to-bottom. `refreshPublicProfile` is a broader header lifecycle and is contextual evidence, not the new function's endpoint.

Baseline `94bced23ae734bcd8a5e236c8b992294bd15b14a` had only initial load, continuation and error retry inside `SocialAuthorPostsSection`. It had no way to refresh an already successful author feed and no distinct refresh/continuation retry intent. This native explicit refresh and recovery chain supports the source read operation; it does not claim Mini has an identical button or retained-cursor UI.

## Identity and lifecycle behavior

The immutable presentation key includes subject member ID, viewer identity/role/epoch, viewer presentation revision, both reader instances, square scope, configuration and sign-in status. Visible cards and navigation re-check this key and the parent's `isCurrent` predicate. A context change resets all old rows. Explicit authorization failures clear rows rather than showing private stale data. No new guest access is granted.

Only one request runs in one context. All results/errors are guarded by a request generation, current presentation and cancellation. A new context can start without waiting for an old non-cancellable request; the old result cannot publish. Leaving the section suspends pending completion but retains its scoped source rows so opening detail does not invalidate its own navigation link. Returning activates the existing page-owned feed. Under an unchanged concrete public-profile target and read approval it retains accepted pages; explicit Refresh still replaces the first page. Generic readers keep their full presentation-revision fence. Parent retirement, account/configuration change or explicit `retire()` clears the snapshot. This page-local cache is not persisted.

Refresh creates a replacement pagination value and commits it only after `accept` succeeds. A failed refresh never silently moves the continuation cursor. Successful empty pages remove old cards. A malformed/repeated continuation stops further pages using the existing `SquareFeedPagination` behavior; Refresh remains available. Normal refresh cannot continue paging after a failed refresh until the user retries or successfully refreshes.

## Historical verification and integration (preceding implementation)

- 22 focused Python source-seam checks pass. These checks inspect source boundaries and are not Swift execution.
- Exact approved Mini methods execute in a local JavaScript sandbox with synthetic data: 7 scenarios pass, no network.
- 18 Core, 8 app-unit and 5 UI tests are authored. Swift, swiftc and xcodebuild are absent; all 31 are NOT_RUN.
- Mutation probes verify the focused source checks reject removed guards/wiring; this is static mutation coverage only.
- Incremental forward/reverse patch replay, allowed-path scope, previous package integrity and preserved central fixture changes are checked in the package evidence.
- Merge the registration/localization fragment centrally. No PBX, central localization catalog, fixture launch router, CI or AppSession was edited here. The DEBUG fixture launch is pending central registration; existing production P108 already calls the new section.

The existing gallery entry was moved unchanged with its original reader behavior. No new working image-preview claim is made. Actual service success, Apple compilation, accessibility layout and UI navigation are not validated by the local source checks.

This package is independent of all six sealed profile-editor increments. No overlays were applied. Central ProfileEditView body decomposition, the two fixture API-base fixes and all preceding sealed archives must stay unchanged.


## 2026-10-19 public-profile detail return

Baseline: `27d2854ab244dd6ce13f7a81dd117a4ac9d008e1`. Mini reference `57b22916e05e0c7eccccb75f68a46a4576ab5bf8`, cy/profile `pageLifetimes.show` (473–498), `refreshPublicProfile(silent)` (708–715), and `refreshAll(silent)` (777–802): a silent return refreshes the header while preserving author feed pagination.

The concrete public-info reader exposes only a read-only retention identity: immutable target UUID/member/viewer revision, currently matching approval UUID, and observed approval-transition revision. Existing header presentation revision, visibility, cancellation and read-generation checks remain unchanged. Nil/revoked/mismatched public authority never falls back to generic retention. Generic readers retain their prior full revision behavior. This is not a new endpoint permission.

The public-profile page owns the feed controller and selected-post ticket above the replaceable header content. Section reconstruction activates that same controller without a new feed request when its exact context already has a result or retry state. Explicit Refresh, Retry and Load More keep their existing semantics. New page ownership starts fresh. Opening a post uses the existing fresh SquareDetailView read, never a cached card as a detail result. The existing object-card achievements entry and other private self sections are unchanged.

A current authoritative header rejection retires only the matching feed context and its ticket; stale/cancelled header callbacks cannot clear a successor. A transient header error keeps the existing error screen, with cache retained internally until successful retry. Account/target/grant/reader/square-context changes invalidate visibility and tickets. The existing provider cannot detect an entirely unobserved swap back to the same unrevoked approval object; this change does not claim a stronger guarantee.

Current increment: 7 Core, 5 public-info app-unit and 2 author-feed app-unit tests authored. All tests, source-check execution, Apple compilation, and real App navigation are NOT_RUN. The production-controller/header lifecycle test does not prove SwiftUI gesture/navigation timing; that remains a runtime acceptance requirement. Earlier historical PASS counts above are not current verification of this increment.
