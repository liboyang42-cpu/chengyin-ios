# P127: retry supplementary merchant information

## Missing action and implementation

The retained P127 delegated detail component exposes `retryMerchant`: after a failed supplementary merchant read, it rereads the already loaded node's merchant ID. The native place page previously displayed only the merchant-failure message. This slice adds that missing action using the existing `RoamReading.roamMerchantDetail(id:)` contract.

The failure section now has an explicit Retry button and a local progress indicator. The loaded place/node, address, status and other actions remain visible. A successful retry restores the merchant's information, gallery and featured-content section. A failed retry leaves the merchant error and Retry action available. It does not reload the node, navigate away, acquire location, change favorites or run any business write. Authentication failure follows the existing whole-detail unavailable path instead of preserving authenticated content as current.

The request uses the loaded node's positive merchant ID and accepts only a response with that same merchant ID. The existing `ManualMapReadTaskOwner` owns and cancels the read. Repeat taps cannot queue multiple current reads. At tap and completion, the action checks the current reader/account/area authority, exact node, map place and read snapshot. Closing the page, replacing the context or starting a complete detail reload cancels this supplementary read. An old completion cannot clear the loading state or install data for a newer attempt.

## Independent delivery and integration

The base is `51d3e24de92427a777f8690f847cec39971b041a`. The overlapping detail view is based on the prior reviewed coupon-wallet afterimage, so its activity and coupon-wallet destinations are preserved. The prior coupon selection type is an unchanged input dependency. The patch contains only this retry increment and does not modify either earlier delivery bundle. Apply it after the declared prior detail-view input; do not replace the file with the raw base version.

`docs/roam-merchant-detail-retry-registration.json` records the new model and app-hosted test membership. Existing English/Chinese Retry, loading and merchant-failure labels are reused. No central project, app root, catalog or CI file is edited, and no new endpoint or check framework is introduced.

## Verification boundary

Focused source checks and Swift syntax parsing are supplementary evidence. The app-hosted tests cover exact request IDs, success/failure/retry, duplicate taps, cancellation, stale context, mismatched response ID and late old completions. They are authored but NOT_RUN here. Swift/Xcode, CN/US builds, simulator/device UI, VoiceOver and real-backend checks are NOT_RUN because the Apple toolchain is unavailable.

After registering the source and test, execute `RoamMerchantDetailRetryModelTests`, an unsigned app build and the ordinary place-detail flow with a failing then successful merchant reader. Check that the node stays visible, gallery/featured actions return only after success, two taps produce one read, a second failure remains retryable, and closing/changing account, area, node or reader prevents late repaint. Verify both languages and accessibility sizes. Existing frozen-source gates and CI remain central-integration work.
