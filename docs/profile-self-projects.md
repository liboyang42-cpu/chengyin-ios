# Own-profile project preview and read navigation

## Source and scope

MASTER-v10 P004 (AccountView, delegated cy-profile), P108 (own public-profile view), pinned Mini f859cd6e2618f618a53f5cd33949259828e86313: active WXML own `projects` tab, `loadProjectPreview`, `reloadProjects`, `onProjectPreviewTap`, `goProject`; `utils/merchant-workbench.js` is the exact schedule helper. Source receipts include pinned blob IDs and relevant excerpts. Backend `ApiProjectController.my` binds topics to the authenticated member, maps startTime/endTime from CmsTopic.startDate/endDate, and uses `type` for projectType, not bizType.

The normal AccountView injects its existing CreatorContentReading plus captured SocialAccountIdentity. Other public-profile callers default to nil. The own-only tab reads once, previews up to eight unended topics, retries/refreshes, preserves previous rows on read failure (clearly stale, non-navigable), clears on authoritative empty or unauthorized, opens typed topic detail, and opens the existing full read-only project browser with topic/activity/play-template detail. The existing Account management/editor destination is unchanged. No creator-center/income read is forwarded.

## Deliberate native transport differences

Mini preview uses up to five pages of eight `/api/topic/list?is_my=1`. This increment reuses the existing normal native `/api/project/my` reader with all/all/all and its existing first-200 cap; it does not invent a paging contract or new permission. Filter bizType=topic locally, then deduplicate typed identity, exclude ended calendar days, and take eight. A source-truncation notice is shown even when zero live rows occur in the loaded subset. The empty text only claims no unended topics in that subset. No total live count, pending count or completeness assertion is fabricated.

The existing full browser preserves its current filters and cap notice. Its older `type` vocabulary/backend mismatch was discovered during targeted field verification and is outside this increment; this preview never sends type=topic. No historical repair was made. The full-list destination is labeled "View all projects", not a newly implemented management editor.

Shanghai business calendar day is explicit and independent of device timezone. Like Mini, date prefixes are treated as calendar labels; unknown start has no status and stays visible, missing/reversed end becomes the start day, end day remains running through that day. No backend lifecycle state is substituted for calendar status. Cards are text-only; no new media reader or working image preview is claimed.

## Identity, cancellation and return

Context fences include positive matching own member, host owner identity, public-reader object/revision, project-reader object/captured scope, configured/authenticated and current-route status. The scoped wrapper checks before dispatch, after success and after failure. A queued old route cannot dispatch a replacement-account project read. Creator center is rejected. Controllers coalesce duplicate refresh, fence generation and cancellation, suppress late results/errors, and keep pushed navigation rows on suspension. Exact current visible rows alone can open, stale rows cannot. Full list and typed detail destinations check the captured context. Normal native public detail readers retain their existing session cancellation behavior.

## Integration and acceptance

Base49 already contains #7 author refresh. Overlay exact #8 -> #10 -> #11 -> #12 before this incremental patch; 43 overlay paths and shared before SHA are recorded. Shared AccountView and SocialPublicProfileView must merge additively, preserving all earlier panels and root decomposition/fixes. Do not replace a newer shared page wholesale. Registration and ten bilingual strings are fragments only; central owner must register source/test files and the dedicated DEBUG fixture.

Passed here: 30 new source assertions, 121 dependency source assertions, 18 static mutation probes, eight exact-Mini synthetic cases; no network/account/photo/permission operations. Forward/reverse patch replay and sealed-prior byte checks are in evidence. Authored 20 Core, seven AppUnit and seven UI tests. Swift/swiftc/xcodebuild are absent: native compilation, runtime tests, device navigation, visual/accessibility QA and actual-account reads are NOT_RUN. Source assertions are not compiler or native behavioral evidence.
