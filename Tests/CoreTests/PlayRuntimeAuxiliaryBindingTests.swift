import XCTest
@testable import QuestifyCore

/// w2-11: additive play runtime auxiliary binding (`entryCode` registration resolution
/// and `PlayCircleLegacyLink` retirement state coordination).
final class PlayRuntimeAuxiliaryBindingTests: XCTestCase {
    func testEntryCodeResolvesMatchingScopeAndRejectsZeroNegativeOrMismatchedScope() throws {
        let topicEntry = try XCTUnwrap(ParticipationPlayEntry(registrationID: 501, scope: .topic(42)))
        let matching = PlayRuntimeAuxiliaryBinding(scope: .topic(42), participationEntry: topicEntry)
        XCTAssertEqual(matching.entryRegistrationID, 501)
        XCTAssertTrue(matching.hasEntryCode)
        XCTAssertFalse(matching.showsMissingEntryCodeExplanation)

        let mismatchedKind = PlayRuntimeAuxiliaryBinding(scope: .activity(42), participationEntry: topicEntry)
        XCTAssertNil(mismatchedKind.entryRegistrationID)
        XCTAssertFalse(mismatchedKind.hasEntryCode)
        XCTAssertTrue(mismatchedKind.showsMissingEntryCodeExplanation)

        let mismatchedID = PlayRuntimeAuxiliaryBinding(scope: .topic(99), participationEntry: topicEntry)
        XCTAssertNil(mismatchedID.entryRegistrationID)

        let missingEntry = PlayRuntimeAuxiliaryBinding(scope: .topic(42), participationEntry: nil)
        XCTAssertNil(missingEntry.entryRegistrationID)
        XCTAssertTrue(missingEntry.showsMissingEntryCodeExplanation)

        XCTAssertNil(PlayRuntimeAuxiliaryBinding.resolveEntryRegistrationID(
            for: .activity(18),
            rawRegistrationID: 0,
            entryScope: .activity(18)
        ))
        XCTAssertNil(PlayRuntimeAuxiliaryBinding.resolveEntryRegistrationID(
            for: .activity(18),
            rawRegistrationID: -7,
            entryScope: .activity(18)
        ))
        XCTAssertNil(PlayRuntimeAuxiliaryBinding.resolveEntryRegistrationID(
            for: .activity(0),
            rawRegistrationID: 501,
            entryScope: .activity(0)
        ))
        XCTAssertEqual(PlayRuntimeAuxiliaryBinding.resolveEntryRegistrationID(
            for: .activity(18),
            rawRegistrationID: 777,
            entryScope: .activity(18)
        ), 777)
    }

    func testLegacyCircleRetirementStateAndRedirectEntryCodeResolution() {
        let missing = PlayRuntimeAuxiliaryBinding.resolveCircleRetirement(query: [:])
        XCTAssertEqual(missing, .missingParameter)
        XCTAssertTrue(missing.isRetiredMissingPrompt)
        XCTAssertNil(missing.playEntry)

        let nonPositiveTopic = PlayRuntimeAuxiliaryBinding.resolveCircleRetirement(query: ["topicId": "0", "registrationId": "501"])
        XCTAssertEqual(nonPositiveTopic, .missingParameter)

        let redirect = PlayRuntimeAuxiliaryBinding.resolveCircleRetirement(
            query: ["topicId": " 12 ", "inviteCode": "AB_12-3", "registrationId": " 501 "]
        )
        XCTAssertEqual(
            redirect,
            .redirectToPlay(scope: .topic(12), topicID: 12, inviteCode: "AB_12-3", registrationID: 501)
        )
        XCTAssertFalse(redirect.isRetiredMissingPrompt)
        XCTAssertEqual(redirect.playEntry, ParticipationPlayEntry(registrationID: 501, scope: .topic(12)))

        let boundToMatchingTopic = PlayRuntimeAuxiliaryBinding(
            scope: .topic(12),
            rawRegistrationID: nil,
            entryScope: nil,
            legacyCircleQuery: ["topicId": "12", "inviteCode": "AB_12-3", "registrationId": "501"]
        )
        XCTAssertEqual(boundToMatchingTopic.entryRegistrationID, 501)
        XCTAssertEqual(
            boundToMatchingTopic.circleRetirement,
            .redirectToPlay(scope: .topic(12), topicID: 12, inviteCode: "AB_12-3", registrationID: 501)
        )

        let boundToDifferentTopic = PlayRuntimeAuxiliaryBinding(
            scope: .topic(99),
            rawRegistrationID: nil,
            entryScope: nil,
            legacyCircleQuery: ["topicId": "12", "inviteCode": "AB_12-3", "registrationId": "501"]
        )
        XCTAssertNil(boundToDifferentTopic.entryRegistrationID)

        let sanitized = PlayRuntimeAuxiliaryBinding.resolveCircleRetirement(
            query: ["topicId": "12", "inviteCode": "bad invite!", "registrationId": "0"]
        )
        XCTAssertEqual(
            sanitized,
            .redirectToPlay(scope: .topic(12), topicID: 12, inviteCode: nil, registrationID: nil)
        )
    }
}
