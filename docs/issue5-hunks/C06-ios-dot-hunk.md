# C06-ios shared hunk for dot

Exclusive owner: Cursor C06-ios (`cursor/c06-merchant-npc-draft-publish-43c4`).
Base: `migration/native-ios` @ `76ce1b313af2595f9b7d7ace49040866209c7974`.
This file is the only shared hunk. Do not treat it as authorization to edit AppSession / pbxproj / Localizable / original writers from the Cursor line.

## Why this hunk exists

New Core types are SwiftPM-visible (`Package.swift` `path: "Core"`). Xcode `check_scaffold.py` still requires every `Core/*.swift` file to be listed in `Questify.xcodeproj/project.pbxproj`. C06 must not edit that project file.

## Dot-owned integration (do not apply from this PR)

1. **pbxproj** — from this SHA, run `python3 tools/generate_project.py` so these new sources join the Questify target:
   - `Core/MerchantNPCDraftApprovalGate.swift`
   - `Core/MerchantNPCPublicPrivateIsolation.swift`
   - `Core/MerchantNPCQualificationRevoke.swift`
   CoreTests are SwiftPM-only (`Tests/CoreTests`); they are not Xcode app-unit sources.

2. **Original review/publish writer** — `MerchantNPCOriginalReviewPublishing` is the exclusive C06 consumer seam. Default `MerchantNPCWaitingSourcePublisher` throws `WAITING_SOURCE` for:
   - `MerchantNpcKnowledgeDraftService.http`
   - `MerchantNpcKnowledgeReviewAuthority.route`
   Do not invent those routes here. When the original writer exists, inject it behind this protocol. Do not let C06 own order/publish writers.

3. **AppSession / composition** — do not wire C06 into `AppSession` from this candidate. Public player consume still uses existing `/api/ai/npc/merchant-chat` after a published revision is present. Theme mainline must remain available when NPC AI grants are off.

4. **AiGateway public auth** — not added. `MerchantNPCHTTPClient.refuseAiGatewayPublicAuth()` is a typed `WAITING_SOURCE` refusal.

5. **Localizable.xcstrings** — not edited. Gate `messageKey` values (`merchantNPC.draft.*`) wait for a later fragment; do not merge them into the shared catalog from this hunk until copy is approved.

## C06 already landed (do not rewrite)

- Gap-fill: `MerchantNPCKnowledgeDraft.swift`, `MerchantNPCKnowledgeValidation.swift`, `MerchantNPCCoordinators.swift`, `MerchantNPCHTTP.swift`
- Exclusive path: draft approval gate, public/private isolation, qualification revoke
- AI can only produce DRAFT; live price/stock/award/presence always refuse
- Missing knowledge review/publish API = `WAITING_SOURCE`, not a successful stub
- Revoke clears public/private caches so an old draft cannot serve

## Verification note

Linux: Python contract `Tests/ContractChecks/test_merchant_npc_draft_cannot_price.py`.
Swift XCTest: authored, **NOT_RUN** on Linux.
