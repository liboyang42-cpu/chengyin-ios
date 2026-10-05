# MerchantBusiness extension: CRM, privacy-sensitive actions and native selection

Status: isolated additive implementation for parent integration. No main-tree edits, remote writes, backend requests, actual messages, exports, contact disclosure, operator changes, uploads or device permissions occurred during this work. All enabled action transports are synthetic. Live action/device grants remain off.

## What is implemented

- Saved CRM segments: exact GET list, five-field saved filter, POST save with name/requestId, 30 UTF-16-unit validation, applying a saved filter while preserving the current keyword. Malformed saved filters fail closed rather than dropping a narrowing field
- Campaign management: source segments/coupon catalog, explicit server audience preview, 60-unit title/500-unit content, exact create request and receipt, separate dispatch and retry reviews, task history/details with per-recipient outcomes and failure reasons. Creating a task never automatically dispatches it
- Broadcasts: current filters plus ALL/TEAM/ROLE and exact group names, 120-unit content, nine required server preview counts, consent/frequency/daily limits, exact send response with partial-result counts. No client customer-ID roster or merchantId is added
- Masked exports: exact complete source filter, create/status/download adapters, one-time creation token held only in memory, source status polling while visible/running, failed status frames preserve the previous valid frame, persisted task-only recovery, exact X-CRM-Export-Token header, separately gated native Files export. No automatic sharing
- Customer contact: exact member-ID detail preflight, explicit call/copy purpose review, fresh audited contact endpoint, hidden one-use response, separate device adapter with default-off gate. No masked number substitution, cross-session disclosure or cached-number retry
- Operator acceptance: exact token/requestId request, active operator receipt, no invented merchant ID, typed `/merchant/team?invite=` parser for an already-approved host route, memory-only login-return continuation and a guest-capable native landing view. No invented invite-preview endpoint
- Evidence: byte/signature-validated JPEG/PNG/GIF selection, provider abstraction with stale-completion rejection, native PhotosPicker and camera bridge, source camera quality 85%, selected-image preview and clear, explicit upload review using the integrated exact multipart evidence adapter. Selection/upload is bound to source refund ID, store, account, realm and epoch
- Existing MerchantBusiness and merchant scanner unknown-outcome repair, supplied separately as a checked patch

## Contract evidence

| Operation | Exact source |
|---|---|
| Segments, campaign catalog/preview/create/dispatch/retry/history, broadcast, contact | `app-audit/lib/data/api/merchant_crm_console_api.dart`; request/response models in `merchant_crm_console.dart`; UI validation in `merchant_customer_page.dart` |
| Export create/status/download | `page_parity_api.dart:341–389`; `merchant_crm_export.dart`; `merchant_customer_page.dart:828–950` |
| Invitation acceptance and operator receipt | `merchant_operator_api.dart`; `merchant_operator.dart`; `merchant_operator_page.dart:422–443`; `app_router.dart:237–241,748–755` |
| Image selection/upload | `merchant_aftercare_detail_page.dart:848–855`; `merchant_aftercare_api.dart:uploadEvidence`; existing native `MerchantAftercareEvidenceAdapter` |
| Source client error assumptions | `merchant_operator_page.dart:201–207`; API envelope decoders in merchant operator/customer/aftercare/review wrappers |

GETs remain GETs. Empty JSON status/dispatch bodies remain `{}`. Contact has only purpose in JSON. Export empty keyword and all-segment become null; list semantics are not mistakenly reused. Campaign preview has only segmentId/channel, including for coupon campaigns. The source does not put requestId on dispatch/retry/contact/download, so this extension does not invent one.

## Authorization, privacy and interruption behavior

1. Each normal read obtains fresh access/me. CRM read, segment, export, sensitive-read, marketing-write, coupon-manage and aftercare-evidence permissions stay separate. Coupon campaigns require both marketing and coupon grants
2. A frozen review captures the account/realm/epoch, exact store and permissions, selected server records, relevant source task/version projection, audience counts and immutable content. Confirmation fetches the same evidence again. Any drift prevents dispatch and requires another review
3. Backend mutation transport, export download, device contact actions, Files export, photo-library selection and camera selection have separate default-off gates. No production URLSession is constructed for actions
4. The integrated journal is reserved before dispatch. It persists only realm/account/store/target/request ID. It never stores invitation/download tokens, phone numbers, draft content, image bytes or downloaded workbooks
5. After a dispatch begins, a status code alone cannot prove there was no effect. 4xx, 5xx, 408, 429, malformed receipts, timeout, cancellation and stale-session completions retain the lock. Only a typed local disabled-before-transport result can clear an unsent reservation. Successful correlated receipts clear their exact intent
6. Permission/auth failures during fresh preflight occur before reservation and before any mutation. These are safely unsent. Source client code clears generic 4xx, but no inspected wrapper establishes server pre-effect guarantees; the native repair deliberately does not assume rollback
7. Known export tasks are persisted separately without download credentials. After reopening, status can resume, but a one-time token cannot be recovered from status. A running export blocks another creation. The token is never placed in a URL, path or log
8. Contact responses are scoped and consumed once. Consumption rechecks the account/store and permission; a failed device action cannot reuse that response. Clipboard delivery, when separately enabled by the host, is local-only with a short expiry; phone URLs accept only dialable characters
9. Images are bound to the selection account/store/session before upload. Late picker results cannot leak into a newer session. The 20 MiB image ceiling is a native memory budget, not a claimed backend limit
10. Explicit source unknown states and missing campaign counts stay unknown. Missing preview counts never become invented zero recipients. Broadcast required counts are strict. No client recipient sum or financial calculation is added

## Files and integration

The package has additive `Core`, `App`, `Tests/CoreTests`, `Tests/AppUITests`, a 130-key bilingual UI localization fragment and one bilingual camera-purpose InfoPlist fragment, advisory checks and an isolated repair patch. Do not copy `repairs` as additional compilation sources: those are replacements/diffs for existing files.

### 1. Apply the unknown-outcome repair

`repairs/merchant-unknown-outcome.patch` updates:

- `Core/MerchantBusinessCoordinator.swift`
- `Core/MerchantRedemptionContext.swift` (the same post-dispatch auth/permission unlock defect)
- `Tests/CoreTests/MerchantBusinessServiceTests.swift` (changes one unsafe expectation; adds five stage-sensitive tests)

`repairs/base-hashes.json` identifies the exact inspected main bytes. `git apply --check` passed against that snapshot. Apply only after checking current hashes/reconciling concurrent edits. The new shared `Core/MerchantMutationFailureDisposition.swift` must be copied before compiling either repaired coordinator.

### 2. Copy additive source and merge localization

Copy the top-level `Core/*.swift`, `App/*.swift`, and new test files into main. Merge `Resources/MerchantEngagementLocalizations.fragment.json` into the existing Localizable.xcstrings `strings` map; do not replace unrelated entries. All new names use MerchantEngagement/CRM/Campaign/Export-specific types and reuse the existing MerchantBusiness value/access/session/journal primitives.

### 3. AppSession factory

Alongside the current MerchantBusiness properties:

```swift
private let merchantEngagementService: MerchantEngagementService?
lazy var merchantEngagementReader = MerchantEngagementSessionReader(
    service: merchantEngagementService,
    session: { [weak self] in self?.currentMerchantBusinessSession },
    onUnauthorized: { [weak self] captured in
        guard let self, self.currentMerchantBusinessSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }
)
lazy var merchantExportRecovery = MerchantExportFileRecoveryStore(
    url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/export-tasks-v1.json")
)
```

Initialize `MerchantEngagementService(configuration: configuration, readTransport: transport)` only inside the existing approved configuration branch; set nil in its unconfigured branch. Do not inject testingActionTransport into the normal factory. Preserve the existing regional storage prefix.

### 4. Reachable native workspace

Pass the engagement reader/recovery store from AccountView through MerchantHomeView, preserving all existing optional parameters. Add an entry next to the current business workspace:

```swift
MerchantEngagementHomeView(
    reader: session.merchantEngagementReader,
    journal: session.merchantBusinessJournal,
    exportRecovery: session.merchantExportRecovery,
    businessReader: session.merchantBusinessReader
)
.id(session.merchantEngagementReader.scope)
```

For a context-specific CRM entry, supply `filter: MerchantCRMFilter(customerQuery: currentQuery)`. Saved-segment application can open the existing MerchantBusinessPage with the exact filter. Contact/evidence screens also accept explicit IDs and fetch the source detail before review; never turn an operator, ticket, owner or merchant row ID into a customer/refund ID.

The current main camera-purpose string mentions QR scanning only. Before enabling evidence camera capture, merge `Resources/MerchantEngagementInfoPlist.fragment.json` into InfoPlist.xcstrings and align `INFOPLIST_KEY_NSCameraUsageDescription` in Base.xcconfig with its English value. This preserves the existing scan purpose and adds the user-chosen evidence-photo purpose without enabling permissions.

The normal host deliberately supplies no contactDelivery adapter and keeps device/photo/camera/file-export grants false. Native provider implementations exist; enabling them is a separate approved runtime/platform decision, not part of this merge.

### 5. Incoming invitations and aftercare evidence

The source route is exactly `/merchant/team` with one nonempty `invite` query parameter. The parent platform router must first validate its supported scheme and host; pass only that approved route to `MerchantOperatorInviteRoute`. Present `MerchantOperatorInvitationLandingView`, including the existing sign-in callback and the same journal/recovery store. Keep the view's invitation in memory through sign-in. Parsing or login does not authorize acceptance; an explicit frozen review is still required.

After an evidence-upload receipt, call `takeEvidenceForResponse(refundID:scope:merchantID:)` from the receiving form's fresh context. This one-use helper checks the exact refund, store, account/realm/epoch and clears the receipt when consumed. Use its objectKey to populate the existing aftercare form. The extension does not automatically append a response or issue a refund. A new aftercare response review remains required. The current hub exposes the receipt as a local result so it is usable without modifying existing editor ownership; a parent callback can connect it directly.

### 6. DEBUG host and project generation

Add `--uitesting-merchant-engagement-fixture` → `MerchantEngagementFixtureHostView()` to the DEBUG app root and the same flag to AppSessionContainer's no-production-session fixture guard. Scenarios: ready, disabled, denied, inactive, unknown, sessionChange. The fake transport executes the same URLRequest/decoder paths and never uses network. The XLSX fake is a structurally valid seven-row synthetic masked workbook.

Regenerate the Xcode project with the repository generator, then run Swift package tests, unsigned app builds and the new UI suite on Apple infrastructure. Also rerun existing MerchantBusiness/operations/scanner/OrderLifecycle suites and the five changed journal-stage tests.

## Verification status

- 18 offline Python source/privacy/localization/fixture checks: PASS
- 23 Swift files including three isolated repaired replacements: Tree-sitter PASS, zero recovery diagnostics
- Repair patch `git apply --check` against inspected main: PASS
- New Swift core/UI test counts are authored inventory only; see verification manifest
- Swift typecheck, package tests, Xcode, simulator, native Files/Photos/camera/contact runtime: NOT_RUN
- Backend/provider/remote actions: NOT_RUN; no such operations were attempted

## Unsupported source contracts and remaining acceptance gates

- The source has no invitation store/role preview endpoint. The review explicitly says the destination and assigned role cannot be looked up beforehand. It never guesses merchant identity from the accepted operator ID
- The source has no export-token refresh/recovery endpoint. Lost one-time credentials cannot be regenerated locally; persisted status is still useful
- The source has no operation-outcome query for unknown segment/broadcast/contact/upload writes, nor a correlation contract proving a later list state belongs to that attempt. Locks remain conservative; no expiry, silent resend or fabricated terminal receipt is added
- Native authorization strings, entitlements, camera availability, VoiceOver, Dynamic Type, image rendering and actual provider behavior still require the Apple runtime matrix. Photos and camera remain disabled in the standard host
- Contact, export and image data are not automatically shared, sent to a third party, logged or retained beyond scoped UI memory. This code does not itself grant real messaging/export/membership/upload permissions
- This extension closes the previously documented client-code gap for these verified contracts. It does not claim publication, Apple compilation, production enablement or real-world end-to-end validation
