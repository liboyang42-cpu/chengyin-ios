import XCTest
@testable import QuestifyCore

final class RoamFeaturedCouponWalletSelectionTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let snapshot = UUID()
    private let presentation = UUID()
    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    private func place(_ id: Int = 11) throws -> RoamPlace {
        try decode(RoamPlace.self, ["id": id, "name": "Synthetic place", "type": 2])
    }
    private func node(merchantID: Int = 22) throws -> RoamNodeDetail {
        try decode(RoamNodeDetail.self, ["poiId": 11, "merchantId": merchantID, "status": 1])
    }
    private func detail(type: Any = 2, featuredID: Int? = nil, name: String = "Synthetic coupon", merchantID: Int = 22) throws -> RoamMerchantDetail {
        var featured: [String: Any] = ["featuredType": type, "name": name]
        if let featuredID { featured["featuredId"] = featuredID }
        return try decode(RoamMerchantDetail.self, ["data": ["id": merchantID], "featured": featured])
    }
    private func scope(account: Int = 7, epoch: UInt64 = 1, readerID: ObjectIdentifier? = nil,
                       presentation: UUID? = nil, longitude: Double = 20) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: readerID ?? ObjectIdentifier(reader), identity: .init(accountID: account, epoch: epoch),
            area: .init(coordinate: .init(latitude: 10, longitude: longitude)!, label: "Manual search"),
            presentationID: presentation ?? self.presentation, isConfigured: true))
    }
    private func select(detail: RoamMerchantDetail? = nil, currentDetail: RoamMerchantDetail? = nil,
                        currentScope: RoamEventNavigationScope? = nil, currentSnapshot: UUID? = nil) throws -> RoamFeaturedCouponWalletSelection? {
        let place = try place(), node = try node(), value = try detail ?? self.detail(), context = try scope()
        return .init(place: place, currentPlace: place, node: node, currentNode: node,
            detail: value, currentDetail: currentDetail ?? value, rendered: context, current: currentScope ?? context,
            snapshotID: snapshot, currentSnapshotID: currentSnapshot ?? snapshot)
    }
    func testCouponFeatureNeedsNoFeaturedID() throws {
        let target = try XCTUnwrap(select()).target
        XCTAssertEqual(target.nodeID, 11); XCTAssertEqual(target.merchantID, 22)
    }
    func testFeaturedIDNeverBecomesAnOwnedCouponOrActivityDestination() throws {
        for id in [-1, 0, 33, Int.max] {
            let detail = try detail(featuredID: id)
            XCTAssertNotNil(try select(detail: detail))
            XCTAssertNil(RoamFeaturedActivityTarget(node: try node(), detail: detail))
        }
    }
    func testActivityUnknownAndStringKindsHaveNoWalletTarget() throws {
        let types: [Any] = [1, 0, 3, "2"]
        for type in types {
            XCTAssertNil(RoamFeaturedCouponWalletTarget(node: try node(), detail: try detail(type: type)))
        }
        let missing = try decode(RoamMerchantDetail.self, ["data": ["id": 22]])
        XCTAssertNil(RoamFeaturedCouponWalletTarget(node: try node(), detail: missing))
    }
    func testWrongMerchantOrPlaceCannotOpenWalletFromAnotherRead() throws {
        XCTAssertNil(RoamFeaturedCouponWalletTarget(node: try node(merchantID: 23), detail: try detail()))
        XCTAssertNil(RoamFeaturedCouponWalletTarget(node: try node(merchantID: 0), detail: try detail()))
        let place = try place(12), node = try node(), detail = try detail(), scope = try scope()
        XCTAssertNil(RoamFeaturedCouponWalletSelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: detail, rendered: scope, current: scope,
            snapshotID: snapshot, currentSnapshotID: snapshot))
    }
    func testChangedPayloadAndEqualPayloadRereadRetireSelection() throws {
        XCTAssertNil(try select(currentDetail: detail(name: "Changed coupon")))
        XCTAssertNil(try select(currentDetail: detail(type: 1, featuredID: 33)))
        XCTAssertNil(try select(currentSnapshot: UUID()))
        let selection = try XCTUnwrap(select())
        XCTAssertFalse(selection.mayRemainOpen(in: try scope(), snapshotID: UUID()))
    }
    func testMissingReadOrAuthorityCannotIssueSelection() throws {
        let place = try place(), node = try node(), detail = try detail(), scope = try scope()
        XCTAssertNil(RoamFeaturedCouponWalletSelection(place: place, currentPlace: place, node: node, currentNode: nil,
            detail: detail, currentDetail: detail, rendered: scope, current: scope,
            snapshotID: snapshot, currentSnapshotID: snapshot))
        XCTAssertNil(RoamFeaturedCouponWalletSelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: detail, rendered: nil, current: nil,
            snapshotID: snapshot, currentSnapshotID: snapshot))
    }
    func testNormalPushKeepsWalletButRejectsOldOverviewTap() throws {
        let selected = try XCTUnwrap(select()), pushed = try scope(presentation: UUID())
        XCTAssertTrue(selected.mayRemainOpen(in: pushed, snapshotID: snapshot))
        XCTAssertNil(try select(currentScope: pushed))
    }
    func testAccountEpochReaderAreaChangesRetireWallet() throws {
        let selected = try XCTUnwrap(select()), other = ReaderMarker()
        let scopes = [try scope(account: 8), try scope(epoch: 2), try scope(readerID: ObjectIdentifier(other)), try scope(longitude: 21)]
        for changed in scopes { XCTAssertFalse(selected.mayRemainOpen(in: changed, snapshotID: snapshot)) }
        XCTAssertFalse(selected.mayRemainOpen(in: nil, snapshotID: snapshot))
    }
}
