# Club read-only native module

## Delivered surfaces

- Club home preserving the source's four separate response sections: created, joined, nearby and club activities
- Separate created-clubs list using `/my`; it never treats that response as joined clubs
- Club directory and explicit name search; no invented category, location or pagination request
- Club detail: introduction, source metadata, membership status and creator/administrator distinction
- Member list with loading, empty, denied, sign-in, malformed-response and retry states
- Offline DEBUG fixtures for owner, member, visitor, legacy administrator without membership, empty, retry, forbidden, guest and missing-member-list states

All screens are native SwiftUI. They use an injected observable reader, do not read credentials, and have no default host. There are no join/quit, invite, create, edit, delete, role, payment, refund, chat-creation or other write methods. Artwork URL fields are retained as source strings but are not loaded remotely in this slice.

## Source evidence and scope

All contracts come from the unchanged sibling `app-audit` Flutter source. They are not independently verified against a backend or a live account.

| Behavior | Source |
| --- | --- |
| POST paths, body encoding and response containers | `lib/data/api/club_api.dart`: `home`, `my`, `list`, `searchByName`, `detail`, `members` |
| Models, join-status absence, viewerIsAdmin, section and home-event shapes | `lib/data/models/club.dart`: `Club`, `ClubMember`, `ClubHome`, `ClubHomeEvent` |
| Home versus directory and owned versus joined separation | `lib/feature/club/club_controller.dart`: `clubHomeProvider`, `clubListProvider`, `clubMyProvider` |
| Detail member visibility uses isOwner OR isJoined | `lib/feature/club/club_detail_page.dart`: `_ClubOverviewTab` |
| A member row's role/isOwner is not the viewer's authority | `lib/data/models/club.dart`; `lib/feature/club/club_detail_page.dart`: `_MemberSection`, `_MemberRow` |
| Empty list with nonzero reported member count is unavailable, not no-members | `lib/feature/club/club_detail_page.dart`: `_MemberSection` |
| 401 requires sign-in; 403 is not a sign-in failure | `lib/feature/club/club_login_gate.dart` |
| Legacy governance is isOwner OR detail.viewerIsAdmin | `lib/data/models/club.dart`: `canGovern` |

The CRM customer list and `club:member:list:read` permission are a different surface from the basic `/members` list. This module does not substitute the CRM gate for source detail membership, does not call access/me, and does not expose CRM/governance controls. `canGovern` is preserved in the domain contract for clarity but grants no operations in this module.

## Exact read contracts

Every request uses POST, raw Authorization when present (no Bearer prefix), JSON Accept, the existing 20-second timeout and no-cache policy. Configuration and HTTPTransport must be injected. The service creates no URLSession.

| Path | Body | `data` shape |
| --- | --- | --- |
| `/api/club/home` | JSON `{}` | `{owned:[], joined:[], nearby:[], events:[]}` |
| `/api/club/my` | JSON `{}` | `{owned:[]}` |
| `/api/club/list` without search | empty multipart FormData | bare array |
| `/api/club/list` with name | JSON `{name: string}` | bare array |
| `/api/club/detail` | multipart `id` | club object |
| `/api/club/members` | multipart `clubId` | bare array |

Home events are `id/title/cover/clubId`, not a topic entity's `name/imgUrl` fields. The source identifies these as classic topic activities; the home accepts an optional `onTopicDestination(Int)` callback so root can wire an existing native topic destination. Without that callback they remain honest read-only rows, with no dead button or invented detail endpoint.

Directory/member data must be actual arrays. Missing/null/wrong containers fail rather than showing a successful empty list. Home's absent section arrays and `/my`'s absent owned array preserve source empty defaults; absent `data` itself is malformed. Positive numeric record IDs and matching detail identity are required. Malformed Boolean role flags fail instead of becoming grants. Unknown numeric join states and member roles remain unclassified; missing join state never means pending. `joinPolicy` follows source normalization (1 approval, otherwise 0). Source strings/URL values are not rewritten. Levels outside source L1–L5 are not given a fabricated label.

HTTP or envelope 401/403 is evaluated before payload parsing, including a malformed optional message. 401 is the only failure which may expire a session. Verbatim server messages are retained for display, while local messages use localization keys. Reads do not auto-retry.

## Exact root integration

New production files are `Core/ClubContracts.swift`, `Core/ClubService.swift`, `Core/ClubReading.swift` and `App/Club*.swift`. No AppSession, root navigation, project, package or shared catalog file was edited.

1. Build `ClubService(configuration: approvedConfiguration, transport: existingTransport)` only when a root-approved configuration exists. Pass nil service otherwise.
2. Create and keep `ClubSessionReader(service:currentSession:onUnauthorized:)`. The synchronous currentSession closure constructs a `ClubReadSession(accountID:epoch:token:)` from the current verified account/credential, or `ClubReadSession(guestEpoch:)` for a guest. Never persist/log this snapshot. Advance the epoch on logout, expiry, account replacement, credential replacement and same-account relogin.
3. Add `ClubReading` conformance to the existing ObservableObject session/adapter and forward:
   - `isClubConfigured: Bool`
   - `clubIdentity: ClubReadIdentity`
   - `clubHome() async throws -> ClubHome`
   - `clubOwned() async throws -> [ClubRecord]`
   - `clubDirectory(name: String?) async throws -> [ClubRecord]`
   - `clubDetail(id: Int) async throws -> ClubRecord`
   - `clubMembers(id: Int) async throws -> ClubMemberDirectory`
4. Publish observable account/epoch changes before showing any replacement account. Views observe that same object and identity-check stored data synchronously. Root should reset the club navigation stack when identity changes so another account does not inherit prior navigation/search state.
5. In onUnauthorized, expire only if the root's live credential/account/epoch still equals the supplied snapshot. The reader already suppresses old-session errors; keep the existing root expiration guard too.
6. Place `ClubHomeView(reader: session, onSignIn: ..., onTopicDestination: ...)` in an existing NavigationStack. Sign-in callback opens the existing login flow; identity change retries the visible read. Omit the topic callback until a real native topic destination is available.
7. Merge `docs/club-localizations.json` into the root catalog and regenerate the project with the existing generator after integration. The package discovers Core/tests automatically.
8. Under DEBUG only, parse `ClubFixtureScenario.selected(arguments:)` and display `ClubFixtureRootView(scenario:)` when opted in. Flag: `--uitesting-club-fixture owner|member|visitor|administrator|empty|retry|forbidden|guest|missingMembers`.

Home, directory and detail allow guest requests to receive the actual source/server decision; they do not invent a universal public-access promise. `/my` and member-list reads require a session before transport. Every member-list load fetches a fresh detail, checks its membership gate, then requests members, all within the same captured session. A logout/account/token/epoch change between the two awaits prevents the second request. A change during the last request discards its response.

A row in `/my.owned` is not automatically promoted to isOwner by the decoder. Clicking a creator entry or arriving through a role-specific navigation choice never changes access. A legacy viewer administrator who is neither creator nor joined member does not pass the source basic-member-list gate. Role badges on member rows confer no viewer privileges.

Read-screen generations reject out-of-order retry/refresh completion and dismissed-page work. Navigation pushes invalidate pending work but retain immutable source rows, avoiding unintended pops from removing the active NavigationLink. The UI checks loaded identity before rendering rows, even before replacement tasks run.

## Verification and remaining gaps

- Added 13 contract, 15 synthetic transport and 14 session-isolation XCTest cases
- Contract checks cover four-section separation, exact field names and encodings, source role distinctions, absence/unknown states, invalid IDs, no inferred grants, server error preservation and empty-versus-unavailable members
- Session cases cover guest restrictions, missing configuration, stale successes/401s, token replacement, same-account relogin, logout, membership revocation and account change between detail/member requests
- Static coverage verified all 56 module localization entries and whitespace/source-bound file checks
- Isolated temporary integration copied the module plus baseline, merged the 56 keys and regenerated the project: structural checks passed (65 Swift source references, 373 bilingual keys, deterministic regeneration). The module checkout intentionally retains the untouched baseline project/catalog; run root integration before its aggregate structural check
- Swift and Xcode are not installed in this Linux workspace. XCTest execution, Swift type checking, Xcode compilation, simulator layout/accessibility and UI interaction checks are NOT RUN; root macOS CI is required before claiming native build/runtime validation
- No live backend, write, secret, production host default, user computer, Codex task, signing, commit, push or PR was used

Remaining source modules: club posts/comments/feed, topic/activity detail, leaderboard, creation/enrollment, join approval, role/governance, customer CRM, workbench, finance/settlement, group chat/code and all mutations. This is the agreed read batch, not full club feature parity.

Suggested root UI checks: home → created/directory → detail → members → Back/reopen; search submit/clear/no results; owner/member/admin/visitor gates; empty member list with nonzero count; retry; guest sign-in and 403 distinction; account switch and logout from a pushed member page; refresh while navigation changes; bilingual long text, VoiceOver and Dynamic Type. Fixture account switching intentionally replaces content and resets navigation without a backend.
