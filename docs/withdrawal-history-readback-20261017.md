# Withdrawal history and support source delivery — 2026-10-17

CY-HANDOFF: IOS

Status: SOURCE_DELIVERED_UNVERIFIED. Tests, compilation, app/simulator/device, CI and live business readback are NOT_RUN. This is one bounded read-only flow, not full application acceptance.

## Baseline and coordination

- iOS: `liboyang42-cpu/chengyin-ios`, `migration/native-ios`, exact parent `6e24e750b805141efb4dfe8073d452ceac9cc830`, tree `1225c5cfa59b71c5bb1b88e23a712f8d445cb9d1`.
- Reread IOS_START_PROMPT, IOS_HANDOFF, BACKEND_CHANGES, COORDINATION, OWNERSHIP and TASKS on `liboyang42-cpu/hengyin`, `codex/mini-bugs-backend-cloud-plan-20261015`. Current control commit verified as `60064301f61a72103e094cd9e5ec305bfe784b85`; this is not a deployed business version.
- [iOS handoff](https://github.com/liboyang42-cpu/hengyin/blob/60064301f61a72103e094cd9e5ec305bfe784b85/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), [backend changes](https://github.com/liboyang42-cpu/hengyin/blob/60064301f61a72103e094cd9e5ec305bfe784b85/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md).
- I04 / BK-ASSET existing readback boundary; NO_API_CHANGE. No server state, DTO, accounting, payout policy or pagination change. TEST_DEPLOYED=NO; no backend files/shared control logs edited.

## Actual gaps and changes

1. The withdrawal list did not pass its existing unavailable flag to the error view. A configured reader whose read grant was denied incorrectly offered retry. The list now passes both unavailable and unauthorized states, preserving retry for transient/business failures.
2. History exposed server status but had no direct support fallback. It now opens the existing WithdrawalSupportContactView in a sheet, including after error or successful empty history. Close returns to the list; existing navigation returns to the wallet. A scope-triggered reload dismisses the sheet.
3. Shared WalletScreen could return early after a scope change while leaving loading set; cancellation became a generic failure. Loading cleanup now belongs only to the matching generation through defer. Scope/stale-session changes clear state, cancellation is silent, and a new read clears loadedScope. An old completion cannot clear the newer request's loading or publish an old value.

The shared screen change also applies to its existing asset/product/cart/checkout/task consumers. It changes only request generation, cancellation and scope cleanup, not their service calls or product behavior. Previous asset and ledger fixes remain intact.

## Existing contracts deliberately preserved

- WalletWithdrawalRecord requires a positive ID and amount and an explicit integer status in 0...3. Existing meanings remain pending review, approved, rejected and paid. Approval is not payment. Missing/null/unknown status or missing amount still fails decoding; none becomes paid or an empty success.
- History still calls only the existing bodyless POST api/withdrawal/list. Its array/rows/list decoding, masked account, server currency and limited-total notice remain. No invented page arguments or load-more.
- Support uses the inherited environment reader already injected by QuestifyApp. AppSession's source and approval still default to nil. The existing reader checks current account/epoch, namespace, market, approval, expiry, and refreshed configuration before copying a contact. No new contact, endpoint, approval, credential or financial data transfer is introduced.
- Contact-sheet production changes are accessibility identifiers only. Its existing clear-on-close/background/disappear, local-only expiring contact clipboard and action-time revalidation remain unchanged.
- No withdrawal submission, bank form, payment, redemption, reward, mutation adapter or capability registry changed or enabled.

## Changed files

- App/WalletCommerceViews.swift: shared read cleanup and withdrawal-only presentation/navigation.
- App/WithdrawalSupportContactView.swift: two accessibility identifiers.
- App/WalletCommerceFixtureHost.swift: synthetic withdrawal denied/401/transient/empty/missing-status responses.
- Tests/AppUnitTests/WalletHistoryCompositionTests.swift: four new methods for denied/401 recovery, actual Task.cancel with non-cooperating late success, old completion while a new read remains in flight, and scope invalidation without an explicit screen clear.
- Tests/CoreTests/WalletCommerceTests.swift: two new methods covering every status mapping and malformed/missing server evidence.
- Tests/AppUITests/WalletCommerceFlowTests.swift: five new methods covering denied, 401, transient recovery, missing status, empty history → unavailable support → close/reopen → back.
- This dedicated delivery note.

Existing project registration covers the edited App/UI/unit suites. Package.swift already discovers the Core suite. No project, CI, generated manifest or dependency changes.

## Verification limits and next acceptance

Source review, exact original Git-blob checks and final byte hashes only. The 11 new test methods are authored, not run or passed. Existing support configuration tests already describe denied-source/no fetch, expiry/revocation, namespace/market/revision/account ABA, in-flight scope/approval changes and cancellation; those were read, not rerun or altered.

Future approved runtime verification should follow ordinary Account → Wallet → withdrawal history, verify server-backed states and masked account, denied/401/transient reads, support with reviewed configuration and without configuration, close/reopen/back, sign-out/account switch while either read is suspended, both languages and accessibility sizes. Synthetic navigation is not evidence of ordinary-root or device acceptance.

## Rollback

Restore the six edited source/test files to the exact parent above and remove this note. No schema, stored data, migrations or deployment changes. Default capability gates remain closed.
