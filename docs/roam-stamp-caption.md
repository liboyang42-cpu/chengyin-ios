# P130 · Write and review a city-stamp caption

## Proven source and actual missing action

The sole master v10 P130 / PA04 calls out `onNoteInput`, retake and send in the city-stamp flow. P127/P128 were checked only for the next concrete action: gallery preview/replay/share already exist or have sealed deliveries; no map capability is enabled here.

At retained Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:

- [P130 page](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/subpackageRoam/citystamp/index.js): `onNoteInput` updates local `note`; retake keeps it; `_createStamp` sends that note as `caption` with the original photo URL and idempotency key. Blob `a09e49e005a0034b2ae9a639bb2c593d2322502c`.
- [P130 view](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/subpackageRoam/citystamp/index.wxml): textarea, 30-unit count, empty caption allowed. Blob `6f057ec557467c8492a8d567717878ff5b3dac06`.

Native base `51d3e24de92427a777f8690f847cec39971b041a` already has a caption-bearing `RoamExperienceMutation.createStamp` contract and `RoamExperienceMath.validCaption`. However, the ordinary `RoamStampCameraView` lacks an editor and its capture coordinator always creates with an empty caption. The separate `RoamCityStampDraftView` is only a local preview; it does not feed the ordinary camera/create flow. This slice adds the missing authoring action in that existing destination, rather than another entry or default-nil destination.

## Behavior

1. The ordinary stamp preparation/review page accepts a local caption and shows its exact text, remaining UTF-16 units and over-limit feedback. Empty is valid. Text is not trimmed or truncated, preserving IME composition and intentional whitespace. Over-limit text cannot upload.
2. Local editing and preview work without a camera/uploader/create grant. When no capture coordinator exists, the view labels the text as a local draft. It neither saves a stamp nor claims an exchange. A pending/unavailable coordinator cannot edit its retained command.
3. Retake preserves the draft. Starting upload freezes the reviewed caption before suspension; editing stays locked during upload and while the pending create command exists.
4. The existing protected pending store persists the exact caption together with the uploaded URL and idempotency key, before create can dispatch. A relaunch/unknown create retry uses those same values. Caption equality is UTF-8 exact, so canonically equivalent Unicode cannot replace the original payload under the same key.
5. Old v1 pending records missing `caption` migrate to the original empty caption. Present null, wrong-type or overlong values fail closed. The storage namespace/account/realm and write/readback gates are unchanged.
6. Leaving the page clears an unsent caption. The existing capture invalidation also clears an unsent coordinator draft on background/camera-disable; a pending caption survives only as its already-persisted exact retry command. The nil-coordinator local preview is ephemeral and is cleared on leaving. Its ordinary session host also recreates the local view on wallet scope or session revision change, including nil-to-nil coordinator transitions.

## Boundaries

No earlier delivery is overlaid or changed. No root composition, project file, main catalog, CI, map adapter, coordinate conversion, grant, camera permission, upload origin or stamp-write approval changes. No live camera, upload, create or exchange was performed. Existing capture/upload/create buttons and explicit user actions retain their original gates. Paper tearing, scratch/reveal, exchange and album save are outside this caption slice.

Two new EN/zh-Hans entries are provided inside `roam-stamp-caption-registration.json` for the central catalog owner. All three production sources are already registered. The new Core XCTest file is discovered by the current Swift package target; no new test framework or CI job is added.

## Verification status

- Thirteen focused Core XCTest methods authored for UTF-16/empty handling, legacy migration, malformed records, disabled-local editing, limits, retake/cancel, upload freeze, exact restore/retry, pending lock, owner scope, UTF-8 identity and stale completion. Native execution: **NOT_RUN**, no Swift/Apple toolchain on this dot computer.
- Four changed Swift files: Tree-sitter syntax parse only. This does not typecheck Swift, validate Apple SDK usage or prove runtime behavior.
- Five original Mini caption cases execute under inert Node VM app/wx stubs. These establish source behavior, not native behavior or backend readiness.
- Focused source assertions and reversible patch replay are recorded with the delivery package; these are not substitutes for XCTest or device acceptance.

## Apple acceptance handoff (not executed)

Run `swift test --filter RoamStampCaptionTests`, the existing `MediaDestinationsTests`, and an unsigned Apple app build after merging localization. On a synthetic approved test configuration check:

- Ordinary roam → stamp page; input/preview works without camera permission and is clearly draft-only when unconfigured.
- EN/zh-Hans, Chinese IME composition, empty caption, 30 Chinese units, 15 emoji, mixed over-limit input, Dynamic Type and VoiceOver count/limit controls.
- Retake keeps text; Back then reopen clears unsent text; account/realm replacement does not carry a draft into another owner's coordinator.
- Upload/create each remain explicit and separately gated; rapid input during upload cannot alter the reviewed command.
- Failed/unknown create followed by close/reopen retains the exact text/URL/key, with no reupload; canceled/stale create cannot claim success or erase the pending caption.
- Legacy missing-caption journal retries as empty; malformed caption is unavailable; new commands never overwrite a different pending caption.
