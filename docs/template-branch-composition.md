# P036 branch step composition

## Complete editing chain
The existing branch step list, step text/ID fields, option text/destination/score/effects fields, ordering/removal, graph validation, local rehearsal and draft save/restore remain in use. This candidate supplies the missing coupled actions inside that flow rather than a second graph editor.

1. Add a step: it starts as a terminal step, with empty title/body, COMPLETED outcome code, the Mini source default outcome label 完成节点, and no options. IDs are collision-resistant UUID-based strings within the existing identifier contract. The native 50-step limit is retained.
2. Edit the title/body and outcome fields in the existing step form. Terminal steps show outcomes; nonterminal steps show the options entry.
3. Choose Continue with a choice on a terminal step: it atomically becomes nonterminal and gains one empty option. Fill its label, destination ID and score through the existing option editor. Ordinary option-add uses the same action, capped at 12. Existing graph validation requires a real destination and reachable ending; no destination is invented.
4. Turning the terminal switch off alone preserves existing options/outcomes and does not invent a choice. Turning it on clears choices and fills only missing/empty outcome code/label, preferring the step title for the label. The form warns that terminal conversion removes choices.
5. Reorder/remove/edit through the existing controls. Validate and rehearse locally, then use existing local draft save/restore. Clearing a final choice does not invent a terminal node or repair references: validation remains authoritative.

## Evidence and boundary
Master P036 names addBranchStep, toggleBranchTerminal, addBranchOption and adjacent branch update/remove events. Real temp-index.js 630–686 defines the exact coupled mutations; WXML 255–286 shows mutually exclusive terminal outcome and nonterminal option fields. The original native generic Toggle and add-row control performed independent writes, not those coupled actions.

Unknown row fields and unrelated families are preserved. Unsupported historical shapes/duplicate IDs retain the generic fallback. Incoming links and startStepId are never rewritten. Existing schema/normalization/validation/storage and remote permissions are untouched. Original Mini time-based IDs are replaced only by valid collision-resistant native IDs; no wire fields are introduced. The Mini's persisted Chinese default label is kept verbatim and remains editable by the author.

Each action captures the whole branch section and the owner/draft/media scope. Retained controls expire on any model publication (including same-value ABA), index/ID changes, reload/restore, owner change, lock and dismissal. Reappearing creates fresh controls; the previous action cannot replay. Existing generic text fields are reused and are not claimed to have new behavior from this candidate.

## Integration and verification
Base 41571fed5c27d4766d0bebb02e2800d798f1edbd, no earlier candidate overlay. The modified common view touches branch conditional fields, generic terminal-toggle dispatch, and branch add-row dispatch. Preserve existing QA/blind/effects/hotspot additions by additive patch integration, not whole-file replacement. Central choice-row initialization is unchanged. Register the App/Core sources and App test, and merge the bilingual fragment; no central registration files were edited.

Core/App XCTest covers terminal defaults, add limits, atomically clearing choices and supplying outcomes, nonterminal transitions, unchanged references/unknown data, existing validation/serialization/local rehearsal, stale scopes and local save/restore. Swift and Xcode are unavailable: native compilation/tests and Apple UI are NOT_RUN. Source checks and execution of original Mini event bodies are reference evidence only. The local rehearsal test does not claim production game execution or server outcome processing.
