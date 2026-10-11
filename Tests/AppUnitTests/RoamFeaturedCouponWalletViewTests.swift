import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamFeaturedCouponWalletViewTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testOverviewConstructionDoesNotEagerlyOpenWalletOrActivity() throws {
        let reader = RoamFixtureReader()
        let place = try decode(RoamPlace.self, #"{"id":11,"type":2,"name":"Synthetic place"}"#)
        var walletCalls = 0, activityCalls = 0
        let host = UIHostingController(rootView: RoamItemDetailView(item: .place(place), reader: reader,
            eventDestination: { _ in activityCalls += 1; return AnyView(Text("Synthetic activity")) },
            couponWalletDestination: { walletCalls += 1; return AnyView(Text("Synthetic wallet")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertEqual(walletCalls, 0); XCTAssertEqual(activityCalls, 0)
    }
    func testCouponSelectionUsesActualReaderScopeAndDoesNotBorrowFeaturedID() throws {
        let reader = RoamFixtureReader(), replacement = RoamFixtureReader(), presentation = UUID(), snapshot = UUID()
        let scope = try XCTUnwrap(RoamEventNavigationScope(readerID: ObjectIdentifier(reader), identity: reader.identity,
            area: reader.searchArea, presentationID: presentation, isConfigured: reader.isConfigured))
        let changed = try XCTUnwrap(RoamEventNavigationScope(readerID: ObjectIdentifier(replacement), identity: replacement.identity,
            area: replacement.searchArea, presentationID: presentation, isConfigured: replacement.isConfigured))
        let place = try decode(RoamPlace.self, #"{"id":11,"type":2}"#)
        let node = try decode(RoamNodeDetail.self, #"{"poiId":11,"merchantId":22,"status":1}"#)
        let detail = try decode(RoamMerchantDetail.self, #"{"data":{"id":22},"featured":{"featuredType":2,"featuredId":33,"name":"Synthetic coupon"}}"#)
        let selected = try XCTUnwrap(RoamFeaturedCouponWalletSelection(place: place, currentPlace: place,
            node: node, currentNode: node, detail: detail, currentDetail: detail, rendered: scope, current: scope,
            snapshotID: snapshot, currentSnapshotID: snapshot))
        XCTAssertEqual(selected.target.nodeID, 11); XCTAssertEqual(selected.target.merchantID, 22)
        XCTAssertFalse(selected.mayRemainOpen(in: changed, snapshotID: snapshot))
        XCTAssertNil(RoamFeaturedActivityTarget(node: node, detail: detail))
    }
}
