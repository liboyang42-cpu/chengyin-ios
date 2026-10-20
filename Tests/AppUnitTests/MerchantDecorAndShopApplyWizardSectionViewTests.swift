import XCTest
import SwiftUI
@testable import QuestifyApp
import QuestifyCore

@MainActor
final class MerchantDecorAndShopApplyWizardSectionViewTests: XCTestCase {

    func testDefaultSnapshotAndViewInstantiation() {
        let snapshot = MerchantDecorAndShopApplySnapshot()
        XCTAssertTrue(snapshot.isDecorJsonCompliant)
        XCTAssertTrue(snapshot.isFourStepWizardComplete)
        XCTAssertTrue(snapshot.hasAllCanonicalInsightKeys)
        XCTAssertTrue(snapshot.isFullyCompliant)
        XCTAssertEqual(snapshot.wizardSteps.count, 4)

        let view = MerchantDecorAndShopApplyWizardSectionView(snapshot: snapshot)
        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body
    }

    func testStepRowStatesAndFourStepWizardValidation() {
        let completedStep = MerchantParityStepRow(
            id: "s1",
            stepIndex: 1,
            stepCode: "BASIC_INFO",
            title: "基础门店信息",
            summary: "门店名称与坐标校验",
            state: .completed
        )
        let activeStep = MerchantParityStepRow(
            id: "s2",
            stepIndex: 2,
            stepCode: "QUALIFICATION_LICENSE",
            title: "资质核验",
            summary: "营业执照上传",
            state: .active
        )
        let pendingStep = MerchantParityStepRow(
            id: "s3",
            stepIndex: 3,
            stepCode: "STOREFRONT_MEDIA",
            title: "门头实景",
            summary: "门头封面上传",
            state: .pending
        )

        XCTAssertEqual(completedStep.statusBadgeText, "已完成")
        XCTAssertEqual(activeStep.statusBadgeText, "进行中")
        XCTAssertEqual(pendingStep.statusBadgeText, "待填写")

        let incompleteWizardSnapshot = MerchantDecorAndShopApplySnapshot(
            wizardSteps: [completedStep, activeStep, pendingStep]
        )
        XCTAssertFalse(incompleteWizardSnapshot.isFourStepWizardComplete)
        XCTAssertFalse(incompleteWizardSnapshot.isFullyCompliant)
    }

    func testDecorJsonAndInsightKeysComplianceDetection() {
        let nonJsonDecorSnapshot = MerchantDecorAndShopApplySnapshot(
            decorSaveContentType: "application/x-www-form-urlencoded",
            decorSaveJsonPreview: "merchantId=8801&decorConfig=CYBER"
        )
        XCTAssertFalse(nonJsonDecorSnapshot.isDecorJsonCompliant)
        XCTAssertFalse(nonJsonDecorSnapshot.isFullyCompliant)

        let missingInsightSnapshot = MerchantDecorAndShopApplySnapshot(
            insightTopLevelKeys: ["exposureCount", "checkInCount"]
        )
        XCTAssertFalse(missingInsightSnapshot.hasAllCanonicalInsightKeys)
        XCTAssertFalse(missingInsightSnapshot.isFullyCompliant)

        let view = MerchantDecorAndShopApplyWizardSectionView(snapshot: missingInsightSnapshot)
        _ = view.body
    }
}
