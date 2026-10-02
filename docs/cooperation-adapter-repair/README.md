# Protected cooperation adapter repair

## Result and boundary

The five source-backed operations now have an executable injected HTTPTransport path: invite, handle, contact, complaint and enrollOffer. Execution requires global dormant enablement **and** an explicit grant for that operation bound to the exact APIConfiguration base URL **and** a transport explicitly conforming to CoopFlowOfflineHTTPTransport. The marker documents an offline injection contract; it is not a security sandbox and must never be added to a real networking transport. There is no production activation in this patch.

The normal reviewed route is CoopFlowCoordinator.prepare → display the exact immutable request, current authoritative baseline and consequences → explicit confirmation → confirm. It still requires its own default-false enablement, a matching account/token/epoch, a review no older than 120 seconds, a second authoritative permission read and unchanged baseline. Protected executors without an endpoint scope fail closed. Scoped review equality is checked before and after suspensions and after dispatch.

The existing CoopFlowSourceEvidenceReader continues to supply source list/complaint evidence for handle/contact/complaint. Invite and enrollOffer still require an explicitly injected audited authoritative reader: missing additional evidence remains denied. An operation grant does not invent invitation authority, offer terms, membership, legal acceptance, complaint allegations or financial authorization. In particular, retain source-selected chapter termsMode; do not derive it from user-entered fields. Only synthetic fixtures are used in the new tests. Any future real execution requires separate authorized product/security/legal review and a separate implementation decision; this packet is not that approval.

Persistent unknown-outcome keys now include endpoint plus account and resource, never epoch, token, free text or money. Old unscoped keys are still checked, so installing this repair cannot clear a previous ambiguous attempt. Journal acquisition remains before send; timeout, cancellation, malformed responses, business rejection, unauthorized response and account/scope changes retain the lock. Success alone clears it. No automatic retry or invented receipt endpoint was added.

## Wire contract

All five use JSON POST, existing raw Authorization token semantics and the existing field validation/serialization:

- invite: api/coop/invite; inviteType/toType/toId/topicId/shareMode/message, applicable fixedFee/originApplyId/scope. Merchant toId stays memberId, not merchantId
- handle: api/coop/handle; id/status; cancellation uses message, accept/reject use handleReason
- contact: api/coop/contact; id; requires positive numeric integral conversationId before acknowledging success
- complaint: api/coop/complaint/report; only topicId/reason; no client-selected fault/payment fields
- enrollOffer: api/coop/offer/enroll; source-selected chapterId/termsMode and mode-specific fields, existing stripping of server-owned fields

Invite and handle accept source void acknowledgements after HTTP/code success. Complaint and enrollment require an object data acknowledgement but do not invent ID fields. Contact missing/zero/string/fractional conversation IDs are ambiguous. Server message strings are preserved; HTTP 401 is recognized even if its response is not JSON.

Source: app-audit/lib/data/api/coop_api.dart lines 133–173, 296–322, 395–421, 458–479; offer form provenance app-audit/lib/feature/merchant/merchant_recruit_sheets.dart lines 582 onward. No financial deposit/refund execution was added.

## Additive integration (parent-owned)

1. Read manifest.json and compare both replaced Core files against their recorded base SHA-256. If either changed, apply only the corresponding reviewed diff hunks from repair.patch; do not overwrite unrelated concurrent edits
2. Add Core/CooperationProtectedDispatch.swift, Tests/CoreTests/CooperationProtectedDispatchTests.swift, tools/check_cooperation_protected_dispatch.py and this docs/cooperation-adapter-repair directory
3. Apply the narrow service/coordinator changes. No AppSession, navigation, UI, localization, project.yml, capability or runtime-factory changes are needed. Existing App factories get nil grants and false write enablement from unchanged defaults
4. Ensure new Core and test sources are included by existing Core/Tests source-directory discovery. Do not create duplicate Xcode file references if directory discovery already handles them
5. Run the new static checker and the existing tools/check_cooperation_flows.py. Run supplementary Swift syntax checking against final integrated bytes
6. On an Apple toolchain, run swift test --filter Cooperation and the repository's normal native build/test gates. XCTest code is authored but NOT_RUN here. Do not report typechecking, compilation or runtime coverage based on the Python or Tree-sitter checks

## Verification

33 static source checks PASS. Four changed/new Swift files have zero Tree-sitter recovery diagnostics (tree-sitter 0.26.0, tree-sitter-swift 0.7.3). This is supplementary parsing only. Swift compiler absent in this environment: Swift compilation, XCTest execution and Apple runtime NOT_RUN. External network actions: zero. Shared chengyin-ios files unchanged by this isolated repair.

Authored tests cover all five exact requests through coordinator plus fake HTTP transport, individual grants, global/default gates, missing marker, endpoint mismatch/swap, fresh-evidence conflict, permission loss, account/epoch changes, post-send session invalidation, persistent unknown locks across relaunch/epoch, cross-account isolation, legacy lock migration, source business messages, HTTP/body unauthorized responses, malformed data, strict contact acknowledgement, void acknowledgements and duplicate confirmation.
