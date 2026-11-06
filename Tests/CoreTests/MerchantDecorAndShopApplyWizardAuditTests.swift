import XCTest
@testable import QuestifyCore

final class MerchantDecorAndShopApplyWizardAuditTests: XCTestCase {
    func testDefaultEvaluationPassesPOIDetailDecorSaveShopApplyAndTopLevelReadbacks() {
        let report = MerchantDecorAndShopApplyWizardAudit.evaluate()

        XCTAssertTrue(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.isEmpty)
        XCTAssertEqual(MerchantDecorAndShopApplyWizardAudit.poiDetailEndpointPath, "/api/merchant/poi/detail")
        XCTAssertEqual(MerchantDecorAndShopApplyWizardAudit.decorSaveEndpointPath, "/api/merchant/decor/save")
        XCTAssertEqual(MerchantDecorAndShopApplyWizardAudit.shopApplyEndpointPath, "/api/merchant/shop/apply")
        XCTAssertEqual(MerchantDecorAndShopApplyWizardAudit.npcVoiceStatusEndpointPath, "/api/merchant/npc/voice/status")
        XCTAssertEqual(MerchantDecorAndShopApplyWizardAudit.merchantInsightEndpointPath, "/api/merchant/insight")
    }

    func testDecorSaveRequiresApplicationJSONContentTypeAndFailClosedWriteGate() {
        let formURLEncodedDecor = MerchantDecorAndShopApplyWizardAudit.DecorSaveContractAudit(
            contentTypeHeader: "application/x-www-form-urlencoded",
            encodesCanonicalJSONBody: false,
            defaultWriteGateFailClosed: false,
            requiresExplicitReviewBeforeSubmit: true
        )
        let report = MerchantDecorAndShopApplyWizardAudit.evaluate(decorSave: formURLEncodedDecor)

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.decorSaveContentTypeNotJSON))
        XCTAssertTrue(report.blockerCodes.contains(.decorSaveWriteGateNotFailClosedByDefault))
    }

    func testShopApplyFourStepWizardOrderAndFailClosedWriteGateEnforcement() {
        XCTAssertEqual(
            MerchantDecorAndShopApplyWizardAudit.orderedShopApplyWizardSteps.map(\.rawValue),
            ["basicInfo", "licenseAndQualification", "storeLocationAndPhotos", "reviewAndSubmit"]
        )

        let skippedLicenseStep = MerchantDecorAndShopApplyWizardAudit.ShopApplyWizardAudit(
            validatedSteps: [.basicInfo, .storeLocationAndPhotos, .reviewAndSubmit],
            validatesEachStepBeforeAdvancing: true,
            defaultWriteGateFailClosed: false,
            resolvesUnknownOutcomeViaReadback: false
        )
        let report = MerchantDecorAndShopApplyWizardAudit.evaluate(shopApplyWizard: skippedLicenseStep)

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.shopApplyWizardStepsIncompleteOrOutOfOrder))
        XCTAssertTrue(report.blockerCodes.contains(.shopApplyWriteGateNotFailClosedByDefault))
    }

    func testPOIDetailVoiceStatusAndMerchantInsightTopLevelReadbackEnforcement() {
        let brokenPOI = MerchantDecorAndShopApplyWizardAudit.POIDetailReadbackAudit(
            decodedKeys: ["poiId", "name"],
            preservesServerStatusWithoutLocalGuess: false
        )
        let brokenVoiceAndInsight = MerchantDecorAndShopApplyWizardAudit.VoiceAndInsightReadbackAudit(
            voiceStatusTopLevelKeys: ["status"],
            insightTopLevelKeys: ["exposureCount"]
        )
        let report = MerchantDecorAndShopApplyWizardAudit.evaluate(
            poiDetail: brokenPOI,
            voiceAndInsight: brokenVoiceAndInsight
        )

        XCTAssertFalse(report.isCompliant)
        XCTAssertTrue(report.blockerCodes.contains(.poiDetailReadbackInvalid))
        XCTAssertTrue(report.blockerCodes.contains(.npcVoiceStatusTopLevelReadbackInvalid))
        XCTAssertTrue(report.blockerCodes.contains(.merchantInsightTopLevelReadbackInvalid))
    }
}
