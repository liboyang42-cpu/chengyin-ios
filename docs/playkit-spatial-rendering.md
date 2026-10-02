# PlayKit native spatial image rendering (v5)

## Implemented

- Real ARKit horizontal-plane detection and an actual existing-plane raycast before image-card placement
- Actual configured image-anchor detection for marker mode, with one-time copy into independent world space. Losing the marker does not remove or drag the card
- Source plane width of 0.4 m, source image aspect ratio, upright camera-facing cards and restrained drop/grow effects. Reduce Motion skips or ends decorative motion
- Explicit camera-purpose review, default-empty per-mode approval and approved media hosts, device support checks, permission denial, 20-second tracking timeout and manual image fallback
- Bounded ephemeral image loading: no account headers, cookie/credential storage or persistent cache; approved redirects only, 10 MB streaming limit, pixel limit and orientation-correct bounded textures
- Cancellation on session/version changes, backgrounding, dismissal and AR interruption. Tracking and visualization never call a task/arrival/reward action

The regular image and v4 screen-space camera overlay remain distinct fallback paths. No preview or plane/image-anchor detection is treated as proof that the QR task succeeded. Server `scanned` must already be true.

## External facts remain gated

`PlayKitSpatialApproval()` grants no modes or origins. Marker requests additionally require an accepted physical width keyed to the exact reference-image URL. The current source wire fields do not provide that measurement, so native code does not assume a meter or add an invented backend field.

Configured 3D `modelUrl` assets are rejected into the image/camera fallback until a GLB decoder and asset-compatibility policy are approved. The image-only renderer does not silently pretend to render a model.

## Evidence

Mini-program snapshot `fad4d6bd7e3c3e501441fe19c8de9a9cd78230fc`:

- `pages/play/components/playkit-scan/ar/index.js`: plane placement, source card dimensions, one-time marker world-lock, image/model distinction and animation semantics
- `pages/play/components/playkit-scan/ar/ar-math.js`: card aspect ratio and physical placement presentation
- `pages/play/components/playkit-scan/ar-gate.js`: accepted scan and configured-mode gates; AR failure returns to the existing image/camera path

Apple's [reference-image initializer](https://developer.apple.com/documentation/arkit/arreferenceimage/init%28cgimage%3Aorientation%3Aphysicalwidth%3A%29) requires physical width. Native plane placement uses the [ARKit raycast-query contract](https://developer.apple.com/documentation/arkit/arraycastquery/init%28origin%3Adirection%3Aallowing%3Aalignment%3A%29). These API references do not substitute for a tested calibration or device run.

## Verification limits

Twelve new pure-Core tests are authored for grant/scan/asset/calibration gates, aspect ratio, real-placement prerequisites and one-time marker lock. Python checks inspect source contracts only. Apple compilation, XCTest, actual tracking/permissions, screenshots, visual/accessibility and live backend acceptance are NOT_RUN in the current Linux workspace. See `playkit-spatial-verification.json` for exact counts.
