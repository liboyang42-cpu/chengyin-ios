# Questify / 城瘾 iOS launch plan

Target launch: **2026-12-04**. Written 2026-11-04 by Claude (overall lead, UI owner). Codex builds everything other than UI.

This plan replaces the status claims in older documents. Do not use `docs/ios-current-status.md`, the `*Closure*`, `*Certificate*` or `*ZeroGap*` files, or old parity scores as evidence that anything works.

## 1. Where the app actually stands

Checked against `claude/ios-base-20261104` and hengyin `master` c6eac3b. Static reading only; nothing has run on this code.

| Measure | Result |
|---|---|
| App + Core typecheck | 0 errors |
| App unit test target typecheck | 6 errors in 2 files, see L1 |
| iOS calls to backend routes | 675 in non-audit code |
| Calls with no route on `master` | about 217: 46 on unmerged branches, 2 under another path, 169 not built |
| Mini-program endpoints in launch flows with no iOS call | 138 of 210 |
| Mini-program pages | 157; native view found for 142, none for 13, 2 unclear |
| Backend address | Empty in `Config/*.xcconfig` |
| Capabilities | `App/RegionalLaunchConfiguration.swift:70` passes `verifiedCapabilities:[]`; `App/AppCompositionRoot.swift` has 109 `{ _ in nil }` defaults |
| Dead code | 118 unreachable view files, 94 unused `SectionView` files, 277 audit or contract named Core files (45,499 lines) |
| Last full CI pass | None on the integrated code |
| Last evidence | `ab2d3905`: Core 10,841 pass; AppUnit 5,597 pass, 5 fail; UI 13 of 32 selected pass. These predate this base by 618 files |

Data files, next to this plan:
- `data/missing-routes.json`: iOS paths with no route on `master`, by domain. Includes about 20 known false positives; re-verify each before building.
- `data/mini-only-endpoints.json`: mini-program endpoints with no iOS literal. Noisy; re-verify each.
- `data/unreachable-views.txt`: view files not reachable from `QuestifyApp`. Four are live: `ActiveDestinationSummary`, `WalkingNavigationView`, `TemplateReasoningRehearsalView`, `TemplateSensorRehearsalView`.

**The core problem:** most features have a client but no working path. Porting routes alone won't enable them, because the app also ships with no address, no capabilities and nil dependencies. A feature counts only when the whole path works.

## 1A. Merge status, checked 2026-11-04

`integration/launch-20261204` is the one complete base. Work from it only.

| Source | State |
|---|---|
| 75 open iOS PRs | All commits are already in this base. They don't need merging; L1 closes them after M1, with a comment naming the base. Their review state doesn't carry over |
| 25 `codex/ui-public-20261103-*` branches | Now included. They were marked "not built", and relied on shared helpers that were never published; those helpers were written fresh in `App/QuestifyMotionComponents.swift`. App + Core typecheck: 0 errors. **No screen has been run** |
| `screenshot/codex-ui-20261103`, `work/native-73e-file-transfer`, `evidence/gemini-*` | Left out on purpose: pilot test changes, old transfer files, evidence |
| Backend: 70 open hengyin PRs | Not merged. L7 ports what is needed; #398 is not merged whole |

**Being in the base doesn't prove a feature works.** Earlier merges were never verified by a complete CI pass. Treat every merged feature as unverified until its journey in section 6 passes. If a conflict resolution lost behaviour, restore it from the source branch.

## 2. Definition of done

A feature is done only when all of these are true:

1. It is reached from a normal entry in the app, not a fixture or debug path.
2. It sends a real request to a real backend route.
3. The server decides the result, and the app reads it back.
4. Failure, retry, unknown result and app restart all behave correctly.
5. It works in English and Chinese, for the markets it applies to.
6. The mini-program keeps working against the same backend.
7. Tests and evidence are recorded on the issue.

**A feature that isn't done by code freeze is removed from navigation.** No disabled buttons, "not available yet" rows, or "preview only" notices may ship. Code existing, tests passing against fixtures, or a contract file saying closed are not evidence.

## 3. Timeline

| Dates | Phase | Goal |
|---|---|---|
| 11-04 to 11-06 | Foundation | M1: green CI on one base; app logs in against a test backend |
| 11-07 to 11-11 | Core connection | M2 (11-11): player and merchant core journeys work end to end. **Scope checkpoint** |
| 11-12 to 11-15 | Completion | M3 (11-15): all launch features complete, including channels, city game and game upload |
| 11-16 to 11-18 | Freeze | M4 (11-18): code freeze, full CI pass, TestFlight build |
| 11-19 to 11-25 | Owner review | Owner reviews the whole app on a device; Claude and Codex fix daily |
| 11-26 to 12-02 | Final review | Full regression, security review, App Store submission by 11-28 |
| 12-02 to 12-04 | Launch | Production migration and deployment by the owner, gradual release |

Apple review time and rejections aren't in our control, which is why submission is 11-28 and not 12-02.

**Scope checkpoint, 11-11:** if channels or the city game are behind, cut in this order: webhooks, lottery and bounty, channel progress boards, H5 games, then city game economy depth. Direct messages, group chat, orders, play and merchant work are never cut.

## 4. Working rules

### Branches
- iOS integration: `integration/launch-20261204` in `chengyin-ios`, from `claude/ios-base-20261104`.
- Backend integration: `integrate/app-launch-20261204` in `hengyin`, from `master`.
- Lane branches: `codex/l<number>-<slug>`, from the integration branch, as draft PRs back into it.
- Never push to `main` or `master`, and never merge to them. The owner merges those after review.

### Parallel work
**Parallel processing is required. Run at least 7 agents at once, one per lane, from day 1.** Twelve lanes are defined below; open more agents for L2 through L12 when capacity allows. Split a lane further if it can be done in parallel, and record the split on its issue. Don't wait for a lane to finish unless the dependency column requires it. Where a route isn't ready, code to the contract in this plan and connect later.

### Issue forum
- Tracking issue: the launch tracker. One issue per lane.
- Claim a lane or sub-task by commenting. Post each result in this form:
  `Status | branch and full SHA | what changed | commands and results | what was not run | blockers`.
- Questions for another lane go on that lane's issue. Decisions for the owner are prefixed `OWNER DECISION:` and also noted on the tracker; carry on with the stated default meanwhile.
- UI requests go on the UI issue, for Claude.
- After a lane finishes, GitHub Actions builds it. If the build or tests fail, **the same lane fixes it**, without waiting to be asked.
- Gemini, Grok and Muse are on hold for now. Verification goes through GitHub-hosted CI.

### Shared files
L1 alone edits `.github/`, `tools/current_ci*`, `tools/current_ci_manifest.json`, `Questify.xcodeproj`, `App/AppSession.swift`, `App/AppCompositionRoot.swift`, `App/NativeRuntimeDependencies*`.
Other lanes put the change they need in `docs/app-composition/<lane>.diff`, and L1 applies them at least daily. Use `tools/current_ci.py refresh` after merging and never hand-merge the manifest: take the target's copy and refresh.

CI details: `native-ios.yml` only runs on listed push branches or manual dispatch. Use `gh workflow run native-ios.yml --ref <branch> -f mode=related` on lanes and full mode on integration only. Repeated pushes cancel the running job on that ref. `Tests/ContractChecks` pins aren't run by CI: don't update them during the build; L3 handles them as a batch.

### UI boundary
New issues found by anyone: Claude updates this plan on GitHub first, then assigns the work on the coordination thread.

Claude owns all SwiftUI visual layout and copy. Codex lanes own `Core/`, services, adapters, wiring, state and tests. If a new screen is needed, build the data and flow with a plain native `List` or `Form` in a new file, then file it on the UI issue. Don't restyle existing screens.

### Hard limits
- Never connect to or change a production database, and never deploy to production. No real payments, payouts or push to real users.
- No keys, tokens, certificates, server addresses or private data in commits, issues or logs. Both repositories are public. Scan before pushing.
- Private repositories (`chengyin`, `chengyin-app`) stay private: don't copy their code or history into public branches. Reimplement what is needed.
- Changes to auth, RBAC or JWT, new dependencies and any change to money rules need the owner's explicit approval first: post `OWNER DECISION:` and wait on that part only.
- Database changes are new versioned `sql/migration_*.sql` files. Never edit an existing migration. Never suppress errors or tests to get green; never add fake users or fixture fallbacks to production paths.
- Write operations check owner and scope on the server. Existing APIs stay compatible for the mini-program: add fields and routes, don't change meanings. Mini-program pages and UI aren't part of this work.

### Product rules every lane must respect
- Theme types are only 城市定向 (`product_type=1`, ordered, server-judged) and 自由探索 (`product_type=2`, unordered, multi-merchant).
- The server decides dice, scores, prices, settlement and review. The client shows receipts and unknown states, and never computes results.
- Merchant scans the player's credential to redeem; the player scans the point code to play. Never merge these.
- Owner and merchant identities are mutually exclusive. Merchant permission comes from server-verified `MerchantPermission`, not entry intent or role names.
- Not doing: voice rooms, live streaming, nested threads, friend recommendations, gacha, Flutter.
- Check `chengyinhub-xcx/` first for behaviour, fields and copy. It is the reference for existing features, but if it looks wrong, ask on the issue rather than copying it.

## 5. Codex lanes

| Lane | Repo | Work | Depends on |
|---|---|---|---|
| L1 | iOS | Integrator, CI, shared files, compile errors | none |
| L2 | iOS | Backend connection, capabilities, login | L1 base |
| L3 | iOS | Test repair and dead code removal | L1 base |
| L4 | iOS | Commerce: orders, invoices, free explore, payment | L2 |
| L5 | iOS | Play: runtime, orienteering, map, AI NPC | L2 |
| L6 | iOS | Club, merchant and cooperation connection | L2 |
| L7 | hengyin | Port stranded backend | none |
| L8 | hengyin + iOS | Messaging and channel backend | none |
| L9 | hengyin + iOS | Friends, push, notifications, webhooks | L8 for the shared base |
| L10 | hengyin + iOS | City Monopoly | L7 for shared migrations |
| L11 | hengyin + iOS | Pre-made game upload | L7 for workshop slice |
| L12 | hengyin + iOS | US and China release | L2 |

### L1 Integrator and CI

**Own:** the shared files in section 4.

1. Create `integration/launch-20261204`, add it to `on.push` in `native-ios.yml`, and commit a refreshed manifest. The base currently fails `current_ci.py check` ("changed without manifest audit").
2. Fix the 6 compile errors: `Tests/AppUnitTests/NativeChannelHostAncestorFenceTests.swift` (`NativeChannelRouteMessageHostFlow`, `NativeChannelRouteMessageHostBinding`, `NativeChannelRouteMessageHostAuthority`) and `Tests/AppUnitTests/NativeChannelNotificationAncestorFenceTests.swift` (`NativeChannelAncestorNotificationBinding`). Decide whether the code or the test is what's missing; restore the code if a real feature needs it. Also typecheck `Tests/CoreTests` and `Tests/AppUITests`, which haven't been checked on this base.
3. Provide a one-command wrapper for manifest refresh after a merge.
4. Apply `docs/app-composition/<lane>.diff` at least daily. Merge lane PRs that compile and pass related checks, at least daily. Run full CI on integration at each milestone and post results.
5. Find out why run 41385679400 was cancelled at 52 minutes, and how many macOS jobs really run at once. Make a full run finish reliably. Target `strategy.max-parallel: 20`, GitHub-hosted runners only.
6. Fix `App/ClubCommunityViews.swift:267` and three fixture files lacking `#if DEBUG` (`ObjectCardFixtureHostView`, `AppStoreReviewDemoAccountAndFixtureSectionView`, `PublisherLifecycleFixtureSupport`): fixtures must not compile into Release. Confirm the Release build contains no fixture entry.

**Done:** full CI green on integration at M1, M3 and M4. Unsigned Release builds for CN and US pass.

### L2 Backend connection, capabilities and login

**Own:** `Core/BusinessRuntimeConfiguration*`, `Core/OperationAdapterSafety*`, `App/RegionalLaunchConfiguration.swift`, `Config/`; composition changes through L1.

1. Design how capabilities are granted, replacing the empty `verifiedCapabilities` and the 109 nil defaults. Post it as `OWNER DECISION:` before changing auth behaviour. Default proposal: a per-environment, per-market list of enabled features in the build, with server-verified login identity. Each row of `data/missing-routes.json` enabled only when its route exists on the backend integration branch.
2. Build configurations for development, staging and production without secrets. Local files hold real addresses. Development defaults to the loopback test backend `http://127.0.0.1:8099`.
3. Login end to end, as in the mini-program where it applies: SMS, WeChat where allowed, Apple on US. The legacy password path can't work natively; remove it from normal flows. Token renewal, expiry, sign-out and account deletion, which App Store review requires.
4. Guest browsing with login prompted on writes, matching the mini-program.
5. App version compatibility: handle HTTP 426 and unknown message or status values safely.
6. Publish a feature ledger, `docs/launch/feature-ledger.md`: feature, route, backend state, iOS state, enabled in which market. All lanes update it. **This is the record the owner reviews.**

**Done:** a clean build logs in against a test backend and loads home, profile and orders with real data.

### L3 Test repair and dead code removal

**Own:** `Tests/AppUITests`, `Tests/AppUnitTests`, `Tests/ContractChecks`, `tools/tests`, `Vendor/`.

1. Fix the 5 known AppUnit failures. `ProfileFavoriteDetailTests` and `ProfileFavoriteTopicReadTests` are navigation fixture problems on current iOS; the other three, including `WorkshopPaidInstallNormalFlowTests`, need rechecking on this base.
2. Fix the 19 UI failures: 10 `Integrated*` at `revealFixtureElement`, 9 SearchMap on `filters`, `chooseArea`, `showMap`, `filter.min`. Likely one shared scrolling helper. Set the GLTFKit2 deployment target. Keep every business assertion.
3. Triage `Tests/ContractChecks` (382 failure blocks at `ab2d3905`): about 217 stale pins, 113 source-literal asserts, 44 inventory counts, 3 to 8 environment. Retire tests that only pin bytes or inventory counts. Hand-check the 10 to 15 candidates that may be real: missing or colliding localization keys, `missing gated read-failure site`, uncatalogued local stores, `https://` in growth source, the roam privacy check.
4. Delete dead code in small compile-checked steps: `data/unreachable-views.txt`, unused `SectionView` files, `Unified*`, `Master*`, `Final*` hubs, and audit or certificate Core files with no production caller. Don't delete anything a live type depends on. Expect to remove a large share of the 45,499 audit lines.
5. Replace old inflated test goals with journey tests per flow in section 6, using a fake server at the HTTP level.

**Done:** Core, AppUnit and selected UI green on integration. The dead code is gone. Every remaining test protects behaviour.

### L4 Commerce

**Own:** new `Core/Invoice*`, `Core/FreeExplore*`, and existing `Core/` order, registration, wallet and coupon services.

Reference pages: `activity/baoming`, `subpackageMember/invoice*`, `subpackageMember/free-explore`, `utils/user-invoice.js`.

1. Registration and order: quote from the server, create, pay, status, cancel, refund, ticket. Include the missing `payment-readiness`, `join_info`, `count_by_date`, `scan_group_member_ticket`, `team/command*`.
2. Free explore bundles (`api/free-explore/*`): 15 endpoints, catalog, purchase, reservation, cancellation (free until 12 hours before), voluntary refund threshold, passport. Backend switches stay controlled per environment.
3. Invoices: 11 endpoints and 5 pages. Minors: `/api/minor/guardian/*`.
4. Payment: WeChat Pay in CN through the WeChat Open Platform flow, gated by a server `PurchaseChannelResolver` (with L12). Test sandbox only.
5. Pending state, duplicate submission and unknown result all recover by reading the same order.

**Done:** browse, register, pay in sandbox, receive ticket, redeem, refund, invoice; both theme types.

### L5 Play

**Own:** new `Core/PlayCheck*`, `Core/Orient*`, existing play, roam and map services.

Reference pages: `pages/play/index` and its utils, `pages/roam/index`, `subpackageRoam/*`, `subpackageMember/orient-score`.

1. City orienteering runtime (`api/play/orient/session*`, `api/orient/*`): 16 endpoints, none called by iOS. Includes team lobby, score, safety confirmation and AR alternatives using the same server judgement.
2. `check/*`, `theme/action*`, club lead actions, `play/poi-challenge`.
3. Regression on all 42 play modes and overlays through normal entries. Fix what's broken: K18 native protocol, K38 witness flow and K01 album are unverified. Sensors need device-only flags.
4. Chapter eggs: `TopicRoutePublicationCompiler.java:616` rejects them as not connected. Coordinate with L7.
5. Map: walking navigation, public layers (`map/public-layers`, from L7), official routes (`subpackageRoam/official-route*`), MapKit retained. Fog must not cut routes. Arrival offers a verification entry only and never auto-completes. A navigation failure never draws a straight line as passable.
6. Personal location sharing and background location: only after active start, separately consented, stops on end. `App/PersonalLocationShareHost.swift:109` currently forces this off, against the spec, and `api/location-share/personal` has no backend. Add with L7.
7. AI NPC: chat, memory, deletion, merchant binding; `knowledge-review` route missing. AI budget and pricing stay as config. Offline packs: strip answers and code hashes; each operation has a permanent `client_operation_id`.

**Done:** start, play, leave, resume and finish on a real session in both theme types, with a leaderboard.

### L6 Club, merchant and cooperation

**Own:** new `Core/Coop*`, `Core/MerchantReviewReply*`, existing club and merchant services.

1. Club: 25 gaps, including post create and comment, `lead` actions, badges (`pages/club/badges`), team report, membership (13 endpoints, default off on the backend; owner decision on enabling).
2. Merchant: 34 gaps, including reviews (5), decor (6), `merchantinfo`, claims (`merchant/claims`), authoring (9, from L7), desk verify and settlement routes (`/api/merchant/desk/*`).
3. Cooperation: 15+ endpoints, remove "preview only" states by making them real.
4. Reports and appeals: `subpackageMember/report-*`, `appeal-mine`. Official events: `publish-check`, `OFF-DRAFT`, `OFF-SCHEDULE`.
5. Ticket list from `02-缺陷与工单`: `TEAM-REPORT-01`, `MCH-CLAIM-01/02`, `POST-RPT-01/03`, `PLAY-CHECK-01`. Check each against the mini-program; `Legacy52Tickets...` claiming 52 closed is false.
6. Merchant permission on every screen comes from server-verified `MerchantPermission`.

**Done:** a merchant can apply, set up a store, publish, sell, redeem, respond to reviews and see settlement. A club owner can create, run, and manage members and events.

### L7 Port stranded backend (hengyin)

**Own:** slices on the backend integration branch.

Base is Java 21 / Boot 4.1.1. PR #398 still has 7 `javax.servlet` controllers, so expect compile breaks. **Don't merge #398 whole.** It is 1,846 commits behind with 754 files and 17 conflicts needing owner decisions, in funds and runtime.

Port in this order, one reviewed slice per PR, adding new migrations:

1. `cursor/w13-e-map-public`: map public layers.
2. PR #398 slices: native device and home, coupon receipt, time-window, `workshop/purchased` (with L11). `cursor/w19-d` private home goes with the home slice.
3. `cursor/w05-j-merchant-authoring`: merchant authoring.
4. `cursor/w17-i-reward-pledge`: reward pledge and rewards. Non-cash only; money stays off.
5. `api/location-share/personal` and `native/blacklist`, which need building.
6. Check `join-request` approve and reject against `api/club/join-request/*`: change iOS if equivalent.
7. Don't port `cursor/c02`–`c11`, #575 and `w16-*` for launch unless a review finds a needed fix. List funds and runtime conflicts as `OWNER DECISION:` with a recommendation.

**Done:** Java 21 tests and real MySQL and Redis integration tests pass on CI for each slice. Each route used by iOS exists with matching fields, and old APIs are unchanged.

### L8 Messaging and channel backend

**Own:** new `Im*` and channel backend classes, new migrations, `Core/NativeChannel*`, `Core/IM*`.

The design source is `App完整实现规格.md` §9 and `17-频道架构/04-城瘾落地方案.md`, supplied by the owner on the Codex machine; the key rules are summarized below. About 94 routes are unbuilt, the largest gap. Estimate 30 to 45 agent-days, so **split into at least 4 parallel sub-agents**.

1. Channel base: `im_channel` shares its primary key with `im_conversation`. Project spaces as `(guild_kind, guild_id)` onto existing club, team, topic, hangout, activity; no new guild table. `is_default` folding keeps old APIs identical for the mini-program. A 25-bit permission mask.
2. Auto-create channels on sale state: self-play themes never reach RUNNING, so hook PRICING→SELLING.
3. Messages: reply, quote, mention, timed edit and recall, pin, search, unread from `im_read_state.last_read_msg_id`. Quote auto-mention uses the quoted sender's member ID. Fix group messages: return sender name and avatar, handle `hangout_` in polls (`ImPollMapper.xml:76/82`) and `bizKey` types `club_`, `team_`, `hangout_`.
4. Governance: roles, mute, kick, ban, audit log, appeals (reuse `audit_appeal`). Join: invite codes, rules, onboarding, approval queue, discovery.
5. Interaction: chain, check-in; lottery only if time allows and with no money.
6. iOS: connect `Core/NativeChannel*` to these routes, adjusting whichever side the spec supports. Render from server permission bits only, never role names. Unknown message types show a placeholder and never run their payload. The message list has All, Channels and Direct tabs, with channels grouped by theme, club and team.

**Done:** create, join, chat, moderate and return on two accounts; no change in the mini-program's chat.

### L9 Friends, push, notifications, webhooks

**Own:** new `ApiFriend*`, device token, notification and webhook backend classes; `Core/NativeFriend*`, `Core/NativeWebhook*`, `Core/NativePush*`.

1. DM gate (`dm_policy`, off by default, App only), server-verified client source, not `X-Client`.
2. Friends: `member_friend`, meta and request tables, 21 routes. Blocking continues through `im_block`, with the missing reverse index. Follow, follower and following lists.
3. Push: device tokens bound to member, install and environment; APNs delivery through an outbox; conversation and global notification levels; quiet hours. Test only; no real sends until owner approval. `im_device_token` doesn't exist on `master` despite old docs.
4. Webhooks: signable secrets (encrypted, with key version), SSRF protection, unique delivery by `(subscription_id, event_id)`, inbound timestamp, nonce and HMAC. First in the cut order.
5. Progress and privacy (three levels; strictest wins), and fix mini-program issue N-02: route and session runtimes don't write `player_node_progress`.

**Done:** two accounts become friends, chat under the DM gate, get a test push, block and unblock.

### L10 City Monopoly

**Own:** `w20` port, new `City*` backend classes, `Core/City*`.

Source: reform plan W20, `cursor/w20-f-city-board` as the base. This is a persistent city board game, not a themed session. Old `CityNode` redemption is a different domain and doesn't replace it.

Rules already decided: geometry, spatial index and business point IDs are separate; one place can belong to several boards, without sharing occupation or income. No bank starting money, passing salary, automatic rent, bankruptcy, mortgage, free-coin or plot trading, default alliance rent cuts, public opponent last position, or new mini-program UI.

1. Port board, season, rules, region, participation and points reads. iOS calls `api/city-game`.
2. Add server-authoritative check-in, occupation and operation writes, with signed evidence, cooldowns and receipts. Reconnect reads the receipt first, never re-applying.
3. All economic values are server configuration, never in code. The owner sets values; defaults are placeholders, and rewards stay non-cash.
4. Map filtering by city, viewport and permission before aggregation. Plot colour, counts or cursors never reveal hidden sources.
5. Shanghai pilot board data as a seed for test only.

**Done:** two accounts play a season on a test board, occupy, see fair results and recover from a lost connection.

### L11 Pre-made game upload

**Own:** new `Mod*`, `Package*`, `H5*` backend classes; `Core/Qmod*`, `Core/Workshop*`, `Core/H5*`.

Sources: `城瘾_01_标准模组包` and `城瘾_02_H5小游戏包`, supplied by the owner on the Codex machine. Their Flutter parts are void. Backend has none of these entities.

1. Write `integration-map.md` (MOD-0). One shared Package, ContentVersion, Installation, PolicyDecision and Receipt model for both.
2. `.qmod.zip`: upload, quarantine and scan, compile to ServerPlan with content hash, server-run engine, venue binding, preview with the real engine. Author and installer flows. A package is data, never code. Import, install and approval are each separate from publishing; authors can't approve themselves.
3. Connect `Core/QmodArchiveInspection`, `App/QmodAuthorImportView`, Workshop library and purchase (`workshop/purchased`) to real routes. Unknown required nodes refuse to start.
4. H5, after qmod works, as second priority: separate registrable hosting domain, CSP, sandbox iframe, MessageChannel, server-issued one-use tickets (`Core/H5LaunchIssuer` mints locally today, and uses the API host as the shell origin; both violate the spec), server-verified results (first slice: card-sort). Native close and report controls outside the WebView. Malicious-page tests pass before H5 touches business logic.
5. Keep `TECHNICAL_READY` and `PUBLIC_RELEASE_ALLOWED` separate. Rewards remain off.

**Done:** an author uploads a module, it passes review, a merchant installs and binds it, and a player finishes it on the server.

### L12 US and China release

**Own:** new `PurchaseChannel*`, `MapProvider*`, `CoordTransform` use, `Core/` market code; market config through L1.

1. Apple sign-in end to end. Reimplement from the spec; the old work is on a private Java 8 branch that can't be copied.
2. SMS provider routing and E.164. US phone numbers currently fail on a China-only format at registration. Email login if needed for US.
3. `PurchaseChannelResolver` on the server: physical services use external payment, digital goods default to IAP. Add StoreKit, as iOS has none. Test only.
4. Time zones: business time from theme or city, device display. `Asia/Shanghai` is hard-coded 93 times in 58 Java files. Coordinates: use the existing `CoordSys` and `/geo/normalize`; store one standard. MapKit stays.
5. Currency and tax: define currency on orders; US market config.
6. Security pages required for review: device list, login history, account deletion, privacy, report and block for user content, age rules (COPPA at 13 in US), privacy manifest and permission strings.
7. Market gating so a feature can be off in one market, for licensing or payment reasons.
8. Backend error messages return keys or both languages, for English display. About 800 Swift lines hard-code Chinese in `Text`: report them to Claude, who fixes visible ones.

**Done:** CN and US builds each complete login, browse and order flows with the right language, phone, time and payment.

## 6. Launch journeys

These are the end-to-end tests that decide launch. Each runs on a test backend, in English and Chinese, on a clean install.

| # | Journey | Lanes |
|---|---|---|
| J1 | Guest browses; login prompted on write; login, logout, delete account | L2 |
| J2 | Find a city orienteering theme, register, pay, ticket, play, finish, leaderboard, review | L4, L5 |
| J3 | Free explore bundle: buy, reserve, visit merchants, redeem, refund | L4, L5 |
| J4 | Team: create, invite, play, leave, resume; location sharing with consent | L5, L6 |
| J5 | Roam, map, walking navigation, fog, nearby, stamps | L5 |
| J6 | Merchant: apply, store, product, publish, scan to redeem, review reply, settlement read | L6 |
| J7 | Club: create, members, events, posts, governance, cooperation | L6 |
| J8 | Author: create a theme, submit, review, publish, edit, withdraw | L6 |
| J9 | Messages: DM, group, channel, moderation, unread, notifications | L8, L9 |
| J10 | Friends, follow, block, DM gate, report, appeal | L9 |
| J11 | City game: join a season, occupy, recover, view results | L10 |
| J12 | Upload a module, review, install, play; Workshop purchase in sandbox | L11 |
| J13 | AI NPC: chat, hints, memory, delete data | L5 |
| J14 | Invoice, minor guardian, coupons, wallet | L4 |
| J15 | US build: Apple sign-in, E.164, English, payment channel | L12 |

Regression for all: backgrounding, restart mid-flow, lost network, expired login, revoked permission, large text.

## 7. Claude's UI lane

Rules: `docs/launch/ui-spec.md`. The mini-program is the main reference, rendered with native SwiftUI; Mobbin and Revolut guide polish only. UI runs as cloud lanes U1 to U9, on `claude/ui-u<n>-*` branches. No unnecessary secondary labels; the layout explains. Where the mini-program's UI is wrong, fix it rather than copy it. **Merchant is light and player is dark.** This stays.

The native tabs already match the mini-program.

| Dates | Batch |
|---|---|
| 11-04 to 11-05 | Native layer: page scaffold, states, toolbar rules, theme domain fix so merchant screens are always light |
| 11-05 to 11-06 | Remove engineering copy from live screens ("preview only", "source contract", "synthetic", and so on) |
| 11-06 to 11-08 | Mine and Settings, following `cy/profile` order; Home and Search, fewer toolbar actions; convert 5 custom tab bars |
| 11-08 to 11-10 | Messages and channels from the owner's Flutter design and Discord references; Club, including the message entry |
| 11-10 to 11-12 | Activity, Topic, Registration; Orders, tickets, wallet, login |
| 11-12 to 11-14 | Roam, map, Play core; Publish and editors |
| 11-14 to 11-16 | Merchant five tabs, highest-traffic screens; new screens from lanes |
| 11-16 to 11-18 | Language sweep, Dynamic Type, device sizes; screenshot review of every journey |

Screenshots for review come from CI. Local simulator access in Claude's session is still blocked.

## 8. Owner actions

| By | Needed | Why |
|---|---|---|
| Now | Copy the spec documents to the Codex machine: `App完整实现规格.md`, the reform plan, the two package documents, the gap checklist, `城瘾全量实施包.zip` | They are private and not in the repo |
| 11-06 | Apple Developer account, team, real Bundle IDs | Currently `invalid.example.questify.ios` |
| 11-06 | Decide the capability design (L2), and #398 conflicts (L7) | Auth and funds need approval |
| 11-08 | City game economic values, or approve a proposal | L10 can't launch on placeholders |
| 11-10 | APNs key, WeChat Open Platform app, Apple sign-in, payment merchant setup | Real login, payment and push |
| 11-11 | Scope checkpoint | Section 3 |
| 11-14 | App Store listing, privacy policy, terms, review demo account | Submission needs them |
| 11-18 | Add reviewer devices to TestFlight | Owner review starts 11-19 |
| Now | Ask counsel: China app filing, game licensing for city game and uploaded games, Apple rule 4.7 scope | Could block the China release; see below |
| 12-02 | Run production migrations and deployment | Agents never touch production |

**Biggest risks**

1. **China release may not make 12-04, regardless of code.** App filing and game licensing take outside processes, and the game features may be affected. This is a legal question and hasn't been verified here. Default: market gating lets the US build launch with everything, and the China build launch with affected features hidden until cleared.
2. **Channels are the largest unknown** at 94 unbuilt routes. Parallel agents make it possible, not certain; the 11-11 checkpoint is the protection.
3. **CI capacity.** Full runs have never completed on this code, and macOS jobs may be limited. L1 handles this first.
4. **Production differs from `master`.** The production schema must be compared before deployment.
5. **The mini-program shares this backend.** Each backend change must leave it working, and mini-program regression runs before any production deploy.
