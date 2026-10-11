# P107 nickname and introduction field editing

This slice adds independently cancellable local editors for the two profile text fields. The ordinary entry remains Account → Edit profile → Nickname / Introduction.

## Confirmed gap and source mapping

The required preimage is `ProfileEditView.swift` after the previously completed page-exit safety slice (SHA-256 `40905088b434a38286e3059a8e4d8f66c8d82c3257a3c86b836ab3806214fa59`), on Git base `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`. That preimage directly bound both visible inputs to the whole-page draft; it had no independent scratch or cancel boundary.

P107 in MASTER v10 identifies the profile editing page. Verified Mini source mapping:

- Nickname: openPop4/cancel4/confirm4
- Introduction: openPop/cancel/confirm
- openPop2/cancel2/confirm2 changes case pictures and their description. It is not the introduction flow and is outside this slice.

The source reference is `f859cd6e2618f618a53f5cd33949259828e86313`, blob `503d31aae4cecc9197a0987926711f8aed51e491`, source SHA-256 `186909962dd0fe0ca30544aef90444183805c803bebd9e9f267ff2f5df79cb6a`. Only behavioral evidence and source identity are included, not the private Mini source.

## Behavior

1. Opening a field starts fresh scratch from the exact current page draft. Whitespace, Unicode representation and multiline introduction bytes are preserved.
2. Typing changes only the sheet's scratch. Cancel or swipe dismissal discards this scratch and leaves all page fields intact. Reopen starts from the current staged page value.
3. Done consumes one current edit and copies exactly that field to the page draft. Other text, route preferences, staged avatar receipt and preview remain unchanged.
4. No per-field network save or read occurs. Whole-page review, normalization, validation, save and verification remain the existing operation. Empty nickname may be staged, but the existing valid-name requirement still blocks saving. Empty introduction remains allowed.
5. Field actions are bound to a unique presentation, account/epoch, viewer revision, model generation, draft revision, exact complete draft and exact preservation snapshot. Repeated or stale confirm/cancel cannot affect a successor. A changed draft, model reset or changed session retires the old edit. A field editor cannot bypass a pending unknown-write lock.
6. Ordinary focus changes, keyboard activity and background/foreground transitions retain scratch. Identity changes do not. Competing page exit, reload, prepare/save and avatar selection are blocked while the field editor is open. Existing `exitCommitted` terminal lifetime and unknown-save behavior are retained.

## Integration and acceptance

Registration and localization: PENDING_PARENT_INTEGRATION. See `profile-text-field-edit-registration.fragment.json` and `Resources/ProfileTextFieldEditLocalizations.fragment.json`. Central PBX, central catalog, coordinator, transport, production capabilities and CI were not modified.

Focused Python checks cover local-only state, exact-byte guards, scoped cancellation, single-use confirmation, lifecycle fences, unchanged page exit, bilingual strings and test wiring. Original Mini source execution uses synthetic local page state and zero production requests. These are source/behavior-evidence checks, not native execution.

Apple: NOT_RUN. The current Linux environment has neither Swift nor Xcode. The newly authored app-unit tests and four new UI scenarios have not been compiled or executed. Large text, VoiceOver, English/Chinese native rendering, sheet swipe behavior and interruption behavior require Apple execution after registration.

The existing UI flow test file has only the text-edit entry interactions and assertions migrated to the new sheets, plus four new cases. Existing refresh/save fixture behavior and older failure expectations are not repaired or claimed passing by this slice. No full-suite or CI claim is made.

Suggested native checks after integration:

- `ProfileTextFieldEditTests` (local state, stale scope, exact bytes, avatar/preferences preservation, saved/unknown/terminal-exit boundaries)
- `ProfileEditFlowTests.testNicknameCancelReopenAndApply`
- `ProfileEditFlowTests.testIntroductionCancelDoesNotRevertPreviouslyStagedNickname`
- `ProfileEditFlowTests.testSwipeDismissDiscardsOnlyLocalFieldScratch`
- `ProfileEditFlowTests.testBackgroundKeepsFieldScratchUntilExplicitCancel`
- Existing `ProfileExitDiscardTests` and `ProfileReloadDiscardTests` for affected model boundaries
