# Play runtime hosts repair

## Implemented
- Normal SessionPlayRuntimeView injects stable, session-owned device/player/circle models; stillness is now retained as well. Runtime keys include namespace, account and authentication epoch. PLAYER projection, command, receipt and circle offers/card/writes reuse the existing source adapters without inventing any game API.
- Native provider implements UIImagePickerController camera selection, Vision QR extraction, CoreLocation one-shot request and CoreMotion accelerometer sampling. Provider grants are empty in the normal host. Merely displaying the host requests no OS permission. Capture cancellation/background navigation tears down pending callbacks.
- Photo selection/capture → preview → explicit uploadOSS request → separate completion review. The upload request is one multipart file, reads the top-level URL, and does not complete a node. Stale account/node/generation responses cannot become reviewed evidence. No automatic retry.
- filter_shot supports only source `night_vision` and `pet_pov`; normalized actual pixels are transformed before PNG upload. Unknown subtype/config is disabled, rather than bypassed to ordinary photo. AR remains unavailable. Filter rendering is native adaptation, not pixel-golden-verified parity.
- CoreLocation remains WGS84; the existing GCJ02 completion validation rejects it. No speculative conversion, local arrival, local capture, filter or sample yields server completion/reward.

## Source evidence
Flutter `lib/feature/play/play_session_page.dart` 806–850 and 1281–1318; `lib/data/api/play_api.dart` 439–456 (`/api/common/uploadOSS`, multipart file, top-level url), `/api/play/photo` around 498 and 556. `lib/feature/play/filter_shot_camera.dart`: back camera with audio disabled, known two styles, actual PNG render, five-element color vectors/18 green bias, scanlines, 72-strip pet distortion and lower shading. Existing native PlayExperienceService.complete retains source completion/route-action semantics.

## Additive integration
1. Use changed-files.json as the exact packet. Copy only its Swift/test/check/guide/localization files, not this worktree wholesale: the worktree carries a shared-main snapshot as dependencies.
2. For AppSession, PlayExperienceView, SessionPlayRuntimeView, PlayDeviceTaskViews and PlayDeviceTasks apply the repair hunks to the latest files, preserving separately owned platform-media/maps and journey-check/ambient integrations. The baseline hashes identify the input versions. `integration.patch` contains only this repair, generated against baseline-hash-verified original bytes. AppSession has concurrent upstream additions, so apply hunks rather than replacing the file.
3. Merge `localizations.json` keys into Resources/Localizable.xcstrings for en and zh-Hans with the existing catalog builder; do not replace the catalog. No new permissions or plist grants are enabled by this packet.
4. Run tools/generate_project.py from the integrated root to include App/PlayNativeDeviceProvider.swift and Core/PlayPhotoEvidence.swift; do not copy an old generated project. The package auto-discovers Core and CoreTests files.
5. All service capabilities and native device grants remain OFF. Activation needs separate integration acceptance, user permission and platform validation. The provided factories do not opt in.
6. Preserve `PlayCompletionReview` confirmation and server-authoritative readback. Do not connect synthetic provider outputs to an enabled live service. No local XP, reward, redemption, or completion shortcut.

## Verification
PASS: scoped source assertions and strict supplementary Tree-sitter parsing of the eight touched Swift files. Authored XCTest coverage: exact upload URL/header/body/top-level result; malformed nested URL; dormant and invalid input zero dispatch; explicit selection-upload-review; changed identity; cancellation/late response; filter output bytes and MIME.
NOT_RUN: Swift XCTest, Apple typecheck/build, simulator UI, accessibility runtime, actual camera/GPS/CoreMotion/Vision, filter pixel goldens, and live network. This Linux executor has no Swift executable or Apple SDK. No actual device/media/permission/network/reward operation was performed.

Apple acceptance should test camera denial/cancel, sheet swipe, repeated capture/upload/review, rotation/orientation, both filter pixel goldens, logout during picker/upload, location denial/stale sample, screen disappearance, VoiceOver/Dynamic Type, and disabled normal-host navigation.
