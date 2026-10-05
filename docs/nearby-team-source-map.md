# Nearby/public teams: native migration

## Scope and boundaries

Coverage item: `nearby_team`, `deliverables/native-migration-coverage-20261001-2036.md:65`.

This module owns nearby browsing, public applications/withdrawal, leader applicant reads/decisions, and my-applications. Existing Team owns `/api/team/my`, team detail, invitation, create/join/quit/kick/disband. Roam/SearchMap retain the general map, projection and coordinate-system conversion. No live location permission or sensor calls exist. No backend, remote, membership, invitation or real-network mutation was executed.

Integrated additively into the native app repository on 2026-10-02. The isolated packet remains in `native-nearby-teams-new`; shared integration is authoritative.

## Source-to-native map

| Flutter source | Native destination | Preserved behavior |
|---|---|---|
| `lib/data/api/team_map_api.dart:nearby` | `NearbyTeamRequest.nearby`, service `nearby` | GET `/api/team/nearby`, query lat/lng/radius; radii 1000/3000/5000/10000/20000 |
| `team_map_api.dart:apply` | request `.action(.apply)`, service `submit` | POST `/api/team/apply`, exact `{teamId}`; success needs envelope code 200, copies only server `data.applyExpireTime` |
| `team_map_api.dart:withdraw` | `.action(.withdraw)` | POST `/api/team/withdraw`, exact `{teamId}`; no fabricated receipt |
| `team_map_api.dart:applications` | `.applications`, coordinator `loadApplicants` | POST `/api/team/applications`, `{teamId}`; applicant identity comes from memberId |
| `team_map_api.dart:handle` | `.action(.handle)` | POST `/api/team/handle`, `{teamId,memberId,approved}`; server re-read after approval, never increment roster locally |
| `team_map_api.dart:myApplications` | `.myApplications`, coordinator `loadMine` | POST `/api/team/my-applications`, no body; pending/rejected display |
| `models/team_map.dart:teamCardState` | `NearbyTeam.mode`, native cards | Leader > joined > pending > rejected > ticket/apply > buy; rejected has no reapply |
| `models/team_map.dart:resolveTeamError` | `NearbyErrorEffect` | Exact operation + errorCode effects, never parse message |
| `models/team_map.dart:teamExpireMinutes` | `NearbyServerTime` | Numeric epoch seconds/milliseconds and source timestamps; missing/unparseable/past deadlines use general rule, never 24h invention |
| `models/team_map.dart:myTeamRows` | `NearbyTeamBridge.myRows` | Joined wins, joined status 3/4 excluded; pending/rejected only; rejected excluded from active count; owner metadata retained in OwnedTeam |
| `models/team_map.dart:teamApplicantRows` | `NearbyApplicant`, native applicant section | Member name/avatar/message/timestamps retained; quoted message only when present; ticket wording says checked at application time |
| `feature/team/team_nearby_page.dart` | `NearbyTeamsView`, coordinator | Radius, selected-point query, cards, mine/applicant sections, review sheet, error display, refresh |
| `feature/roam/roam_team_markers.dart` | `NearbyTeamBridge.markers/markerDestination/roamQuery` | Team marker ID `teamId*10+4`; 1000m Roam context; no coordinates means no point; joined/leader active; only team markers owned here |
| Flutter `test/feature/team/team_map_models_test.dart`, nearby page/entry tests, Roam marker tests | Swift domain/UI tests and supplementary Python source checks | Contract, error, expiry, identity, ownership, navigation and interruption cases |

## Error matrix

- Apply TICKET_REQUIRED: clear ticket, status NONE
- Apply APPLY_REJECTED / APPLY_PENDING / ALREADY_JOINED: status REJECTED / PENDING / JOINED
- Apply TEAM_FULL / ACTIVITY_STARTED / TEAM_UNDER_REVIEW / TEAM_NOT_PUBLIC: drop team
- Apply APPLY_BLOCKED: report only
- Withdraw APPLY_NOT_PENDING: refresh
- Handle APPLY_NOT_PENDING / TICKET_REQUIRED / APPLY_BLOCKED: remove applicant
- Handle TEAM_FULL: refresh
- Unknown/empty errorCode: display server message without state changes
- Transport/cancellation/malformed mutation result: no speculative state changes, unresolved lock, no automatic retry

## Safety and conscious hardening

- Only concrete in-memory `NearbyTeamFakeTransport` can receive mutation request descriptions. Injected `NearbyTeamReadTransport` has no mutation execution path. Live reads require explicit `liveReadGrant`, default false; service default is unconfigured. There is no production write grant.
- Role is native `Account.effectiveRole` player; merchant/unknown role cannot read or review. The TeamSession bridge copies account/epoch/region/storage namespace/role, without token extraction.
- Typed team/applicant IDs are distinct. Team ownership is carried via existing OwnedTeam, never guessed from a nearby marker or activity ID. Private inviteCode/leaderMemberId/ownerType fields are absent from nearby decoding/view models.
- Unlike the permissive source UNKNOWN→NONE fallback, unknown viewer status is read-only. It cannot silently become an application or leadership grant.
- Manual/injected coordinates are display/query context only, never location, ticket, or membership evidence. Native code does not normalize GCJ-02 into another coordinate system or claim eligibility from proximity.
- Review contains an immutable action, team/applicant/application snapshot, account/epoch/region/namespace, and data revision. Confirm rechecks exact snapshot, role, loaded applicant, expiry and current state. Back/cancel/session changes invalidate reviews.
- Duplicate submissions lock before the first suspension. Unresolved intent is persisted as a namespaced account bit with no names, tokens, applicant data or coordinates. Account switch, navigation, refresh and re-login do not clear ambiguity. No fabricated status/receipt/reconciliation endpoint is introduced; a real integration needs an independently verified resolution process before enabling writes.
- Authoritative terminal fake results may release the unresolved lock; successful exact actions remain replay-blocked for the coordinator lifetime. Account-bound late results do not patch a newer screen/account.
- `applyExpireTime` never changes state by local countdown alone. Expired applicant reviews are blocked; otherwise absent expiry remains unknown and no invented deadline is asserted.
- Server text is displayed verbatim; authored UI/error copy has en/zh-Hans keys. Minimum 44pt targets, semantic labels, readable state text, Dynamic Type wrapping, explicit loading/empty/error/disabled states and no color-only status.
- Avatar URLs are retained only as data; no unapproved remote asset loading is introduced.

## Host integration contract

1. Copy Core/App/tests/docs/source-check files into corresponding existing app directories, and merge all `strings` from `Resources/NearbyTeamLocalizations.fragment.json` into `Localizable.xcstrings` (82 keys).
2. Build a player/account-scoped coordinator using the existing Team session through `NearbyTeamSession(teamSession:)`. Retain it per workflow and call `bind` on every account/epoch/region/role/namespace change. Redraw private screens on auth changes, as other session modules do.
3. Route `NearbyTeamsView(coordinator:context:joinedTeams:navigate:)` from the native Team/Roam entry point. Optional `context` is a selected point; no location request is needed. Pass already-read OwnedTeam rows rather than calling `/team/my` here.
4. Map `.team(NearbyTeamID)` to existing Team detail, `.activity(Int)` to the existing activity/ticket detail, `.topic(Int)` to the existing topic module. Purchase navigation only opens the source-supported session; it does not buy a ticket.
5. Roam can render `NearbyTeamBridge.markers`; call `roamQuery` for the source's 1000m layer, and use the same nearby coordinator/card UI for selected team IDs. Team marker parsing does not capture activity/topic/retired kinds.
6. In the host DEBUG fixture dispatch add `--nearby-team-fixture` → `NearbyTeamFixtureRoot()`. UI tests require this explicit fixture launch branch. The DEBUG host branch and production-container bypass are now installed.
7. Keep grants off. Authorize and verify any live read transport/auth strategy separately. Never attach URLSession to the fake transport or turn synthetic success into live receipt evidence.

## Verification

- 13 supplementary Python source/fixture checks: PASS (2026-10-02)
- Focused Tree-sitter Swift parse: 17 new/edited files, 0 recovery nodes, 0 diagnostics (supplementary only)
- 22 authored Swift XCTest cases (18 domain + 4 scoped HTTP reader); 3 authored XCUITest cases
- Swift compiler/typecheck: NOT_RUN, Swift toolchain absent
- XCTest/XCUITest, Xcode build, simulator, screenshots, VoiceOver, Dynamic Type runtime: NOT_RUN, Xcode/Apple runtime absent
- Live backend/location/membership execution: NOT_RUN, deliberately disabled

Commands:

```
python native-nearby-teams-new/tools/check_nearby_team_module.py
swift-syntax-venv/bin/python chengyin-ios/tools/check_swift_syntax.py --root native-nearby-teams-new $(find native-nearby-teams-new -name '*.swift' | sed 's@native-nearby-teams-new/@@')
```

Source checks are not a Swift compiler or behavior execution. Fixture source and UI assertions still require Apple CI after host integration.


## Integrated host status — 2026-10-02

AppSession now supplies `nearbyTeamSession`, the selected Roam query context and an account-scoped coordinator. `makeNearbyTeamCoordinator(readApproval:transport:)` accepts exact `OperationEndpointApproval` with independently supplied HTTPTransport; every endpoint checks deployment URL, namespace, account, read allowlist and current session before/after suspension. Default callers pass no grant. Four fake-HTTP tests cover query/authorization, wrong-account rejection, mutation rejection even when a path is granted, and epoch changes.

`SessionTeamHomeView` passes already-read owned teams from `TeamHomeView` into `SessionNearbyTeamsView`. Roam has an optional typed nearby destination supplied only by the normal session root. The native destination opens existing Team/Activity/Topic screens, and binds the nearby session whenever the existing team-view identity changes. The fixture root never constructs production AppSession. Existing OfficialAction hosts and all previous modules were retained.

Main source checker now covers the nearby localization prefix. The 13 nearby source tests are included in aggregate ContractChecks. Main exact totals: 1543 authored Core tests, 236 authored UI tests in 37 classes, 4079 bilingual keys. Six exhaustive shards: 41/39/39/39/39/39. This is authored inventory, not runtime test success.

Aggregate evidence: 289 ContractChecks, 16 tooling tests, 14 pinned parser self-tests PASS; deterministic project/scaffold PASS (469 App/Core/UI Swift references); focused parser 17 files PASS. Whole-tree parser checks 567 Swift files and retains the same ten pre-existing diagnostics in six unrelated files, unsuppressed. All previous module gates were rechecked, including settings with the explicit Flutter source root. No remote write, publication or CI execution occurred.


## Executable write repair integrated 2026-10-02
The earlier fake-only mutation limitation is superseded by [the executable write repair](nearby-team-write-repair.md). Exact apply/withdraw/handle HTTP adapters, fresh evidence and durable replay journals are now present. Normal read/write approvals remain nil. This is offline implementation evidence, not backend or Apple runtime acceptance.
