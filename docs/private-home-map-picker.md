# W19 private game-home picker: source-only, provider inactive

## Actual baseline and scope

Inspected the owner UI and session/journal source tree `e80e4b6bf67547b264ffa186c764b5b34f87653a`
from `native-next-rebased-repair-20261003` before adding this slice. That UI already had
manual WGS84 entry, immutable review, expectedVersion/requestId, owner invalidation and
secure exact-retry storage. It had no map-point selection. Those core owner/service/journal
and composition files are unchanged by this slice.

This implements the **fail-closed picker contract and native owner-UI subflow**, not a
working production map. Normal entry opens an honest unavailability explanation, disabled
point review and a return to the working manual WGS84 form. The inactive adapter cannot
mount MapKit, request tiles, obtain location or emit a selection. No region is approved.
A visibly labelled DEBUG fixture offers synthetic point buttons through the same picker
contract. It is not a fake map and does not purport to be provider acceptance.

The game home may be any safe player-chosen point, not necessarily a real residence.
Nothing in this UI certifies residence, safety, ownership or real-world access. Server
placement and cooldown rules continue to apply. No presence proof, automatic arrival,
manual “I'm back”, public place, NPC memory, sharing or export was added.

## Datum decision and existing reuse

`SearchMapCanvas` renders supplied `RoamCoordinate` values and selects existing pin IDs;
it neither produces a new map point nor certifies datum provenance. The publishing MapKit
search adapter returns untyped coordinates and is separately default-off. Walking uses
`WalkingCoordinateDatum` and requires independently accepted WGS84 regions, with no region
approved by default. Its documentation explicitly leaves Mainland China renderer/provider
behavior unresolved. This slice reuses that datum enum and `PrivateHomePoint.parse`
(latitude/longitude bounds, strict decimal syntax, six-place maximum), not those public
renderers or private-point-to-public services.

Official Apple documentation inspected on 2026-10-03:

- [CLLocationCoordinate2D](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d)
  documents the type using the WGS 84 reference frame.
- [MapProxy.convert(_:from:)](https://developer.apple.com/documentation/mapkit/mapproxy/convert(_:from:))
  converts a point in a view coordinate space to an optional map coordinate. This is not a
  GCJ02-to-WGS84 conversion service.
- [MapKit map geometry](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/MapKit/MapKit.html)
  distinguishes geographical map coordinates from projected map points and view points,
  and requires validation of coordinates returned by view conversion.

These type/API statements do not establish this deployment's provider/renderer provenance
or Mainland China acceptance. They are not used to relabel a bare selected point WGS84.
The live renderer remains blocked until an independently reviewed provider, region, datum,
contract revision, terms/privacy and output-to-basemap contract is supplied. Future Apple
implementation can use MapReader/MapProxy only after that decision; this change does not
instantiate them.

## Contract and privacy

- `PrivateHomeMapPointPicking` starts only on explicit opening; the inactive adapter is
  not even started. Its reviewed source is nil. The ordinary account destination supplies
  no alternate adapter. No feature config, deployment grant or session grant was changed.
- Candidates retain decimal text and optional source metadata. Source provider, region,
  datum and revision must exactly match an independently injected WGS84 contract.
  Nil/unknown, GCJ02, changed region/provider/revision and malformed inputs fail closed.
- More than six decimals, including a seventh trailing zero, is rejected. No rounding,
  truncation, datum conversion or Double conversion is performed. Manual entry remains
  available for an intentionally chosen WGS84 point within the endpoint's precision.
- The displayed preview and final owner review use the validated endpoint Decimal values
  in latitude, longitude order with an explicit WGS84/six-decimal explanation.
- Selection and preview never mint a request ID, save a journal or send HTTP. The point
  feeds the unchanged owner's prepareSet; only the existing confirmation can dispatch.
  The stable requestId/expectedVersion and unknown-outcome exact retry remain unchanged.
- Generation tickets reject late callbacks after close/reopen. Owner readiness, current
  session, captured home version and provider-contract revocation are checked again before
  review. Normal phase invalidation, disappearing owner view and scene inactivity discard
  the selection. Cancel clears the ephemeral point and sheet-only label; manual form
  values never get overwritten by an unconfirmed map point.
- Sensitive point/candidate/selection descriptions are redacted. No telemetry, logs,
  public map, NPC, persistence, clipboard/share action, location manager or permission
  prompt was introduced. All test coordinates and accounts are synthetic.

## Independent lifecycle review

The review found two boundary gaps in the original picker packet:

1. `@State` kept its initial picker owner when the destination's coordinator changed in
   place. Manual text fields could survive that same view identity as well. The actual
   account destination now uses a stateless wrapper that keys the whole private owner form
   by coordinator object identity. New owners receive fresh manual fields, picker and sheet
   state. The sheet is also keyed by selection generation to make cancel/reopen explicit.
   Cleanup never clears a durable pending journal.
2. Provider source revocation was checked before picker review but not at the later final
   owner confirmation. The picker now binds a source proof to the existing review request
   identity and rechecks it inside the final confirmation Task immediately before invoking
   the unchanged owner's confirmation. A revoked or changed source cancels that local review
   with an explanation and makes no journal save or mutation dispatch. A separately prepared
   manual review has a different request identity and remains independent of map availability.
   This check does not change the existing transaction/retry contract once confirmation starts.

The DEBUG fixture can keep the actual account link route open while replacing its synthetic
owner. Added authored UI recorder cases cover replacement with typed manual values, replacement
with a picker selection and sheet-only label, late cancelled callbacks, reopening, and source
revocation after picker review but before final confirmation. Additional app-unit cases cover
those final-confirmation source/session checks, independent manual input and preservation of
an unknown-outcome journal during view cleanup. These are authored tests, not Apple execution.

## Verification and exact remaining gap

Authored 8 Core tests, 13 app-unit tests and 10 UI-recorder tests, including no startup,
unknown/GCJ02 provenance, exact six-place values, excess precision, cancel/reopen, late
callbacks, owner/session/version/source revocation, preview-before-confirm, unchanged
journal retry, both languages and maximum accessibility text size. The DEBUG recorder
reports only counts and an exact-synthetic-coordinate boolean, never credentials or a
real point. UI timing additions are explicit estimates, not measured runs.

Linux source checks: 26 focused private-home contracts, 100 tooling tests, and 905 full
contracts (46 external-source checks skipped); deterministic project/scaffold check and
8-file supplementary Tree-sitter parse pass. The skips are not verification passes.

Swift/Core execution, Apple SDK typechecking/compilation, app-unit execution, UI execution,
screenshots, simulator, device, VoiceOver and actual provider/datum field acceptance:
**NOT_RUN**. Swift and Xcode are absent in this Linux executor. Parsing and source checks
cannot establish those outcomes. No live MapKit, GPS, permission or backend call was made.

The remaining functional gap is explicitly the real map renderer and its reviewed regional
coordinate provenance/precision workflow, followed by Apple/device acceptance. This is not
W19 completion, launch readiness, real-location testing, or authority to enable a provider.
No remote push, deploy, signing, legal acceptance or normal configuration activation.
