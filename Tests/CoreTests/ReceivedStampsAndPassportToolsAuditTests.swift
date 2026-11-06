import XCTest
@testable import QuestifyCore

final class ReceivedStampsAndPassportToolsAuditTests: XCTestCase {

    func testReceivedStampsExactGrantAndModerationFiltering() {
        let rows: [ReceivedStampsAndPassportToolsAudit.StampRowCandidate] = [
            .init(id: 101, isVisible: true),
            .init(id: 102, isVisible: false),
            .init(id: 103, isVisible: true)
        ]
        let compliant = ReceivedStampsAndPassportToolsAudit.auditReceivedStampReadback(
            grantedPaths: ["api/roam/stamp/received"],
            pageSize: 20,
            activeAccountID: 88,
            replyAccountID: 88,
            activeEpoch: 3,
            replyEpoch: 3,
            rawRows: rows
        )
        XCTAssertTrue(compliant.isCompliant)
        XCTAssertTrue(compliant.isGrantExact)
        XCTAssertTrue(compliant.isAccountFenceIntact)
        XCTAssertEqual(compliant.visibleStampIDs, [101, 103])

        // Album route `api/roam/stamp/list` cannot satisfy `api/roam/stamp/received`
        let wrongGrant = ReceivedStampsAndPassportToolsAudit.auditReceivedStampReadback(
            grantedPaths: ["api/roam/stamp/list", "api/roam/stamp/received"],
            pageSize: 55,
            activeAccountID: 88,
            replyAccountID: 88,
            rawRows: [.init(id: 10, isVisible: true), .init(id: 10, isVisible: true)]
        )
        XCTAssertFalse(wrongGrant.isGrantExact)
        XCTAssertFalse(wrongGrant.isCompliant)
        XCTAssertTrue(
            wrongGrant.violations.contains(
                .invalidReceivedStampGrantPaths(["api/roam/stamp/list", "api/roam/stamp/received"])
            )
        )
        XCTAssertTrue(wrongGrant.violations.contains(.invalidReceivedStampPageSize(55)))
        XCTAssertTrue(wrongGrant.violations.contains(.duplicateOrNonPositiveStampIDs([10])))
    }

    func testAccountAndEpochFenceIsolationRejectsCrossAccountStampReply() {
        let staleReply = ReceivedStampsAndPassportToolsAudit.auditReceivedStampReadback(
            activeAccountID: 88,
            replyAccountID: 99,
            activeEpoch: 4,
            replyEpoch: 3,
            rawRows: [.init(id: 501, isVisible: true)]
        )
        // Default behavior retires cross-account/stale-epoch replies so displayedStampIDs is empty
        XCTAssertFalse(staleReply.isAccountFenceIntact)
        XCTAssertTrue(staleReply.visibleStampIDs.isEmpty)
        XCTAssertTrue(staleReply.isCompliant)

        // If a broken caller leaks the foreign account's stamps into display, it is flagged as a violation
        let leakedReply = ReceivedStampsAndPassportToolsAudit.auditReceivedStampReadback(
            activeAccountID: 88,
            replyAccountID: 99,
            activeEpoch: 4,
            replyEpoch: 3,
            rawRows: [.init(id: 501, isVisible: true)],
            displayedStampIDs: [501]
        )
        XCTAssertFalse(leakedReply.isCompliant)
        XCTAssertEqual(
            leakedReply.violations,
            [
                .crossAccountOrEpochStampReadbackLeaked(
                    expectedAccountID: 88,
                    actualAccountID: 99,
                    expectedEpoch: 4,
                    actualEpoch: 3
                )
            ]
        )
    }

    func testAllFiveW209PassportPrivateToolsAreAccountedForAndDormantOnWrites() {
        let eval = ReceivedStampsAndPassportToolsAudit.auditPassportPrivateTools()
        XCTAssertTrue(eval.hasAllFiveTools)
        XCTAssertTrue(eval.isCompliant)
        XCTAssertEqual(
            eval.registeredToolSlugs,
            [
                "capsule",
                "exploration-goals",
                "exploration-export",
                "exploration-anniversary",
                "monthly-recap"
            ]
        )
        XCTAssertEqual(
            ReceivedStampsAndPassportToolsAudit.PassportPrivateTool.monthlyRecap.miniProgramSubpackagePath,
            "subpackageRoam/monthly-recap"
        )

        let incomplete = ReceivedStampsAndPassportToolsAudit.auditPassportPrivateTools(
            registeredToolSlugs: ["capsule", "exploration-goals"],
            toolsWithLiveMutationEnabled: ["capsule"]
        )
        XCTAssertFalse(incomplete.hasAllFiveTools)
        XCTAssertFalse(incomplete.isCompliant)
        XCTAssertEqual(
            incomplete.missingToolSlugs,
            ["exploration-export", "exploration-anniversary", "monthly-recap"]
        )
        XCTAssertTrue(
            incomplete.violations.contains(.liveMutationEnabledOnPassportPrivateTool(toolSlug: "capsule"))
        )
    }

    func testRoamPrivateToolsBilingualCatalogCompleteness() {
        let complete = ReceivedStampsAndPassportToolsAudit.auditRoamPrivateToolsCatalog(
            entries: [
                .init(key: "roam.private.capsule.title", english: "Time Capsule", simplifiedChinese: "时间胶囊"),
                .init(key: "roam.private.recap.title", english: "Monthly Recap", simplifiedChinese: "月度漫游回顾")
            ]
        )
        XCTAssertTrue(complete.isBilingualComplete)
        XCTAssertEqual(complete.tableName, "RoamPrivateTools")
        XCTAssertTrue(complete.incompleteKeys.isEmpty)

        let missingTranslation = ReceivedStampsAndPassportToolsAudit.auditRoamPrivateToolsCatalog(
            entries: [
                .init(key: "roam.private.goals.title", english: "Exploration Goals", simplifiedChinese: nil)
            ]
        )
        XCTAssertFalse(missingTranslation.isBilingualComplete)
        XCTAssertEqual(missingTranslation.incompleteKeys, ["roam.private.goals.title"])
        XCTAssertEqual(
            missingTranslation.violations,
            [.incompleteRoamPrivateToolsLocalization(missingOrEmptyKeys: ["roam.private.goals.title"])]
        )
    }
}
