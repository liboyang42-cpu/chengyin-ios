import XCTest
@testable import QuestifyCore

final class ReformWorkPackagesW02ToW20ComplianceAuditTests: XCTestCase {
    func testAllNineteenWorkPackagesW02ToW20ArePresentAndOrdered() {
        let audit = ReformWorkPackagesW02ToW20ComplianceAudit()
        XCTAssertEqual(audit.records.count, 19)
        XCTAssertEqual(audit.records.first?.packageID, .w02)
        XCTAssertEqual(audit.records.last?.packageID, .w20)
        XCTAssertTrue(audit.missingPackageIDs.isEmpty)
        XCTAssertTrue(audit.nonCompliantPackageIDs.isEmpty)
        XCTAssertTrue(audit.isAllCompliant)
    }

    func testDomainDistributionCoversFAndGAndH() {
        let audit = ReformWorkPackagesW02ToW20ComplianceAudit()
        let fPackages = audit.records(for: .f).map(\.packageID)
        let gPackages = audit.records(for: .g).map(\.packageID)
        let hPackages = audit.records(for: .h).map(\.packageID)

        XCTAssertEqual(fPackages, [.w12, .w13, .w14, .w15, .w20])
        XCTAssertEqual(gPackages, [.w04, .w05, .w06, .w07, .w08, .w17])
        XCTAssertEqual(hPackages, [.w02, .w03, .w09, .w10, .w11, .w16, .w18, .w19])
        XCTAssertEqual(fPackages.count + gPackages.count + hPackages.count, 19)
    }

    func testPrimaryContractsAndDefaultFailClosedGatesArePopulated() {
        let audit = ReformWorkPackagesW02ToW20ComplianceAudit()
        for record in audit.records {
            XCTAssertFalse(record.primaryContract.isEmpty, record.id)
            XCTAssertFalse(record.failClosedGateName.isEmpty, record.id)
            XCTAssertTrue(record.failClosedByDefault, record.id)
            XCTAssertTrue(record.isCompliant, record.id)
        }
    }

    func testNonFailClosedOrMissingPackageIsFlaggedByAudit() {
        var modified = ReformWorkPackagesW02ToW20ComplianceAudit.defaultRecords
        modified[0] = ReformWorkPackageComplianceRecord(
            packageID: .w02,
            domain: .h,
            title: "内容发布与媒体上传合规流水线",
            primaryContract: "CreatorContentMediaUploadContract",
            failClosedGateName: "CreatorMediaUploadGate",
            failClosedByDefault: false
        )
        let nonCompliantAudit = ReformWorkPackagesW02ToW20ComplianceAudit(records: modified)
        XCTAssertFalse(nonCompliantAudit.isAllCompliant)
        XCTAssertEqual(nonCompliantAudit.nonCompliantPackageIDs, [.w02])

        let missingLast = ReformWorkPackagesW02ToW20ComplianceAudit(
            records: Array(ReformWorkPackagesW02ToW20ComplianceAudit.defaultRecords.dropLast())
        )
        XCTAssertFalse(missingLast.isAllCompliant)
        XCTAssertEqual(missingLast.missingPackageIDs, [.w20])
    }
}
