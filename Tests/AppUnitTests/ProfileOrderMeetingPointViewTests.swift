import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfileOrderMeetingPointViewTests: XCTestCase {
    @MainActor private final class Reader: ProfileReading {
        var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1, viewerRevision: 2)
        var isConfigured = true
        var requests = 0
        func profileOrders() async throws -> [ProfileOrder] { requests += 1; throw APIError.notConfigured }
        func profileOrder(id: Int) async throws -> ProfileOrder { requests += 1; throw APIError.notConfigured }
        func profileParticipants() async throws -> [ProfileParticipant] { requests += 1; throw APIError.notConfigured }
        func profileParticipant(id: Int) async throws -> ProfileParticipant { requests += 1; throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { requests += 1; throw APIError.notConfigured }
    }
    private func order() throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self,from:Data(#"{"id":41,"memberId":81,"omsTicket":{"meetingPoint":"Synthetic destination","gatherLat":31.2,"gatherLng":121.5}}"#.utf8))
    }
    private func context(_ value: ProfileOrder, _ reader: Reader) throws -> ProfileOrderMeetingPointContext {
        try XCTUnwrap(ProfileOrderMeetingPointContext.capture(order:value,requestedID:41,reader:reader))
    }
    func testNormalDetailAndDefaultHostConstructionDoNotOpenOrRead() throws {
        let reader = Reader(), value = try order()
        _ = ProfileOrderDetailView(id:41,reader:reader)
        _ = ProfileOrderMeetingPointHost(order:value,requestedID:41,reader:reader) { entry in List { entry } }
        XCTAssertEqual(reader.requests,0)
    }
    func testInjectedHandoffIsUsedOnlyAfterExactExplicitConfirmation() async throws {
        let reader = Reader(), value = try order(), c = try context(value,reader); var sent: [PlatformMapDestination] = []
        let host = ProfileOrderMeetingPointHost(order:value,requestedID:41,reader:reader,open:{sent.append($0);return true}) { entry in List { entry } }
        let model = ProfileOrderMeetingPointModel(context:c); model.appear(current:c,sceneActive:true)
        XCTAssertTrue(sent.isEmpty); model.prepare(current:c); XCTAssertTrue(sent.isEmpty)
        let review = try XCTUnwrap(model.review)
        await model.confirm(review,current:{c},open:host.open)
        XCTAssertEqual(sent,[c.destination]); XCTAssertEqual(reader.requests,0)
    }
    func testInitialNilAndOldBindingsCannotReadOrCloseNewReview() throws {
        let reader = Reader(), value = try order(), c = try context(value,reader)
        let model = ProfileOrderMeetingPointModel(context:c); model.appear(current:c,sceneActive:true)
        let initial = model.presentation(for:nil,current:{c}); model.prepare(current:c)
        let a = try XCTUnwrap(model.review), old = model.presentation(for:a,current:{c})
        XCTAssertEqual(old.wrappedValue,a); old.wrappedValue = nil; model.prepare(current:c)
        let b = try XCTUnwrap(model.review), fresh = model.presentation(for:b,current:{c})
        XCTAssertNil(initial.wrappedValue); XCTAssertNil(old.wrappedValue)
        initial.wrappedValue = b; old.wrappedValue = b; initial.wrappedValue = nil; old.wrappedValue = nil
        XCTAssertFalse(model.cancel(id:a.id)); XCTAssertEqual(fresh.wrappedValue,b)
        fresh.wrappedValue = nil; XCTAssertNil(model.review)
    }
    func testBindingFailsClosedOnLiveOwnerChangeBeforeHostObserver() async throws {
        let reader = Reader(), value = try order(), c = try context(value,reader)
        let model = ProfileOrderMeetingPointModel(context:c); model.appear(current:c,sceneActive:true); model.prepare(current:c)
        let review = try XCTUnwrap(model.review)
        let live = { ProfileOrderMeetingPointContext.capture(order:value,requestedID:41,reader:reader) }
        let binding = model.presentation(for:review,current:live)
        reader.identity = .init(accountID:82,epoch:2,viewerRevision:3)
        XCTAssertNil(binding.wrappedValue); var calls = 0
        await model.confirm(review,current:live,open:{_ in calls += 1;return true})
        XCTAssertEqual(calls,0); XCTAssertEqual(reader.requests,0)
    }
    func testWholeHostSuspensionClearsPendingReviewAndOldDismissCannotClearReturn() throws {
        let reader = Reader(), value = try order(), c = try context(value,reader)
        let model = ProfileOrderMeetingPointModel(context:c); model.appear(current:c,sceneActive:true); model.prepare(current:c)
        let old = try XCTUnwrap(model.review), binding = model.presentation(for:old,current:{c})
        model.disappear(); model.sceneChanged(active:true,current:c)
        XCTAssertNil(binding.wrappedValue); XCTAssertFalse(model.canPrepare(current:c))
        model.appear(current:c,sceneActive:true); model.prepare(current:c)
        let fresh = try XCTUnwrap(model.review); binding.wrappedValue = nil
        XCTAssertFalse(model.cancel(id:old.id)); XCTAssertEqual(model.review,fresh)
    }
    func testNewSourceRetiresOldHostRatherThanAdoptingSuccessor() async throws {
        let reader = Reader(), value = try order(), c = try context(value,reader)
        let old = ProfileOrderMeetingPointModel(context:c); old.appear(current:c,sceneActive:true); old.prepare(current:c)
        let offered = try XCTUnwrap(old.review); old.retire()
        let fresh = ProfileOrderMeetingPointModel(context:c); fresh.appear(current:c,sceneActive:true); fresh.prepare(current:c)
        let replacement = try XCTUnwrap(fresh.review); var calls = 0
        await old.confirm(offered,current:{c},open:{_ in calls += 1;return true})
        old.cancel(id:offered.id)
        XCTAssertEqual(fresh.review,replacement); XCTAssertEqual(calls,0)
    }
    func testConcreteHostCanMountAndUnmountWithoutAnyAutomaticHandoff() throws {
        let reader = Reader(), value = try order(); var calls = 0
        let host = ProfileOrderMeetingPointHost(order:value,requestedID:41,reader:reader,open:{_ in calls += 1;return true}) { entry in
            List { Section { entry } }
        }
        let controller = UIHostingController(rootView:host)
        controller.loadViewIfNeeded(); controller.beginAppearanceTransition(true,animated:false); controller.endAppearanceTransition()
        controller.beginAppearanceTransition(false,animated:false); controller.endAppearanceTransition()
        XCTAssertEqual(calls,0); XCTAssertEqual(reader.requests,0)
    }
}
