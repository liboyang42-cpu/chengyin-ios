# Complete profile draft comparison and local restoration

Base `96d727404a966cd3b3d2437c79449046beda560f` plus five sealed profile increments. ProfileEditView preimage: `4fbcce9924bed3736eb2129bc71fa92c53f31874e15b55bf0c54d281b8f77891`. Preserve the central body decomposition during integration.

## Source relationship and gap

MASTER v10 P107 maps the existing profile's local cancel/confirm operations and saveInfo. D7 explicitly keeps jointly validated fields in one form and requires draft retention, cancellation/reentry and identity-safe results. Approved Mini source `f859cd6e2618f618a53f5cd33949259828e86313` stages field scratch locally and sends the complete profile in saveInfo; cancel leaves each page field untouched.

The native before-state has a prepared, server-backed review of proposed values plus Save and Cancel. It does not show a complete before/after difference list, and there is no action to discard the complete reviewed draft while remaining on the editor. This increment adds that supporting native review/restore workflow. It does not claim Mini has this exact comparison screen or restore button, and it does not duplicate the five field editors.

Website was considered and excluded: DTO/controller/self read support it, but the current Mini input handler accepts only name and introduction and the website presentation is commented out. No new website capability is invented here.

## User flow

1. Stage any supported profile edits and open the existing Review action. That existing action reads the current self snapshot once.
2. Expand Compare changes to inspect original and proposed values for each changed field: nickname, introduction, case description, preferences, avatar, contact QR and work images. Unchanged fields are omitted.
3. Text uses the actual payload, including its existing normalization behavior; exact UTF-8 comparisons keep Unicode-only differences in the list. Empty and whitespace-only text have distinct presentation. Image references are never displayed; avatar/QR use presence/change labels and work images use the full count, including the gallery's omitted tail.
4. Choose Discard reviewed changes. A separate local confirmation explains that all reviewed changes will be dropped and nothing saved. Cancelling keeps the review and draft intact.
5. Confirming consumes only this review, adopts its freshly read baseline, clears all staged flags/text/preferences/avatar selection, dismisses the review and leaves the same editor available. A distinct status says nothing was saved.
6. Editing, reviewing and saving again remain available. Existing Save and ordinary Cancel are unchanged.

## Atomicity and boundaries

The model captures the complete draft and its revision before preparing the review. Restoration requires the same review ID, model generation/revision, draft revision and exact draft bytes, account/epoch and viewer revision. A draft changed during the preparation read receives no restoration capability. A later edit-and-revert ABA, reset, old review, inactive/retired lifetime, busy operation or competing editor blocks the action.

The coordinator independently requires its exact active confirmation and full current session, including the token, while not busy, cancelled or locked. It consumes the confirmation synchronously and adopts that confirmation's self snapshot. It does not read again, dispatch a POST, call onSaved, manufacture a successful save or clear a pending-write record. Unknown writes remain locked. A known rejection requires a fresh review before restoration.

This restores local editing state only. It is not server rollback and does not delete an already uploaded avatar asset. Avatar lifetime retirement makes a stale local upload callback unable to re-stage the discarded selection. Existing production gates and optional image-reader dependencies are unchanged.

## Delivery and tests

Registration/localization: PENDING_PARENT_INTEGRATION via fragments; 15 new bilingual keys. No shared project, catalogue, AppSession, adapter, permission or CI file changes. All five previous packages remain sealed. Only this increment's before/after images and patch are delivered.

Apple: NOT_RUN. Core, AppUnit and UI tests are authored but not compiled or executed on this machine. Focused source checks, mutation sensitivity, original Mini scratch/save evidence and exact patch replay are separate evidence, not a native-runtime or CI-green claim. Historical failures are not investigated or repaired.
