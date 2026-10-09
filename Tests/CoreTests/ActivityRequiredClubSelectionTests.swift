import XCTest
@testable import QuestifyCore

final class ActivityRequiredClubSelectionTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let readID = UUID()
    private let presentationID = UUID()
    private let gate = ActivityDetailAccess.clubRequired(clubID: 81, message: "Synthetic gate")
    private func scope(activity: Int = 11, identity: String = "account7:epoch1:content1", read: UUID? = nil,
                       presentation: UUID? = nil, readerID: ObjectIdentifier? = nil) throws -> ActivityRequiredClubScope {
        try XCTUnwrap(.init(activityID: activity, readerID: readerID ?? ObjectIdentifier(reader), identity: identity,
            readID: read ?? readID, presentationID: presentation ?? presentationID, isConfigured: true))
    }
    private func selected() throws -> ActivityRequiredClubSelection {
        let context = try scope()
        return try XCTUnwrap(.init(access: gate, currentAccess: gate, rendered: context, current: context))
    }
    func testOnlyExplicitReturnedClubIDBecomesDestination() throws {
        let result = try selected()
        XCTAssertEqual(result.clubID, 81); XCTAssertNotEqual(result.clubID, 11)
    }
    func testMissingInvalidClubAndAllowedActivityCannotCreateGateRoute() throws {
        let context = try scope()
        for id in [nil, 0, -1] as [Int?] {
            let value = ActivityDetailAccess.clubRequired(clubID: id, message: "81 is not an ID source")
            XCTAssertNil(ActivityRequiredClubSelection(access: value, currentAccess: value, rendered: context, current: context))
        }
        let allowed = try JSONDecoder().decode(ActivityDetailAccess.self, from: Data(#"{"id":11,"name":"Allowed"}"#.utf8))
        XCTAssertNil(ActivityRequiredClubSelection(access: allowed, currentAccess: allowed, rendered: context, current: context))
    }
    func testReplacedClubOrGateMessageRejectsCapturedActionAndAcceptedRoute() throws {
        let context = try scope(), result = try selected()
        for value in [ActivityDetailAccess.clubRequired(clubID: 82, message: "Synthetic gate"), .clubRequired(clubID: 81, message: "Changed")] {
            XCTAssertNil(ActivityRequiredClubSelection(access: gate, currentAccess: value, rendered: context, current: context))
            XCTAssertFalse(result.mayRemainOpen(access: value, in: context))
        }
        XCTAssertFalse(result.mayRemainOpen(access: nil, in: context))
    }
    func testNormalPushKeepsAcceptedClubButRetiresOverviewCallback() throws {
        let context = try scope(), retired = try scope(presentation: UUID()), result = try selected()
        XCTAssertTrue(result.mayRemainOpen(access: gate, in: retired))
        XCTAssertNil(ActivityRequiredClubSelection(access: gate, currentAccess: gate, rendered: context, current: retired))
    }
    func testSamePayloadRereadAndActivityIdentityReaderReplacementRevoke() throws {
        let context = try scope(), result = try selected(), other = ReaderMarker()
        let replacements = [try scope(read: UUID()), try scope(activity: 12), try scope(identity: "account8:epoch2:content2"),
            try scope(readerID: ObjectIdentifier(other))]
        for changed in replacements {
            XCTAssertFalse(result.mayRemainOpen(access: gate, in: changed))
            XCTAssertNil(ActivityRequiredClubSelection(access: gate, currentAccess: gate, rendered: context, current: changed))
        }
    }
    func testNoCompletedReadOrConfiguredScopeCannotMintReceipt() {
        XCTAssertNil(ActivityRequiredClubScope(activityID: 11, readerID: ObjectIdentifier(reader), identity: "scope",
            readID: nil, presentationID: presentationID, isConfigured: true))
        XCTAssertNil(ActivityRequiredClubScope(activityID: 11, readerID: ObjectIdentifier(reader), identity: "scope",
            readID: readID, presentationID: presentationID, isConfigured: false))
        XCTAssertNil(ActivityRequiredClubSelection(access: gate, currentAccess: gate, rendered: nil, current: nil))
    }
}
