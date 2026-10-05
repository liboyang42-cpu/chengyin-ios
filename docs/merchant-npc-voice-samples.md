# MerchantNPC voice samples

## Scope and verified source

Adds the missing local capture/playback and single-file upload consumer, feeding existing MerchantNPCResourcesCoordinator.prepare(.enroll). No duplicate enrollment/status provider API. MerchantNPC merchant-row scope, access revalidation, resource journal and final enrollment review remain authoritative. This is NOT ShopNPC voice-chat.

Source evidence: app-audit/lib/feature/merchant/merchant_npc_voice_page.dart:147–245 captures five ordered m4a samples, preserves an old sample when interrupted recording returns nil, supports playback, sequentially calls PublishApi.uploadFile(fileType: 'm4a'), then voiceEnroll. lib/data/api/publish_api.dart:346–364 posts multipart /api/common/uploadOSS with file, optional fileType/fileName, code 200 and top-level url. Native sends file and fileType=m4a; fileName is omitted. Filenames are generated, not user-controlled. Authentication uses existing raw Authorization convention.

## Default-off integration

The normal AppSession resource editor mounts a localized configuration-required section even when resource reads are unavailable. It does not instantiate the voice provider or uploader without attested configuration. All ordinary grants remain OFF. Optional makeVoiceSamples is added to the existing resource editor and operations destination; original imageContext, imageRealm, approvedImageHosts, retained image picker and cleanup are preserved.

A separately authorized composition root must supply a reviewed MerchantNPCVoiceConfiguration (sample rate, channel count, bit rate, minimum/maximum duration, byte bound, allowed receipt hosts), independently enable local capture/playback and MerchantNPC grants, authorize the exact deployment/account upload endpoint, and use the independently enabled ResponseLimitedHTTPTransport. The default upload transport is that same bounded adapter with enabled=false; explicit HTTPTransport injection remains for deterministic test doubles. Image capabilities do not authorize voice upload. No source-backed provider duration/encoder limits are known; nil configuration blocks the workflow. Test fixture numbers are synthetic, not contract facts.

The factory receives the EXISTING MerchantNPCResourcesCoordinator. Inject the SAME OperationPendingJournal as that coordinator, current-scope/token/grant closures, and register the returned sample coordinator with the SAME MerchantNPCSessionOwner. Do not create an unrelated resource coordinator or journal. Existing session-owner invalidation now cancels registered sample consumers. Do not enable live grants while merging this packet.

Merge Resources/MerchantNPCVoiceSamples.fragment.json strings into the canonical catalog preserving other entries; it is a fragment, not a replacement catalog. Add App/Core files and AppUnitTests through the existing project generator. Core tests reuse MerchantNPCTests.HTTP/Journal only as synthetic test seams.

## Safety and behavior

- Explicit ownership/consent precede recording. Server script must contain exactly five nonempty lines with consentIndex zero; sample zero must exist before recording other lines. No imported voice or third-party ownership inference.
- Record is the only permission entry point. Provider construction, rendering, and default-off tests do not request microphone permission or activate audio.
- AAC-in-m4a encoder settings and bounds are deployment configuration. Local validation checks the configured duration/size and ISO BMFF ftyp; this is not a claim of full codec validation or provider acceptance.
- AVFoundation recordings use protected random temporary files, then bounded memory-only clips. Stop/nil/interruption retains the prior successful clip. Cancellation, background, session invalidation and view exit discard ephemeral bytes/URLs; on interruption the active attempt is deleted, preserving previous samples. Max-duration auto-stop discards the unfinished attempt rather than silently saving/transmitting it.
- One reviewed transmission per sample, in index order. Review shows exact destination, sample index, duration and byte count; confirmation refreshes merchant access/script before sending. No auto upload, retry, enrollment, playback or provider action.
- Each send persists the existing resource write-ahead lock before invoking uploader. Unknown, malformed, cancelled, stale-session or failed cleanup outcomes retain it. Same owner/merchant-row key deliberately excludes epoch/revision, so re-login/recreation cannot bypass uncertainty. Enrollment and uploads cannot race through that shared lock.
- Recovery exposes only OperationPendingRecord metadata (operation identity, account/deployment/target, acknowledged step count); raw audio, script, URLs and credentials are never journaled. No invented remote delete/status/receipt endpoint, retry or local unlock button. An independently verified recovery flow is required to resolve an unknown remote upload before retrying.
- After five acknowledged uploads, a separate button prepares the existing enrollment review. Only the existing final Confirm executes enrollment, with its existing authoritative revalidation and durable lock. Acceptance still does not mean the provider voice is ready.
- Temporary-file deletion is best effort on process interruption; iOS process termination cannot run cleanup. No recovery reads/reuses orphan audio. Device/runtime validation must include kill/relaunch cleanup policy before enabling production capture.

## Verification

Source structural checks PASS. Pinned Tree-sitter 0.26.0 / tree-sitter-swift 0.7.3 parser PASS, 9 Swift files, zero ERROR/MISSING recovery nodes. These checks are not compilation.

Nine Core test cases authored: default grants, consent-first ordering, nil/interruption preservation, five distinct upload reviews and final enrollment review, unknown durable recovery, consent revocation, HTTP default-off, exact multipart/top-level URL, malformed/stale response, configured validation (some cases cover multiple assertions). Two AppUnitTests authored for default-off microphone/playback guards. XCTest execution, Swift typecheck, Apple build, simulator/device accessibility/audio and UI runtime: NOT_RUN (no Swift compiler or Apple SDK here).

No microphone permission, recording, playback, upload, cloning, provider, or network action was invoked while implementing or checking this packet.
