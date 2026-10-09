import XCTest
@testable import QuestifyCore

final class RoamEventDestinationTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let lease = UUID()
    private let presentation = UUID()
    private var area: RoamSearchArea { .init(coordinate: .init(latitude: 1, longitude: 2)!, label: "Manual") }
    private var identity: RoamReadIdentity { .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease) }
    private func event(_ kind: String = "activity", id: Int = 7, title: String = "Same title") throws -> RoamEvent {
        let data = try JSONSerialization.data(withJSONObject: ["kind":kind,"id":id,"title":title])
        return try JSONDecoder().decode(RoamEvent.self, from: data)
    }
    private func scope(identity: RoamReadIdentity? = nil, area: RoamSearchArea? = nil, presentationID: UUID? = nil,
                       readerID: ObjectIdentifier? = nil) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: readerID ?? ObjectIdentifier(reader), identity: identity ?? self.identity,
                           area: area ?? self.area, presentationID: presentationID ?? presentation, isConfigured: true))
    }
    func testCanonicalKindKeepsSameNumericActivityAndTopicIDsSeparate() throws {
        XCTAssertEqual(RoamEventDestination(event: try event("activity")), .activity(7))
        XCTAssertEqual(RoamEventDestination(event: try event("topic")), .topic(7))
        XCTAssertNotEqual(RoamEventDestination(event: try event("activity")), RoamEventDestination(event: try event("topic")))
    }
    func testMissingCoordinatesAreAllowedButUnknownKindsAndInvalidIDsNeverRoute() throws {
        let value = try event(); XCTAssertNil(value.coordinate); XCTAssertEqual(RoamEventDestination(event: value), .activity(7))
        for kind in ["hangout", "merchant", "player", "template", "ACTIVITY", "unknown"] {
            XCTAssertNil(RoamEventDestination(event: try event(kind)), kind)
        }
        for id in [0, -1] { XCTAssertNil(RoamEventDestination(event: try event(id: id))) }
        let missing = try JSONDecoder().decode(RoamEvent.self, from: Data(#"{"kind":"activity","name":"Missing ID"}"#.utf8))
        XCTAssertNil(RoamEventDestination(event: missing))
    }
    func testExactEventSnapshotIsRequiredBeforeIssuingSelection() throws {
        let original = try event(), scope = try scope()
        for current in [try event("topic"), try event(id: 8), try event(title: "Changed")] {
            XCTAssertNil(RoamEventNavigationSelection(event: original, currentEvent: current, rendered: scope, current: scope))
        }
        XCTAssertNil(RoamEventNavigationSelection(event: original, currentEvent: nil, rendered: scope, current: scope))
        XCTAssertNotNil(RoamEventNavigationSelection(event: original, currentEvent: original, rendered: scope, current: scope))
    }
    func testRetiredOverviewCannotIssueOldTapButAcceptedRouteSurvivesNormalPush() throws {
        let event = try event(), original = try scope(), retired = try scope(presentationID: UUID())
        let selected = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: original))
        XCTAssertNil(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: retired))
        XCTAssertTrue(selected.mayRemainOpen(in: retired))
    }
    func testAccountRoleEpochViewerAreaAndApprovalChangesRetireAcceptedRoute() throws {
        let event = try event(), original = try scope()
        let selected = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: original))
        let identities = [RoamReadIdentity(accountID: 8, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 2, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "merchant", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 2, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 2, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: nil),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: UUID())]
        for identity in identities {
            let changed = try scope(identity: identity)
            XCTAssertFalse(selected.mayRemainOpen(in: changed))
            XCTAssertNil(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: changed))
        }
    }
    func testReaderReplacementAreaAndMissingConfigurationNeverAdoptOldSelection() throws {
        let event = try event(), original = try scope(), other = ReaderMarker()
        let selected = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: original))
        XCTAssertFalse(selected.mayRemainOpen(in: try scope(readerID: ObjectIdentifier(other))))
        XCTAssertFalse(selected.mayRemainOpen(in: try scope(area: .init(coordinate: .init(latitude: 2, longitude: 3)!, label: "Elsewhere"))))
        XCTAssertFalse(selected.mayRemainOpen(in: nil))
        XCTAssertNil(RoamEventNavigationScope(readerID: ObjectIdentifier(reader), identity: identity, area: area, presentationID: presentation, isConfigured: false))
        XCTAssertNil(RoamEventNavigationScope(readerID: ObjectIdentifier(reader), identity: nil, area: area, presentationID: presentation, isConfigured: true))
        XCTAssertNil(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: nil))
        let again = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: original, current: original))
        XCTAssertNotEqual(selected.id, again.id)
    }
}
