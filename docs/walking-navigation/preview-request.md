# W15 explicit preview-origin request bridge

## Current-source finding (2026-10-08)

Reviewed actual source tree `5b0058e53f1867de900e8da00cd0ebe1f7710889`, corresponding to
remote baseline `c95737b4c54881a7492ca72bd31f68749304d1d1`. The copied directory's local
Git HEAD is older and is not the input baseline. The change is against the actual files.

The master construction document's historical statement that SearchRoutePreview still
uses a straightLine fallback and has no real provider is stale for this baseline:
`MapKitWalkingRoutePlanner` already invokes the walking-only MKDirections executor, and
`SearchRoutePreviewView` already rejects straight-line output. Neither is reimplemented.

The remaining request-side defect was concrete: the preview view always constructed the
legacy request defaults (`gcj02`, `region=nil`), so even a properly approved WGS84 factory
could never authorize that request. The existing foreground navigation coordinator uses
its own explicit device-fix contract and does not have this preview construction defect.

## Increment and boundaries

- The host may explicitly provide `previewOriginContext: WalkingCoordinate`. This means
  the reviewed datum/region of the displayed search center, not a device fix or proof of
  physical presence. A host is responsible for sourcing that context from its approved
  coordinate contract. Merely choosing a market, language, target region or rendering a
  map does not establish it. No production host receives synthetic coordinate context.
- `SearchRouteRequest.walkingPreview` accepts that context only when its point exactly
  equals the displayed origin. Missing or mismatched context returns no request, and the
  view rejects it before constructing a planner. No GCJ02/WGS84 conversion or relabeling
  occurs; explicit datum and region are forwarded unchanged.
- The existing authorized preview planner still re-reads the exact destination reference,
  checks short expiry, source identity, destination point, datum and region, then passes
  the request to the existing real MapKit adapter. Provider execution remains gated by
  approved WGS84 regions. GCJ02 and mismatched regions remain unavailable.
- R2 stores the authoritative current input and generation in the shared, observable
  `SearchRoutePreviewLoader` reference. The view's synchronous appearance and input-change
  callbacks bind it; disappearance clears it. The task key is the loader-issued owner,
  not just the view's request. If a task is initially evaluated before binding, it has no
  owner; binding publishes a new observed owner and therefore a new task key. Input change
  before or after appearance is covered in authored shipping-loader tests.
- Retry captures that issued owner before scheduling. `load` checks shared current owner
  before cancelling any planner, issuing an attempt, constructing a provider or modifying
  route/failure. Async work cannot replace an owner. Both success and catch recheck owner,
  attempt and cancellation. An old View value's stored properties have no authority to
  make input A current after input B. The UI also hides route/failure whenever its visible
  input does not match the loader's current owner.
- No factory default, AppSession, composition root, CITY delivery, PBX, CI, shared
  localization, entitlement or permission is changed. No new strings are needed.
- This does not enable production directions, request location, grant target authority,
  prove arrival, complete a task, reward, redeem, upload a track or add background access.

Ordinary city/nearby search hosts still have no reviewed origin coordinate context and
stay unavailable. The backend target evidence remains independently blocked as described
in [source-target-contract.md](source-target-contract.md). This is an acceptance-ready
request-construction increment, not production activation or completion of W15.

## Offline synthetic fixture

Use the existing search-map fixture host with `--uitesting-search-map-entry walkingPreview`.
It provides an explicitly synthetic WGS84/US origin at (1, 1), the existing authorized
synthetic target, and the existing mock directions seam. `offline: true` avoids map tiles.
This fixture shows the provider's three-point path, two instructions, road distance and
ETA through the shipping preview view, factory and adapter. No actual directions call
is made by the fixture.

The separate `walking` entry stays untyped. This deliberately preserves existing navigation
scenario tests: their one-shot suspended directions response must not be consumed by a
preview before the user taps Start. The generic `route` entry still demonstrates unavailable
preview; no global fallback or production defaults are loosened.

Suggested Apple-hosted UI checks (not executed here): open `walkingPreview`, verify road
route/steps/ETA, dismiss and reopen, use noRoute/network/locked scenarios, and switch account
while loading. Run the existing `walking` routing cancel/reopen scenario unchanged. Cover
English/Chinese and large text. Navigation outcomes are never arrival verification.

## Verification record

Authored executable Swift coverage:

- Four Core tests: missing/mismatched origin context, unchanged datum/region, and request
  identity changes for same-coordinate contexts; legacy defaults are intentionally unchanged.
  Shipping-loader ownership coverage rejects absent, disappeared and superseded inputs.
- Thirteen app-hosted tests: the view's exact request builder to the authorized factory and
  real adapter with a mock executor; missing/mismatched origins; unsupported datum/region;
  target revocation and destination mismatch; no-route/network/throttled failure; late
  cancellation plus reopening; late account-context changes. Location construction is
  explicitly counted and must remain zero. Six direct shipping-loader tests additionally
  cover queued retries after dismissal/reopening; same-appearance A-to-B origin, target or
  scope changes with an old uncancelled retry; late old success/failure after a new route;
  appearance/input callback order; cancelled-task success/failure for the same owner;
  and straight-line rejection. These call `loader.load`
  itself, with no test-side owner guard. They do not claim to execute SwiftUI rendering.
- Ten new Python source-contract checks retain the fail-closed and no-side-effect boundaries.

Focused Python contracts and advisory parsing are recorded in the adjacent delivery evidence.
Swift/Core execution, Apple SDK typechecking, app-hosted tests, UI runtime, real provider,
location permissions, mainland coordinate/coverage and device walking: **NOT_RUN** in this
Linux workspace. No Swift or Xcode toolchain is available here. Offline structural success
must not be reported as Swift compilation, runtime, UI acceptance or launch approval.

## R1 review correction

R0 is retained as a superseded candidate. Review found that its unstructured retry Task
could begin after onDisappear and create a new query ticket, despite earlier invalidation.
R1 closes that separate appearance-lifetime hole; a query ticket alone was insufficient.
No new write paths, permissions, external calls or activation were added.

## R2 review correction and existing contract migrations

R0 and R1 remain retained, superseded candidates. R1's appearance generation did not solve
same-appearance input changes: a queued closure could compare against its old SwiftUI
value's properties, cancel B's planner and try A again. R2 replaces that value-snapshot
check with the shared loader described above. No queued task is allowed to rebind inputs.

The same-appearance regression starts B's real shipping load and suspends its mock
executor, then releases a previously queued A retry. It asserts no A planner construction,
no B cancellation, no additional provider request and no failure write. After B succeeds,
another A load attempt must preserve B's route. Three cases vary origin, target reference
at the same coordinates, and account scope. Separate tests finish A with success or failure
after B completes and assert B remains visible.

Exactly two existing structural contracts were migrated, with their safety assertions
retained and strengthened:

- `Tests/ContractChecks/test_source_walking_targets.py`: the preview-identity test now checks
  typed request/scope/reference input, synchronous view binding, shared owner comparison,
  both completion guards and the direct-loader same-appearance negative control. The
  backend source-authority, target provenance, namespace and coordinate checks are unchanged.
- `Tests/ContractChecks/test_walking_navigation_contracts.py`: straight-line rejection is
  checked in the shipping loader, the view must call that loader, and a direct-loader
  straight-line rejection test is required. Provider/permission/authority boundaries and
  the other original checks are unchanged.

These are the only two additional files beyond the original seven-file increment. No
production provider, location permission, coordinate conversion or gameplay write is enabled.
