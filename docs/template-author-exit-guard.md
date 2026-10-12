# P036 editor back confirmation

Base: f329ff5180551ef3956b2718cb9ef071e2635409, tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd. Feature35 adds a complete exit decision to the existing authoring root, without changing its editing/save/publish controls.

## Source and non-duplication

The sole master P036 names goBack and onNativeBackGuard. The real Mini chengyinhub-xcx/pages/publish/temp/index.js at 95e499471eaa39c28f77d16125f0cc17b8c37123, blob76e39df5c326aaf029bda8da21562072fb352553, lines432–451 closes a preview first, ignores back while submitting, immediately exits a clean page, and asks a dirty page to continue or discard. Its confirmation calls exit only; it does not clear the form or delete a saved draft. Lines2383–2400 retain top-overlay priority.

This is separate from existing native “delete local draft” confirmation. Features25–30 are samples/rehearsals;31–33 are timer/check presets;34 edits profile override. Existing note/DIY string rows, classification editors and photo-frame controls were inspected and rejected as already implemented. None is rebuilt here. No private Mini module is copied into the patch.

## Actual workflow

The ordinary editor Back control reads the same-owner, same-identity local checkpoint. A byte-equivalent saved draft, or an exact untouched empty draft with no local record, exits once. Otherwise the user can continue editing or explicitly leave without saving. Existing saved records and the in-memory draft remain unchanged, matching Mini's exit-only action. This does not invoke the existing delete-local-record action.

A missing record with content is unsaved. An unreadable/incompatible/foreign-owner record or an unencodable current/checkpoint draft is unverified, never silently clean. The unverified dialog offers a real recheck. If recheck verifies matching saved content it completes the pending Back request; otherwise it shows a fresh confirmation. Existing SaveLocal remains the save action; its actual successful stored bytes determine whether the next Back is clean. A failed save is not treated as success.

The native boundary is local save, not Mini's server-side dirty flag. Server-seeded content without an exact local checkpoint conservatively prompts. The dialog says so. No remote write, publish, grant, reward or new permission is introduced.

## Lifetime and layering

The modifier supplies a normal Back item, hides the default back control and requests interactive-dismiss disabling so the explicit exit flow owns this screen's ordinary navigation. Preview, media and the original local-discard dialog remain independent upper layers. The controller reads their live visibility and retires old callbacks after transitions. It does not dismiss those overlays. Busy/submitting/publication-review states reject root Back.

Owner/session, draft identity, full sorted-JSON snapshot, metadata/media generations, coordinator state/restore status and a per-event generation fence all apply. Model publications retire pending exit dialogs. Background, disappearance and reentry retire Back, Confirm, Cancel, Retry and stale presentation bindings. A duplicate confirmed exit runs only once. The code does not intercept unrelated tab changes, account navigation or app termination.

The added coordinator method is strictly read-only. It wraps the existing store.load with owner, identity, generation, lock and restore checks before/after the read, without synchronizing or changing coordinator state. It rejects an owner change during a reentrant storage read.

## Integration

Only one additive modifier line in App/TemplateAuthoringView.swift and one additive read-only method in Core/TemplateAuthoringCoordinator.swift. Two new production sources, one App test source and Resources/CreatorExitGuard.xcstrings are registered in the actual Xcode project. The Core test uses existing Package.swift directory discovery. Seven EN/ZH keys are supplied in the compiled dedicated catalog, and every new title/button/message explicitly reads the CreatorExitGuard table. Existing target settings, catalog keys, original code and prior packages are retained.

No dependency on unpublished samples, presets or feature34 is required. The independent candidate and its complete patch are built against the actual f329 tree. A separate temporary check verifies applying the sealed34 batch and this batch together; it does not change the central81 tree.

## Validation limits

The real Mini goBack harness, focused Python source contracts, OpenStep/PBX graph checks, additive-byte checks and actual Git forward/reverse/reapply witnesses are recorded separately. Native XCTest files contain12 Core methods and18 App methods. Supplementary Swift parsing does not establish typechecking or SDK correctness. Real Swift build, Core/App XCTest and navigation/UI execution remain NOT_RUN without an Apple toolchain. Actual toolbar placement, interactive-dismiss behavior and alert-layer behavior still require native UI verification.
