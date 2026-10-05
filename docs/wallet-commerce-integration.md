# Integrated wallet / commerce batch

Integrated into the shared native tree under exclusive ownership. Normal account → wallet host routes assets, income and withdrawal history to the new session reader. That reader defaults to no read grant. Exact account/namespace/deployment/path approval is required to install a read transport; its allowlist rejects all mutations. Existing hidden points/mall visibility stays closed in the normal host, and all mutations remain unmounted. The injectable host can consume source-approved visibility later. Club finance delegates to the existing cooperation reader.

The DEBUG fixture uses --wallet-commerce-fixture and is excluded from production AppSession construction. Wallet translations are merged into Localizable with environment-aware computed strings. The source below describes pre-integration authoring context; its copy instructions have now been carried out.

Swift/Xcode/Apple/UI runtime: NOT_RUN. No remote operations occurred.

---

# Wallet / commerce native migration — additive integration

## Status and scope

Code and synthetic fixtures are isolated in `native-wallet-commerce-new`. No shared main files were edited. No production endpoint/provider was contacted; no purchase, redemption, payout, transfer, account setup or remote operation occurred.

- Swift typecheck/build/unit tests: **NOT_RUN** (Swift/Xcode absent)
- Apple UI/device/VoiceOver/visual tests: **NOT_RUN**
- Python source assertions: 11 passed
- Tree-sitter syntax preflight: 8 Swift files passed; supplementary syntax only, not compilation

## Additive files

Copy `Core/WalletCommerce*.swift` to the existing Core target, `App/WalletCommerce*.swift` to the App target, and `Tests/CoreTests/WalletCommerceTests.swift` to the current QuestifyCoreTests target. Copy `Tests/UITests/WalletCommerceFlowTests.swift` to the existing `Tests/AppUITests` directory/target.

The new code uses existing `APIConfiguration`, `APIError`, `HTTPTransport`, `AuthRequestBuilder`, `OperationEndpointApproval`, `OperationPendingRecord`, `OperationPendingJournal` and `OperationDefaultsJournal`. Do not duplicate those types. The existing Package.swift automatically discovers Core and CoreTests files. Follow the project's existing Xcode generator for App/UITest file membership.

Merge the keys from `Resources/WalletCommerceLocalizations.xcstrings` into the existing Localizable catalog (preserve unrelated keys); do not assume `Text("wallet.key")` reads a separately named string table. The fragment includes English and Simplified Chinese.

## Composition and visibility

1. Default reader is `WalletCommerceReader(service: nil, session: ...)`; the nil service gate is intentional. Live deployment/region/account verification is a separate task.
2. For authorized reads, inject the exact configured `WalletCommerceService` and existing ephemeral, no-redirect HTTPTransport. The session closure returns the current account namespace, account ID, unique session epoch and in-memory token. Never persist/log its token.
3. Reset each navigation subtree with `.id(reader.scope)` when account, deployment or epoch changes. The host must observe session changes; the reader closure itself is not an ObservableObject.
4. Wire existing typed destinations to `WalletAssetsView`, `WalletIncomeView`, `WalletLedgerView(kind: .points)`, `WalletProductsView`, `WalletCartView`, `WalletWithdrawalsView`. `WalletCommerceHomeView` is optional and has all visibility gates false; it does not install an entry itself. Copy existing visibility policy; do not add a root tab or expose hidden gamification/subscription paths.
5. Income's Club button must route to the existing cooperation-finance destination. It is not an income event filter. Keep the existing creator-income summary, OrderLifecycle and ticket issuance ownership.
6. Source profile has points/mall links in its achievements section; preserve that established placement only when that section's existing gates permit it. Do not infer feature enablement from a successful request.
7. Source withdrawal is historical read-only. Keep existing platform-support handoff behavior. No new bank form, submit/preflight/transfer method or provider integration exists. The source's hardcoded support contact is not embedded into this new financial module; a current approved support surface must own any contact/copy action.

## Dormant writes and ambiguous outcomes

`WalletCommerceDormantAdapter` authors exact add/update/delete/redemption requests, but `enableReviewedWrites` defaults false and no UI calls `execute`. Only synthetic tests enable it with a fake transport. Do not flip this gate as part of integration.

Future authorized wiring must obtain `reader.checkout(cartIDs:)`, which creates an account/epoch-bound `WalletCheckoutSnapshot`; then create an immutable review. A raw preview cannot be substituted at the public API. The review requires the same selected cart IDs, address ID, known item amounts/fees/total/balance and a sufficiently recent snapshot. It does not claim stock or fulfillment guarantees. A fresh server preview is still only a preview.

Execution binds exact deployment/account/path approval and current epoch, persists an account-wide cart/redemption replay lock before dispatch, consumes the review once and clears the lock only after an acknowledged source response (and positive order ID for redemption). Cancellation, timeout, stale account, malformed receipt and errors after dispatch retain the lock across process restart and new login epochs. No local reset/retry shortcut is provided because the source has no correlatable operation receipt/idempotency contract. A returned order ID is not payment, refund or fulfillment success; forward it to existing OrderLifecycle only after an independently authorized future integration.

Journal content is restricted to namespace/account owner, generic target, operation UUID and acknowledged count. No addresses, bank details, names, remarks, prices, tokens or full request bodies are persisted. Address decode retains ID and masked phone only; withdrawal decode retains masked account only, including masking short strings fully.

## UI fixture and test wiring

Add one DEBUG-only case to the existing `--uitesting-module` switch: `walletCommerce` -> `WalletCommerceFixtureHost()`. This host uses synthetic transport exclusively. `--wallet-failure` forces read failures. Do not install it in normal navigation. No fake mutation success is provided in this fixture.

Then run on macOS:
- `swift test --filter WalletCommerceTests`
- Existing Xcode build and WalletCommerceFlowTests UI scheme
- Both languages; large Dynamic Type; VoiceOver reading order and 44-point controls
- Back navigation from cart preview/product detail; refresh/retry; logout/account/region switch during slow loads; background/foreground interruption
- Additional hold-and-release fake transport tests for cancellation/overlapping requests, duplicate submits, persistence corruption and wrong-deployment approvals

Check in source tests and reports without describing the Linux syntax/source results as runtime verification.

## Deliberate source limits

Legacy balance/asset-points endpoints return complete arrays and expose no page parameters. User-points and income use real `pageNum/pageSize`; points direction filtering is local over loaded records. Product/cart/withdrawal wrappers expose only the first returned batch even if backend data has `total`; UI marks truncation instead of inventing paging parameters. Withdrawal returns array, `data.rows`, or `data.list`. Stages fail independently of ledgers; missing/invalid amounts never turn into zero. The date parser rejects impossible calendar dates (stricter than the source regex).

Monetary currency is nullable, never guessed from language/market. Shop prices and fees remain points, never divided by 100 or rendered as CNY. Income event/direction and withdrawal state are separate. Rejected-withdrawal returns are ledger events; approved withdrawal is distinct from paid out. Ledger rows have no fabricated payout status.

Product detail currently provides accessible plain-text HTML fallback and SKU/price/stock fields. Rich external gallery rendering remains a host image-pipeline integration; no remote HTML is executed. Bank/contact data, identity details and logs are intentionally minimized.
