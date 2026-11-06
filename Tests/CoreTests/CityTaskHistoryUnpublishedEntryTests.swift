import XCTest
@testable import QuestifyCore

@MainActor final class CityTaskHistoryUnpublishedEntryTests: XCTestCase {
    func testHistoryOwnerReadsWithoutConfiguredMapReader() async throws {
        let f = try CityTaskHistoryRuntimeOwnerTests.Fixture()
        let map = CityPlayerReader(approval: nil, transport: f.wire, isCurrent: { false }, onUnauthorized: {})
        XCTAssertFalse(map.isConfigured)
        let owner = try f.owner()
        XCTAssertEqual(owner.regionID, try XCTUnwrap(f.approval).regionID)
        await owner.controller?.load()
        XCTAssertEqual(owner.controller?.loaded, true)
        XCTAssertEqual(f.wire.calls, 1)
    }
    func testDifferentRegionCannotBorrowHistoryApproval() throws {
        let f = try CityTaskHistoryRuntimeOwnerTests.Fixture()
        XCTAssertThrowsError(try CityTaskHistoryRuntimeOwner(context: f.context, revision: 1, regionID: "other-region",
            approval: f.approval, underlying: f.wire, current: { f.live }, currentRevision: { f.revision }, selected: { _ in f.approval }))
        XCTAssertEqual(f.wire.calls, 0)
    }
}
