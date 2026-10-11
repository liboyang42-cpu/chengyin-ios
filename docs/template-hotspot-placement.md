# P036 hidden-object target placement

## Complete authoring flow
Enter the existing hidden-object Creator form. The normal target-list field delegates to the new target-placement destination; other fields (scene URL, title, hint, attempts, XP) remain where they were. Malformed historical target lists and unsupported scene references retain the previous generic field editor. An HTTPS scene address is required before the new placement entry replaces that field.

1. Enter an existing HTTPS scene URL in the parent form. In target placement, explicitly load or retry the scene. Loading, failure and missing/unsupported URLs cannot accept placements.
2. Add/name/remove targets within the existing 3–5-target contract; move up/down retains the previous native list-ordering capability. New targets use the Mini defaults: center x/y 0.5 and system radius 0.08. Existing radius values and unknown fields are preserved.
3. Select a target, then tap its location on the displayed image. Selecting the same target again cancels. A tap without selection does nothing. Successful placement updates only that target's x/y and clears selection.
4. Numbered markers and target names provide position readback. Return to the existing parent validation/rehearsal and authoring local save/restore actions.

The new destination has no manual coordinate or radius inputs. It adds no upload, provider, server contract, effect execution or publication permission. It does not manufacture a game result. Existing generic controls remain only as an unsupported-shape fallback.

## Source and native adaptation
Master P036 lists armHotspot/placeHotspot and the advanced row actions. Real temp-index.js 2201–2241 toggles a selected index, measures nonzero bounds, normalizes/clamps coordinates, rounds to four decimal places and disarms after placement. Its WXML 344–385 explicitly excludes coordinate/radius input and groups scene, labels, selection, add and remove. Existing native schema requires 3–5 targets with the same x/y/r fields and existing serializers remain unchanged.

The native canvas uses the actual aspect-fit image bounds, matching the existing native hidden-object rehearsal/player pattern, rather than storing coordinates in image letterboxing. The Mini uses its displayed scene bounds. HTTPS URL syntax is constrained (no credentials, fragment, whitespace or relative paths); loading occurs only after the user presses Load scene. This is ordinary AsyncImage loading, not a new retained-media/upload factory. Existing relative references remain editable in the parent but cannot be loaded by this new canvas.

## Stale input and lifecycle
The Core editor captures the exact hidden-object section. Mutations preserve other families and unknown row fields. IDs, rather than current array indices, identify targets. Duplicate/invalid IDs and unsupported radius/list shapes keep the generic fallback.

The controller captures owner/draft/media lease. Every external model publication clears the scene request and selected target, including same-value ABA edits. Own label/add/remove/place writes keep the already loaded image while retiring stale actions; repeated typing remains usable. Old image completions cannot revive a request after retry, scene change, backgrounding, leave, restore or owner change. Image presentation disappears and selection is discarded on dismissal/background. Returning requires another explicit load. No network cancellation beyond AsyncImage's lifecycle is claimed.

## Integration and verification
Base: 41571fed5c27d4766d0bebb02e2800d798f1edbd. No earlier candidate overlay is required. The seam is the top-level Creator configuration fields/section, separate from the QA/blind/effects generic field seams in sealed earlier packages. Preserve those seams when merging additively; do not overwrite their whole common file with this base-relative after image. The central choice-row initialization fix is unchanged.

Register the App/Core sources and App test via the registration fragment; merge localization additively. No central registration, schema, normalization or storage edits are included.

Native Core/App XCTest cases cover geometry, defaults/counts, preserved radius/unknown data, URL loading boundaries, full editing, image readiness/retry, stale target/image callbacks, owner/lock/lifecycle and local save/restore. Swift/Xcode are unavailable here: native build/tests and Apple UI/network interaction are NOT_RUN. Source checks and a bounded original-Mini event reference exercise are separate evidence, not native execution.
