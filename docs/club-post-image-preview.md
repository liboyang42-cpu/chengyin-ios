# P045 club post image preview

## Scope and source

This independent slice implements `onPreviewImage` from the club detail page. The prior native post tile rendered `AsyncImage` values but offered no image-preview action.

- Native base: `51d3e24de92427a777f8690f847cec39971b041a`.
- Overall product document: P045, `onPreviewImage`.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- `chengyinhub-xcx/pages/club/detail/index.js`, lines 2458–2464: pass the tapped picture index and the same `picList` to the native image viewer.
- `chengyinhub-xcx/pages/club/detail/index.wxml`, line 148: post-card `preview` event binding.
- Read compatibility necessary for this action: detail JS line 416 accepts both comma and semicolon image separators; line 1637 joins uploaded image references with commas. Native reads now accept both separators while the existing write contract is unchanged.

Calendar and member-report patches remain independent, sealed siblings; neither is required to apply this patch.

## Behavior

A loaded post image is a real preview button. The selected decoded image opens immediately at its exact index; the viewer reads other pictures through the same existing `AsyncImage` path. No disabled replacement reader, new transport, arbitrary URL field, new origin, upload, save or share function was introduced.

A large native sheet preserves the underlying post list and its page, with explicit compact-size sheet adaptation. It provides paging/swiping, previous/next buttons, a position label, close/dismiss, bounded pinch and pan, double-tap zoom/reset, a reset control and VoiceOver zoom actions. Large-text paging controls stack vertically. Loading, failed image reads and retry are visible.

The selection is tied to the exact account/guest epoch, club, post, post version, image order and read scope. Every read/refresh invalidates the scope before clearing the old snapshot. Old rendered callbacks cannot capture fresh authority after a refresh. Preview content checks the live session and current accepted post; changing account, post or read scope retires the selection. Closing restores accessibility focus to the tapped thumbnail when it is still current.

The new viewer retains the existing URL-loading semantics. It does not claim a new approved-origin or authenticated media contract. Relative/unloadable references still require valid source data and show a read failure; this patch does not invent a host or rewrite media locations.

## Focused checks

Executed on the current computer:

- 15 focused source/static checks passed.
- Four exact Mini action cases passed with `wx.previewImage` stubbed. This checks the source oracle and performs no remote image request.
- Supplementary pinned Tree-sitter parse: five Swift files, zero recovery diagnostics.
- Patch whitespace and before-to-after application/hash checks passed.

Authored: nine Core cases for comma/semicolon read compatibility, exact index/order, invalid selection, paging/reopening, post/club/account/epoch/read-scope retirement, guest context, duplicate source positions, and bounded/resettable/nonfinite-safe zoom.

NOT RUN: Swift compilation/typechecking, the nine Swift tests, iOS/VoiceOver/gesture/UI execution or real backend image acceptance. The current computer has no Swift or Xcode toolchain. Static and source checks are not native runtime acceptance.

## Integration

Register the new sources and merge the localization fragment using the existing integration process; the exact list is in `club-post-image-preview-registration.fragment.json`. No PBX, aggregate catalog, CI workflow, fixture host, governance view, public-profile view or earlier sealed patch was modified.
