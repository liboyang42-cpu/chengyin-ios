import XCTest
@testable import QuestifyCore

final class TopicSessionSelectionTests: XCTestCase {
    private func detail(_ fields: String) throws -> TopicDetail {
        try JSONDecoder().decode(TopicDetail.self, from: Data("{\"id\":7,\"name\":\"Synthetic\",\(fields)}".utf8))
    }

    func testResolutionDistinguishesMissingEmptyUnavailableAndReady() throws {
        let missing = try detail("")
        XCTAssertNil(missing.activities)
        XCTAssertEqual(TopicSessionSelectionResolution.resolve(activities: missing.activities, hasDestination: true), .missingData)

        let empty = try detail("\"activityList\":[]")
        XCTAssertEqual(TopicSessionSelectionResolution.resolve(activities: empty.activities, hasDestination: true), .empty)
        XCTAssertEqual(TopicSessionSelectionResolution.resolve(activities: empty.activities, hasDestination: false), .empty)

        let listed = try detail("\"activityList\":[{\"id\":41,\"name\":\"Morning session\"},{\"id\":42,\"name\":\"Evening session\"}]")
        let activities = try XCTUnwrap(listed.activities)
        XCTAssertEqual(TopicSessionSelectionResolution.resolve(activities: activities, hasDestination: false), .destinationUnavailable(activities))
        XCTAssertEqual(TopicSessionSelectionResolution.resolve(activities: activities, hasDestination: true), .ready(activities))
    }

    func testSelectionUsesOnlyRealActivityIDsFromTheCapturedSnapshot() throws {
        // Ticket 99 exists on the topic but has no activity mapping; its id
        // must never be accepted as an activity id.
        let listed = try detail("\"activityList\":[{\"id\":41,\"name\":\"Morning session\"}],\"omsTicketList\":[{\"id\":99,\"name\":\"Ticket only\"}]")
        XCTAssertEqual(listed.tickets.map(\.id), [99])
        var flow = TopicSessionSelectionFlow()
        let scope = UUID()
        flow.open(scope: scope, activityIDs: try XCTUnwrap(listed.activities).map(\.id))
        XCTAssertNil(flow.select(activityID: 99, hasDestination: true))
        XCTAssertNil(flow.select(activityID: 7, hasDestination: true), "The topic id is not an activity id")
        XCTAssertEqual(flow.select(activityID: 41, hasDestination: true), 41)
    }

    func testDuplicateTapAndMissingDestinationCannotSelect() throws {
        var flow = TopicSessionSelectionFlow()
        flow.open(scope: UUID(), activityIDs: [41, 42])
        XCTAssertNil(flow.select(activityID: 41, hasDestination: false))
        XCTAssertEqual(flow.select(activityID: 41, hasDestination: true), 41)
        XCTAssertNil(flow.select(activityID: 42, hasDestination: true), "A second tap must not push another activity")
        XCTAssertNil(flow.select(activityID: 41, hasDestination: true))
        flow.returnedFromActivity()
        XCTAssertEqual(flow.select(activityID: 42, hasDestination: true), 42, "Returning re-arms an explicit new choice")
    }

    func testCloseReopenBackgroundAndScopeChangeRejectStaleIDs() throws {
        var flow = TopicSessionSelectionFlow()
        let firstScope = UUID()
        let firstPresentation = flow.open(scope: firstScope, activityIDs: [41])
        XCTAssertEqual(flow.open(scope: firstScope, activityIDs: [41]), firstPresentation, "Reopening while presented is a no-op")
        flow.close()
        XCTAssertNil(flow.select(activityID: 41, hasDestination: true))

        let secondPresentation = flow.open(scope: firstScope, activityIDs: [42])
        XCTAssertGreaterThan(secondPresentation, firstPresentation)
        XCTAssertNil(flow.select(activityID: 41, hasDestination: true), "An id from the earlier presentation is stale")
        XCTAssertEqual(flow.select(activityID: 42, hasDestination: true), 42)

        flow.returnedFromActivity()
        flow.backgrounded()
        XCTAssertFalse(flow.isPresented)
        XCTAssertNil(flow.select(activityID: 42, hasDestination: true), "Nothing is replayed after backgrounding")

        flow.open(scope: firstScope, activityIDs: [42])
        XCTAssertTrue(flow.scopeChanged(to: UUID()))
        XCTAssertFalse(flow.isPresented)
        XCTAssertNil(flow.select(activityID: 42, hasDestination: true), "An account change discards the snapshot")
        XCTAssertFalse(flow.scopeChanged(to: UUID()), "No sheet is presented to dismiss after invalidation")
    }
}
