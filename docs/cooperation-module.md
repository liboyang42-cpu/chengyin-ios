# Native cooperation reads

## Scope and provenance

Source audit: Flutter `a63e9e91`, `lib/data/api/coop_api.dart`, `lib/core/network/dio_client.dart`, models `coop_invite_row.dart`, `coop_pool.dart`, `coop_candidate.dart`, and pages under `lib/feature/coop/`. Native starting point: `a1be59e`. This is a bounded read-only slice, not complete cooperation migration.

Implemented native SwiftUI surfaces:

- Received/sent cooperation invitations, fresh directional invitation detail and source terms/replies/contact fields
- Independent club leadership-application history and received merchant registrations under the appropriate inbox direction
- Cooperation pool, including the server's `hasClub` gate and all eight known source states
- Topic-publisher candidate directory, reached from the owner's received application/registration topics, with server-enforced ownership

Out of scope: official platform merchant invitations, invitation creation/dispatch/acceptance/rejection/cancellation, application submission/withdrawal/decline, candidate confirmation/rejection, conversation creation, supply/template operations, contracts, deposits/payments/refunds, finance/my-business ledgers, settlements, reviews and complaints. The UI explicitly explains unavailable native actions; no misleading working controls or empty implementations are provided. No production requests or real agreements were executed.

## Exact requests and envelopes

All reads are JSON `POST`, with raw `Authorization` and no query string. No Bearer prefix, account ID in a body, synthetic pagination, or guessed routing is introduced.

| Route | Body | `data` contract |
|---|---|---|
| `/api/coop/list` | `{}` | Object containing `sent`, `received`, optional `slots` |
| `/api/coop/pool/mine` | `{}` | Bare application array; includes processed history |
| `/api/coop/pool/received` | `{}` | Bare received club-application array |
| `/api/coop/candidates/received` | `{}` | Object containing `rows`, optional `hasMore` |
| `/api/coop/pool/list` | `{}` | Object containing `rows`, `hasClub` |
| `/api/coop/candidates` | `{"topicId": <positive integer>}` | Object containing `clubApplies`, `registrations` |

Received inbox loads three independent sources; sent inbox loads two and never requests received registrations. Each source has a separate success/failure section. A failure does not become an empty successful section. Any current HTTP/body 401 closes the entire private inbox, even when another source succeeds. HTTP/body 403 and the audited candidate-publisher denial are permission states. Genuine server message text retains its provenance and is displayed verbatim. Refresh retries the read snapshot, never a mutation.

Detail makes exactly one new `/api/coop/list` request, selects only the requested direction, and uses its slots. A same ID in the other direction does not satisfy the lookup. Absence has a distinct no-retry state. Repeated IDs within the selected direction yield an ambiguous-identity state rather than silently choosing an agreement. List rows use per-response ordinal identity to avoid dropping duplicate rows.

## Honest data presentation

- Unknown/missing status remains unknown; unknown pool state never defaults to open
- No missing fee, rate, deposit or slot count is coerced to zero or an invented default amount
- Fixed fee/deposit values are preserved, but currency remains explicitly unconfirmed because the audited payload has no currency code. The source UI’s hardcoded yen/yuan symbol is not sufficient to establish US/CN settlement currency; no locale-based currency or conversion is introduced
- All supplied contact fields remain read-only; no conversation/call action is created
- Terms, original message and handling reason remain separate. Legacy merchant-node invitations are explicitly historical/read-only
- Game occupancy uses `pending/cap`, topic occupancy uses `accepted/cap`. Missing/invalid occupancy is omitted
- Bare unzoned date strings remain source text, without an invented timezone or countdown. Numeric millisecond timestamps use native date formatting
- Application `scope` is retained in the contract. Historical sent application data comes from `/pool/mine`, never reconstructed from the open pool
- Candidate registration `status` has no audited label mapping, so it is labeled as a source status code rather than borrowing received-registration `auditStatus` meanings
- `hasMore=true` is disclosed without inventing a pagination request unsupported by the source wrapper
- Malformed envelopes/rows and missing top-level `data` fail closed rather than silently masquerading as empty data. This intentionally hardens Flutter's permissive defaults

## Session and lifecycle safety

`CooperationReadSession(accountID:epoch:token:)` includes exact credential identity privately. `CooperationSessionReader` exposes an opaque UUID scope, with equality across account, epoch and token. Every result, including 401, is compared against the captured session and scope before return or invalidation. The main actor read model clears previous values at a fresh read, rejects superseded generations, hides mismatched scopes synchronously during rendering, and cancels pending work without removing same-scope navigation rows.

No private persistence, token-based view identity, logging or caching was added. The production composition must continue observing its `AppSession` and rebuild/re-evaluate the reader scope on session changes, as existing private modules do. No authentication role is inferred from a route, picker or fixture.

## Design and accessibility

Uses system `NavigationStack`, inset-grouped `List`, segmented `Picker`, native `NavigationLink`/buttons, semantic Dynamic Type, stacked labeled values, wrap-friendly text and text-plus-symbol states. Readability takes priority over dense equal-weight metadata. No custom spring, parallax, repeating timer, decorative shimmer or fabricated success animation is added; navigation and refresh use native Reduce Motion behavior. No new OS API above iOS 17 is required. Native colors support light/dark and increased contrast by construction; rendered and VoiceOver acceptance remains pending.

## Integration handoff

New owned files only: `Core/Cooperation*.swift`, `App/Cooperation*.swift`, `Tests/CoreTests/CooperationTests.swift`, `Tests/AppUITests/CooperationFlowTests.swift`, `Tests/ContractChecks/test_cooperation_structure.py`, and this document plus `cooperation-localizations.json`.

Parent integration:

1. Copy the files and merge the 98 English/Simplified Chinese localization entries into the existing String Catalog
2. Compose `CooperationSessionReader(service:currentSession:onUnauthorized:)` from the current account, session epoch and current token. Route matched 401 invalidation through the existing safe session flow
3. Add a module/home entry for `CooperationBrowserView(reader:)`; expose `CooperationCandidatesView(topicID:reader:)` only with a known topic ID, with the server still enforcing publisher ownership
4. Add DEBUG fixture module `cooperation` -> `CooperationFixtureHostView`; its flag is `--uitesting-cooperation-scenario`
5. Regenerate the existing Xcode project at the integration root and include cooperation UI tests in the parent-owned cloud workflow

Fixture scenarios: `content`, `empty`, `failure`, `partial`, `partialEmpty`, `noClub`, `forbidden`, `unavailable`, `refreshed`, `guest`, `unconfigured`, `loading`, `sessionChange`. All are in-memory synthetic inputs. They never instantiate an HTTP transport.

## Verification

Locally passed: eight Python source guards (allowlist, fresh detail, partial/auth isolation, session safety, native controls, UI selectors, bilingual state coverage, synthetic JSON validation); `git diff --check` and JSON parsing. All twelve existing tooling tests passed. These checks do not establish Swift correctness.

Added XCTest coverage includes exact route/body/header contracts; direction/duplicate-ID handling; application and registration envelope separation; partial and partial-empty inboxes; unauthorized sibling precedence; candidate permissions; unknown statuses and missing amounts; all eight pool states; slot and cover fallback semantics; malformed data; invalid request suppression; guest/unconfigured gates; account/token/epoch/signout changes; cancellation; matched 401 invalidation; and generation overlap.

Added XCUITest covers detail/back/reopen/direction switches, partial inboxes, no-club/owner permission states, pool unknown states, candidate navigation, refresh replacement, signout hiding private content, empty/error/unavailable states and a Chinese login gate. Selectors target native buttons/navigation controls, never assume sheet element typing or tappability of static text.

Swift/Xcode and simulator execution are unavailable in this Linux worker. Parent cloud compilation, complete XCTest, simulator screenshots, Chinese/dark/accessibility-size/Reduce Motion review, VoiceOver, interrupted/repeated navigation, actual device Release performance and approved live-backend acceptance are separate pending gates. No commit, push or PR was made by this worker.
