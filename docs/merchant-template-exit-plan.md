# Merchant template: session-local offline and exit plan

This independent W05.2 increment follows the participation-plan batch. It adds two manually authored fields inside the existing merchant template editor: an alternative when the network is unavailable, and steps for stopping/leaving if the activity fails or the participant chooses to exit.

## Behavior

- The merchant explicitly adds the group. Both fields start empty and must be nonblank before local review. Each field is bounded to 600 UTF-16 units; overlong text is rejected without truncation.
- The group can be used without a participation plan. Adding either group makes the entire template local-only. Removing one group does not re-enable submission while the other remains.
- Existing coordinator editing, dirty-state navigation, immutable review, review cancellation, edit invalidation, discard/reload and account-scope fences are reused.
- The review renders the exact frozen instructions as plain text. It states that these are unapproved planning notes, with no claim of approved safe/accessible routes, order cancellation, refunds or rewards.
- The form explicitly says the fields live only in this editing session: leaving, reloading or discarding removes them. This is not persistent local storage.

## Contract boundary

The MASTER W05.2 requires offline alternatives and failure exit alongside the other merchant operating/safety fields. This implements their bounded local authoring/review slice only. It does not enable offline gameplay, switch runtime branches, validate a real escape route, publish a game or establish end-to-end W05.2 completion.

The prior batch's exact `f859cd6e2618f618a53f5cd33949259828e86313` Mini evidence establishes merchant citynode authoring through the existing template-submit route. That evidence does not provide a verified mapping for these two new operational instructions. No backend key, route, decoder or write grant is invented. The fields remain outside AI suggestion allowlists, server decoding and wire payloads. `localOnlyReview` includes both local groups; confirmation and request-preview guards prevent any submission with either group, rather than silently dropping fields.

## Integration

Depends on participation-plan candidate `c80fcab1d70996e172ed9ff6c8452a7b9cb8f98d` (which descends directly from true iOS base `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`). The patch for this increment contains only the exit-plan delta.

Merge `Resources/MerchantTemplateExitPlanLocalizations.fragment.json` through the integration line: 11 English/Simplified-Chinese entries. Runtime changes use already registered files. Register `Tests/CoreTests/MerchantTemplateExitPlanTests.swift` (7 tests) and `Tests/AppUITests/MerchantTemplateExitPlanFlowTests.swift` (2 tests) through the central test/project process. No central PBX/catalog/CI file is changed.

## Verification

Supplementary Python checks cover field limits, absent server/AI mapping, independent-group request guards, mounted editor/frozen review, translations and authored regression coverage. Swift tests cover blank/overlong input, UTF-16 boundaries, no invented server facts, old payload preservation, independent groups, AI non-overwrite, immutable review, cancel/edit/discard/reload/session behavior and zero dispatch. UI cases exercise incomplete/remove and complete/review/cancel flows on the synthetic merchant fixture.

When Swift/Xcode is absent, authored XCTest/UI tests, Apple compilation, actual rendering, VoiceOver and Dynamic Type remain NOT_RUN. Tree-sitter parsing and Python source checks do not replace those gates. No real merchant/backend/provider/payment/reward operation is tested or performed.
