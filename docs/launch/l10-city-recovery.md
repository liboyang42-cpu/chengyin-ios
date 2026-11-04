# L10 city action receipt recovery — partial delivery, not accepted

Issue: https://github.com/liboyang42-cpu/chengyin-ios/issues/136

Base: public `integration/launch-20261204` at `eec839502b11f1119a6ede212c768bb3f2de4f29`.
Backend contract freeze: public `hengyin` at `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
Branch: `codex/l10-city-receipt-recovery`.

## Ownership and reuse

This task owns the independent Core receipt recovery slice below, per the L10 delegation.
Issue #136 had no assignees or comments at inspection. No public `g06`/`G06` branch was
returned. G06's private UI source and its outstanding screenshot approval were not
accessed, copied, resubmitted or changed. G06's current owner cannot be verified from
public metadata; the coordinator must retain that assignment, not reassign its UI.

Reused public `cloud/w2-21-city-game-base` at
`4227748672af63555717b3abf694a254c1867ddc`, which is already an ancestor of this base.
The existing CityPlayerView, CityGamePanel, DTOs, quotes, payer consent and coordinator
are retained. The mini-program's CityNode domain is not treated as Monopoly.

Exact file whitelist for this slice:

- `Core/CityActionContract.swift`
- `Core/CityActionRecoveryJournal.swift`
- `Core/CityGameCoordinator.swift`
- `Tests/CoreTests/CityGameCoordinatorTests.swift`
- `tools/test_l10_city_recovery.py`
- `docs/app-composition/l10.diff`
- `docs/launch/l10-city-recovery.md`

## Implemented behavior

The existing coordinator now reads the original receipt before reconnect/retry.
A valid receipt settles without another submit. A missing receipt leaves explicit
readback unknown; explicit retry may send only the same request ID and canonical body.
A failed or mismatched lookup cannot submit. Prices and results stay server facts.

An injected local journal atomically writes the identifiers and original intent
before dispatch. Fresh coordinator instances restore into UNKNOWN, including frozen
boards. Account, environment/market/role namespace, game, board, region, season and
participation are isolated. Screen/session invalidation retains pending work. Only a
validated matching receipt clears it. Corrupt records, write failures and clear
failures fail closed. No tokens, location, signed evidence or balances are stored.
The journal does not turn on capabilities or review endpoints.

Composition must supply an app-private, persistent directory and an opaque namespace
that is specific to backend configuration, market and role. All coordinators for that
scope must use the same directory/namespace. The existing optional parameter preserves
DEBUG fixture compatibility; any future live factory must inject the journal.

## Shared-file handoff

`docs/app-composition/l10.diff` adds only the new journal to the existing Core Xcode
target. `git apply --check` passes against this base. No PBX, AppSession,
AppCompositionRoot, NativeRuntimeDependencies, CI manifest or workflows were edited.
There is no truthful live-service composition diff yet: the backend writer does not
exist in the frozen contract. Do not invent or enable it. L1 must audit/refresh the
shared test manifest when integrating the changed/new XCTest declarations.

## Remaining launch blockers

A recursive tree and tracked-source audit of the frozen public backend finds no
`api/city-game`, `ApiCityGameController`, `CityGame*` writer, snapshot or action receipt
route. The published iOS `CityGameEndpointAllowlist.reviewed` is empty, and only DEBUG
fixtures implement `CityGameServing`. No backend changes or private W20 port were made.

Therefore normal entry → real writer → server result → readback is NOT delivered.
Signed evidence, cooldown enforcement, occupation, two-account season play, permission
filtered map aggregation and test-only Shanghai board data remain unverified/unbuilt
against this contract. Backend port ownership/contracts must be supplied by coordination
before live transport and composition can be implemented. Economic rules, identities,
RBAC/JWT and capability grants were not changed.

No iOS simulator, device, Xcode build, actual process-kill/relaunch test, live backend,
production writes, DDL, transactions, awards, CI or PR was run/created. Fresh-instance
journal tests are not a claim of device relaunch or two-account acceptance.

## Validation evidence

- `python3 tools/test_l10_city_recovery.py` (with `SWIFT_EXECUTABLE` pointing to
  official Linux Swift 6.0.3, 6.1.3, then 6.2.1): production subset and XCTest sources
  compile; dynamic linking fails in all three at `libswiftObservation.so` with
  `undefined reference to swift::threading::fatal(char const*, ...)`. **XCTest did
  not execute.** The final file has 14 tests (8 existing, 6 new). The harness copies
  the city implementation and tests unchanged and extracts existing read DTOs and
  market/language declarations; this is not a full QuestifyCore build.
- A supported `-static-stdlib` attempt with 6.2.1 compiles the production subset,
  but that toolchain has no static XCTest module. No error was suppressed, no
  replacement Observation/XCTest code or runtime stub was introduced.
- Pinned Tree-sitter parse of the four changed/new Swift files: PASS, zero recovery
  nodes. Supplementary syntax evidence only.
- `python3 -m unittest Tests.ContractChecks.test_city_game_base
  Tests.ContractChecks.test_city_player_recovery
  Tests.ContractChecks.test_city_point_selection`: 20 tests, 19 passed, 1 failure.
  The failing existing `test_production_entry_points_pass_no_game_or_restore_model`
  expects `.borderedProminent` while the unchanged App uses `.questifyPrimary`.
  Re-running that single test against an archive of the immutable base reproduces
  the same failure. Neither the assertion nor the UI was changed to make it green.
- `git diff --check` and `git apply --check docs/app-composition/l10.diff`: PASS.
- Credential-pattern scan of the five code/test deliverables: PASS.
- Both repository workflows were inspected: the lane branch matches no push
  trigger; commits carry `[skip ci]`. No CI dispatch or PR was requested.

Implementation commit: `269ee4dd` (full SHA and remote byte-verification receipt are
reported by the coordinator after publication). Validation is limited as above;
this is not launch acceptance or real-backend completion.

## Follow-up group: current snapshot and action selection boundaries

Ownership was rechecked before this group: #136 still has no assignee/comments,
public integration is still `eec839502b11f1119a6ede212c768bb3f2de4f29`, and the
only public L10 iOS lane branch found is this task's branch. G06 UI ownership is
unchanged and still not independently identifiable from public metadata.

The existing public backend source `cursor/w20-f-city-board` at
`36071cdfd55513b59966c5185153eac692a9753d` was inspected without altering it.
It already contains `ApiCityGameReadController` and publication classes. That
controller identifies itself as a candidate, is not approved for transport, and
explicitly states participation/points are unavailable without their real sources.
It is outside the frozen backend contract. This work does not duplicate its port,
change auth, or enable it; coordination still needs the missing writer/receipt
contract and the appropriate backend port owner before live integration.

Exact additional group whitelist:

- `Core/CityGameBoardProjection.swift`
- `Core/CityGameCoordinator.swift`
- `Tests/CoreTests/CityGameProjectionTests.swift`
- `Tests/CoreTests/CityGameCoordinatorTests.swift`
- `tools/test_l10_city_recovery.py`
- `docs/launch/l10-city-recovery.md`

Snapshots now reject invalid/incomplete read context (including missing point
projection, unavailable membership, invalid participation, duplicate/invalid points,
and non-member "mine" facts). Selection must match the current complete property
value and its published service value, preventing stale objects or unpublished fees
from being accepted as action inputs. The coordinator retains a version/sequence
watermark across failed reloads, so failure does not permit an older snapshot to
become actionable. The watermark is cleared on session/screen invalidation.

Validation for this group:

- `SWIFT_EXECUTABLE=<official Swift 6.2.1>/usr/bin/swift python3
  tools/test_l10_city_recovery.py --suite projection`: **11 XCTest executed, 0
  failures** on Linux. This suite uses the unchanged production projection, action,
  delta and capability sources plus extracted existing read declarations. It has no
  Observation dependency, network service, production fixture fallback or replaced
  runtime implementation. This is a selected domain suite, not a full app build.
- `--suite recovery`: production subset and all **16 coordinator XCTest sources**
  compile, then the same Observation linker failure prevents execution. Two added
  integration tests cover coordinator selection rejection and watermark retention.
  They are authored/compiled, not reported as passed.
- The pinned Swift syntax check passes for the four affected Swift files.
- `python3 -m unittest Tests.ContractChecks.test_city_player_recovery
  Tests.ContractChecks.test_city_point_selection`: **13 passed**.
- `git diff --check`: PASS. No UI or shared runtime/PBX changes. New CoreTests are
  discovered by SwiftPM; L1 must refresh its shared audit manifest at integration.

This group does not close the remaining launch blockers above. In particular, no
normal-entry real-writer flow, two-account season play or device restart acceptance
has been demonstrated. No CI, PR, production write, award or transaction was run.

After both public pushes and byte verification, this task's dedicated iOS checkout,
its downloaded temporary toolchains and matching local test logs may be removed as
recoverable task files. The pre-existing `/workspace/hengyin` workspace is not part
of that cleanup. Public source, test scripts and this record remain on the lane.

Follow-up implementation commit: `17c98bb0279ab589ea1f04501c1750929044af9a`.
Projection run log SHA-256:
`d6e8df86ea1edc810c0c27bcb59bac3404e9b3b24e95b0d6dd0f3b6d7b85c97b`.
Coordinator compile/link attempt log SHA-256:
`2ee48e5be34583cae0cee6f323c77da09d0cf7642dfdea01a0f7e0ff9e89df11`.


## Stop decision after remaining-scope audit

A final read-only audit found no further complete, non-duplicating independent L10
group under the current frozen backend contract. This is a blocked handoff, not a
claim that the lane is complete. Only this record is updated by this audit.

Rechecked refs:
- iOS integration: `eec839502b11f1119a6ede212c768bb3f2de4f29`.
- iOS completed client groups: `49e0ac5afa0cab260d9a1cfdc0a7494fcf1bed5e`.
- Backend contract remains frozen at `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Public backend integration is `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`;
  its tracked tree also has no CityGame/CityBoard implementation. It does not
  supersede the frozen contract.
- #136 still has no assignee or comments. No additional public iOS L10 owner branch
  was found. Existing G06/private work was not accessed or reassigned.

| Remaining group | Concrete blocker |
| --- | --- |
| Board/season/rules/region/participation/points live reads | Existing public board-publication work at `36071cdfd55513b59966c5185153eac692a9753d` is a candidate outside the frozen contract. Its production source probe is UNAVAILABLE, current board is FROZEN, and participation/points return 503 rather than authoritative membership or points. Porting a second copy would duplicate that work. |
| Check-in, occupation, operating actions and reconnect | No player writer, signed-evidence contract, cooldown source or original-action receipt route exists in the frozen backend. The iOS operation protocol cannot be promoted to live transport by inventing routes. |
| Economic configuration and fair server decisions | Real quote/dice/ownership sources and owner-provided rule values are missing. Client-side computed outcomes or invented defaults would violate the assigned scope. |
| City/viewport/permission filtering before aggregation | Authoritative location-permission and source probes are not connected. Client filtering cannot substitute for server authorization or prove hidden-source counts/cursors are safe. |
| Shanghai pilot and two-account season acceptance | Persistent playable board/season/action/receipt sources and test environment are required first. Candidate SQL is not executed and is not part of the frozen contract. A fictional seed cannot prove play. |

The existing public operations work at
`37a3c5baca3a8cb8e87bf90197be16693d8b3b46` was also inspected. Its contract
`docs/contracts/w20-city-game-operations.md` is explicitly
`CITY_OPS_TRACE_V1`, `transport: NOT_APPROVED`, and records
`NO_EVIDENCE_SOURCE`, `NO_TASK_SOURCE`, `NO_DICE_SOURCE`,
`NO_QUOTE_SOURCE`, and `NO_OWNERSHIP_SOURCE`. Its administrative correction
request receipts are not player occupation/action receipts. No duplicate port or
new permission grant was attempted.

The frozen backend [AGENTS.md](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/AGENTS.md)
requires development/test backends and Java tests to stay on the dedicated test VPS:
"Do not start local Docker, Colima, Java build/test processes, Java application
servers or Redis, and do not fall back locally when the VPS is unavailable."
No authorized test-VPS route was supplied for this task. No local Java/backend
fallback, private source, user computer, credentials or network expansion was used.

Next coordination dependency: retain/identify the existing backend port owner,
supply reviewed authoritative read/write/receipt contracts in an explicitly
designated backend base, provide owner economic configuration and an authorized
test environment, then have L1 apply the shared wiring/manifest handoff. Until
those prerequisites change, this task stops implementation. No permission denial
was retried or bypassed. No new code, test execution, CI, PR, production write,
DDL, transaction or award was performed during this final audit.
