import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileSelfOrdersAppTests: XCTestCase {
    private func setup(_ scenario:String="content") throws -> (ProfileSelfOrdersFixtureSocial,ProfileSelfOrdersFixtureReader,ProfileSelfOrdersScopedReader) {
        let social=ProfileSelfOrdersFixtureSocial(),orders=ProfileSelfOrdersFixtureReader(scenario)
        let access=ProfileSelfOrdersAccess(reader:orders,owner:social.identity)
        let context=try XCTUnwrap(access.context(memberID:81,social:social,isCurrent:true))
        return (social,orders,.init(context:context,social:social,orders:orders,isCurrent:{true}))
    }
    func testPreviewTenRowsShowsEightAndFullReaderKeepsTen() async throws {
        let (_,orders,reader)=try setup();let rows=try await reader.profileOrders()
        XCTAssertEqual(ProfileSelfOrdersPreview(rows:rows).rows.count,8);XCTAssertEqual(rows.count,10);XCTAssertEqual(orders.listReads,1)
    }
    func testCardFreshDetailUsesOnlySelectedID() async throws {
        let (_,orders,reader)=try setup();let row=try await reader.profileOrder(id:3)
        XCTAssertEqual(row.id,3);XCTAssertEqual(orders.detailReads,1);XCTAssertEqual(orders.listReads,0)
    }
    func testConfiguredAccessStillRequiresSameProfileOwner() throws {
        let (social,orders,_)=try setup();let access=ProfileSelfOrdersAccess(reader:orders,owner:social.identity)
        XCTAssertNil(access.context(memberID:92,social:social,isCurrent:true))
    }
    func testRevocationPreventsCreatingNewEntry() throws {
        let (social,orders,_)=try setup();let access=ProfileSelfOrdersAccess(reader:orders,owner:social.identity)
        orders.isConfigured=false;XCTAssertNil(access.context(memberID:81,social:social,isCurrent:true))
    }
    func testRefreshFailureRetainsSnapshotUntilRetry() async throws {
        let (_,_,reader)=try setup("refreshFailure");let model=ProfileSelfOrdersController()
        await model.load(reader:reader);await model.load(reader:reader);XCTAssertEqual(model.rows?.count,10);XCTAssertEqual(model.issue,.readFailed)
        await model.load(reader:reader);XCTAssertNil(model.issue)
    }
    func testEmptyAfterRefreshReplacesCardRows() async throws {
        let (_,_,reader)=try setup("becomesEmpty");let model=ProfileSelfOrdersController()
        await model.load(reader:reader);await model.load(reader:reader);XCTAssertEqual(model.rows,[])
    }
    func testStandaloneHostBuildsWithoutPublicPageOverlays() {
        let host=UIHostingController(rootView:ProfileSelfOrdersFixtureHost());host.loadViewIfNeeded();XCTAssertNotNil(host.view)
    }
}
