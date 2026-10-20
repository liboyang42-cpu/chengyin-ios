import XCTest
@testable import QuestifyCore

final class PushNotificationAndLiveActivityParityAuditTests: XCTestCase {
    func testCanonicalFiveCategoriesPassPushParityReadiness() {
        let result = PushNotificationAndLiveActivityParityAudit.evaluate()
        XCTAssertEqual(PushNotificationCategoryKind.allCases.count, 5)
        XCTAssertEqual(result.totalCategories, 5)
        XCTAssertEqual(result.compliantCategories, 5)
        XCTAssertTrue(result.coversAllCategories)
        XCTAssertTrue(result.isPushParityReady)
    }

    func testUnsanitizedDeepLinkRouteRejectsPushParityReadiness() {
        var descriptors = PushNotificationAndLiveActivityParityAudit.canonicalDescriptors
        descriptors[0] = PushNotificationCategoryDescriptor(
            id: PushNotificationCategoryKind.imDirectMessage.rawValue,
            category: .imDirectMessage,
            sanitizesDeepLinkRoute: false,
            redactsSensitivePreviewWhenLocked: true,
            respectsUserMutePreferences: true
        )

        let result = PushNotificationAndLiveActivityParityAudit.evaluate(descriptors: descriptors)
        XCTAssertFalse(descriptors[0].isCompliant)
        XCTAssertEqual(result.totalCategories, 5)
        XCTAssertEqual(result.compliantCategories, 4)
        XCTAssertTrue(result.coversAllCategories)
        XCTAssertFalse(result.isPushParityReady)
    }

    func testUnredactedLockedScreenPreviewFailsComplianceCheck() {
        var descriptors = PushNotificationAndLiveActivityParityAudit.canonicalDescriptors
        descriptors[1] = PushNotificationCategoryDescriptor(
            id: PushNotificationCategoryKind.teamInviteHandshake.rawValue,
            category: .teamInviteHandshake,
            sanitizesDeepLinkRoute: true,
            redactsSensitivePreviewWhenLocked: false,
            respectsUserMutePreferences: true
        )

        let result = PushNotificationAndLiveActivityParityAudit.evaluate(descriptors: descriptors)
        XCTAssertFalse(descriptors[1].isCompliant)
        XCTAssertEqual(result.compliantCategories, 4)
        XCTAssertTrue(result.coversAllCategories)
        XCTAssertFalse(result.isPushParityReady)
    }

    func testMissingCategoryDetectionRejectsCoverageAndReadiness() {
        let incompleteDescriptors = Array(
            PushNotificationAndLiveActivityParityAudit.canonicalDescriptors.dropLast()
        )

        let result = PushNotificationAndLiveActivityParityAudit.evaluate(
            descriptors: incompleteDescriptors
        )
        XCTAssertEqual(result.totalCategories, 4)
        XCTAssertEqual(result.compliantCategories, 4)
        XCTAssertFalse(result.coversAllCategories)
        XCTAssertFalse(result.isPushParityReady)
    }
}
