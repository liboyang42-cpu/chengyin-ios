# Merchant business fixture ownership

## Observed failure and scope

CI138 [UI44](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/37792301124/job/113373676578), commit `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865`, ran ten `MerchantBusinessFlowTests` methods: six failed, four passed. Four failures have accessibility dumps showing the existing stale-route message immediately after the Home entry was opened:

- `testAftercareSeparatesOpinionFromRefund`
- `testCRMCustomerAndTimelineAreReachable`
- `testLocalNoteReviewCanBeCancelledWithoutSuccess`
- `testProductionDisabledPreviewHasNoDispatchButton`

The Chinese aftercare search and scan classification methods fail at their first input control. They traverse the same guard and are consistent with the ownership defect, but their individual cause is not proven. Their failures have no retained accessibility hierarchy or screenshots. The actual exported UI44 artifact contains no screenshots and an empty accessibility-record packet; no other shard's images were substituted.

The DEBUG fixture previously recreated its reader and journal in the View initializer. A parent reconstruction could replace those dependencies while a previously constructed `MerchantBusinessHomeRoute` correctly retained and required the original objects. The scope, authorization-generation default and configured state in these scenarios were constant. Replacing the fixture dependencies was the source-supported explanation for the four observed stale guards.

## Repair boundary

`MerchantBusinessFixtureHostView` now retains one reference-type `MerchantBusinessFixtureOwner` in SwiftUI `@State`. Each mounted host owns its original synthetic reader and in-memory intent journal. The owner contains no access model, shared singleton, network transport, persistence or new dispatch path. Existing scenario selection and sign-out/navigation-reset behavior remain intact.

`MerchantBusinessHomeView` still owns its access model with `@StateObject`. Its route admission, scope/account/epoch, reader identity, journal identity, authorization-generation and configuration guards are unchanged. Core production authorization, dispatch and unknown-intent handling are unchanged. Review pagination in `MerchantBusinessViews.swift` is untouched.

The optional observer defaults to nil. Its DEBUG-only zero-size `UIViewRepresentable` is accessibility-hidden and cannot receive hit tests. It only reports the retained owner and parent render revision. It does not drive navigation, alter scope, dispatch a mutation, schedule work or add any UI-test control.

## Regression coverage and evidence limits

Five new hosted AppUnit methods reuse the existing `HostedNavigationSceneWindow` foreground-scene lifecycle helper, construct real `UIHostingController` parents and wait for a render-event expectation, with the existing two-second hosted-test bound and no polling or sleep:

1. Two actual parent redraws retain the owner, reader, journal and current preexisting routes. A reserved synthetic unknown intent remains present and continues to reject duplicate reservation.
2. Two independently mounted hosts have different owners/readers/journals. The second window is created after the first is key, and separate defers retire them in reverse order to restore the key-window chain. Reserving or completing the same synthetic intent in one cannot clear the other's intent; signing out one cannot alter the other's scope or current routes.
3. Sign-out rejects old routes while retaining the unknown intent.
4. A new account rejects old routes without rebinding their dependencies.
5. A new epoch rejects old routes without rebinding their dependencies.

These tests exercise the actual mounted fixture's dependency lifetime and the unchanged real route guard; they do not tap through an XCUITest navigation flow. The advisory Python checks verify source boundaries and authored coverage. Python results are not Swift compiler or simulator evidence.

The ten existing UI methods remain unchanged, SHA-256 `6f7abf0f8348ef9c53137270d0fdb3150a5e1cefb625710a218aa4b5c4aa305c`. No UI wait, retry, timeout, cost profile, measured flag, method inventory or historical source assertion is changed. No new UI source projection is introduced. Historical verification JSON files remain historical records, not rewritten evidence for the repaired source.

Apple stages are **NOT_RUN** in this Linux workspace: Swift compilation, hosted XCTest and all ten unchanged UI44 methods require the final integrated project on the Apple runner. Root integration must register the new AppUnit source through the deterministic project generator and inspect the resulting target-only registration. The remaining two ambiguous failures must be re-evaluated from that run; this repair does not claim they are already fixed.
