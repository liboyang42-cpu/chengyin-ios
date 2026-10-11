# P036: Add and remove choice options

## User-facing behavior

The existing native template completion form now offers two to four choice rows. Add option creates the next blank row; Remove option deletes a row and closes the gap. Two rows is the minimum and four the maximum. Text, image and audio references move together. If the removed row was correct, the first remaining option becomes correct; otherwise the surviving correct row retains its identity under the new letter.

The behavior follows master P036 events addChoiceOption/deleteOption and the Mini handlers in temp-index.js 1645–1665 and 1712–1744. The Mini WXML places deletion on each row and the add action below the list. The native app previously rendered all four editable strings and all four attachment entries without row operations.

## Existing contract, no new service dependency

Rows use questionA, questionB, questionC, questionD, correctAnswer and questionOptionMediaJson. A present empty string records an explicitly added blank row; no new persistence or wire field is introduced. Native local save/restore preserves blank rows. Existing publication validation still requires enough nonempty options and a valid correct answer.

Opening or reloading the editor never rewrites a draft. Media-only, answer-only and sparse historical rows are retained. Reordering requires the existing supported option-media schema and a recognized answer identity. Unknown/malformed media or an unknown answer blocks row addition/removal rather than guessing or dropping stored data. Ordinary text edits remain available without rewriting unknown media.

Deletion preserves attachment values exactly while changing their existing A–D keys. The JSON is re-encoded only if the attachment mapping actually changes. Removing its final attachment produces the existing explicit empty-string media field. No URLs are loaded or uploaded, no media trust is granted and no new backend capability is required.

## Lifecycle and shared forms

The row controller guards session, draft identity, media generation and completion-method generation. Each topology change retires old text/media/answer bindings and row actions before letters move, then invalidates pending local media review before assigning the new local draft. Draft metadata generation and exact captured field bytes reject stale or committed ABA actions. Normal repeated typing remains supported by the current row binding.

Reload, restore, discard, completion-method changes and editor dismissal reject retained callbacks. Write locks remain controlled by the existing authoring model. Shared owner/read-only QA and media forms are retained, with their default fixed A–D read representation unchanged. Only the editable choice route opts out of the old fixed controls and mounts the new row editor.

The earlier narration-clear, controlled narration-preview and story-image-removal changes are preserved in this candidate.

## Verification and integration

Ten authored Core tests cover row bounds, blank persistence, row/media/correct-answer alignment, sparse historical values, unsupported data, exact-byte stale targets and the existing payload. Ten authored App tests cover local coordinator persistence, stale callbacks, repeated typing, method changes, owner/lifecycle changes and pending-media cancellation.

Five feature-specific Python source contracts and the six existing choice-media contracts are targeted checks. The existing media contract's single old-entry assertion is replaced by stronger assertions for the new editable entry and its use of the original guarded media binding; its other source, owner, catalog and lifecycle assertions remain unchanged. That supporting path is declared in the scope amendment before editing.

These source checks do not execute Swift. The authorized current machine has no Swift/Xcode, so Core/App execution, simulator/device UI, accessibility and localization acceptance remain NOT_RUN. Central PBX/catalog/CI files are unchanged. Register the new sources/tests through the supplied registration fragment and merge the localization fragment additively during integration.
