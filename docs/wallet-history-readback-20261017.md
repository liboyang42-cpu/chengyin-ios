# Wallet ledger readback source delivery — 2026-10-17

CY-HANDOFF: IOS

Status: SOURCE_DELIVERED_UNVERIFIED. Source review and newly authored regression cases only; tests, compilation, simulator, device, live business readback and CI were NOT_RUN. This is a bounded wallet history flow, not completion of the full application plan.

## Baseline and backend coordination

- iOS repository `liboyang42-cpu/chengyin-ios`, branch `migration/native-ios`, exact parent `2765f582a68ded799024661963cfb36ef6abf02c`, tree `fbbf89142501ecb8b4b74edb8cc9990eff5a8a47`.
- Read the shared control documents at `liboyang42-cpu/hengyin`, `codex/mini-bugs-backend-cloud-plan-20261015`, control commit `60064301f61a72103e094cd9e5ec305bfe784b85`. This is a control-document revision, not an asserted deployed business build.
- [iOS start](https://github.com/liboyang42-cpu/hengyin/blob/60064301f61a72103e094cd9e5ec305bfe784b85/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md), blob `920fe1d4bcb65ac8dec5870f89f6da1e68d3a9c6`.
- [iOS handoff](https://github.com/liboyang42-cpu/hengyin/blob/60064301f61a72103e094cd9e5ec305bfe784b85/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), blob `cd3a9f3ca755c36c932067f0d4da7f5683b7438a`.
- [Backend changes](https://github.com/liboyang42-cpu/hengyin/blob/60064301f61a72103e094cd9e5ec305bfe784b85/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md), blob `7b441463b745a5ab0488004cd813e452159b64c2`.
- Also reread COORDINATION, OWNERSHIP and TASKS at that control commit. I04/I07 and BK-ASSET remain the relevant shared contract: NO_API_CHANGE. No new DTO, endpoint, permissions, accounting policy, balance calculation or server pagination. TEST_DEPLOYED=NO; no runtime backend version was verified. No backend files or shared control logs were edited.

## Actual defects found

1. `WalletLedgerPager` retained only a boolean failure. A configured reader denied by the read grant, or a 401 without immediate session teardown, therefore rendered as a retryable generic failure. The view also offered load-more after failure.
2. Initial `loadedScope` and signed-out `reader.scope` were both nil; equality was insufficient proof of a successful empty response. The initial view could show empty history while sign-in was required.
3. An account change during a request returned from the old catch path before clearing loading. Further reads could become stuck without an external reset.
4. First-page duplicate calls compared the still-nil successful `loadedScope` to the active owner, resetting the generation before checking the loading gate. A second tap could dispatch a duplicate read. Reusing the pager with another ledger kind could also reuse the old completed page.

## Source behavior after this patch

- Existing Account → wallet → assets → balance/points links remain. The asset-points link gains a stable UI-test identifier.
- `hasLoadedPage` explicitly proves a successful result. Empty state requires a successful current-scope page, no loading and no failure; missing/error/denied results never become empty-success or zero.
- Pager exposes `requiresLogin` and `unavailable`. `WalletIssueView` receives those states; neither category offers retry or load-more. A permission failure clears any earlier visible rows. Transient/network/business failures preserve prior pages and retry the same page.
- Scope and ledger kind are bound before dispatch. Same-context duplicate calls use one in-flight gate; a different owner/kind resets. Generation checks reject cancelled/replaced requests. A stale scope/token result clears state; cancellation does not become a business failure. A matching request clears loading using `defer`.
- Load-more requires an actual successful page, a remaining server page and no error. The existing balance and asset-points array contracts still end after one response. Income and paged-points contracts still use raw loaded rows for paging.
- Direction filtering remains presentation-only and does not change request/page progress. Existing row ordering, de-duplication, sign/direction handling, missing amounts/currency and point-unit formatting remain unchanged. Source review found no need to replace those contracts.
- Returning from a ledger continues the existing asset refresh path; leaving invalidates the pager generation. No automatic finance writes, payment, withdrawal submission or redemption capability was enabled.

## Changed paths

- `Core/WalletCommerceSafety.swift`: ledger pager only; reader and dormant mutation adapter unchanged.
- `App/WalletCommerceViews.swift`: ledger state presentation and identifiers only; prior asset-stage fix retained.
- `App/WalletCommerceFixtureHost.swift`: synthetic denied/401/transient/empty ledger responses only.
- `Tests/CoreTests/WalletCommerceTests.swift`: ten new focused methods.
- `Tests/AppUITests/WalletCommerceFlowTests.swift`: five new focused methods.
- This dedicated delivery note. No project/CI registration changes.

Existing `Package.swift` discovers `Tests/CoreTests`. The existing Xcode project references the UI suite and wallet source/fixture files. Only existing registered suites were extended.

## Authored regressions (all NOT_RUN)

Core additions cover: denied/401 classification; permission loss after a successful page; transient failure versus successful empty array and retry; ledger-kind changes; first-page duplicate dispatch; cancel plus late response followed by a newer result; account change while loading and subsequent recovery; cancellation versus business failure; actual Task.cancel with a non-cooperating transport returning late; old-generation completion while the new request is still in flight. The existing same-page retry/preserve-earlier-rows test remains unchanged.

UI additions follow Assets into balance or asset-points: denial with no retry/load-more/empty; 401 sign-in with no retry; transient balance failure then server-row recovery; successful empty asset-points without error; signed-out ledger without empty-success. Existing returning-to-assets refresh and signed-out account tests remain.

No test runner, compiler, app, simulator, CI trigger, linter or live service was executed for this delivery. The authored cases are a future verification plan, not passing evidence. Real ordinary-navigation/device, direction-menu interactions, accessibility/localization and backend readback still require approved runtime verification.

## Rollback and remaining boundaries

Revert the five changed source/test files to the exact parent above, preserving all earlier wallet assets work. This patch has no migration or persisted schema. Approval issuance remains separate and default closed; navigation is not authority. No credentials, real account data or financial mutations are part of fixtures or delivery. Full product parity and other wallet/withdrawal/commerce actions remain separately scoped.
