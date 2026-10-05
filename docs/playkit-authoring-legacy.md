# PlayKit authoring and legacy sections (v3)

This increment builds on the native PlayKit screen packet. Endpoints, login, payments, signing, live grants and the publication owner are unchanged.

## Implemented

### Five creator panels

The existing account-scoped local template editor now offers sort, match, classify, compass and shout alongside the seven Flutter scalar panels. They use the established draft/save/review pipeline; production publishing stays off.

- Sort: 2–8 items, stable unique IDs, accessible reordering, nonempty labels up to 40 UTF-16 units, prompt 1–200 units. Serialization derives `answerOrder` from entered order instead of trusting a stale key
- Match: 2–6 paired rows per side, equal column sizes, stable IDs, explicit repair of asymmetric imported columns. Serialization derives `pairs` from corresponding rows
- Classify: 2–4 bins and 2–10 items; every item requires an explicit valid assignment. Removing a bin clears its assignments and requires the author to choose replacements
- Compass: blank direction stays invalid, not zero/north. Integer bearing 0–359°, tolerance 5–90°, hold 1–10 seconds, hint up to 60 UTF-16 units and integer points 0–1000
- Shout: continuous duration 5–300 seconds and integer points 0–1000. Creator copy explains microphone consent and environmental/social cost

Root `present` is preserved and validated, with explicit default/inline/dedicated choices. Incompatible inline choices fail validation rather than silently changing presentation. Runtime chrome is still native and purpose-specific.

Creator rehearsal renders actual reasoning controls using a projection without secret answer/reward fields and shows the proposed payload without sending it. Sensor rehearsal shows configured boards and purpose while hardware stays off. No preview creates a live session, successful acknowledgment or reward. Owned row/image data and unknown sections are preserved; unsupported enabled sections still block serialization.

### Six active legacy runtime sections

- Blind taste: instructions, source-key options, attempt feedback and retries until server `solved`; exact `SUBMIT_BLIND_TASTE { key }`
- DIY name: suggestions, UTF-16-safe length, public-display/content-review disclosure; exact `SUBMIT_DIY_NAME { name }`
- Slow task: server `started/claimed/daysLeft`, explicit START/CLAIM review, no device-date unlock, voluntary reveal of text returned after claim
- Music corner: source media through the approved audio factory, with no completion or points claim
- Silent order: foreground-only local companion clock, explicit stop and witness code only if supplied; no fabricated witness/completion action
- Time window: source clock labels, subscription readback and honest native subscription gate; no device-clock unlock or substitute reminder

All six participate in native dispatch and story priority. Immutable version/account reviews, unknown-result locks and exact retries govern their writes. Text limits use the backend's UTF-16 unit without splitting a visible grapheme.

### Camera/AR fallback

Returned scan `overlayUrl` now appears as a normal approved-host image, explicitly labeled static. This is the existing source fallback after camera/AR failure, not a claim of spatial placement. Scan acceptance still comes solely from the server QR action.

## Source proof

Read-only mini-program snapshot `fad4d6bd7e3c3e501441fe19c8de9a9cd78230fc`:

- `pages/publish/utils/publish/advanced-game-config.js`: registry/presentation 1–105; sensor defaults 524–527; reasoning defaults 577–606; normalization 951–974 and 1199–1238; validation 1546–1568 and 1938–2006
- `pages/play/utils/playkit-view.js`: legacy priority/projection/completion/actions; no music or silent-order completion action
- `pages/play/components/playkit-scan/index.wxml`: normal-image fallback for returned overlay
- `pages/play/components/playkit-photocheck/index.js`: framing is an aid, never a judgment condition; failure falls back to ordinary capture/selection
- `pages/play/components/playkit-scan/ar/{index.js,ar-math.js,ar-gate.js}`: plane placement, world-lock after marker recognition and optional GLB models

Read-only backend `AdvancedGameRuntimeServiceImpl` methods 1268–1419 and projections 2728–2828 corroborate action fields, server-day waiting, content checking and platform-specific proof. Only derived requirements and newly written native code are included here.

## Remaining, classified

Implementable offline but not included in this increment:

- In-camera photo framing and screen-space scan preview are implemented by the later v4 camera-presentation packet; physical-device and permission acceptance remain outstanding
- Native image-only plane/marker AR is implemented by the later v5 packet with explicit calibration/activation gates. The mini-program deleted local game-timer/sticker-book orphan families on 2026-09-20; they are stale Flutter references, not active implementation gaps
- Creator panels for existing advanced sections beyond these twelve; preserving a section is not an editor

Requires accepted external/provider facts or configuration:

- WeChat step proof (`code/encryptedData/iv`) has no approved native replacement; pedometer counts are not equivalent
- WeChat subscription authorization cannot be replaced by an iOS notification permission
- The marker physical-size policy is absent from current wire fields; models are GLB. Native calibration and model-format/decoder compatibility need accepted configuration, not invented source fields
- Media origins, hardware permissions, physical-device behavior, Apple runtime/visual/accessibility and backend acceptance remain separate gates

See `playkit-authoring-legacy-verification.json` for exact source-only execution and authored/not-run evidence.
