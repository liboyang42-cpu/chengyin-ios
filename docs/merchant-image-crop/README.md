# Merchant logo, cover and gallery crop (offline implementation)

## Source and bounded scope

Mini source commit `11be8cb2f09073496f3a7d5130d558da60cf5439`:

- [`chengyinhub-xcx/pages/merchant/decor/index.js`](https://github.com/liboyang42-cpu/chengyin/blob/11be8cb2f09073496f3a7d5130d558da60cf5439/chengyinhub-xcx/pages/merchant/decor/index.js), Git blob `36f0d912f63369d8d110b56757387c66ae81d307`, lines 622–647: independent image draft; `chooseEditImage` selects logo 1:1 and cover 5:3 before the separate save.
- [`chengyinhub-xcx/app.js`](https://github.com/liboyang42-cpu/chengyin/blob/11be8cb2f09073496f3a7d5130d558da60cf5439/chengyinhub-xcx/app.js), Git blob `b62184a6198a068502225becd3e63a6c05020612`, lines 470–560: page-bound crop step before upload, cancellation aborts the selection.

All source captures were checked against their exact Git blob IDs. The gallery successor adds only **gallery 16:9** to the existing crop infrastructure, on reviewed tree `d1f6ea0294893eedf7cfa989b6ea334c8d9548aa`. Other destinations remain unchanged; this is not full merchant-media parity. The native base is reviewed tree `b9d20e9bef289ce213948777bd88ed7ad7443581`, which builds on published tree `8dc1403117e860c427b653471e322ca055995d0c` (published commit reported as `5fe1c93aa1fed514eb8fade532693cd22775e73d`). This local unit is not evidence of publication.

## Behavior

The existing selected-item-only picker normalizes all EXIF orientations using ImageIO's thumbnail transform, bounds decode dimensions to 4096, strips metadata, and returns an upright JPEG. The new crop stage accepts only this bounded representation. Integer crop geometry enforces exact 1:1, 5:3 or 16:9 output within source bounds, without upscaling. Accessible horizontal/vertical position and 1–4× zoom sliders let the user select composition; a local cropped preview is shown before confirmation.

Confirming a crop only creates the existing scoped upload review. Upload confirmation and applying the uploaded result to the merchant draft remain separate actions. The crop stage does not send any bytes, save a merchant record, or grant permission. Native picker, uploader, and allowed production origins remain disabled/empty in the normal factory.

Replacement discards the prior local logo/cover/gallery crop/review. Cancel drops the crop bytes. A crop UUID rejects old confirmation callbacks. Current account, document/access/draft scope and existing unresolved-upload locks remain authoritative. Leaving, backgrounding, or observed scope invalidation clears local crop and picker work; unresolved uploads keep the original fail-closed lock. Noncrop destinations retain their previous selection/review behavior.

## Verification and limits

- Six pure Swift geometry tests and twelve app-hosted synthetic tests are authored. Coverage includes all three ratios, portrait/landscape/edge crops, invalid/nonfinite geometry, tiny source sizes, all eight EXIF orientation dimensions, metadata removal, different pan pixels, separate upload review, cancellation/leave, replacement UUIDs, stale scope, noncrop review preservation, and unresolved-upload locks.
- Eight Python source contracts guard routing, dimensions, separate review, orientation boundary, default-off grants, localized controls, and project wiring.
- Local Python tooling/source checks and supplementary Tree-sitter parsing are separate from Apple execution.
- **UNRUN:** Swift compiler/typechecking, XCTest, UIKit pixel execution, SwiftUI UI tests, simulator/device, VoiceOver, Dynamic Type, dark mode, and live backend/upload acceptance. No actual user photo or network upload was used. The synthetic transport rejects in memory.
- Apple validation must run the `QuestifyAppUnitTests` scheme, pure `swift test`, unsigned simulator/device builds and UI acceptance before claiming native runtime readiness. This unit does not authorize production activation.

## Gallery source binding and preserved boundaries

At private mini commit `11be8cb2f09073496f3a7d5130d558da60cf5439`:

- `chengyinhub-xcx/pages/merchant/decor/gallery/index.wxml`, Git blob `7191986534121293c7ea8b2e23f3a855326a4aac`: the active add control binds `addGallery`, within the ready-state gallery, and profile-write access remains required.
- `chengyinhub-xcx/pages/merchant/decor/gallery/index.js`, Git blob `af618b6445e0df2bdc1b801fbe49d99119e7812f`: `addGallery` passes remaining capacity and `cropScale: '16:9'` into `app.chooseImage`; successful results append in order and are capped at nine. Removal and the separate save remain source-owned actions.
- The exact `app.js` blob above consumes `options.cropScale` and sends the ratio to the crop page before upload. This verifies an active binding, rather than inferring a ratio from thumbnails or comments alone.

The native successor reuses the selected-item picker, renderer, geometry, crop review, upload review, and lifecycle fences. Gallery-specific authored synthetic cases cover ratio output, wrong aspect, stale replacement IDs, cancel/leave, access-revision change, unknown-upload locks, and fake picker cancellation. All orientation cases now include gallery. Noncrop cancellation tests use avatar, preserving their original noncrop purpose.

Existing gallery order, append-only consumption, nine-item limit, duplicate rejection, deletion, owner/role scope, storefront pending locks and production gates are byte-unchanged. The existing native picker still selects one image at a time; mini batch selection/whole-batch cancellation is not implemented or claimed by this ratio-only successor. No actual picker, upload, permissions, production origins, or new grants are enabled.


## Gallery batch successor

The document-owned batch successor replaces the single-image limitation above for the merchant gallery only. The selected-item PhotosUI bridge accepts the exact remaining capacity (nine minus current gallery size), uses ordered selection, and sanitizes providers serially. Retained sanitized bytes are limited to 24 MiB total, in addition to the existing 20 MiB input, eight MiB output and dimension limits. Other destinations still select one image.

Every queued image has separate 16:9 crop, transmission review and explicit local Use actions. No upload follows crop confirmation automatically. A document-owned ephemeral queue outlives individual draft revision views. After Use, only exact item/proof and before/after draft equality, an unchanged access fence and a successful durable locallyApplied transition permit requesting a fresh context. The old upload context stays retained until that result returns, including when append synchronously invalidates the cache. Existing journal schema, upload transport and default-off capabilities are unchanged.

Skip/replace applies only to an untransmitted current image. Cancel stops the remainder; earlier consumed images remain in the local unsaved gallery draft. Cancellation after acknowledgement does not delete the upload. Account/role/session changes, other document edits, review/save preparation, refresh, leave and background release untransmitted selections. Unknown upload or any journal failure stops the entire batch and retains the existing target lock, without retry, deletion or a fabricated reconciliation route. This explicit partial-local-success behavior adapts the mini's all-crop-before-upload lifecycle to native review authority; it is not transactional rollback parity.

Source proof remains private ref 11be8cb2f09073496f3a7d5130d558da60cf5439, gallery blob af618b6445e0df2bdc1b801fbe49d99119e7812f and app blob b62184a6198a068502225becd3e63a6c05020612, independently re-fetched for this successor. No raw private source is copied. Synthetic batch lifecycle, picker-configuration and budget tests are authored. Apple compilation, PhotosUI provider/runtime, XCTest, accessibility, device and actual backend execution remain unrun locally; Python source checks and syntax parsing do not establish those outcomes.
