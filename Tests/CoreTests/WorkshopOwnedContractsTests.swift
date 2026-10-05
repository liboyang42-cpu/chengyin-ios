import XCTest
@testable import QuestifyCore

final class WorkshopOwnedContractsTests: XCTestCase {
    func testFreeAcquisitionAndUnavailableAreDistinctFromPurchasedOwnership() throws {
        let value: WorkshopOwnedPage = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.page())
        XCTAssertEqual(value.items.first?.claimId, "synthetic-claim"); XCTAssertEqual(value.items.first?.status, .active)
        let disabled: WorkshopOwnedPage = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.page(items: [], enabled: false))
        let empty: WorkshopOwnedPage = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.page(items: []))
        XCTAssertEqual(disabled.metadata.availability, .notEnabled); XCTAssertEqual(empty.metadata.availability, .freeClaimsOnly)
    }
    func testAllStoredStatusesAndRetirementRemainMetadata() throws {
        for state in ["ACTIVE", "SUSPENDED", "REVOKED", "EXPIRED"] {
            let item: WorkshopOwnedItem = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(stored: state, status: state, publication: "RETIRED"))
            XCTAssertEqual(item.status.rawValue, state)
        }
        let expired: WorkshopOwnedItem = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(status: "EXPIRED"))
        XCTAssertEqual(expired.storedStatus, .active)
    }
    func testEmergencyAndUnknownSourceCannotLookActive() throws {
        for publication in ["EMERGENCY_BLOCKED", "UNAVAILABLE"] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(publication: publication), as: WorkshopOwnedItem.self))
            let item: WorkshopOwnedItem = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(status: "UNAVAILABLE", publication: publication))
            XCTAssertEqual(item.status, .unavailable)
        }
    }
    func testUnknownAndContradictoryStatesFailClosed() throws {
        for state in ["REFUNDED", "PURCHASED", "SUBSCRIPTION_EXPIRED", "active"] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(status: state), as: WorkshopOwnedItem.self))
        }
        for pair in [("REVOKED", "ACTIVE"), ("SUSPENDED", "EXPIRED"), ("EXPIRED", "ACTIVE"), ("ACTIVE", "REVOKED")] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(stored: pair.0, status: pair.1), as: WorkshopOwnedItem.self))
        }
    }
    func testMissingExpiryIsNeverPerpetualAndForeignScopesAreRejected() throws {
        for (key, value) in [("acquisition", "PAID"), ("buyerKind", "ORGANIZATION"), ("buyerKind", "MERCHANT")] {
            var row = WorkshopOwnedTestData.item(); row[key] = value
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(row, as: WorkshopOwnedItem.self))
        }
        var row = WorkshopOwnedTestData.item(); row["validUntil"] = NSNull()
        XCTAssertThrowsError(try WorkshopOwnedTestData.decode(row, as: WorkshopOwnedItem.self))
    }
    func testMissingUnknownAndProtectedFieldsAreRejected() throws {
        for key in WorkshopOwnedTestData.item().keys {
            var row = WorkshopOwnedTestData.item(); row.removeValue(forKey: key)
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(row, as: WorkshopOwnedItem.self))
        }
        for key in ["content", "terms", "title", "licenseId", "ownerMemberId", "editingAllowed"] {
            var row = WorkshopOwnedTestData.item(); row[key] = "unexpected"
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(row, as: WorkshopOwnedItem.self))
        }
    }
    func testBoundedUniqueListAndExactSentinel() throws {
        for object in [WorkshopOwnedTestData.page(items: [WorkshopOwnedTestData.item(), WorkshopOwnedTestData.item()]),
                       WorkshopOwnedTestData.page(more: true),
                       WorkshopOwnedTestData.page(items: (0..<51).map { WorkshopOwnedTestData.item("claim-\($0)") })] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(object, as: WorkshopOwnedPage.self))
        }
        let page: WorkshopOwnedPage = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.page(items: (0..<50).map { WorkshopOwnedTestData.item("claim-\($0)") }, more: true))
        XCTAssertEqual(page.items.count, 50); XCTAssertTrue(page.hasMore)
    }
    func testUnavailableShapeCannotContainSuccessfulRows() throws {
        XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.page(enabled: false), as: WorkshopOwnedPage.self))
        XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.detail(enabled: false), as: WorkshopOwnedDetail.self))
        XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.detail(item: nil), as: WorkshopOwnedDetail.self))
        let detail: WorkshopOwnedDetail = try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.detail(item: nil, enabled: false))
        XCTAssertNil(detail.item)
    }
    func testIdentifiersAndUTCMetadataAreStrict() throws {
        for id in ["", "a/b", "x&buyer=8", "a\n", "汉字", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopOwnedTestData.item(id), as: WorkshopOwnedItem.self))
        }
        let times: [Any] = [123, "2026-10-05", "2026-13-05T00:00:00Z", "2026-10-05T00:00:00Z\n", NSNull()]
        for time in times {
            var row = WorkshopOwnedTestData.item(); row["validUntil"] = time
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(row, as: WorkshopOwnedItem.self))
        }
    }
    func testVersionAndUseFlagsCannotExpandContract() throws {
        for (key, value) in [("schema", "workshop-owned-v2"), ("scope", "MERCHANT"), ("purchasedLibraryStatus", "AVAILABLE"), ("contentUseStatus", "ALLOWED")] {
            var page = WorkshopOwnedTestData.page(); page[key] = value
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(page, as: WorkshopOwnedPage.self))
        }
    }
}
