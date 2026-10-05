# Retained native image consumers — additive integration

Status: implementation packet, not merged and not Apple-verified. Source: Flutter `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`. No OS selection, camera, network, upload, account action or transmission occurred during this work.

## Ownership and files

Copy additive Core/App/Tests files listed in MANIFEST.json and merge the 17 bilingual localization entries. Overlay only these already-existing files after reconciling the recorded baseline hash:
- Core/PublicMerchantReviewWrites.swift
- Core/PublicMerchantReviewCoordinator.swift
- App/PublicMerchantReviewEditor.swift
- App/PublicMerchantReviewsView.swift
- App/MerchantOperationsEditor.swift

Do not replace AppSession, MerchantOperationsViews, app root, project.pbxproj, or existing localization catalogs wholesale. This packet does not own SquareWorkspace's community media registration, Play photo completion, voice sampling, QR or camera. Existing IM uploadOSS transport/coordinator remain the only IM upload implementation.

Dependencies: PublicMerchantHome, MerchantOperations, IMExpanded, and MerchantNPC contracts. The NPC bridge can be moved to a separate file/target if the NPC packet has not yet been integrated. No production defaults are changed by copying files.

## Normal IM host (required integration)

1. Add a retained `let retainedImagePickerHost = RetainedImagePickerHost()` to AppSession. Default `nativeSelectionEnabled` is false.
2. Mount `RetainedImagePresenterHost(host: session.retainedImagePickerHost)` once as the signed-in shell's background. It creates only an inert UIViewController. Do not mount it inside each repeated row.
3. In AppSession.imImageUploadCoordinator(for:), replace the `IMDormantImagePicker()` argument with `retainedImagePickerHost.imPicker(scope: scope, currentScope: { [weak self] in guard let self, self.imExpandedWriter.identity == scope.identity else { return nil }; return scope })`. Keep existing scope construction, writer and coordinator cache unchanged.
4. Existing `IMImageUploadCoordinator.clear()` calls cancel the picker and invalidate asynchronous selection completions. Preserve existing account/scope teardown; clear cached owners on sign-out/navigation destruction. Never recreate an unknown upload merely to unlock it.
5. OS selection can be granted separately at a reviewed deployment boundary, before constructing owners. The native host checks the grant again when presenting. This does not grant upload or send permission. IM writer/origin gates stay off.

The shared picker restricts selected item access to one image, rejects multiple frames/oversized encoded files/oversized pixel declarations, downsamples before decode, redraws on an opaque canvas, and re-encodes fresh JPEG bytes. No EXIF/GPS metadata is copied. File representation size is checked before Data loading. Cancel, interactive dismissal, task cancellation, and stale-session callbacks complete/ignore once. It never requests full-library access or opens a camera.

## Public merchant reviews

`PublicMerchantReviewCommand.create` adds a defaulted fourth associated value `images: [RetainedUploadedImage] = []`. Existing construction calls work, but pattern matches must bind/match four fields. The two packet-owned pattern-match files are updated; search all external `.create` matches during integration. Text-only calls still send `imageUrls: []`.

Provide `PublicMerchantReviewWriteContext.imageContext` only from the authenticated account/session owner. For each `(session.scope, target.merchantRowID, registrationID)` cache a single RetainedImageSelectionContext and upload owner:
- Scope accountID = session.accountID, epoch = session.scope, realm = session.realm
- Destination = `.publicReview(merchantRowID: target.merchantRowID.rawValue, registrationID: registrationID)`
- currentScope returns that scope only while account/token/realm, eligible registration and target are unchanged
- picker = retainedImagePickerHost.makePicker()
- uploader = RetainedImageHTTPUploader with injected transport and token closure, enabled false and empty approvedOrigins by default

Do not create a fresh context on every SwiftUI render. Discard byte selection and invalidate on account/registration/target changes. Keep an unknown upload owner locked for its scope. Upload has no verified status/receipt-recovery API; do not invent one.

The editor separately selects, reviews upload, applies a verified uploaded result, removes images, freezes review submission, and submits using the existing durable public-review journal. Max nine unique image selections. Body validation rejects wrong merchant/registration; prepare and execution reject wrong account, epoch or realm. The existing create receipt (`reviewId`, `status`, `version`, `replayed`, `auditTaskId`) and public eligibility refresh remain unchanged.

For public review image rendering, pass `imageReader: RetainedPublicImageReader(enabled: false, origins: [])` to PublicMerchantReviewsView by default. Approved runtime configuration may set exact HTTPS origins and enable reading. It uses anonymous, ephemeral, no-redirect, streaming size-bounded downloads. No token/cookie storage or IM identity is used. Source URLs must come from the current validated review snapshot. Thumbnail tap opens a larger preview; dismissal cancels the SwiftUI task and clears pixels. The same sanitizer bounds remote image decode.

## MerchantOperations editor hooks

Add an optional `imageContext: ((MerchantImageField) -> RetainedImageSelectionContext?)? = nil` property/initializer argument to MerchantOperationsDocumentView and forward it to `MerchantOperationsEditor(model: model, imageContext: imageContext)`. Thread it through normal merchant-home/template navigation where exact merchant row/account/access identity is available; do not infer merchant identity from the account ID.

Cache contexts separately for logo, coverImage, gallery, avatar and imgUrl, with `.merchant(merchantRowID: verifiedRowID, field: field)`. Use the authenticated account ID, current reader.scope as epoch, configured realm, and a draft/access-specific accessRevision. For template imgUrl, set resourceID to the actual template draft.id (nil for a new draft), and require a nonnil per-draft accessRevision. currentScope must compare the current reader.scope, merchant access revision, destination and template ID/draft revision before returning a scope. Return nil when permissions or target change.

Applying the proof changes only the matching local draft field and preserves all unrelated fields. Gallery append enforces nine and rejects duplicates. Template proof checks resource identity. Existing MerchantOperations confirmation, whitelist, ownership/permission refresh and durable save journal still control merchant mutations. Upload never auto-saves a merchant draft.

## NPC avatar seam

`RetainedUploadedImage.npcAvatar(scope:realm:approvedHosts:)` returns `MerchantNPCMediaReference(kind: .avatarImage)` only after checking account, epoch, realm, captured deployment/region namespace, merchant row, avatar field, and accessRevision against MerchantNPCScope. It preserves selectionID and upload URL; it creates no media-registration receipt. For NPC imagery, pass the existing session/deployment namespace into RetainedImageScope.namespace at selection time. Do not derive it from the account, substitute realm, or invent a constant. The bridge rejects nil/empty or different namespaces. MerchantNPCScope now requires its own namespace initializer argument; this packet does not construct NPC scopes. Use only this typed bridge for uploaded avatar imagery. The caller must pass its current scope after upload and before provider review. Keep server/provider/legal/resource-ownership/media grants independent and false by default. Voice samples and voice consent are outside this packet.

## Fixture and test wiring

- Add DEBUG root route `--retained-images-fixture <success|unknown>` → RetainedImageFixtureView(mode:). This uses in-memory synthetic image and fake HTTP transport only. Normal PhotosUI selection is disabled even in the fixture.
- Core tests go in the existing QuestifyCoreTests target.
- UI tests go in QuestifyUITests and require that DEBUG route.
- AppUnitTests/RetainedImageSanitizerTests.swift needs an iOS unit-test target with @testable import Questify, UIKit/ImageIO and application target dependency. The current project does not establish such a target; these four tests are authored, NOT_RUN, not silently counted as executed.
- Merge Resources/RetainedImages.xcstrings entries into the existing catalog, or add the separate catalog as a resource without duplicate keys.
- Add all new Core/App files to the respective package/project file groups and build phases. Do not add XCTest files to production app sources.

## Evidence and remaining acceptance

`tools/check_retained_images.py` passes source/structural contracts. Pinned Tree-sitter 0.26.0 / tree-sitter-swift 0.7.3 parses all 16 Swift files without recovery. 10 core, 4 app-unit, 3 UI tests are authored and NOT_RUN. Swift compiler, typecheck, XCTest, Apple SDK, device/simulator, UIKit presenter/sheet hierarchy, cancellation timing, memory ceiling and accessibility runtime checks are NOT_RUN. The file manifest is integrity evidence, not an Apple compile guarantee.

OS selection, live upload, public remote image reads, approved origins, NPC provider and all origin grants remain OFF. Live deployment additionally requires approved endpoint/account/legal/media policy and no-redirect transport for upload requests. The existing generic HTTPTransport buffers upload responses before the one-MiB response check; a streaming response-limited transport remains an enablement requirement. No storage hostname was invented as production configuration. The fixture `.example.com` domains are used only with fake transport.

The B6 audit cited incorrect line ranges, not a changed source revision. Actual relevant source ranges: public picker/upload 236–277 and image renderer 799–827; router 720–730 selects PublishApi.uploadImage; publish_api 346–366 proves its `file`/top-level `url` contract. Review API create 124–139 and merchant_review.dart create draft 323–372 establish body/validation. Play API 436–453 is the merchant image helper upload contract; club_image_picker 58–120 supplies NPC/template helper chaining. See manifest for source hashes.
