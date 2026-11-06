import Foundation
import XCTest
@testable import Questify

final class NativeNotificationPermissionStatusPresentationTests: XCTestCase {
    private typealias Status = NativeNotificationPermissionStatusPresentation

    func testInitialAbsentSnapshotIsWaitingNotLoading() {
        XCTAssertEqual(Status.project(authorization: nil, busy: false, hasIssue: false), .waiting)
    }
    func testAbsentSnapshotDuringReadIsLoading() {
        XCTAssertEqual(Status.project(authorization: nil, busy: true, hasIssue: false), .loading)
    }
    func testFailedReadWithoutSnapshotIsUnavailableNotLoadingOrDenied() {
        XCTAssertEqual(Status.project(authorization: nil, busy: false, hasIssue: true), .unavailable)
    }
    func testRetryWhilePreviousIssueRemainsIsLoading() {
        XCTAssertEqual(Status.project(authorization: nil, busy: true, hasIssue: true), .loading)
    }
    func testKnownAuthorizationIsPreservedForAllBusyAndIssueCombinations() {
        let values: [NativeNotificationPermissionAuthorization] = [.notDetermined, .denied, .authorized, .provisional, .ephemeral, .unknown(999)]
        for value in values {
            for busy in [false, true] {
                for hasIssue in [false, true] {
                    XCTAssertEqual(Status.project(authorization: value, busy: busy, hasIssue: hasIssue), .known(value))
                }
            }
        }
    }
    func testFutureAuthorizationRetainsRawValueAndHasNoFabricatedMessageKey() {
        let status = Status.project(authorization: .unknown(999), busy: false, hasIssue: false)
        XCTAssertEqual(status, .known(.unknown(999)))
        XCTAssertNil(status.messageKey)
    }
    func testPresentationKeysSeparateIdleBusyAndFailure() {
        XCTAssertEqual(Status.waiting.messageKey, "permission.status.waiting")
        XCTAssertEqual(Status.loading.messageKey, "permission.status.loading")
        XCTAssertEqual(Status.unavailable.messageKey, "permission.status.unavailable")
        XCTAssertNil(Status.known(.denied).messageKey)
    }
    func testKnownTitleReusesOriginalLocaleMappingWithoutNewPermissionMeaning() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            for value in [NativeNotificationPermissionAuthorization.notDetermined, .denied, .authorized, .provisional, .ephemeral, .unknown(999)] {
                XCTAssertEqual(Status.known(value).title(locale: locale), NativeChannelNotificationPresentation.authorization(value, locale: locale))
            }
        }
    }
    func testFailureAndRetryRecoveryProjectOnlyReturnedSnapshot() {
        let states: [Status] = [
            .project(authorization: nil, busy: false, hasIssue: false),
            .project(authorization: nil, busy: true, hasIssue: false),
            .project(authorization: nil, busy: false, hasIssue: true),
            .project(authorization: nil, busy: true, hasIssue: true),
            .project(authorization: .denied, busy: false, hasIssue: false)
        ]
        XCTAssertEqual(states, [.waiting, .loading, .unavailable, .loading, .known(.denied)])
    }
}
