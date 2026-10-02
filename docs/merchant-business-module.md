# MerchantBusiness native slice

## Delivery status

Additive isolated module. No shared `chengyin-ios` files were changed by this worker. No backend, remote, account, role, camera, messaging, refund or payment action was executed. All synthetic transports are offline fakes; production mutation and evidence-upload factories are disabled by default.

This is a broad, source-backed business workspace, not a claim that every merchant feature or real-world operation is complete. Apple compiler, Swift tests, simulator UI and device verification are **NOT_RUN** because Swift/Xcode are unavailable in this executor.

## Source-backed coverage

| Surface | Native implementation | Source |
|---|---|---|
| CRM customer directory | Search, all/repeat/new/noted segments, source type/date range, available-tag filter, explicit pages, server segment summary and selected-customer batch-tag form | `merchant_crm_console_api.dart`, `merchant_crm_console.dart` |
| Customer detail | Exact customer-member ID, system/store tags, visits/pending/refund counts, money withheld vs zero, chronological source timeline, local add/correct/hide note and assign/remove tag drafts | `merchant_customer_detail_api.dart`, `merchant_customer_detail.dart` |
| Aftercare list/detail | Source buckets, page consistency, exact refund ID, platform state separate from merchant opinion, source policy/deadline, append-only responses, AGREE/REJECT/EVIDENCE form | `merchant_aftercare_api.dart`, `merchant_aftercare.dart` |
| Merchant reviews | Management pages, ratings, content, images, immutable source status, explicit canReply/canReport/canEditReply gates, reply/edit/delete/report frozen forms | `merchant_review_api.dart`, `merchant_review.dart` |
| Finance | Five independent source overview amounts, adjustment count, redemption ledger, signed entry list, batch directory and exact batch detail with separate earnings/adjustments, redemption detail | `merchant_api.dart:348–373,720–736,880–962`, `merchant_ledger.dart`, `merchant_finance.dart` |
| Verification actions | Separate read contract from finance; never treated as a money ledger | `merchant_api.dart:824–845` |
| Operator team | Roles/permission descriptions, active/revoked members, pending/expired/revoked invites, invite/change-role/remove/revoke forms | `merchant_operator_api.dart`, `merchant_operator.dart` |
| Scanner | Local classification preview; typed legacy chapter and station-registration choices; executable synthetic flow including persistent unknown-result lock | `verification_scan.dart`, `scan_result.dart`, `merchant_scan_page.dart`, registration/activity/coupon/group-code API wrappers |
| Evidence upload | Exact dormant multipart `file` + `bizType=merchant_aftercare_evidence` adapter and top-level `fileName` object-key receipt | `merchant_aftercare_api.dart:uploadEvidence` |

### Exact injectable writes

`MerchantBusinessMutation.request` builds exact source JSON bodies for the source CRM, aftercare, review and operator action types. `MerchantBusinessService.execute` builds and sends URLRequest through an explicitly injected `MerchantBusinessTestTransport` and decodes source receipts. It is not a permanent not-sent placeholder. No production URLSession mutation transport is constructed.

- CRM: notes, notes/hide, tags, tags/remove, tags/batch
- Aftercare: respond with query `refundId`; JSON decision/content/optional evidenceKeys/requestId. This appends an opinion and does not execute a refund
- Reviews: reply, reply/update, reply/delete, manage/report. Source update/delete promises only an object response; correlation or a terminal receipt endpoint is not invented
- Operators: invite, role, remove, invite/revoke, preserving exact operator/invite ID and version. EXACT_RESULT requires next version; LATER_AUTHORITATIVE requires a later version and is not labeled as the original requested role succeeding
- Redemption: correct form endpoint for legacy ticket, dynamic ticket, coupon, group; second step chapterId vs registrationMerchantId stays typed. Needs-choice takes precedence over business error code and cannot be displayed as success
- Evidence: uploadOSS uses a separate default-disabled transport and validated object-key receipt. No automatic retry or native file-picker integration

## Safety and identity boundaries

1. Access must be active with positive merchant row ID, known merchant role, explicit permissions. Owner labels never substitute for permission bits. Operator management additionally requires the source `canManageOperators` bit
2. Finance entry/ledger surfaces use `merchant:finance:read`, matching the source home finance entry. Verification action records use the separate `merchant:verify:record:read`. Reviews do not get an invented review permission; source row capabilities decide available actions
3. Account ID, epoch and API realm are captured. Mutation confirmation stores the frozen access/document/role snapshot and exact request. A full fresh read must still match before reserving/sending
4. Customer IDs, refund IDs, review IDs, operator IDs, invite IDs, batch IDs, chapter IDs and registration-merchant IDs are distinct Swift wrappers. No ticket/member/owner ID is guessed into a merchant row ID
5. The journal is atomically persisted before send. It contains realm/account/store/target/request ID, never token, draft content, phone number, evidence bytes or scan code. Unknown results survive refresh, navigation, logout, process restart and new session epoch; they do not expire automatically
6. Success only clears the exact received operation. Explicit rejected/unauthorized/forbidden results may unlock. Timeout, cancellation, malformed response, post-dispatch stale session and journal failure remain uncertain. List resemblance never clears a lock. There is no invented reconciliation endpoint or retry affordance
7. Finance strings are retained, not summed, rounded through Double, or recalculated. Source explicitly identifies this merchant domain as CNY. Missing, zero, signed negative, no-cash reason, pending money, source net direction, and adjustment count remain separate. Display dates stay raw source strings because no source timezone was supplied
8. Scanner code bytes are memory-only, not Codable. UI offers a masked local route preview, no camera/scan permission/real dispatch. The synthetic coordinator binds choices to the exact response/session/store and blocks noncandidate choices. Group issuance remains in ClubGovernance; consumer pass issuance stays in OrderLifecycle

## Integration recipe (parent owns shared-file edits)

1. Copy additive `Core/*.swift`, `App/*.swift`, `Tests/CoreTests/*.swift`, `Tests/AppUITests/*.swift`, and this document into the corresponding folders in `chengyin-ios`
2. Merge the 278 entries from `Resources/MerchantBusinessLocalizations.fragment.json` into the existing `Localizable.xcstrings` `strings` map. Preserve unrelated catalog content. Do not replace the catalog wholesale
3. Add to `AppSession` beside MerchantOperations:

```swift
private let merchantBusinessService: MerchantBusinessService?
private var currentMerchantBusinessSession: MerchantBusinessSession? {
    guard let account, let token else { return nil }
    return try? MerchantBusinessSession(accountID: account.id, epoch: gate.currentStamp, token: token)
}
lazy var merchantBusinessReader = MerchantBusinessSessionReader(
    service: merchantBusinessService,
    currentSession: { [weak self] in self?.currentMerchantBusinessSession },
    onUnauthorized: { [weak self] captured in
        guard let self, self.currentMerchantBusinessSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }
)
lazy var merchantBusinessJournal = MerchantBusinessFileIntentStore(
    url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MerchantBusiness/intents-v1.json")
)
```

Initialize the service only inside the existing approved-configuration branch using `MerchantBusinessService(configuration: configuration, readTransport: transport)`. Set it to nil in the unconfigured branch. Never inject a testing mutation transport in this factory. The reader is unauthenticated when the captured session is nil.

4. Add optional `businessReader: (any MerchantBusinessReading)? = nil` and `businessJournal: (any MerchantBusinessIntentStore)? = nil` parameters to `MerchantHomeView`; forward them to its private workbench. Add the workspace NavigationLink when both exist:

```swift
NavigationLink {
    MerchantBusinessHomeView(reader: businessReader, journal: businessJournal)
        .id(businessReader.scope)
} label: {
    Label("merchant.business.title", systemImage: "building.2.crop.circle")
}
.accessibilityIdentifier("merchant.business.open")
```

The source identity/individual permission checks remain inside the business workspace. In `AccountView`'s existing MerchantHomeView call, pass `session.merchantBusinessReader` and `session.merchantBusinessJournal`. Old merchant fixtures continue to omit these optional arguments.

5. Add `--uitesting-merchant-business-fixture` routing to `MerchantBusinessFixtureHostView()` in the DEBUG root and include the same flag in `AppSessionContainer`'s fixture exclusion guard. The flag must never construct a production session. Supported scenarios: ready, denied, malformed, unknown, changedSession, disabled
6. Regenerate the Xcode project with the repository's `tools/generate_project.py` after copying. Package.swift auto-discovers Core/tests
7. Run Swift package tests, unsigned Xcode builds and the eight new UI tests on Apple infrastructure. Rerun the existing merchant/operations/order/club suites to check navigation and shared behavior

## Verification in this executor

- 14 offline Python source/fixture/localization checks: PASS
- 18 Swift files, Tree-sitter 0.26.0 / Swift grammar 0.7.3: PASS, zero recovery diagnostics
- Swift core test methods and UI test methods are authored inventory only; see verification manifest for counts
- Swift typechecking: NOT_RUN
- Swift package tests: NOT_RUN
- Xcode builds / simulator / accessibility runtime: NOT_RUN
- Live backend/provider/network/financial/role/redemption tests: NOT_RUN and not authorized/enabled in this slice

An initial advisory parser crash exposed a raw-string delimiter collision in a synthetic hex-color fixture. The fixture delimiter was corrected; all final files parse. A parser pass is not Apple compiler evidence.

## Remaining gaps and explicit limits

- No claim of full merchant parity: CRM saved-segment create/list, campaign/broadcast preview/create/dispatch/retry/history, export jobs, and audited contact reveal/call/copy are not implemented here. These remain separate CRM/marketing source work. No message is sent or number revealed
- Operator invite creation is implemented but token sharing and invite acceptance/deep-link enrollment are not integrated. No member permission is actually changed. This slice does not invent a public invitation lookup endpoint
- Evidence upload adapter exists but native selection, camera, credential-bound upload freshness and uploaded-object retention flow still need platform integration. Existing object-key entry is a local form only
- Reviewer source photos are read from their HTTPS source URLs; no review image creation/upload or public consumer review creation is included. Merchant review management is this module; consumer registration-based eligibility belongs in its own owner context
- Scanner routing/choice/receipt/mutation adapters are synthetic-only. UI does not activate camera or show a redeem button. No server nonce, operation lookup or idempotency header is fabricated
- Financial overview, entries and transfer batches are reads. No transfer, settlement execution, refund payment, arbitrary fees, receipt terminal endpoint, bank account or provider SDK is implemented
- Multi-device/operator concurrent changes are handled conservatively through fresh exact snapshots and server versions. Backend idempotency semantics and delayed-result reconciliation still require source-backed contracts and runtime evidence
- UI uses Dynamic Type-compatible native List/Form/Picker, explicit labels, masked scanner input and accessibility identifiers. Actual VoiceOver, large accessibility sizes, Reduce Motion, full visual layout and dismissal behavior still require Apple runtime validation
- The read adapter depends on the parent-approved backend/region/session configuration. Absence is reported; no production host is invented
