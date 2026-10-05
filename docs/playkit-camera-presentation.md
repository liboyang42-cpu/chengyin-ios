# PlayKit camera presentation (v4)

## Implemented

- A typed optional `PlayKitPhotoFrame` reaches `PlayDeviceCaptureCoordinator` and its configured native provider. The native camera displays the outline at the source opacity (0–100%, default 40%) without baking it into the captured photo. Loading failure hides only the guide, leaving the shutter usable
- Source-backed fallback through the system photo picker selects one image without requesting broad photo-library access. Actual selected bytes enter the same capture → explicit upload → task review pipeline. Unsupported library requests never silently open the camera instead
- After the server says `scanned`, a reviewed camera presentation can display the returned overlay at the source width ratio (20–100%, default 60%). It is labeled screen-space overlay. It does not claim spatial AR, save/record media, submit another code or complete a task
- Static returned-image display remains available when the camera is unavailable, denied or interrupted
- Late camera/library callbacks are bound to the exact native operation generation. Account/version checks in the existing coordinator and evidence UI still apply
- First-use permission acquisition is separated from gameplay measurement. Temporary OS-permission inactivity no longer destroys the sensor child or cancels its own camera grant; background/session changes still cancel. Sensor/timing children retain their own interruption rules
- System capture cancellation is treated as cancellation, not an unknown server write outcome

## Safety and activation

Hardware grants, media hosts, backend capabilities and factories remain unchanged/off. Frame/overlay URLs require exact approved HTTPS hosts; credential-bearing URLs and nonstandard ports are rejected. QR acceptance precedes visualization. Framing is only an aid, never evidence by itself. Camera and photo-picker controls open only after explicit user actions; uploads still require separate review.

The photo guide uses the source image without modifying submitted pixels. The overlay camera has no shutter or upload callback. Camera capability and its installed purpose declaration must be present before a preview opens.

## Source evidence

Mini-program snapshot `fad4d6bd7e3c3e501441fe19c8de9a9cd78230fc`:

- `pages/play/components/playkit-photocheck/index.js` 98–188: frame viewfinder, image failure, ordinary camera/album fallback, original capture handoff
- `pages/play/components/playkit-photocheck/index.wxml` 40–51: aspect-fit guide opacity and independent shutter/cancel controls
- `pages/play/utils/playkit-view.js` 302–305: frame opacity clamp
- `pages/play/components/playkit-scan/index.js` 39–42: overlay width clamp; `index.wxml` 56–133: camera overlay and static fallback, distinct AR surface

No private implementation or secrets are included. This is newly written native presentation with derived source contracts.

## Still distinct

The v5 increment adds native image-only plane/marker AR rendering; it is distinct from this 2D camera overlay. GLB rendering still requires an accepted decoder/asset policy. Marker physical size is absent from the wire configuration, and GLB decoder/model compatibility needs an accepted native policy. The source-approved static result remains usable while these are unresolved. Other creator panels remain separate implementation work. The mini-program retired gameTimer/stickerBook orphan families; their stale Flutter files are not active runtime gaps.

Apple compilation, XCTest execution, screenshots, actual camera/library permissions, device behavior, accessibility and live backend acceptance are NOT_RUN for this packet in the Linux workspace. Python source checks are not a camera test.
