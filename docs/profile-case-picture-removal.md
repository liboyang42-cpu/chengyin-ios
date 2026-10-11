# P107 remove all existing work pictures

Base: `96d727404a966cd3b3d2437c79449046beda560f` plus four sealed profile increments. ProfileEditView's required preimage is `85bf7f9427031511c6628c002894fad98fa5d1bc88a657a5cf9ffa0f8a047dc1`. Central integration must retain the newer body decomposition.

## Source-backed missing operation

MASTER v10 P107 lists openPop2/deleteCasePic/cancel2/confirm2/saveInfo. The approved Mini source at `f859cd6e2618f618a53f5cd33949259828e86313` copies the work-image list to scratch, deletes by index, and joins the confirmed list into casePics. Repeated deletion until empty produces `casePics: ""` in the existing whole-profile update. The update DTO has String casePics; the authenticated controller uses getAppUserId and setCasePics; the mapper accepts an explicit empty value and the self response exposes casePics.

The existing native portfolio editor supports description staging and a gallery entry but has no removal operation. This increment adds a bulk clear-all affordance for the exact empty-list result of Mini deletion. It does not claim that Mini has a dedicated clear-all button, and it does not rebuild a gallery or add an upload route.

## User operation

Edit profile → Manage existing work images.

- See the total number of nonblank existing references, including duplicate positions and images beyond the gallery's 100-image display cap.
- Remove all work images changes only this editor's local choice. The wording explicitly covers every image while preserving the work description.
- Keep all existing images reverses the local decision. Cancel/swipe close leaves the page draft unchanged.
- Done stages clear-all intent; reopen starts from that intent and permits keeping all originals before whole-page save.
- Description editing remains available. When removal is staged it shows a pending-removal message instead of presenting the original gallery as the current selection.
- Whole-profile review explicitly states that all work images will be removed. The original save and empty-field readback finish the operation.

The all-image decision is unambiguous without image downloads. This view does not accept raw URLs, does not select unidentified individual images and does not depend on the currently missing authorized personal image reader. Existing case/QR viewer entries still have that loading dependency and are not claimed as real usable previews.

## Contract and stale-state protection

`removesCasePictures` is a clear-only Boolean; review metadata is excluded from CodingKeys. False preserves the complete original casePics byte string, including delimiters. True with at least one nonblank reference sends an empty string. Empty/delimiter-only sources are a no-op and retain original bytes. Clear-all includes references beyond the preview cap, not just the displayed prefix.

The existing local editor UUID, identity/epoch, viewer revision, model/draft generation and exact snapshot guards protect staging. The shared helper accepts only empty or the original casePics bytes for this field. New byte-exact casePics checks before review and before write prevent clearing a concurrently changed source, including canonically equivalent Unicode drift.

Description, name, introduction, QR, avatar and preference proposals remain intact. Avatar staging/discard and draft fingerprints retain the new intent. An acknowledged save needs exactly empty casePics readback; unknown results stay locked and never auto-repeat the POST. Known rejection and failed refresh retain the proposal. A stale pre-save editor cannot restore cleared server state.

## Delivery and verification

PENDING_PARENT_INTEGRATION: registration and ten bilingual localization keys are fragments. Four earlier packages remain byte-identical. Two preceding source checkers are updated only to recognize the explicit clear-all branch and propagation of its Boolean alongside their original contracts.

Apple: NOT_RUN. Nine Core, seventeen AppUnit and five UI tests are authored, not compiled or executed. Named source checks, static mutation checks, original Mini synthetic execution, backend source seams and patch forward/reverse are distinct evidence. No production write, new grant, endpoint or token flow is introduced.

One accidental broad `test_profile_*.py` discovery also collected historical admission tests from the scratch cwd. It reported 156 tests, 13 failures and 115 errors (including unavailable import paths and integrated-fragment assertions); that run is not acceptance evidence, was not repaired and its truncated-output limitation is recorded separately. Focused checks use explicit filenames. Historical failures, existing compiler diagnostics and CI remain assigned to the parent/sixth line.
