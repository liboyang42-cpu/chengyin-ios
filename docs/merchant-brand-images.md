# Merchant saved brand-image viewer

## Baseline and precise dependency

Actual upstream: `41571fed5c27d4766d0bebb02e2800d798f1edbd`.
Exact before-image: batch10 `d6e64a0741cf5414ee14e1dc6c6973bbaa78f409` (415 plus store-industry increment).
The four shared files are App/MerchantOperationsEditor.swift and Core/MerchantOperationsService.swift, MerchantOperationsReading.swift, MerchantOperationsSyntheticFixtures.swift. They include batch10; this patch adds independent hunks. It does not include template6–9. Integrate incrementally into the combined tree; never replace newer files with these standalone after-images. All ten prior archives remain immutable.

## Actual requirement and read contract

MASTER v10 merchant responsibilities225–226 and W05 shop facts399–427 place brand-center facts with the merchant. The concrete existing interaction is Mini `chengyinhub-xcx/pages/merchant/decor/index.js:336,728–730` at `f1fe895f34c3664783aafd6145cf93e0de15878d`, SHA `36f0d912f63369d8d110b56757387c66ae81d307`: split persisted `derivatives` CSV into URL candidates, then preview the ordered brand images. Native profile has a merchandise text editor but no saved-brand-image viewer.

`ApiMerchantController.coopProfile:547–557`, SHA `ac739a411d2de90de83bebecf482508e1d363a2a`, POST `/api/merchant/coop-profile`, requires COOP_MANAGE, resolves the authorized merchant and returns `MerchantEditProfileVO`. The VO SHA `6af0245032951e75c5ab7bb4388301c01050061b` includes `derivatives` but explicitly excludes `businessLicense`. This increment therefore only views brand pictures. It does not expose licenses, switch to an onboarding endpoint, or broaden permissions. No persistence model or write whitelist is modified.

The new read makes fresh access/me, retains the profile entry's existing PROFILE_WRITE requirement and checks the endpoint's existing COOP_MANAGE requirement. It validates the returned merchant ID both in transport and the viewer lease. No write approval is added or consumed.

## Complete viewing flow

Open Profile → View saved brand images. A separate source read retrieves the current persisted CSV. Unsaved edits in the profile are untouched and never substituted as the image source. Loading, failed read with retry, empty source, unsupported reference, failed image with retry and ended session are separate states.

Candidate order and duplicate image positions are preserved. Text-only merchandise descriptions are not images. Null/missing derivatives means no images; wrong outer data types fail. The source Mini also recognizes HTTP and relative references; native keeps those candidates visibly unavailable because there is no confirmed relative-image base or permitted insecure transport. Only absolute credential-free HTTPS without control characters is rendered. The viewer neither repairs nor deletes the source. No original URL is displayed, copied, shared or downloaded.

Choose an image, pan/zoom1–5, reset zoom, move to previous/next supported image, return to the source list, retry a failed image, or reload the saved collection. Unsupported candidates keep their original list position; navigation skips them. Only the selected image mounts AsyncImage; adjacent images are not prefetched. DEBUG synthetic mode renders local SF Symbols instead and never requests its example URLs.

A viewer lease belongs to the current document identity, unchanged draft, reader scope and current authenticated owner. Changing draft, opening review, reload, close/back out of the sheet, backgrounding, session change or retiring the owner prevents stale images/callbacks from reappearing. Source request generations and image generations fence late results. No durable local save is claimed. Viewing doesn't assert material verification or approval.

## Verification / integration

New runtime registration: `Core/MerchantBrandImages.swift`, `App/MerchantBrandImagesView.swift`.
New Core/UI tests and 17 English/Simplified Chinese localization entries are supplied in the integration fragment; central PBX/catalog/CI remains untouched.

PASS: 27 focused source checks (11 new, 12 industry, 4 store-hours), 8 Swift files parsed with pinned Tree-sitter, whitespace and reverse-patch checks, exact dependency before-images, and unchanged prior ten archives. These checks are supplementary only. Authored 18 Core XCTest methods and 3 UI flows are NOT RUN. The selected dot environment has no `swift` or `xcodebuild`: no compiler/typecheck, XCTest, Xcode, simulator screenshots, VoiceOver/Dynamic Type runtime, real backend/media read or production write acceptance was executed. Synthetic UI tests use no external image service. No real payment, reward or upload was attempted.
