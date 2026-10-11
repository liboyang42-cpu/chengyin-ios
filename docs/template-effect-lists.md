# P036 typed effect-list authoring

## User flow
From an existing QA/profile/branch option or one of the four check outcome effect lists, open the effect list. Add a row, choose SET / INC / ADD_TAG, enter a variable and numeric value or a tag, reorder/remove rows, then return to the existing authoring/local save/restore flow. Existing validation appears inside the list as well as in the parent configuration.

- New rows use `{var: "", op: "INC", value: 1}` and the source maximum of 16.
- SET/INC show the variable and integer inputs. Valid finite numeric input is stored as a number. Incomplete/invalid text remains editable and is handled by existing native validation/serialization rather than converted to nonfinite JSON.
- Switching to ADD_TAG keeps an existing string value or clears a numeric value to an empty string. The variable is hidden and preserved locally; existing serialization removes it from a tag effect.
- Switching to SET/INC keeps a finite numeric value (including decimal text accepted by the existing native number parser), otherwise starts at 1. An empty string falls back to 1; whitespace-only string follows Mini's numeric-zero transition. Native controls do not introduce JavaScript-specific nondecimal-number syntax.
- Move up/down retains the previous generic list's ordering capability; removal may leave an empty list.

This configures effects only. It does not apply effects to a player, simulate server state, grant XP/luck/tags, execute a check or create a new capability.

## Evidence and constraints
Master P036 names `addEffectRow`, `updateEffectField`, `pickEffectOp`, `removeEffectRow`. The real `temp-index.js` 902–973 specifies the shared list shape, row cap, typed value edits and op/value transitions. Existing `TemplateCreatorSchema` declares the same paths: QA option effects; profile question-option effects; branch step-option effects; check success/fail/crit/fumble effects.

The existing generic field renderer had raw editable rows, but no operation/value transition. This candidate adds a typed list destination at that existing entry. The generic renderer remains the fallback for unsupported historical shapes or oversized lists; condition lists and arbitrary paths are never intercepted. Unknown row fields are retained and continue to obey existing submission validation. No schema, validation, normalization, storage or remote service code changes.

The Core snapshot covers the whole owning family. The controller additionally captures owner/draft/media scope and a parent fingerprint with only this effect list removed. Editing effects keeps that parent identity stable; an enclosing option/question or sibling configuration change cannot silently retarget an already-open list, even after reload. The user is told to return and reopen. Every model publication retires old buttons; structural/op/other external changes also retire field bindings. Own text typing keeps stable row positions. Pending locks and ownership changes deny writes.

## Dependency and verification
Apply after the sealed seventh blind-option package, which contains the sixth QA dependency. Preserve both existing mounts. No dependency on the D6 or reward packages. Register source/App tests and merge the localization fragment additively; no central files were edited.

Native Core/App tests cover the complete workflow, caps, malformed data, paths, serialization, parent scope and local save/restore. Swift/Xcode are unavailable in this environment, so native tests/build/UI are NOT RUN. Python source checks and bounded execution of original Mini event bodies are not native execution. No remote or production checks are claimed.
