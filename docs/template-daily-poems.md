# P036 daily-sign multiline poem pool

## Complete authoring flow
Open the existing daily-sign poem pool. Add a poem, paste or type its whole text in the multiline editor, inspect the normalized line preview, correct any existing validation issues, or remove the poem. Return to the existing authoring local save/restore flow; signer and seal remain in the parent form.

The input is a local raw string, exactly as typed, including leading/trailing whitespace, empty lines and the trailing newline needed to keep writing. Explicit add/edit/remove actions rebuild the existing poems array by splitting at newline, trimming each line and omitting empty lines. The input control is not rebound to that normalized array, so ongoing typing/pasting does not lose its blank lines. A raw-only change still invalidates old buttons even when the persisted draft is byte-identical.

New poems have empty input and an empty canonical line array. Removing the last poem is allowed as in Mini; the existing validator then reports the empty pool. The existing native cap is 60 poems, with 1–4 nonempty lines per poem and 24 UTF-16 units per line. No input is truncated or silently accepted: invalid line counts/lengths continue to block the existing serialization contract. A normalized preview is text readback, not a generated draw or today's server-selected result.

## Evidence and existing delegate gap
Master P036 names addDailyPoem/updateDailyPoem/removeDailyPoem. Real temp-index.js 714–737 retains dailySignDrafts as the edit-time fact source, joins stored lines for display, and uses _poemsOfDrafts to rebuild the full pool on each action. WXML 1066–1080 specifies textarea input, one sentence per line, the same line/length guidance, and add/remove controls.

The original native .poems destination reused a generic .strings list, with one single-line field per line. It could edit individual lines, but not the source's whole-poem paste/newline-preserving workflow. This candidate changes only the supported destination; malformed historical shapes retain that generic fallback. Opening is read-only. The first explicit pool edit may normalize the other displayed poem strings too, matching Mini's whole-pool rebuild. Unknown dailySign fields, signer/seal and unrelated families are preserved.

## Raw state and ownership
Local row UUIDs identify duplicate-text occurrences and never enter JSON or storage. The Core pool captures the exact dailySign section. The controller additionally tracks owner/draft/media and separate text/action generations. Own typing keeps the same row and binding; structural edits retire old bindings. Every external draft publication, including same-value assignments/ABA, invalidates the editor and asks for explicit reload. The existing parent onChange(draft) calls changed() again after edits; its review/revision-only publications retire old buttons but must preserve raw text and its live input binding. Media/owner lease changes also invalidate editing. Dismissal retires all controls. Reload/reopen/local restore reconstructs raw display from canonical stored lines, rather than persisting raw whitespace in a new field.

No media, service, factory, server clock, random draw, reward or permission is added. Existing generic controls and shared validation/storage are not modified.

## Integration and verification
Base 41571fed5c27d4766d0bebb02e2800d798f1edbd, no prior candidate dependency. A supported-destination branch is added inside the existing poems NavigationLink; previous common-view additions must be preserved by additive patch integration, not whole-file replacement. Source/App test registration and bilingual localization are fragments only. Central ChoiceOptionRows initialization is unchanged.

Core/App XCTest covers full paste/edit/delete, raw-only edits, duplicates, source whole-pool normalization, limits, unknown data, stale controls, external reload, locks and canonical local save/restore. Swift/Xcode are unavailable, so native build/tests and Apple TextEditor/IME interaction are NOT_RUN. Source checks and bounded original Mini helper/event reference execution are separate evidence, not native or production execution.
