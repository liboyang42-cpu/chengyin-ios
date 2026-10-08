# Professional-topic image App integration

## Scope and acceptance status

This is a code-complete, default-off integration candidate, not end-to-end production acceptance. It adds a native image picker, 3:4 cover and 16:9 gallery crop/preview, explicit upload and a separate explicit apply-and-local-save action. It does not complete the user's full image/video requirement. No selectable video entry was added. Topic video upload, playable media transport, publishing fields, moderation and recovery remain unimplemented.

The topic upload approval is default nil. No account, production deployment, media origin or policy was enabled. The retained story image grant, generic retained-image journal and existing-topic owned-cover capability do not authorize this feature. The optional topic-specific source is independently composed in AppSession and rechecked at the outer HTTP boundary.

## Source contract

Read-only review of [liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636](https://github.com/liboyang42-cpu/chengyin/tree/ce61c0bbace743ff835cb297ef41c89b52181636) established:

- Mini `pages/fabu/index.js`: `IMG_ARR_MAX = 9`; cover selection/crop is one 3:4 image; gallery is up to nine 16:9 images. Gallery writes comma CSV and reads legacy comma/semicolon CSV.
- Mini `app.js` + `utils/upload-client.js`: `POST /api/common/uploadOSS`, multipart `file` and `bizType`, selecting `image_3_4` for the cover and `image_16_9` for the gallery; root-level `url` in the success reply. No topic ID is required, so a new draft can upload before creation.
- Backend `AppUploadService`/`UploadImagePolicy`: images only; ratio tolerance 2%; positive dimensions; at most 40 million source pixels. Native output is stricter, an exact integer ratio and no more than the existing 4096-pixel sanitizer edge/8 MiB sanitized JPEG cap. Approval-supplied local limits can be tighter; there is no local policy fallback.
- `AppTokenService` accepts the raw Authorization token or strips `Bearer ` when present. The native source retains the existing raw-token/captured-token equality contract.
- The checked `run41-prod-ddl.sql` snapshot retains `cms_topic.img_url varchar(255)` and `img_arr varchar(2000)`. Native checks use conservative UTF-16 length limits (cover 255, total gallery CSV 2000), with no truncation or URL rewriting. This source snapshot is not proof of current production DDL.

This increment does not add an endpoint or claim URL replies are asset ownership, immutable content, moderation or release evidence.

## Flow and boundaries

1. Full-edit professional personal-topic context is captured from the actual coordinator session/identity/snapshot scope, draft product/owner/publishMode, monotonic draftMutationRevision, editorIncarnation and ownsVisit.
2. A topic-specific, currently approved source and independently enabled native picker are required before opening.
3. The selected-item-only RetainedNativeImagePicker is reused. Its image-only PhotosUI filter and RetainedImageSanitizer bound, decode, redraw and strip original metadata. No album-wide access or provider URL persistence is introduced.
4. Native fixed-ratio crop produces a bounded, upright JPEG. It is placed in a private app-owned temporary directory under an opaque reference.
5. The inspector opens only its bound regular file with O_NOFOLLOW/O_NONBLOCK, checks descriptor identity/change metadata, streams bounded complete bytes, verifies they equal the immutable crop, and actually decodes those same bytes with ImageIO. Core owns independent hashing/counting and the aggregate inspection budget.
6. The existing Core sequence is used unchanged: begin → prepareInspection → InspectionEvidence.inspect → finishInspection → confirm. The one-use local intent is never sent or used as an upload credential.
7. Explicit upload uses the field-specific topic client and exact outer multipart route. No automatic retry, endpoint fallback, generic upload proxy or URL-derived digest exists.
8. Only a successful current reply offers a separate apply action. Current context, draft revision, visit, source identity/policy and permittedURL are rechecked, then the exact reference is applied and local persistence is confirmed. Existing gallery bytes and order remain unchanged; a comma and the new URL are appended.
9. Cancel, dismissal, backgrounding, changed draft (including same-byte replacement), owner/session/configuration change, an observed approval withdrawal (even if the identical grant later returns), or a newer editor visit retires the selection and prevents late callbacks. Upload cancellation does not prove the server did not receive bytes. Unknown/error outcomes never fill the draft or retry automatically.

Temporary bytes and receipts are intentionally not journaled or recovered after closing. A successful remote file can be orphaned if the user closes before apply or if the upload outcome is unknown; no deletion API or reconciliation receipt is invented. Retrying local save does not upload again. Restoring the saved draft uses its ordinary local draft envelope, containing only applied remote references.

## Verification

- Python focused source contracts are runnable with `python3 -m unittest Tests.ContractChecks.test_project_topic_media_app Tests.ContractChecks.test_project_topic_media_local_selection Tests.ContractChecks.test_project_story_image Tests.ContractChecks.test_project_edit_composition_fence`.
- Authored Core tests cover default denial, field-specific denial, exact multipart shape, raw-token semantics, ratio rejection, merchant exclusion, origin/length/duplicate-key rejection, receipt context/field binding, revocation, unknown outcomes, single-attempt fencing and response budgets.
- Authored App tests use actual native image decoding/cropping/inspection with a synthetic picker and synthetic HTTP responses. They cover explicit apply, exact returned URLs, persisted local drafts, legacy gallery order, count/aggregate length caps, draft ABA, account/visit changes, local-save retry, unknown outcomes, queued cancellation, late picker callbacks, source withdrawal/regrant ABA and exact route rejection.
- Swift compilation, Core XCTest, App XCTest and simulator/device UI: NOT_RUN. No Swift or Xcode toolchain is available in this executor. Python source checks do not substitute for compilation or execution.
- Live upload, production grant configuration, server readback, physical-device Photos permissions/selection, interruption UI and full publishing acceptance: NOT_RUN.
- PBX/test target registration is reserved for the integrator and is not changed by this patch.

## Patch scope

13 paths: four new App topic-media files, one minimal ProjectEditView mount, one App unit-test file, one Python contract file, this document; plus the approved additions of Core/ProjectTopicImageUpload.swift, optional ProjectEditCoordinator source wiring, topic-only AppSession/AppCompositionRoot composition, and one Core test file. No Muse settings/profile/favorites/notifications paths or frozen media-core sources were changed.
