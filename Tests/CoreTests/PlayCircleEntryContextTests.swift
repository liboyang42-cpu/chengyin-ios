import Foundation
import XCTest
@testable import QuestifyCore

final class PlayCircleEntryContextTests: XCTestCase {
    func testCarriesValuesWithoutNormalizationOrCreatingTicketCapability() throws {
        let value = try XCTUnwrap(PlayCircleEntryContext(topicID: 17, inviteCode: "Ab_09-x", registrationID: 23))
        XCTAssertEqual(value.topicID, 17)
        XCTAssertEqual(value.inviteCode, "Ab_09-x")
        XCTAssertEqual(value.registrationID, 23)
        XCTAssertEqual(value.legacyLink, .play(topicID: 17, inviteCode: "Ab_09-x", registrationID: 23))
    }

    func testMissingTopicRetainsOriginalOptionalContext() throws {
        let value = try XCTUnwrap(PlayCircleEntryContext(topicID: nil, inviteCode: "Ab_09-x", registrationID: 23))
        XCTAssertEqual(value.legacyLink, .missingParameter)
        XCTAssertEqual(value.inviteCode, "Ab_09-x")
        XCTAssertEqual(value.registrationID, 23)
        XCTAssertEqual(PlayCircleEntryContext(topicID: nil, inviteCode: nil, registrationID: nil)?.legacyLink, .missingParameter)
    }

    func testInvalidParametersAreRejectedRatherThanSilentlyDropped() {
        for invalid in [0, -1] {
            XCTAssertNil(PlayCircleEntryContext(topicID: invalid, inviteCode: nil, registrationID: 23))
            XCTAssertNil(PlayCircleEntryContext(topicID: 17, inviteCode: nil, registrationID: invalid))
        }
        for invalid in ["", " a", "a ", "a/b", "a%2Fb", "a+b", "圈", String(repeating: "a", count: 65)] {
            XCTAssertNil(PlayCircleEntryContext(topicID: 17, inviteCode: invalid, registrationID: 23))
        }
    }

    func testOptionalValuesAndInviteBoundaryRemainExact() {
        XCTAssertEqual(PlayCircleEntryContext(topicID: 17, inviteCode: nil, registrationID: nil)?.legacyLink,
                       .play(topicID: 17, inviteCode: nil, registrationID: nil))
        let code = String(repeating: "A", count: 64)
        XCTAssertEqual(PlayCircleEntryContext(topicID: 17, inviteCode: code, registrationID: Int.max)?.inviteCode, code)
    }

    func testRevisionAndRetirementDiscardPresentation() throws {
        let context = try XCTUnwrap(PlayCircleEntryContext(topicID: 17, inviteCode: "Ab_09-x", registrationID: 23))
        var presentation = PlayCircleEntryPresentation(context: context, sessionRevision: 4)
        XCTAssertEqual(presentation.context(currentSessionRevision: 4), context)
        XCTAssertNil(presentation.context(currentSessionRevision: 5))
        presentation.retire()
        XCTAssertNil(presentation.context(currentSessionRevision: 4))
        XCTAssertNil(presentation.context(currentSessionRevision: 5))
    }

    func testAddingContextDoesNotEnableExternalURLRouting() {
        // Synthetic negative controls, not a proposed production URL contract.
        for origin in ["https://example.test", "http://example.test", "https://evil.test"] {
            let url = URL(string: origin + "/unapproved-circle?topicId=17&inviteCode=Ab_09-x&registrationId=23")!
            XCTAssertNil(NativeEntryLinkPolicy().parse(url))
            XCTAssertNil(NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"]).parse(url))
        }
    }
}
