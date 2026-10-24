# Wallet assets readback — I04 / B03 / BK-ASSET

CY-HANDOFF: IOS

Status: Source review candidate; runtime validation NOT_RUN. Publication is determined by the subsequent repository commit and branch readback, not by this document alone.

## Baseline and scope

- Repository: liboyang42-cpu/chengyin-ios, migration/native-ios.
- Exact baseline: 85e97226683113e6fea034b4defebf7c92160662.
- Exact tree: d74531a0150d2cdabdd31352f297e50d14aa0e0b.
- First production edit: 2026-10-17 12:26 UTC, App/WalletCommerceViews.swift: unknown-amount branch excludes all monetary rows; asset failure forwards unavailable. Its original blob is 6969b4d089362179cf638583bcf763ece23be5e3 (21,851 bytes), SHA-256 28cd9ba6f13344544d47cbad5c6ec8c4a1c60dfed1a2c123bf8694f188dd242e.

Allowed change paths for this group:

1. App/WalletCommerceViews.swift (asset presentation; internal access to existing WalletScreen for hosted tests)
2. App/WalletCommerceFixtureHost.swift (DEBUG-only asset outcome fixtures)
3. Tests/AppUnitTests/WalletHistoryCompositionTests.swift (existing registered hosted suite)
4. Tests/AppUITests/WalletCommerceFlowTests.swift (existing registered UI suite)
5. docs/wallet-assets-readback-20261017.md

AppCompositionRoot.swift and project.pbxproj were read only. Existing test registrations already include both test files and the fixture host. No new target, dependency, endpoint, capability, payment action, root navigation or workflow change is required.

## Public backend control sources

Read the [public control directory](https://github.com/liboyang42-cpu/hengyin/tree/codex/mini-bugs-backend-cloud-plan-20261015/docs/plans/mini-codex-cloud-20261015): IOS_START_PROMPT, IOS_HANDOFF, BACKEND_CHANGES, COORDINATION, OWNERSHIP and TASKS. Protocol CY-COORD-20261015-v1. I04 preserves existing asset readback and default gates; B03/BK-ASSET backend source and isolated historical test evidence do not establish TEST_DEPLOYED. No runtime target or account was accessed. Current control files remain authoritative over historical handoff snapshots. No backend write was made.

NO_API_CHANGE. Reuse existing WalletCommerceService.stages → api/wallet/stages, WalletFundsStages amountsKnown/currency/amounts, WalletCommerceReader and owner-history lease. Do not guess missing fields or change decoder compatibility. Default walletHistoryReadApproval remains nil; commands and payment/payout gates are unchanged.

## Verified source findings and fixes

1. Before: amountsKnown=false displayed its warning and then displayed numeric pending/disputed/complaint-period/withdrawable values, including apparent zero balance. After: the unknown branch shows only the existing unknown warning; every amount and availability date is in the known branch. Known zero withdrawable still renders zero. Existing currency formatting and not-payout notice remain.
2. Before: the screen recorded unavailable for notConfigured or WalletCommerceSafetyError.unavailable, but the asset page omitted this flag when building WalletIssueView. After: unavailable is forwarded, so a configured-but-denied reader does not offer transient retry. Real HTTP/business failure presentation remains retryable; unauthorized still follows the existing login presentation.
3. The existing loader remains generation- and scope-fenced. Each new load clears the old value and error state; a newer read supersedes an older read; onDisappear changes generation. The existing task(id: reader.scope) clears and reads on appearance and scope change. Reappearance with the same scope is intended to start a fresh view task; actual native navigation behavior remains NOT_RUN. The return fixture changes its authoritative value from zero to seven on the second asset read so its UI test distinguishes refresh from cached data.

## Entry-to-result acceptance map

| Step/state | Existing source or change | Evidence level |
| --- | --- | --- |
| Account entry | AccountView account.wallet → SessionWalletCommerceView → WalletCommerceHomeView assets link | Source read only; no new entry |
| Capability/account | Existing session walletHistoryReader and walletHistoryViewIdentity reset; default lease nil | Existing source and authored composition tests; not executed |
| Loading | Existing WalletScreen loading with added wallet.assets.loading accessibility ID | New hosted test authored |
| Known zero/nonzero | Existing format.amount inside known branch | New zero UI test and recovery-positive UI test authored |
| Unknown including nonzero placeholders | All amount rows excluded | Original UI expectation corrected; additional nonzero UI test authored |
| Denied | funds.unavailable forwarded; no retry in existing issue view | Hosted classification and denied UI tests authored |
| Transient failure → retry → result | Existing reader/service request reused; no mutation | Hosted and synthetic 503-then-result UI tests authored |
| Cancel/return | Existing onDisappear generation retirement and task clear/load | New late-result and same-scope return tests authored |
| Refresh race | Existing newest-generation wins; older completion ignored | New noncooperative older-read hosted test authored |
| Scope loss | Revoked lease invalidates scope; view/model clears and rejects old response | New hosted test authored; existing broader account/role/session tests retained |
| History/support links | Existing asset balance/points history and withdrawal-support destinations retained | No support/payment policy changed |

## Authored regression delta

Existing WalletHistoryCompositionTests: five added methods testAssetScreenLoadingThenResultUsesCurrentScope, testAssetScreenDistinguishesDeniedAndTransientThenRecovers, testAssetScreenCancelledLateResultCannotOverwriteReopenedRead, testAssetScreenNewestRefreshWinsOverNonCooperativeOlderRead, testAssetScreenScopeSwitchCannotRefillOldResult. Uses existing real composition and synthetic Wire; delayed transport deliberately completes after generation retirement. This cancels the screen generation through screen.cancel(); it does not call Task.cancel() and is not evidence of actual SwiftUI task cancellation or native lifecycle execution.

Existing WalletCommerceFlowTests: five added methods testUnknownNonzeroPlaceholdersNeverAppearAsMoney, testKnownZeroRemainsAnExplicitZero, testDeniedAssetReadHasNoRetry, testTransientAssetReadRetriesAndShowsServerResult, testReturningFromLedgerReloadsAssetsInSameScope. The earlier test expecting unknown zero was corrected while retaining its original method name testFundsStagesUnknownCurrencyAndZeroRemainDistinct. New fixture switches are DEBUG-only, restricted to the asset stages path, and other routes use their original offline transport.

These are ten new authored tests and one corrected test, not ten passed tests. No test, static contract runner, lint, compiler, app, simulator, CI, preview or backend was run. Only source reading, diffs, file writes and byte/hash recording were performed. Type-checking, XCTest, UI localization/accessibility queries, actual back navigation, device behavior and live server readback all remain NOT_RUN. The four source/test files and this document are the five integration paths. Independent source review and integration precede any later authorized runtime validation.
