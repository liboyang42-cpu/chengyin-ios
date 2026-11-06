import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublicMerchantHomeBusinessStateViewTests: XCTestCase {
    private func home(_ json: String) throws -> PublicMerchantHome {
        try JSONDecoder().decode(PublicMerchantHome.self, from: Data(json.utf8))
    }
    func testOwnerProfileUsesReturnedMemberAndNeverMerchantRowFallback() throws {
        let scope = UUID(), snapshot = UUID()
        let value = try home(#"{"id":31,"memberId":77}"#)
        let legacy = PublicMerchantHomeTarget.legacyMerchantRowID(PublicMerchantRowID(31)!)
        let selected = try XCTUnwrap(PublicMerchantOwnerProfileSelection(home: value, target: legacy, scope: scope, snapshot: snapshot))
        XCTAssertEqual(selected.owner.rawValue, 77)
        for json in [#"{"id":31}"#, #"{"id":31,"memberId":0}"#, #"{"id":31,"memberId":-1}"#] {
            XCTAssertNil(PublicMerchantOwnerProfileSelection(home: try home(json), target: legacy, scope: scope, snapshot: snapshot))
        }
        XCTAssertNil(PublicMerchantOwnerProfileSelection(home: value,
            target: .ownerMemberID(PublicMerchantOwnerID(31)!), scope: scope, snapshot: snapshot))
        XCTAssertNil(PublicMerchantOwnerProfileSelection(home: value,
            target: .legacyMerchantRowID(PublicMerchantRowID(77)!), scope: scope, snapshot: snapshot))
    }
    func testOwnerProfileRetiresOnSnapshotScopeTargetAndReturnedOwnerChanges() throws {
        let scope = UUID(), snapshot = UUID(), target = PublicMerchantHomeTarget.ownerMemberID(PublicMerchantOwnerID(77)!)
        let value = try home(#"{"id":31,"memberId":77}"#)
        let selected = try XCTUnwrap(PublicMerchantOwnerProfileSelection(home: value, target: target, scope: scope, snapshot: snapshot))
        XCTAssertTrue(selected.matches(home: value, target: target, scope: scope, snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: value, target: target, scope: UUID(), snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: value, target: target, scope: scope, snapshot: UUID()))
        XCTAssertFalse(selected.matches(home: value, target: .legacyMerchantRowID(PublicMerchantRowID(31)!), scope: scope, snapshot: snapshot))
        XCTAssertFalse(selected.matches(home: try home(#"{"id":31,"memberId":88}"#), target: target, scope: scope, snapshot: snapshot))
    }
    func testOwnerProfileContextIsAbsentForUnconfiguredStandaloneHosts() {
        XCTAssertNil(PublicMerchantHomeContext().ownerProfile)
    }

    func testOpenClosedAndUnknownHaveSeparateTextAndShape() {
        let open = PublicMerchantHomeBusinessStatusLabel(state: .open)
        let closed = PublicMerchantHomeBusinessStatusLabel(state: .closed)
        let unknown = PublicMerchantHomeBusinessStatusLabel(state: .unknown)
        XCTAssertEqual(open.localizationKey, "merchant.publicHome.open")
        XCTAssertEqual(closed.localizationKey, "merchant.publicHome.closed")
        XCTAssertEqual(unknown.localizationKey, "merchant.publicHome.businessUnknown")
        XCTAssertEqual(Set([open.symbol, closed.symbol, unknown.symbol]).count, 3)
    }
    func testUnknownLabelCanRenderWithAccessibilityTextWithoutReaderOrActionContext() {
        let host = UIHostingController(rootView: PublicMerchantHomeBusinessStatusLabel(state: .unknown)
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
}
