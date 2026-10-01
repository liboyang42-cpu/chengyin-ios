# Merchant read-only native module

## Delivered surfaces

- Server-authorized merchant home: store identity and role; inactive application summary; owner-only pending-work and recent-event sections; owner plus finance-permission revenue and seven-day amounts
- Merchant orders: server-side order/aftersale filters in a native sheet/Form, pull-to-refresh, empty/error/loading handling, selectable read-only order summary sheets
- Merchant-hosted projects: an explicitly MERCHANT-scoped first-page list, server-supplied type/state/acceptance labels, schedule/statistics, selectable read-only summary sheets, and an explicit notice when the server reports more rows
- Opt-in DEBUG fixture roots: owner, finance employee, disabled identity, first-access retry, and empty lists; entirely offline

Summaries deliberately show the fields already returned by their list response and say so. They do not claim to call a nonexistent order/project detail endpoint. There are no fake menu destinations, verification actions, role enrollment, project edits, refunds, payments, deletions, remote images or production URL defaults.

## Source evidence

Flutter source is unchanged in the sibling `app-audit` checkout.

| Native behavior | Flutter evidence |
| --- | --- |
| Authoritative active identity, fixed roles, permission names, inactive application validation | `lib/data/api/merchant_api.dart`, `MerchantAccess`; `lib/core/merchant_access_provider.dart` |
| Owner-only dashboard/todo/events; revenue also requires finance:read | `lib/feature/merchant/merchant_home_page.dart`, `_Workbench` |
| Dashboard revenue strings, pending counters, seven-day series | `lib/data/models/merchant_dashboard.dart` |
| CNY domain, absence is not zero | `lib/feature/merchant/merchant_money.dart` |
| Order fields, known order statuses 0…6 and aftersale states 1…4 | `lib/feature/merchant/merchant_orders_page.dart` |
| Exact `aftersaleStatus` spelling; seller must not be sent | `lib/data/api/merchant_api.dart`, `merchantOrders`; `test/data/api/merchant_orders_test.dart` |
| Merchant-hosted scope | `lib/feature/merchant/merchant_game_node_page.dart`, `merchantHostedProjectsProvider` |
| Project first-page request and response | `lib/data/api/my_project_api.dart`, `page`; `lib/data/models/my_project.dart` |
| Distinct review/account statuses and disabled precedence | `lib/data/models/merchant_application.dart` |

No backend repository or live server was consulted. These contracts are source-backed migration contracts, not independently verified live-backend behavior.

## Exact read contracts

All use POST, raw Authorization token (no Bearer prefix), JSON Accept, 20-second request timeout and no cache. Inject `APIConfiguration` and `HTTPTransport`; none is created by the UI.

| Route | Body | Response data | Required server access projection |
| --- | --- | --- | --- |
| `/api/merchant/access/me` | none | access object | signed-in token |
| `/api/merchant/dashboard` | none | dashboard object | active owner AND merchant:finance:read |
| `/api/merchant/todo-summary` | none | todo object | active owner |
| `/api/merchant/events` | `{}` JSON | bare array | active owner |
| `/api/merchant/orders` | JSON with optional `status` and `aftersaleStatus` only | bare array or `{rows:[…]}` | merchant:order:read |
| `/api/project/my` | multipart: type=all, state=all, ownerType=all, scope=MERCHANT, pageNum=1, pageSize=200 | `{rows:[…], total:…}` | merchant:project:manage |

The project API source only exposes first-page reads. This module does not invent a next-page contract. The source home requests 10 rows; this dedicated listing uses the source API's existing 200-row default and discloses a partial result using the reported total.

Unknown order/aftersale codes retain their numeric value and receive no invented meaning. Project state/type labels stay server text. Event times stay the source `MM-dd HH:mm` text; no year/timezone is guessed. Money uses CNY because the merchant source explicitly establishes that currency, and is normalized with Decimal rather than Double. Missing, blank or invalid amounts remain an em dash. Revenue strings are preserved in the model.

## Authorization and session integration

`MerchantAccess` can only be decoded from a server projection; it has no role-selection initializer. Active must be Boolean, the merchant ID positive, and the role one of the five known fixed roles. Only supported known permissions are retained. Missing permissions grant nothing; malformed permission containers fail closed. Inactive access clears permissions, and application presentation requires a recognized applicationState, owner role and valid status/accountStatus summary.

Core methods independently reject insufficient access before transport. This is a UI/request-preflight gate, not a replacement for backend enforcement. Do not derive this access object from Account.effectiveRole, Account.userType, onboarding choices or a merchant entry button.

`MerchantHomeView<Reader: MerchantReading>(reader:)` expects an existing NavigationStack. It does not create a nested root stack. `MerchantReading` is an @MainActor ObservableObject protocol:

- isConfigured: Bool
- isSignedIn: Bool
- sessionRevision: UInt64
- merchantAccess() async throws -> MerchantAccess
- merchantDashboard(access:) async throws -> MerchantDashboard
- merchantTodo(access:) async throws -> MerchantTodo
- merchantEvents(access:) async throws -> [MerchantEvent]
- merchantOrders(access:filter:) async throws -> [MerchantOrder]
- merchantProjects(access:) async throws -> MerchantProjectPage

Wire those calls to the current session's token and MerchantService's `access`, `dashboard`, `todo`, `events`, `orders`, `projects` methods. Each session method must capture its epoch/token before awaiting, reject responses after a session change, and route matching 401s through the existing expiration logic. Publish sessionRevision changes on logout/account replacement. Keep the adapter/session alive for the navigation lifetime.

The observable reader is watched directly, so revision changes synchronously hide old-account state. Read-model generations ignore older refresh responses. The UI also checks revision between access/me and the subsequent list read. Order and project destinations re-fetch access on every load rather than inheriting an old navigation grant. Sheets are dismissed on revision change, and their contents independently check session identity. Do not clear home state in onDisappear: native NavigationLink pushes also trigger disappearance and clearing its root would destroy the navigation destination.

Root integration still owns AppSession, AccountView/root navigation, shared localization catalog, project generation and CI. No such shared files were edited by this module.

## Localization

`docs/merchant-localizations.json` contains independent `{key,en,zh-Hans}` entries for root merge. Dynamic status/role keys are included. Existing `action.retry`, `auth.notConfigured` and `auth.expired` keys are reused. Server labels and original event/time text are not translated or remapped.

## Verification

- Added 15 pure contract tests and 10 synthetic transport tests under `Tests/CoreTests/Merchant*`
- Coverage includes fail-closed role/permission/identity data, owner/finance distinction, inactive account states, exact routes/body encodings/filter spelling, no merchant ID parameter, money precision/absence, unknown statuses/types, server times/labels, malformed envelopes, 401/403/business failures, invalid headers and no transport retries
- DEBUG fixture root supports `--uitesting-merchant-fixture owner|finance|inactive|retry|empty`, after root wiring
- Static localization-key coverage and `git diff --check` are performed locally
- Swift/Xcode are absent from this Linux workspace. Swift tests, app compile and fixture simulator tests are NOT RUN here and require root's existing macOS CI workflow
- No live backend, signing, device deployment, commit, push or PR was performed

Suggested root UI checks: owner dashboard to orders to summary to dismiss/back/reopen; filters apply/cancel/reset and empty result; projects summary and back/reopen; finance employee never requests or sees revenue/todo/events; inactive access has no operating links; access retry; logout/account replacement while a sheet or load is active; bilingual layout and Dynamic Type.
