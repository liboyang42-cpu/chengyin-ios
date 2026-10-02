# MerchantNPC additive integration

## Scope and source authority

This isolated packet addresses audit B5 and the distinct merchant portion of A2. It does not replace native-shop-npc-new. Merchant chat is complete moderated JSON, not SSE. PublicMerchantHome passes `PublicMerchantRowID`; `bizId` is that row ID. Never substitute owner member ID or Play node ID. Source: `app-audit/lib/data/api/merchant_npc_api.dart:60–183`, `data/models/merchant_npc.dart`, `feature/npc/merchant_npc_chat_controller.dart:95–170`, public merchant home line 405.

## Additive install

1. Add Core files to QuestifyCore, App files to the app, and merge MerchantNPC.xcstrings. Dependencies are existing PublicMerchantRowID, MerchantOperationsReading, MerchantAssetResources, MerchantVoiceResource, MerchantAvatarResource.Job, and OperationPendingJournal/OperationDefaultsJournal/OperationPendingRecord from OperationAdapterSafety.swift. Keep their original source ownership.
2. In the existing PublicMerchantHomeContext construction, call `installMerchantNPC(grants:scopeForRow:currentScope:client:)`. All grants default false. Build scope from the required deployment/operational-region namespace, current authenticated account, session epoch, merchant row and access revision. Never reuse a namespace across independent deployments. The context helper sets the existing source-named `shopNpcChat` flag and supplies the exact row-aware destination. It does not call ShopNPC APIs. Rebuild the context on gate/session changes; closing or backgrounding permanently invalidates the presented coordinator.
3. For merchant operations `.assets`, mount MerchantNPCResourceEditor with the SAME MerchantOperationsReading owner currently used by MerchantOperationsDocumentView. Keep existing profile/character editor and status views. This editor calls `reader.access()` and `reader.document(.assets)`; it does not implement duplicate status HTTP endpoints or save profile data. Gate the host using the same access decision and match access.identity.merchantID to the scoped row ID. The supplied MerchantNPCOperationsDestination is the additive constructor replacement: it routes .assets to this editor and every other destination to the unchanged MerchantOperationsDocumentView.
4. An authenticated host may inject MerchantNPCHTTPTransport only after existing origin, auth, region, provider, legal, capability and production-write gates. Transport must preserve the provided scope and enforce it before transmission and after response. No default URLSession, origin, token or provider exists here. Default client transport throws disabled.
5. DEBUG fixture route: `--merchant-npc-fixture` -> NavigationStack { MerchantNPCFixtureView() }. It uses existing MerchantOperationsFixtureReader and a local fake transport. No network, recording, real media, cloning or legal acceptance occurs. Add this launch route in the app's existing fixture switch, not a second @main.

## Exact resource contract

- voice/script POST `{}` returns available, script and consentIndex. Exactly five nonempty lines and consentIndex zero are required to offer enrollment. A ready voice status does NOT establish provider availability.
- voice/enroll POST `{sampleUrls, requestId}` contains exactly five ordered URL references. The first reference corresponds to the authorization statement. Review binds scope, script, inputs, explicit consent and voice ownership. A UUID remains in that reviewed action. No automatic resend.
- voice/revoke POST `{requestId}`. Non-200 business responses preserve safe server text; never report withdrawn on failure. Server acceptance is a message receipt, never proof of remote deletion inferred from a status read.
- avatar/generate POST `{imageUrl, style}`. Do not add a request ID field absent from source. Style must be server-supported, status available must be true, and pending tasks block another generation.
- Existing voice/status and avatar/status readers remain source-owned. Voice 1 and avatar PENDING poll at five-second intervals while active. Unknown status stops automatic polling. Every refresh immediately revokes write authority and any review. A failed or denied refresh preserves only display status, leaves write authority revoked, clears stale script availability and never resolves an unknown operation. Confirmation re-reads authoritative access, status and script, then checks grants and the reviewed inputs immediately before dispatch. Enroll/revoke accepted responses carry message only; avatar receipt is the source job object. No invented receipt endpoint.

## Bounded media handoff contract for next owner

`MerchantNPCMediaReference(scope:selectionID:kind:url:approvedHosts:)` is the only input seam. Avatar kind is `.avatarImage`; voice kinds must be `.voiceSample(index: 0...4)` in order. References require HTTPS, explicit host allowlist, no embedded credentials or fragment and current scope. The upcoming shared consumer must own image selection permission, real format decoding, dimensions/byte limits, metadata removal, cancellation, approved origin/upload service, session fencing and confirmation. Construct the reference only after that bounded upload succeeds. Its selectionID is a client provenance ID, NOT a server media receipt or evidence of moderation. Keep any actual server receipt in its original upload-domain type. Do not derive these URLs from arbitrary text or convert IM identities.

Voice is separate: require voice ownership and independently approved cloning, microphone/capture/upload permissions, provider format/duration/size requirements and all five source scripts before real capture. Those details are not established here, so no recording/upload implementation is supplied. Fixture references use synthetic.invalid and never fetch bytes. Do not recycle ShopNPC voice-chat multipart uploads or image OSS for these samples.

## Unknown outcomes / lifecycle

Transport failure, HTTP 5xx and malformed post-send responses are unknown. Before any resource mutation, the coordinator writes an OperationPendingRecord to its injected OperationPendingJournal (default: existing OperationDefaultsJournal backed by UserDefaults.standard). Production composition must retain a durable journal, never substitute a memory store. The lock key contains deployment/region namespace, account ID and merchant row ID; it deliberately excludes session epoch/access revision. It blocks all resource mutations for that target across closing, backgrounding, login changes, new coordinators and process recreation. Journal read corruption or write failure fails closed before transport. Only an acknowledged success or explicit non-ambiguous rejection clears its exact record. Store only operation identity and owner/target keys, never token, media URLs, scripts, voice data or message contents.

A status refresh is never an operation receipt and cannot clear the journal. No reconciliation API is invented. Unknown records require separately established authoritative resolution before a future explicit recovery mechanism can clear them; this UI offers no reset or inferred retry. A confirmed response arriving after session invalidation conservatively leaves the lock intact.

Chat alone uses up to three attempts with the SAME UUID and message, server retry eligibility/delay and epoch fencing. Malformed/missing success data after dispatch maps to unknownOutcome and retains that UUID for retry; it cannot silently become a fresh billable request. Close/background/session changes clear text and review data and ignore late completions, without touching the resource journal.

## Review repair regression coverage

Added denied-refresh stale authority, confirm-time fresh access, newly pending avatar status, durable-store recreation with a new login epoch, journal write failure, namespace/account isolation and malformed chat UUID and consent-change-during-revalidation regressions. These are authored XCTest cases, not executed on this Linux environment.


## Still off / not a runtime completion claim

No real samples, audio playback, provider activation, upload, clone, new legal acceptance, production transport, remote edit, deployment or Apple build was performed. The main app integration and Apple tests remain an integrator responsibility. Source/Tree-sitter checks are not Swift typechecking or runtime verification.
