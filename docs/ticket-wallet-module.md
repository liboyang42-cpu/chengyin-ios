# Native ticket wallet read slice

## Scope and source evidence

Bounded native implementation against Flutter commit `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`, based on native `b47b34aeef78f736c70f8652b9af6f3bd63b802d`.

Source files:

- `lib/feature/tickets/tickets_page.dart`: `myTicketsProvider`, `WalletSnapshot`, merge/failure rules, `walletTicketAction`, ticket face/stub
- `lib/feature/tickets/ticket_wallet_copy.dart`: localized ticket state and notice copy
- `lib/feature/tickets/ticket_detail_page.dart`: fresh detail, contact/number/date, entitlements, pending count and redemption gate
- `lib/data/api/activity_api.dart`: `topicTicketList`, `ticketList`, `ticketInfo`
- `lib/data/models/activity.dart`: `MyRegistration`, `RegistrationDetail`, `Entitlement`
- `lib/data/models/registration_read_failure.dart`: backend-message versus fallback provenance
- Audited but not implemented: `pass_page.dart`, `explore_completion_section.dart`, team-entry and order/payment routing

The delivered denominator is three authenticated reads (route list, activity list, registration detail), four data projections (ticket, embedded owner, entitlement, wallet with partial failure), source status/action/redemption gates, merged native list and native detail, distinct guest/loading/empty/partial-empty/failure/unavailable/unconfigured states, and account/epoch/token plus request-generation isolation. This does not represent full migration of all four Flutter ticket surfaces.

## Wire contracts and behavior

1. `POST /api/registration/list`, multipart `owner_type=1`: accepts `data` array or `data.rows` object. Missing/null data is source-defined empty, not a network fallback. No `owner_type=3` order read, pagination, status or invented filter is sent.
2. The independent `POST /api/registration/list`, multipart `owner_type=2`, requires `data` array (missing/null is source-defined empty). Source supports an optional `is_online` argument; the wallet itself does not set it and this narrow service does not expose it.
3. Merge is route tickets followed by activity tickets, preserving each response order and retaining all product types, including null and classic. No sort, client-generated ticket, product filter or deduplication is introduced. List identity uses response index so repeated server IDs do not collide in SwiftUI.
4. One failed lane returns the successful lane and an explicit lane warning, including when the successful lane is empty. Partial-empty copy says the wallet is incomplete. Both failed lanes use the route failure. A current 401 from either lane closes the entire private wallet; this is an intentional fail-closed strengthening of Flutter's half-failure handling.
5. `POST /api/registration/info`, multipart `id`: fetched by ID on navigation, refresh and return from background. A row snapshot is never treated as current detail. Null/missing detail or a different ID is unavailable. A malformed detail/row is a failed read, never a blank successful ticket.
6. HTTP success and `code=200` are required before payload decoding. HTTP/envelope 401 takes priority over payload and message decoding. Explicit backend `msg` strings, including empty strings or Chinese strings identical to fallback copy, retain server provenance. Backend prose is rendered verbatim rather than as localization keys; other failures have native localized explanations.
7. Requests use the shared raw `Authorization` header, multipart encoding, ephemeral injected transport and `.reloadIgnoringLocalCacheData`. No independent production endpoint or transport is created by this module. There is no disk cache, token persistence or logging.

Ticket display status preserves source precedence: verified first, then cancelled/expired, then paid/ready, then known unpaid. Action routing separately uses registration status: paid tickets open detail; unpaid, cancelled, expired and unknown rows show explanatory text. Payment/order navigation is deliberately not represented as a functioning action. Unknown registration status is explicitly unknown rather than mislabelled unpaid, a fail-closed divergence from Flutter's default `pending` label.

Embedded activity metadata precedes embedded topic metadata. Amounts remain optional Decimal; unknown is not zero. Only audited fields used by the ticket slice are projected, not the full order/payment/refund entity. Detail keeps source-supplied number/date/contact/masked phone and verification time in memory. No personal data is included in fixtures.

Entitlement order and source status labels are retained. A ticket may be `verificationStatus=1` and still have pending entitlements; pending count, rather than the ticket's first-verification flag, controls its read-only explanation. Missing/unknown entitlement status never becomes pending and cannot falsely claim all benefits are redeemed. Valid record and entitlement IDs must be positive; malformed rows fail their lane instead of being silently dropped. These are explicit data-quality safeguards over permissive Flutter defaults.

## Integration

Owned files are `Core/TicketWallet*.swift`, `App/TicketWallet*.swift`, `Tests/CoreTests/TicketWalletTests.swift`, `Tests/AppUITests/TicketWalletFlowTests.swift` and this document/localization JSON. No shared AppSession, app entry, catalog, project or workflow edits are included in the module handoff.

1. Create `TicketWalletService(configuration:transport:)` only from approved existing configuration and transport. Nil service denotes unconfigured access.
2. Retain one `TicketWalletSessionReader(service:currentSession:onUnauthorized:)` in AppSession. The session provider must build `TicketWalletReadSession(accountID:epoch:token:)` from the verified active account, monotonic session epoch and exact token. Guests return nil. Never synthesize credentials or an account ID.
3. Observe AppSession in a host and present `TicketWalletView(reader:onClose:onSignIn:)`. It owns a NavigationStack. Supply sign-in only when an actual sign-in path is available. Use `.id(reader.scope)` on the host to clear navigation on identity/token changes. Do not recreate the reader on every render.
4. For an authenticated direct detail route, push `TicketWalletDetailView(id:reader:)` in an existing stack. The host must still observe session changes. Both views hide data immediately whenever scope or authentication stops matching.
5. Advance the session epoch for every session transition, including logout/relogin with identical credentials. Reader scope also changes if account or exact token changes without an epoch change. Credentials never enter the navigation key or UI.
6. The reader checks captured account/epoch/token and opaque scope after success and failure. Only a current authenticated 401 invokes `onUnauthorized`, once for the paired wallet read. Stale success/failure/401 and cancelled reads cannot cross sessions or invalidate newer credentials.
7. `TicketWalletReadModel` drops stale overlapping completions and clears prior content at fresh-read start. Navigation disappearance cancels pending publication while retaining same-scope source rows, so pushing detail does not destroy the NavigationLink. Scope changes still hide that content immediately. The UI refetches on visible appearance/refresh and genuine background-to-active return, without an extra initial-active refresh.
8. Merge `docs/ticket-wallet-localizations.json` (54 English/Simplified Chinese keys) into the existing String Catalog. Existing shared `action.close` is reused. Regenerate the shared project using the repository tool after copying the owned Swift files.
9. Add DEBUG `ModuleFixture.ticketWallet` with raw value `ticketWallet` and `TicketWalletFixtureHostView()`. UI tests launch `--uitesting-module ticketWallet`. Optional `--uitesting-ticket-wallet-scenario` accepts `content`, `empty`, `partial`, `partialEmpty`, `failure`, `unauthorized`, `unconfigured`, `unavailable`, `guest`, `refreshed`, `sessionChange`. Fixtures are synthetic and have no network service, code, QR, payment credential or real record.

## Explicitly incomplete surfaces

- Dynamic code issuance (`/api/verify/dyncode/issue`), countdown, refresh/reissue, QR images and manual redemption codes are not implemented. No scannable-looking placeholder or inert code pretends to work; native detail states this clearly.
- Merchant verification/redemption, payment, refunds, order list/detail, Apple/WeChat payment integration, ticket transfer, authoring and every mutation are outside this slice.
- Wallet team index and team navigation, focus-ID scrolling, exploration completion album/rewards/revisit/follow/join/next-edition actions, image loading and linked source activity/topic navigation remain pending. No empty completion shell or fabricated team data is shown.
- The native layout uses system List/NavigationStack, Dynamic Type and localized controls rather than reproducing Flutter's ticket artwork/punched-paper style. Product-level visual, VoiceOver and device acceptance remain open.

## Verification status

Fifteen authored core tests exercise exact request fields/headers/cache policy, fresh paired reads and source order, lane-specific envelopes, missing/null versus malformed data, partial-empty and double-failure behavior, authorization precedence, server-message provenance, detail matching, invalid requests, status/action matrix, entitlement counts and unknown states, source owner precedence and nullable amounts, guest/configuration gating, stale account/epoch/token/signout success/401, paired cancellation/current 401, and overlapping/stale/disappeared screen requests.

Six authored XCUITests cover detail/entitlements/back/reopen with no functioning redemption/payment action, partial-empty retry, unavailable retry, fresh status replacement, session-change privacy clearing, and distinct empty/failure/guest/unconfigured screens.

This Linux authoring environment has no Swift/Xcode compiler or iOS simulator. Domain tests and UI tests are **authored, not executed locally**. JSON parsing, localization coverage, owned-file whitespace and no-mutation-route checks were run locally. macOS core/build/targeted UI CI is required after integration; these static checks do not demonstrate a functioning iOS binary. No live API requests, redemption, payment/refund, commits, pushes, pull requests, local Mac access or Codex task creation occurred during authoring.
