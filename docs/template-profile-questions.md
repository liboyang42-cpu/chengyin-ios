# P036 profile question composition

## Complete editing flow
The profile's existing question and option field forms remain the destinations: label, key, maximum length, effects and override conditions are not duplicated. The new typed list controls and kind picker complete the missing composition behavior.

1. Add a question. The source defaults are empty label, text kind, maximum length 12, required true and the first free qN starting at the current question count plus one. Keep 1–8 questions.
2. Enter the question text/key using the existing form. Choose text or pick with the native picker. Switching to pick seeds two empty options when the previous list has fewer than two; it replaces that undersized list, as Mini does. Two or more existing options are preserved intact. Both kind choices set required true.
3. In pick mode, edit the existing option labels/keys/effects/override fields, add options up to six and remove down to two. New option keys scan every question, including retained text-mode options, for the first free A–Z then opt1/opt2/etc. Existing keys are never silently renamed.
4. Switching back to text retains options and effects so a subsequent switch back does not lose a valid choice list. Question/option sorting retains the original native list ordering ability. Batch deletion obeys source minimums, not merely a disabled single-delete affordance.
5. Continue through existing validation, serialization and authoring local save/restore. An override pointing to a removed option remains visible to the existing reference validator; the editor does not invent another choice or rewrite the reference.

## Evidence and boundaries
Master P036 lists the profile question/kind/option events. Real temp-index.js contains nextProfileOptionKeys at 138–150, addProfileQuestion at 794–807, removeProfileQuestion/pickProfileKind/addProfileOption at 850–893, and removeProfileOption at 1024–1035. WXML 712–739 supplies the question/kind/option and nested effect workflow. Current native generic choice writes only kind, generic add-row chooses IDs within one list, and generic delete does not implement these minimums. Existing kind-dependent field visibility is reused unchanged.

Unknown data is preserved. Malformed historical list/identity shapes fall back to the original generic renderer. Existing duplicate option keys across different questions are not auto-repaired; the allocator avoids all occupied keys and existing validation remains authoritative. The Mini's kaccha helper is not used or recreated because the native contract exposes override instead. No schema, normalization, validation, storage, server profile write or reward/effect execution is added.

## Scopes and integration
Each new picker/add/delete/move action captures the exact profile snapshot, model generation and owner/draft/media lease. Option lists also bind to the original question key and position. Any model publication, including ABA, invalidates retained actions; reordering or renaming a question cannot redirect an old controller. List dismissal retires its controls and returning creates fresh actions. Existing generic text bindings are reused; this candidate does not claim to alter their behavior.

Base 41571fed5c27d4766d0bebb02e2800d798f1edbd with no earlier candidate overlay. Profile list dispatch is added in the field body, not inside earlier effects/branch generic-row dispatch. The kind picker also dispatches at the field body, leaving the earlier generic choice/toggle/row branches untouched. Apply patch additively and preserve QA/blind/effects/hotspot/branch changes; never overwrite the entire common file with the base-relative after image. Registration and bilingual localization are fragments only. The central choice initialization remains unchanged.

## Verification honesty
Native Core/App XCTest covers full multi-question construction, global key allocation, kind round trips and data preservation, limits and batch deletion, movement, stale scopes, existing serialization and local save/restore. Swift/Xcode are unavailable: native compile/tests and Apple UI are NOT_RUN. Python source checks and bounded original Mini helper/event execution are reference evidence, not a native runtime or real profile-state write.
