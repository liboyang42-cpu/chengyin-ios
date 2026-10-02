# Normal retained-image host integration

Additive integration packet. The source checkout was read-only for this worker. No OS picker, camera, upload, remote image read, authentication request, review mutation, merchant save, or external transmission was performed.

## Exact deliverables

Production additions:
- `Core/PublicMerchantReviewHostGate.swift`
- `App/RetainedImageContextCache.swift`
- `App/MerchantRetainedImageHost.swift`
- `App/RetainedPublicMerchantReviewHost.swift`

Narrow host patches (apply only after reviewing the surrounding source):
- `patches/MerchantOperationsViews.patch`: document view/model/template navigation only; does not alter MerchantOperationsHomeView or its parent's destination factory
- `patches/MerchantOperationsEditor.patch`: stable image-control identity follows the current draft fence
- `patches/PublicMerchantReviewEditor.patch`: session/leave teardown and a second exact-scope check when applying an image

`patched-hosts/` contains reviewable combined results, NOT replacement files to copy wholesale. Parent changes in MerchantOperationsHomeView, NPC routing and other host code must be preserved. Recorded source hashes are in `docs/HOST_BASELINES.json`.

Tests:
- `Tests/CoreTests/PublicMerchantReviewHostGateTests.swift`: 8 authored core tests
- `Tests/AppUnitTests/RetainedImageNormalHostTests.swift`: 6 authored iOS application tests; requires an application unit-test target with `@testable import Questify`

## AppSession merge

Use the exact properties and getter in `docs/AppSession.snippet.swift` as a merge guide inside AppSession. It is not a standalone build input.

- Reuse the parent's `retainedImagePickerHost`; do not create another presenter or replace IM upload ownership
- `retainedImageContextCache` is account-session-owned and retained for the lifetime of AppSession
- `retainedMerchantImages` is the normal merchant document factory
- `retainedPublicMerchantReviews` composes an actual PublicMerchantReviewHTTPWriter behind a false gate, the separately false scoped review reader, disabled public image reader, existing merchant-business durable journal, and cached image factory
- Rotate `publicMerchantReviewEpoch` and invalidate both retained hosts/cache in the existing account/token/stamp-change branch of `synchronizeAccountMarketingEntry`
- Do not set `retainedImageContextCache` to nil on logout; `invalidate()` keeps unresolved upload owners
- Preserve the existing disabled public-home reader and merge any already-added NPC destination into the PublicMerchantHomeContext getter

The parent's normal operations destination factory should return this for non-assets destinations:

```swift
AnyView(MerchantOperationsDocumentView(reader: merchantOperationsReader,
    destination: destination, imageHost: retainedMerchantImages))
```

If MerchantNPCOperationsDestination wraps all operations destinations, add an optional `imageHost` parameter there and forward it only to its non-assets DocumentView branch. The document view itself propagates the same host to new and existing templates.

The NPC assets image seam may reuse `retainedImageContextCache.context(...)` with `.merchant(row, .avatar, templateID: nil, newDraftID: nil)`. Its independently retained ownerID and current-scope callback must check the NPC's exact account, namespace, epoch, row and accessRevision. Use only the existing typed `npcAvatar` bridge; empty approvedHosts and all resource/provider/legal/media grants remain false.

## Fences and ownership

Merchant image contexts are created only after the existing MerchantOperationsCoordinator has loaded a draft and the same reader has refreshed authoritative access. Merchant identity is `access.identity.merchantID` converted to `PublicMerchantRowID`; it is never accountID or ownerMemberID. Context creation requires the destination's access gate and correct draft/field pair.

Each document model owns one MerchantRetainedImageDocumentOwner. Its current-scope predicate checks reader.scope, account/token credentials, access revision, draft revision, unchanged draft, destination, current authentication, busy/confirmation/unknown-lock state, and exact template resource ID. Existing template scopes contain the actual draft.id; a new template scope contains nil and a nonnil per-draft local revision. Reload, edits, discard, save attempts, disappearance and session changes invalidate selection. Applying an image remains a local edit; the existing save confirmation/journal stays authoritative.

Review eligibility is cached only from a validated authenticated PublicMerchantReviewPage obtained through the retained reader or gated writer evidence. It checks the full target, exact session including token, `ELIGIBLE`, and exact registrationID. Refresh suspends the evidence; changed eligibility invalidates the revision. Review image contexts cache by exact session scope, typed row and registration. They are invalidated on account/session change, target change, eligibility change or editor teardown. Submitted images still pass the existing coordinator's fresh eligibility and per-proof validation.

The cache reuses a single picker/upload coordinator for a current context. An unresolved upload is conservatively locked by namespace, account, realm and logical destination across token rotation/logout/login. For new templates, an unresolved nil-template target ignores random screen/draft identity. Reopening a document or creating a new local scope cannot manufacture a fresh uploader for the unresolved target. Unknown owners are retained; there is no retry or invented receipt/status recovery endpoint.

Locks are in-memory, consistent with the existing retained-upload owner contract. Process-death durable upload ambiguity remains an enablement design requirement; this packet does not claim process-restart recovery. All upload gates remain false.

## Grants

The normal cache hard-codes `enabled: false, approvedOrigins: []` for upload. Public review reads and writes each hard-code false. Remote pixels use `RetainedPublicImageReader(enabled: false, origins: [])`. Native selection remains the shared parent host's false default. There is no UI switch, fixture fallback, synthetic credential/merchant factory or automatic network work. Existing merchant reads are not newly enabled or disabled by this packet.

Future enablement requires a reviewed configuration/endpoint/origin/account/media boundary and bounded transport requirements already documented by native-image-consumers-new. Editing these gates alone is not deployment approval.

## Verification

Run from the workspace:

```sh
python3 native-retained-image-host-integration/tools/check_retained_image_hosts.py
```

Result: PASS source/structural assertions. Pinned Tree-sitter 0.26.0 / tree-sitter-swift 0.7.3 parsed all 9 production/test/patched-host Swift files without recovery. This is syntax evidence only.

8 core + 6 app-unit tests are AUTHORED, NOT_RUN. `swift`/`xcodebuild`, Apple SDK, Swift type checking, XCTest, simulator, UI presentation, real permission transitions, cancellation timing and memory ceilings are unavailable/not run here. No runtime or compile pass is claimed.

Add production files to the app source build phase and Core gate to the Core package. Add only the CoreTests file to QuestifyCoreTests; AppUnitTests require the dedicated iOS app unit target and must never be compiled into the production app. No project.pbxproj, package settings or localization catalog was edited by this packet.
