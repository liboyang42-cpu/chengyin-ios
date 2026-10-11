# Device-only personal cover

## Delivered behavior and limits

My and the same account's own Public profile now show a device-only cover. Customize opens an editor. The existing selected-item-only native image picker supplies one bounded, sanitized JPEG. The user adjusts a 16:9 crop, previews the result, then explicitly saves on this device. Choosing, cropping, previewing or cancelling does not persist anything. Restore default creates a separate explicit review; cancelling it keeps the saved image, confirming removes only this app's derived local cover file. Closing, account changes and backgrounding cancel an unfinished selection/review. Reopening reads the saved cover.

The interface explicitly says the image is for this account on this device, is not uploaded, not displayed to other people, and not synced. No actual user photos were accessed and no permission prompts were operated during implementation or local checks. The reused picker is only presented following the user's in-app Choose action; no photo-library-wide request or camera capability is added.

This is the independently authorized native local appearance chain, not completion of Mini's uploaded-image implementation or cross-device parity. No profile update, avatar upload approval, merchant grant, URL reader, upload service, server field, API endpoint or AppSession change is involved.

## Actual Mini source

The sole master is MASTER-v10-extracted-text.txt, P004 and P108. Approved Mini ref `f859cd6e2618f618a53f5cd33949259828e86313`, `subpackageMember/components/cy/profile/index.js`, blob `99008cdb5c877c851f87f68fecac09f27c9eb46e`:

- `onChangeHeroBg` (1538–1548) closes the menu, selects one image with crop scale 16:9, stores the returned URL in `member_hero_bg`, updates `heroImg`.
- `loadBanner` (806–819) consumes that local value only for self; otherwise falls back to the existing common banner read.
- `app.js` `chooseImage` (508–583) actually calls authenticated `getUploadClient().uploadAll` before returning URLs; the derived upload business type for this crop is `image_16_9`.

That source is not a purely local image pipeline. The unresolved native dependency is a separately scoped personal-cover uploader plus approved upload/origin/receipt/read integration corresponding to that exact Mini path. This package neither borrows avatar authority nor enables it. Its persisted value is sanitized JPEG bytes, never a Mini URL or a fabricated server receipt.

## Isolation and persistence

The durable owner combines account ID with the existing RegionalSessionStorageScope namespace. My reconstructs that namespace from the existing validated regional configuration and matching build endpoint/market/bundle/realm. Missing or mismatched configuration produces no owner. No guest/global owner fallback exists. The namespace plus account is length-framed then SHA-256 hashed into a filename.

The live context additionally includes reader instance, complete viewer identity and presentation revision. Other public profiles do not receive a local owner. Rendering checks self ownership; stale picker, crop and confirmation tokens cannot save. Account switching never displays the other account's cover. Durable keys intentionally exclude login epoch so the same account can read its cover on a later login, while pending actions still expire across epoch/role/revision changes.

App-owned Application Support files are bounded binary property lists, atomically written with complete file protection on iOS. The directory is excluded from backup. Decoding checks envelope version, full owner, byte bounds, regular/non-symlink file, JPEG bounds and exact ratio; the view validates decoded pixel dimensions before rendering. The existing selected-image sanitizer and crop renderer redraw pixels rather than copying source metadata. No file path or photo-library asset reference is persisted.

Save compares the current stored image to the reviewed baseline, writes only the current owner's file, then verifies exact bytes/dimensions by readback. A changed file or failed readback cannot produce success; the editor requires a fresh load before another change. Restoring default uses the same reviewed compare/readback path. This is local derived-file removal, not photo-library deletion or server rollback.

## Integration

Base: 94bced23ae734bcd8a5e236c8b992294bd15b14a. Seventh increment afterimages are the only source overlay dependency. The new public-profile cover insertion preserves the seventh author-post section. AccountView is a six-line change from the exact base; merge those lines into any later central revision rather than overwrite other account entries. First six editor packages, central ProfileEditView body split and both fixture API-base repairs are unchanged.

Register the two App files and two Core files, test files, DEBUG synthetic fixture and 18 bilingual keys using the fragment. No central PBX/catalog/router/CI file was edited. The production entry calls the real local store; it is not a default-nil preview or a fixture-only path. The DEBUG fixture injects a locally generated image into the same production preview/confirm/cancel view and never selects user photos.

## Verification

27 new focused source checks plus 22 seventh-seam checks pass. Exact approved Mini methods run with synthetic callbacks in 6 cases. Static mutation checks and forward/reverse patch replay are recorded separately. These are source checks, not Swift execution.

18 Core, 9 app-unit and 5 UI tests are authored, including cancellation, confirmation/readback, default restoration, account/realm separation, stale review/crop, corruption, concurrency conflict and reload. Swift, swiftc and xcodebuild are absent: all 32 tests, Apple compilation, actual OS picker, UI appearance and device persistence are NOT_RUN. No historical CI or compiler failures were investigated.
