# P036 QA answer-selection workflow

## User flow
In template authoring, open Advanced → creator QA, enable the QA family and choose PICK. Continue using the existing question/title/media fields and option list to add, label, reorder or remove options. The new answer overview displays the current labels and selection state.

- Single choice: tap an option to make it the sole correct answer. Tapping it again keeps it selected.
- Multiple choice: enable Allow multiple, then tap options to select or unselect each independently.
- Return to single: turn Allow multiple off. Retain the first currently correct option in the current list order; clear the other correct flags. If none was correct, do not invent an answer.
- Option editing, QA validation, local rehearsal, local save and explicit restore continue through their existing paths. Rehearsal checks the resulting exact set of option IDs; no player completion or reward action occurs.

Mini evidence: P036 event index `pickCorrectQaOption` / `onQaMultiToggle`; `temp-index.js` 1678–1705 and WXML 404–429. The former generic renderer exposed independent correctness booleans, but lacked this linked answer-selection interaction. Generic option label/feedback/effects/list editing is reused. The root `multi` control now hosts the overview; ordinary nested correctness toggles are hidden for supported configurations.

## Data and lifecycle
Only existing `advanced.qa.multi` and `advanced.qa.options[].correct` change. No schema, storage, transport, identity, reward or production capability changes. Opening the view does not normalize imported data. Option order, IDs, labels, feedback, effects, unknown extension fields, question fields and other families are preserved. A multiple-selection enable does not alter any existing correct flag. Multiple-selection disable follows Mini's first-correct retention.

Malformed option lists/flags remain unchanged. The selector refuses non-array/non-object options, more than four rows, non-boolean correctness/multi flags and malformed labels; existing generic row controls and the multi-field fallback remain available for explicit repair. Empty or incomplete lists retain existing validation, rather than getting synthesized answers. Unknown extension fields survive edits and continue to fail existing submission validation.

The core applies only to the captured exact serialized QA snapshot. The UI controller also captures the current model generation and owner/draft/media lease. It synchronously retires actions on every model publication, protecting option reorder/removal, same-value reload and mode/list A→B→A edits even before the parent `onChange` callback. Leaving the view retires callbacks; reappearance publishes a fresh control generation. Pending-write locks and changed owner sessions reject edits.

## Verification / integration
Native tests cover the complete selection flow, legacy preservation, malformed data, exact snapshots, local persistence/rehearsal, stale controls and write locks. This Linux environment has no Swift/Xcode toolchain: native tests and UI interaction are authored but NOT RUN. Focused Python checks are source-contract checks only. Register the new app/Core source and app unit test via the supplied fragment; merge localization additively. This feature has no pending reward/choice package dependency or overlapping changed file.

Apple manual acceptance: configure 3 named options; choose the third as single; turn multiple on and select first; turn multiple off and confirm first remains; edit/reorder/remove options through the existing list and verify labels and answer flags follow the same rows; rehearse correct and incorrect sets; save/leave/restore; switch QA mode or owner and confirm retained controls cannot change the new draft.
