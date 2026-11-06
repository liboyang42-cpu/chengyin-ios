import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class OfficialEventBrowseStateViewTests: XCTestCase {
    func testMineKeywordProducesSearchEmptyRatherThanClaimingNoParticipation() {
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .mine, keyword: "Missing").emptyKey, "official.searchEmpty")
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .mine, keyword: "").emptyKey, "official.emptyMine")
        XCTAssertTrue(OfficialEventBrowseQuery(bucket: .mine, keyword: "Missing").isPrivate)
    }
    func testUnknownTaskUsesUnknownCardTextWhileRemainingBrowsable() throws {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":71,"title":"Synthetic task","status":42,"signed":true}"#.utf8))
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .live, keyword: "task").visible([event]), [event])
        XCTAssertEqual(event.statusKey, "official.status.unknown")
        XCTAssertEqual(event.participationKey, "official.participation.unavailable")
        let host = UIHostingController(rootView: OfficialEventCard(event: event).environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
    func testGuestMineReadStillRejectsBeforeNetworkDespiteLocalSearchSupport() async throws {
        let reader = OfficialSessionReader(service: nil, currentContext: { OfficialReadContext(guestEpoch: 1) })
        do { _ = try await reader.myEvents(); XCTFail("Guest private data was read") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }

    func testOfficialResultReturnAcceptsOnlyCurrentVisibleActiveDetailVisit() {
        let scope = UUID(), visit = UUID()
        let lease = OfficialDetailReturnLease(eventID: 71, scope: scope, visit: visit)
        XCTAssertTrue(lease.permits(eventID: 71, scope: scope, visit: visit, visible: true, active: true))
        XCTAssertFalse(lease.permits(eventID: 72, scope: scope, visit: visit, visible: true, active: true))
        XCTAssertFalse(lease.permits(eventID: 71, scope: UUID(), visit: visit, visible: true, active: true))
        XCTAssertFalse(lease.permits(eventID: 71, scope: scope, visit: UUID(), visible: true, active: true))
        XCTAssertFalse(lease.permits(eventID: 71, scope: scope, visit: visit, visible: false, active: true))
        XCTAssertFalse(lease.permits(eventID: 71, scope: scope, visit: visit, visible: true, active: false))
    }

    func testReturningToSameEventDoesNotReviveOldPresentationLease() {
        let scope = UUID(), oldVisit = UUID(), newVisit = UUID()
        let lease = OfficialDetailReturnLease(eventID: 71, scope: scope, visit: oldVisit)
        XCTAssertFalse(lease.permits(eventID: 71, scope: scope, visit: newVisit, visible: true, active: true))
    }

    func testParticipationPresentationCannotBeOverwrittenWhileOpenOrClosing() throws {
        var state = OfficialParticipationPresentation()
        var firstReturns = 0, secondReturns = 0
        state.open(command: .signup(71), onReturn: { firstReturns += 1 })
        let firstID = try XCTUnwrap(state.entry?.id)
        state.open(command: .signup(72), onReturn: { secondReturns += 1 })
        XCTAssertEqual(state.entry?.id, firstID)
        state.beginDismiss(id: firstID)
        state.open(command: .signup(72), onReturn: { secondReturns += 1 })
        XCTAssertEqual(state.entry?.id, firstID)
        XCTAssertFalse(state.isPresented)
        let callback = state.finishDismiss(id: firstID)
        XCTAssertNil(state.entry)
        callback?()
        state.finishDismiss(id: firstID)?()
        XCTAssertEqual(firstReturns, 1)
        XCTAssertEqual(secondReturns, 0)
    }

    func testOldDismissalCannotConsumeNewPresentationInSameDetailVisit() throws {
        var state = OfficialParticipationPresentation()
        state.open(command: .signup(71), onReturn: nil)
        let oldID = try XCTUnwrap(state.entry?.id)
        state.beginDismiss(id: oldID)
        state.finishDismiss(id: oldID)?()
        var newReturns = 0
        state.open(command: .signup(71), onReturn: { newReturns += 1 })
        let newID = try XCTUnwrap(state.entry?.id)
        XCTAssertNotEqual(oldID, newID)
        state.beginDismiss(id: oldID)
        state.finishDismiss(id: oldID)?()
        XCTAssertEqual(state.entry?.id, newID)
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(newReturns, 0)
        state.beginDismiss(id: newID)
        state.finishDismiss(id: newID)?()
        XCTAssertEqual(newReturns, 1)
    }
}
