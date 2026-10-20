import XCTest
@testable import QuestifyCore

final class MerchantAndPublishAuthoringAuditTests: XCTestCase {

    func testStoryEndingBooleanOnlyFallbackEnforcement() {
        let validEndings: [MerchantAndPublishAuthoringAudit.StoryEndingAuditItem] = [
            .init(chapterID: 101, fallbackValue: .bool(true), whenConditionCount: 0),
            .init(chapterID: 102, fallbackValue: .bool(false), whenConditionCount: 2)
        ]
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditStoryEndings(validEndings),
            .valid(endingCount: 2, fallbackChapterID: 101)
        )

        // String, integer, and null fallback values must be strictly rejected (I03 & w2-11/13)
        let stringFallback: [MerchantAndPublishAuthoringAudit.StoryEndingAuditItem] = [
            .init(chapterID: 201, fallbackValue: .string("true"), whenConditionCount: 0)
        ]
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditStoryEndings(stringFallback),
            .rejectedNonBooleanFallback(chapterID: 201, actualValue: .string("true"))
        )

        let numberFallback: [MerchantAndPublishAuthoringAudit.StoryEndingAuditItem] = [
            .init(chapterID: 202, fallbackValue: .int(1), whenConditionCount: 0)
        ]
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditStoryEndings(numberFallback),
            .rejectedNonBooleanFallback(chapterID: 202, actualValue: .int(1))
        )

        let nullFallback: [MerchantAndPublishAuthoringAudit.StoryEndingAuditItem] = [
            .init(chapterID: 203, fallbackValue: .null, whenConditionCount: 1)
        ]
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditStoryEndings(nullFallback),
            .rejectedNonBooleanFallback(chapterID: 203, actualValue: .null)
        )
    }

    func testMerchantStoreParityAndInStoreGameAuthoringPillars() {
        let compliantSnapshot = MerchantAndPublishAuthoringAudit.MerchantStoreParitySnapshot()
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditMerchantStoreParity(compliantSnapshot),
            .compliant
        )

        let missingInsightKeySnapshot = MerchantAndPublishAuthoringAudit.MerchantStoreParitySnapshot(
            insightTopLevelKeys: ["exposureCount", "checkInCount"]
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditMerchantStoreParity(missingInsightKeySnapshot),
            .missingInsightTopLevelKeys(missing: ["conversionRate", "repeatVisitRate", "couponRedemptionCount"])
        )

        let validGameInput = MerchantAndPublishAuthoringAudit.InStoreGameAuthoringAuditInput(
            completedParts: MerchantAndPublishAuthoringAudit.InStoreGameAuthoringPart.allCases,
            maxParticipants: 24,
            canonicalSkuID: "SKU-MERCHANT-GAME-01",
            merchantStoreApproved: true,
            contentSafetyApproved: true
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditInStoreGameAuthoring(validGameInput),
            .readyForPublish(boundSkuID: "SKU-MERCHANT-GAME-01", maxParticipants: 24)
        )

        let unapprovedGameInput = MerchantAndPublishAuthoringAudit.InStoreGameAuthoringAuditInput(
            completedParts: MerchantAndPublishAuthoringAudit.InStoreGameAuthoringPart.allCases,
            maxParticipants: 24,
            canonicalSkuID: "SKU-MERCHANT-GAME-01",
            merchantStoreApproved: true,
            contentSafetyApproved: false
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditInStoreGameAuthoring(unapprovedGameInput),
            .pendingDualDomainApproval(merchantStoreApproved: true, contentSafetyApproved: false)
        )
    }

    func testPublishMediaEditorCrossOwnerRefusalAndPipelineValidation() {
        let crossOwnerInput = MerchantAndPublishAuthoringAudit.PublishMediaEditorAuditInput(
            resourceOwnerDomain: .merchant,
            resourceOwnerID: 8801,
            resourceWorldID: "world-hangzhou",
            actorOwnerDomain: .creator,
            actorOwnerID: 8801,
            actorWorldID: "world-hangzhou"
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditPublishMediaEditor(crossOwnerInput),
            .crossOwnerEditRefused(
                expectedDomain: .merchant,
                expectedOwnerID: 8801,
                actualDomain: .creator,
                actualOwnerID: 8801
            )
        )

        let crossWorldInput = MerchantAndPublishAuthoringAudit.PublishMediaEditorAuditInput(
            resourceOwnerDomain: .club,
            resourceOwnerID: 310,
            resourceWorldID: "world-shanghai",
            actorOwnerDomain: .club,
            actorOwnerID: 310,
            actorWorldID: "world-beijing"
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditPublishMediaEditor(crossWorldInput),
            .crossWorldEditRefused(expectedWorldID: "world-shanghai", actualWorldID: "world-beijing")
        )

        let missingPosterVideoInput = MerchantAndPublishAuthoringAudit.PublishMediaEditorAuditInput(
            resourceOwnerDomain: .creator,
            resourceOwnerID: 501,
            resourceWorldID: "world-shanghai",
            actorOwnerDomain: .creator,
            actorOwnerID: 501,
            actorWorldID: "world-shanghai",
            hasVideoAttachment: true,
            videoPosterURL: nil
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditPublishMediaEditor(missingPosterVideoInput),
            .missingVideoPoster
        )

        let validVideoInput = MerchantAndPublishAuthoringAudit.PublishMediaEditorAuditInput(
            resourceOwnerDomain: .creator,
            resourceOwnerID: 501,
            resourceWorldID: "world-shanghai",
            actorOwnerDomain: .creator,
            actorOwnerID: 501,
            actorWorldID: "world-shanghai",
            hasVideoAttachment: true,
            videoPosterURL: "https://cdn.questify.com/posters/501.jpg"
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditPublishMediaEditor(validVideoInput),
            .authorizedAndValidated
        )
    }

    func testWorkshopModUpgradeH5DesignOnlyGuardAndActiveRunIsolation() {
        let executableH5Input = MerchantAndPublishAuthoringAudit.WorkshopModUpgradeAuditInput(
            activeRunPinnedVersion: "1.2.0",
            candidateUpgradeVersion: "1.3.0",
            mutatesActiveRunInPlace: false,
            isH5Package: true,
            h5ContainsExecutableOrRuntimeScript: true,
            h5DesignAssetsOnly: false,
            explicitCreatorUpgradeConfirmation: true
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditWorkshopModUpgrade(executableH5Input),
            .h5DesignOnlyPackageGuardTriggered
        )

        let inPlaceMutationInput = MerchantAndPublishAuthoringAudit.WorkshopModUpgradeAuditInput(
            activeRunPinnedVersion: "1.2.0",
            candidateUpgradeVersion: "1.3.0",
            mutatesActiveRunInPlace: true
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditWorkshopModUpgrade(inPlaceMutationInput),
            .activeRunIsolationViolated(pinnedVersion: "1.2.0", candidateVersion: "1.3.0")
        )

        let unconfirmedUpgradeInput = MerchantAndPublishAuthoringAudit.WorkshopModUpgradeAuditInput(
            activeRunPinnedVersion: "1.2.0",
            candidateUpgradeVersion: "1.3.0",
            explicitCreatorUpgradeConfirmation: false
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditWorkshopModUpgrade(unconfirmedUpgradeInput),
            .explicitUpgradeConfirmationRequired
        )

        let validUpgradeInput = MerchantAndPublishAuthoringAudit.WorkshopModUpgradeAuditInput(
            activeRunPinnedVersion: "1.2.0",
            candidateUpgradeVersion: "1.3.0"
        )
        XCTAssertEqual(
            MerchantAndPublishAuthoringAudit.auditWorkshopModUpgrade(validUpgradeInput),
            .upgradeStagedSafely(pinnedActiveVersion: "1.2.0", stagedCandidateVersion: "1.3.0")
        )
    }

    func testFullAuthoringAuditReportAggregatesAllFivePillars() {
        let report = MerchantAndPublishAuthoringAudit.FullAuthoringAuditReport(
            storyEndingVerdict: MerchantAndPublishAuthoringAudit.auditStoryEndings([
                .init(chapterID: 10, fallbackValue: .bool(true), whenConditionCount: 0)
            ]),
            merchantStoreVerdict: MerchantAndPublishAuthoringAudit.auditMerchantStoreParity(.init()),
            inStoreGameVerdict: MerchantAndPublishAuthoringAudit.auditInStoreGameAuthoring(
                .init(
                    completedParts: MerchantAndPublishAuthoringAudit.InStoreGameAuthoringPart.allCases,
                    maxParticipants: 16,
                    canonicalSkuID: "SKU-STORE-16",
                    merchantStoreApproved: true,
                    contentSafetyApproved: true
                )
            ),
            publishMediaVerdict: MerchantAndPublishAuthoringAudit.auditPublishMediaEditor(
                .init(
                    resourceOwnerDomain: .merchant,
                    resourceOwnerID: 42,
                    resourceWorldID: "world-01",
                    actorOwnerDomain: .merchant,
                    actorOwnerID: 42,
                    actorWorldID: "world-01"
                )
            ),
            workshopModUpgradeVerdict: MerchantAndPublishAuthoringAudit.auditWorkshopModUpgrade(
                .init(activeRunPinnedVersion: "2.0.0", candidateUpgradeVersion: "2.1.0")
            )
        )
        XCTAssertTrue(report.allPillarsPassing)
    }
}
