# Saved roam card: explicit Photos save (P128 / PA04)

## Bounded increment

P128 includes `saveShareCard` and retrying a failed album save. The native history share sheet already rendered a card and offered the system share sheet, including its platform Save Image action. It lacked the dedicated save action and in-screen permission/error/retry states. This increment adds those states to the ordinary history → record → share entry. It does not add public share snapshots, tokens, feeds or messaging.

After preparing a card, Save to Photos requests only add-only photo permission. Denial offers an explicit Settings button and retry; a device restriction, missing build configuration, and write failure have separate messages. Retry reuses the prepared image. Success is reported only from a successful PhotoKit completion, and the same prepared card cannot be saved again by repeated taps. No photo-library asset is fetched. PNG bytes come from the existing renderer, without attaching the original GPS points or metadata. Photos may sync according to the user's device/iCloud settings.

Preview, system sharing and direct saving use the same prepared card. Optional route inclusion still defaults off, retains the existing 10%-per-end geometric clipping, omits original POIs and fails closed for degenerate/unrepresentable routes. This does not change or strengthen the prior claim: clipping reduces disclosure, but is not anonymization.

## Ownership and interrupted work

Rendering and saving check the presentation reader's exact identity and configuration. Saving rereads the existing local history to compare the complete record, not only its timestamp, including after an asynchronous permission result. The prepared image is gated by record, route choice and owner before its actions are shown. Record, account, route-choice changes and dismissal invalidate the image and cancel the local task. Late callbacks cannot report a different card as saved. One outstanding permission/write flight blocks further saves even after invalidation.

A PhotoKit transaction already submitted to the OS cannot be undone by closing this sheet. Closing cancels work that has not yet been submitted and suppresses stale completion UI; it does not promise to delete a photo the user already requested. No automatic retry or automatic Settings launch occurs.

## Integration

`docs/roam-share-photo-save-registration.json` lists the new app/test sources, the Localizable fragment and the add-only permission text for the existing InfoPlist catalog. The default usage description is included in `Config/Info.plist`. The central project, catalogs and CI are deliberately not edited here. This candidate therefore needs central registration and catalog merging before a complete app build or localized UI can be claimed.

Apple references: [add-only authorization](https://developer.apple.com/documentation/photos/phaccesslevel/addonly), [photo-library authorization and changes](https://developer.apple.com/documentation/photos/phphotolibrary), [add-only usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription).

## Verification boundaries

Focused Python source checks and the Tree-sitter parse are supplementary static checks. They do not run PhotoKit, typecheck Swift or prove an app flow. The new Core state tests and app-hosted writer/model tests are authored for Apple execution. Xcode, Swift/XCTest, simulator/device, permission alerts, visual/VoiceOver and CN/US runtime checks remain NOT_RUN in this environment.

After registration, run `swift test --filter RoamSharePhotoSaveStateTests`, the app-hosted `RoamSharePhotoSaveModelTests`, an unsigned CN/US build, and the following UI cases: route off/on matching card; permission allowed/denied/restricted; returning from Settings and explicit retry; failed write/retry; rapid taps; close before permission resolves; account/record change while permission is pending; close after submission; reopen; Dynamic Type and VoiceOver in English/Chinese. Verify full history replay and storage remain unchanged. Existing frozen-source admission gates are owned by central integration, not rewritten by this feature.
