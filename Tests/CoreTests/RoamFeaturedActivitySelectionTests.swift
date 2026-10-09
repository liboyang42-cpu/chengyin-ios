import XCTest
@testable import QuestifyCore

final class RoamFeaturedActivitySelectionTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let lease = UUID()
    private let presentation = UUID()
    private let snapshot = UUID()
    private func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
    private func place(id: Int = 11, name: String = "Synthetic place") throws -> RoamPlace {
        try decode(RoamPlace.self, ["id":id,"name":name,"type":2])
    }
    private func node(id: Int = 11, merchantID: Int = 22, name: String = "Synthetic place") throws -> RoamNodeDetail {
        try decode(RoamNodeDetail.self, ["poiId":id,"merchantId":merchantID,"name":name,"status":1])
    }
    private func detail(merchantID: Int = 22, type: Any = 1, activityID: Int = 33, name: String = "Synthetic activity") throws -> RoamMerchantDetail {
        try decode(RoamMerchantDetail.self, ["data":["id":merchantID,"name":"Synthetic merchant"],
            "featured":["featuredType":type,"featuredId":activityID,"name":name]])
    }
    private func scope(presentation: UUID? = nil, identity: RoamReadIdentity? = nil,
                       readerID: ObjectIdentifier? = nil, area: RoamSearchArea? = nil) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: readerID ?? ObjectIdentifier(reader),
            identity: identity ?? .init(accountID: 7, epoch: 1, role: "player", manualMapApprovalRevision: lease),
            area: area ?? .init(coordinate: .init(latitude: 10, longitude: 20)!, label: "Manual search"),
            presentationID: presentation ?? self.presentation, isConfigured: true))
    }
    private func selection(currentPlace: RoamPlace? = nil, currentNode: RoamNodeDetail? = nil,
                           currentDetail: RoamMerchantDetail? = nil, currentScope: RoamEventNavigationScope? = nil,
                           currentSnapshot: UUID? = nil) throws -> RoamFeaturedActivitySelection? {
        let place = try place(), node = try node(), detail = try detail(), scope = try scope()
        return .init(place: place, currentPlace: currentPlace ?? place, node: node, currentNode: currentNode ?? node,
            detail: detail, currentDetail: currentDetail ?? detail, rendered: scope, current: currentScope ?? scope,
            snapshotID: snapshot, currentSnapshotID: currentSnapshot ?? snapshot)
    }
    func testExplicitActivityIDKeepsAllThreeDomainsDistinct() throws {
        let selected = try XCTUnwrap(selection())
        XCTAssertEqual(selected.target.nodeID, 11)
        XCTAssertEqual(selected.target.merchantID, 22)
        XCTAssertEqual(selected.target.activityID, 33)
    }
    func testCouponUnknownStringTypeAndMissingOrInvalidFeaturedHaveNoDestination() throws {
        let node = try node()
        let types: [Any] = [2, 0, 3, "1"]
        for type in types {
            XCTAssertNil(RoamFeaturedActivityTarget(node: node, detail: try detail(type: type)))
        }
        for id in [0, -1] {
            XCTAssertNil(RoamFeaturedActivityTarget(node: node, detail: try detail(activityID: id)))
        }
        let missing = try decode(RoamMerchantDetail.self, ["data":["id":22]])
        XCTAssertNil(RoamFeaturedActivityTarget(node: node, detail: missing))
    }
    func testWrongMerchantAndWrongPlaceNeverBorrowAnActivity() throws {
        XCTAssertNil(RoamFeaturedActivityTarget(node: try node(merchantID: 23), detail: try detail()))
        XCTAssertNil(RoamFeaturedActivityTarget(node: try node(merchantID: 0), detail: try detail()))
        let context = try scope(), place = try place(id: 12), node = try node(), detail = try detail()
        XCTAssertNil(RoamFeaturedActivitySelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: detail, rendered: context, current: context,
            snapshotID: snapshot, currentSnapshotID: snapshot))
    }
    func testFullPayloadReplacementAndEqualPayloadRereadRejectOldCallbacks() throws {
        XCTAssertNil(try selection(currentPlace: place(name: "Changed")))
        XCTAssertNil(try selection(currentNode: node(name: "Changed")))
        XCTAssertNil(try selection(currentDetail: detail(name: "Changed")))
        XCTAssertNil(try selection(currentDetail: detail(activityID: 34)))
        XCTAssertNil(try selection(currentSnapshot: UUID()))
        let selected = try XCTUnwrap(selection())
        XCTAssertFalse(selected.mayRemainOpen(in: try scope(), snapshotID: UUID()))
    }
    func testMissingReadOrAuthorityCannotIssueSelection() throws {
        let place = try place(), node = try node(), detail = try detail(), context = try scope()
        XCTAssertNil(RoamFeaturedActivitySelection(place: place, currentPlace: place, node: node, currentNode: nil,
            detail: detail, currentDetail: detail, rendered: context, current: context,
            snapshotID: snapshot, currentSnapshotID: snapshot))
        XCTAssertNil(RoamFeaturedActivitySelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: nil, rendered: context, current: context,
            snapshotID: snapshot, currentSnapshotID: snapshot))
        XCTAssertNil(RoamFeaturedActivitySelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: detail, rendered: nil, current: nil,
            snapshotID: snapshot, currentSnapshotID: snapshot))
    }
    func testNormalPushPreservesAcceptedTargetButRetiresOldOverviewAction() throws {
        let selected = try XCTUnwrap(selection()), retired = try scope(presentation: UUID())
        XCTAssertTrue(selected.mayRemainOpen(in: retired, snapshotID: snapshot))
        XCTAssertNil(try selection(currentScope: retired))
    }
    func testIdentityPermissionReaderAndAreaChangesRevokeAcceptedRead() throws {
        let selected = try XCTUnwrap(selection()), other = ReaderMarker()
        let changed = [try scope(identity: .init(accountID: 8, epoch: 1, role: "player", manualMapApprovalRevision: lease)),
            try scope(identity: .init(accountID: 7, epoch: 2, role: "player", manualMapApprovalRevision: lease)),
            try scope(identity: .init(accountID: 7, epoch: 1, role: "merchant", manualMapApprovalRevision: lease)),
            try scope(identity: .init(accountID: 7, epoch: 1, role: "player", manualMapApprovalRevision: UUID())),
            try scope(readerID: ObjectIdentifier(other)),
            try scope(area: .init(coordinate: .init(latitude: 20, longitude: 30)!, label: "Changed"))]
        for scope in changed {
            XCTAssertFalse(selected.mayRemainOpen(in: scope, snapshotID: snapshot))
            XCTAssertNil(try selection(currentScope: scope))
        }
        XCTAssertFalse(selected.mayRemainOpen(in: nil, snapshotID: snapshot))
    }
}
