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
