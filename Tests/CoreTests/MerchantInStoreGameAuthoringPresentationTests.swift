import XCTest
@testable import QuestifyCore

final class MerchantInStoreGameAuthoringPresentationTests: XCTestCase {
    private let sampleCatalog: [CanonicalSKUFact] = [
        CanonicalSKUFact(merchantID: "m1", skuID: "sku-latte", priceMinor: 3200, currency: "CNY"),
        CanonicalSKUFact(merchantID: "m2", skuID: "sku-other", priceMinor: 1800, currency: "CNY")
    ]

    private func completeGameDraft() -> InStoreGameDraft {
        var draft = InStoreGameDraft()
        draft.interactionTemplateID = "tpl-riddle"
        draft.durationMinutes = 15
        draft.maxParticipants = 4
        draft.businessHoursText = "10:00-21:00"
        draft.needsStaff = false
        draft.noiseAndFilmingLimits = "禁止闪光灯与喧哗"
        draft.accessibleAlternative = "吧台桌面解谜卡"
        draft.offlineFallback = "纸质线索信封"
        draft.failureExit = "可随时跳过并继续后续节点"
        draft.reward = .approvedRule(id: "rule-points-10")
        return draft
    }

    private func validProductDraft() -> MerchantProductDraft {
        MerchantProductDraft(
            merchantID: "m1",
            source: .canonical(skuID: "sku-latte"),
            claimedPriceMinor: 3200,
            claimedDiscountText: nil,
            createsThemeInventoryCopy: false
        )
    }

    private func approvedRevision(touchesTheme: Bool = true) -> MerchantAuthoringRevision {
        MerchantAuthoringRevision(
            draftID: "draft-101",
            version: 5,
            stage: .approved,
            authorID: "operator-1",
            contentHash: "hash-v5",
            touchesThemeContent: touchesTheme,
            merchantFactsApproval: MerchantAuthoringApproval(
                authority: .storeOwner,
                approverID: "store-owner-1",
                approvedHash: "hash-v5"
            ),
            themeContentApproval: touchesTheme ? MerchantAuthoringApproval(
                authority: .themeOwner,
                approverID: "theme-owner-1",
                approvedHash: "hash-v5"
            ) : nil
        )
    }

    func testDefaultGatesKeepPublishDisabledEvenWhenDraftsAndApprovalsPass() {
        let requestID = UUID()
        let presentation = MerchantInStoreGameAuthoringPresentation(
            revision: approvedRevision(),
            gameDraft: completeGameDraft(),
            approvedTemplates: ["tpl-riddle"],
            approvedRewardRules: ["rule-points-10"],
            productDraft: validProductDraft(),
            catalog: sampleCatalog,
            requestID: requestID,
            gates: .disabled
        )

        XCTAssertTrue(presentation.isGameDraftComplete)
        XCTAssertTrue(presentation.isProductDraftValid)
        XCTAssertFalse(presentation.isPublishGateEnabled)
        XCTAssertFalse(presentation.isReadyToPublish)
        XCTAssertNil(presentation.publishCommand)
        XCTAssertEqual(presentation.approvalBlockers.map(\.blocker), [.capabilityDisabled])
    }

    func testInStoreGameDraftReportsMissingOperationalFieldsAndUnapprovedRules() {
        var game = InStoreGameDraft()
        game.interactionTemplateID = "unapproved-tpl"
        game.durationMinutes = 0
        game.reward = .approvedRule(id: "unapproved-rule")

        var enabledGates = MerchantAICommerceGates.disabled
        enabledGates.merchantAuthoringPublish = true

        let presentation = MerchantInStoreGameAuthoringPresentation(
            revision: approvedRevision(),
            gameDraft: game,
            approvedTemplates: ["tpl-riddle"],
            approvedRewardRules: ["rule-points-10"],
            productDraft: validProductDraft(),
            catalog: sampleCatalog,
            requestID: UUID(),
            gates: enabledGates
        )

        XCTAssertFalse(presentation.isGameDraftComplete)
        XCTAssertEqual(presentation.missingGameFields.count, InStoreGameDraft.Field.allCases.count)
        XCTAssertTrue(presentation.gameChecklist.allSatisfy { !$0.isSatisfied })
        XCTAssertFalse(presentation.isReadyToPublish)
        XCTAssertNil(presentation.publishCommand)
    }

    func testProductDraftCanonicalSKUValidationFlagsPriceDiscountAndInventoryIssues() {
        let badProduct = MerchantProductDraft(
            merchantID: "m1",
            source: .canonical(skuID: "sku-latte"),
            claimedPriceMinor: 1990,
            claimedDiscountText: "限时半价",
            createsThemeInventoryCopy: true
        )

        var enabledGates = MerchantAICommerceGates.disabled
        enabledGates.merchantAuthoringPublish = true

        let presentation = MerchantInStoreGameAuthoringPresentation(
            revision: approvedRevision(),
            gameDraft: completeGameDraft(),
            approvedTemplates: ["tpl-riddle"],
            approvedRewardRules: ["rule-points-10"],
            productDraft: badProduct,
            catalog: sampleCatalog,
            approvedPromotionTexts: [],
            requestID: UUID(),
            gates: enabledGates
        )

        XCTAssertFalse(presentation.isProductDraftValid)
        XCTAssertEqual(
            presentation.productIssues.map(\.issue),
            [.priceClaimMismatch, .inventedDiscount, .duplicatesInventory]
        )
        XCTAssertFalse(presentation.isReadyToPublish)
        XCTAssertNil(presentation.publishCommand)
    }

    func testTwoDomainApprovalBlockersPreventSelfApprovalWrongAuthorityAndStaleHash() {
        let badRevision = MerchantAuthoringRevision(
            draftID: "draft-101",
            version: 5,
            stage: .approved,
            authorID: "operator-1",
            contentHash: "hash-v5-edited",
            touchesThemeContent: true,
            merchantFactsApproval: MerchantAuthoringApproval(
                authority: .themeOwner,
                approverID: "operator-1",
                approvedHash: "hash-v5"
            ),
            themeContentApproval: nil
        )

        var enabledGates = MerchantAICommerceGates.disabled
        enabledGates.merchantAuthoringPublish = true

        let presentation = MerchantInStoreGameAuthoringPresentation(
            revision: badRevision,
            gameDraft: completeGameDraft(),
            approvedTemplates: ["tpl-riddle"],
            approvedRewardRules: ["rule-points-10"],
            productDraft: validProductDraft(),
            catalog: sampleCatalog,
            requestID: UUID(),
            gates: enabledGates
        )

        XCTAssertEqual(
            presentation.approvalBlockers.map(\.blocker),
            [.wrongAuthority, .selfApproval, .editedAfterReview, .missingThemeApproval]
        )
        XCTAssertFalse(presentation.isReadyToPublish)
        XCTAssertNil(presentation.publishCommand)
    }

    func testIdempotentPublishCommandBuiltWhenAllChecksPassAndGateEnabled() {
        var enabledGates = MerchantAICommerceGates.disabled
        enabledGates.merchantAuthoringPublish = true
        let requestID = UUID()

        let presentation = MerchantInStoreGameAuthoringPresentation(
            revision: approvedRevision(touchesTheme: true),
            gameDraft: completeGameDraft(),
            approvedTemplates: ["tpl-riddle"],
            approvedRewardRules: ["rule-points-10"],
            productDraft: validProductDraft(),
            catalog: sampleCatalog,
            requestID: requestID,
            gates: enabledGates
        )

        XCTAssertTrue(presentation.isReadyToPublish)
        XCTAssertEqual(presentation.publishCommand?.kind, .publish)
        XCTAssertEqual(presentation.publishCommand?.requestID, requestID)
        XCTAssertEqual(presentation.publishCommand?.draftID, "draft-101")
        XCTAssertEqual(presentation.publishCommand?.expectedVersion, 5)
        XCTAssertEqual(presentation.publishCommand?.reviewedHash, "hash-v5")
    }
}
