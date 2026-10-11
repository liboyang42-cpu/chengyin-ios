# P036: Independent reward configuration

## Complete editing flow

The existing reward form now has independent coupon, text-feedback and medal switches. Enable a type to reveal its existing fields, enter values, disable it to clear only that type, and re-enable it for fresh entry. Multiple types can coexist. The empty-state hint explains that publishing requires reward contents or an explicitly disabled reward module.

This implements Mini onToggleCoupon, onToggleText, onToggleMedal and the corresponding field-editing/reload chain together. The source handlers clear only their type; initModuleState infers active types from couponId, feedbackText and medal image/name. Exact source excerpts and master P036 mapping are recorded with the candidate.

## Persistence and unchanged authority

The existing coupon ID field, feedbackText, medalImg, medalName and medalStyle remain the only stored data. Enabling an empty type is presentation state and does not fabricate data. Filled values persist through the existing local save/restore flow and determine which editors open on a fresh visit. Empty selections are retained across same-lease scroll re-entry but are not new persisted preferences, matching the source's field-based inference.

Turning a subtype off clears its local content to the native optional-field empty representation. Turning it back on does not restore cleared data. Turning the whole reward module off/on preserves its contents, retaining the existing native module behavior. The old binding generation is retired either way.

Medal subtype disable clears image and name but retains style, matching Mini onToggleMedal. The previously delivered Clear medal action stays within the medal editor, resets the style to glow, and leaves the editor open so the user can replace the medal. A saved style alone does not reactivate an empty medal subtype. Unknown style or historical numeric values are preserved without normalization and appear in their existing fields when the type is enabled.

No new persistence schema, wire field, service factory, uploader, coupon catalog, entitlement check or production grant is added. Coupon availability/issuance and remote publishing remain governed by the existing application contracts. Existing reward validation still rejects an enabled module with no usable contents.

## Lifecycle

The editor binds to session, draft identity and media generation. Per-type generations retire hidden text/number/style controls on disable while allowing typing in other reward types to continue. Module toggles, reload/restore/discard, owner changes and dismissal retire old callbacks. Current values remain visible under the same owner's write lock, but all mutations remain denied.

Opening/reloading never writes the draft. All accepted field edits and off-switches synchronize through the existing local coordinator before navigation. Existing choice-row, narration and story-image editing remains present.

## Verification and integration

Six Core and ten App tests are authored for inference, isolated clears, existing payload/validation, all three complete edit flows, fresh local restore, no resurrection, cross-type typing, Clear medal replacement, module off/on, old callbacks, scroll re-entry, historical values and durable write locks. Six targeted Python contracts inspect the actual route, field bindings, mutation limits, lifecycle and fragments.

The current authorized computer lacks Swift/Xcode. Core/App execution, Apple builds, simulator/device interaction, VoiceOver and localization acceptance remain NOT_RUN; source checks are not runtime acceptance. Integrate the new sources/tests and additive localization fragment through the existing central workflow. Prior packages and central PBX/catalog/CI files remain unchanged.
