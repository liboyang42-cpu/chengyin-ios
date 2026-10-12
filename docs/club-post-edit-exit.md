# P045 edit-post exit confirmation

## Source and scope

Base 077273784d7fed5397f84f17b2a659723f3f3b22. MASTER-v10 P045 explicitly lists requestClosePostEdit, confirmDiscardPostEdit and cancelDiscardPostEdit. Mini pages/club/detail/index.js at f859cd6e2618f618a53f5cd33949259828e86313, blob b49b5fb14caf49d47e971cd93ffd73cd94d8e044, lines1718–1742 compares changed text to the original, opens one discard confirmation, keeps text on cancellation and discards only on confirmation. Native edit composer previously had a direct Cancel close and no dirty-exit flow.

The addition is editing-only. A clean Cancel closes immediately. A changed Cancel asks Keep Editing or Discard Changes. Keep Editing leaves text/images untouched. Discard consumes a single current ticket before closing. New-post Cancel and all existing review/stageDraft/update operations remain unchanged.

## Local draft contract

Content and image strings compare exact UTF-8 bytes. Whitespace, line endings, canonical Unicode variants, image order and duplicate references are meaningful; reverting exactly to the source is clean. The Mini editor edits text only; the existing native editor can also modify image references, so those local changes are included in its guard. No draft normalization, persistence, image operation or transport is added.

Interactive swipe dismissal is disabled for dirty edits or while busy/uploading. The visible Cancel remains the explicit route into discard confirmation. This does not intercept or redesign parent navigation/account-change cleanup.

## Current-view fences

The ticket binds the local draft, original snapshot, club/post/version, community-model instance and complete current community session (identity epoch and credentials). Credentials remain in-memory existing session values; they are never logged or serialized. Confirmation also checks visibility, lifetime, current bindings and busy/uploading/scene state. Draft or scope changes invalidate the ticket; leave/background consumes its lifetime. Old Keep Editing cannot cancel a newer ticket. Repeated Cancel while presented does not create duplicate dialogs. A new request after outside dismissal replaces the old ticket.

SwiftUI may clear a dialog presentation binding before invoking the selected action. Presentation dismissal therefore hides only the presentation, preserving the one ticket for the immediate chosen action. Explicit keep/discard, next request or lifecycle/draft invalidation retires it.

## Verification

Focused checks verify exact two composer hunks and entire old-file restoration, boundaries, labels, source identity and all prior sealed patch hashes. The exact Mini handlers execute locally in Node without networking. Five Swift files pass supplementary Tree-sitter parsing. Ten Core and twelve App unit tests are authored, not compiled or run because Swift/Xcode are absent. No Apple UI, backend or network action is claimed. Forward apply and actual reverse compare every permitted file hash.

Root integrates the registration/localization fragments. Native target compilation and clean/dirty/revert/keep/discard/drag-close/background/repeated-click flows remain Apple acceptance requirements. Canceled P043 and prior1–26 are untouched.
