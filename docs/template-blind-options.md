# P036 blind-taste option composer

## Complete author flow
Open Advanced → Blind tasting and enable the family. Existing title, instructions, hint and XP fields remain. The native option composer now supports:

1. Add an option. Allocate the first unused letter among A–J, with Mini's six-option maximum. Adding a blank row does not create a correct answer.
2. Edit its key and label. Renaming the selected option's key updates `answerKey` in the same draft mutation. Other edits preserve the selected answer.
3. Choose an answer directly from the existing options. The chooser requires a unique schema-valid key; invalid/duplicate keys remain editable and existing validation still reports them.
4. Remove an option. If it was the answer, select the first remaining key, or an empty answer if no rows remain. Removing a non-answer leaves the answer unchanged. Incomplete lists remain drafts with existing validation; no minimum row count is invented beyond Mini behavior.
5. Move options up/down. This retains the existing generic list’s ordering capability while keeping each row and the selected key together.
6. Use the existing local rehearsal, save, leave and explicit restore. Rehearsal compares the existing selected key against the configured `answerKey`; it grants no player result or reward.

Mini evidence: P036 `addBlindOption`, `updateBlindOption`, `removeBlindOption`, `setBlindAnswer`; `temp-index.js` approximately 736–772 and the corresponding WXML blind-taste section. The previous generic row form used generic option keys and a separate manually typed answerKey. It lacked this linked composer. New form mounting preserves the sixth QA answer-selection increment.

## Contract and preservation
Only existing `advanced.blindTaste.options` and `answerKey` fields are edited. No new schema, stored row IDs, wire fields, factories or permission gates. Opening a draft does not normalize its data. Unknown option/module fields and unrelated families survive edits. Existing backend validation and unknown-field failure remain unchanged.

Malformed lists, more than six historical rows, and non-string key/label/answer values are preserved. The original generic answer and row controls remain as explicit repair fallbacks. Missing key/label strings can be filled through the composer. New answers are selectable only when their key is unique and satisfies the existing schema pattern.

Core mutations require the exact captured serialized blind-taste snapshot. UI buttons also require current model generation, owner/draft/media lease and an active view. Synchronous model-publication observation retires stale buttons and text callbacks before reordered/deleted/reloaded rows can receive edits. Own key/label typing keeps the same row positions and permits repeated input; structural changes, external edits, session transitions and leaving the view retire those bindings. Reappearance publishes a fresh generation. Durable pending-write locks deny edits.

## Verification and integration
Focused Python checks are source-contract checks, not native execution. Swift Core/App tests cover the full flow, persistence/rehearsal, preservation, caps, malformed data, typing and stale callbacks. Swift/Xcode are unavailable in this environment, so those native tests and Apple UI checks are NOT RUN.

Apply after the sealed QA answer package. Use the supplied registration and localization fragments; no central project/catalog/CI files were edited. Apple acceptance: add C, fill its label, choose it, rename its key, verify answer follows, remove it and verify fallback; edit successive characters; save/restore and rehearse; check stale controls after deletion, reload and owner change.
