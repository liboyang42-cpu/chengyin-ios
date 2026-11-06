import Foundation
import XCTest
@testable import QuestifyCore

/// Synthetic in-memory operations only. No SMS, provider or backend is contacted.
@MainActor private final class QueuedIntentService: AuthChannelServing {
    var sms = 0, phones = 0, apples = 0, reads = 0
    var readError: Error?
    var verifiedID = 7
    func account(_ id: Int) throws -> Account {
        try JSONDecoder().decode(Account.self,
            from: Data("{\"id\":\(id),\"role\":\"player\",\"nickname\":\"Verified\"}".utf8))
    }
    func sendSMSCode(phone: String) async throws { sms += 1 }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult {
        phones += 1
        return LoginResult(token: "synthetic-token", account: try account(7))
    }
    func loginWithApple(identityToken: String) async throws -> LoginResult {
        apples += 1
        return LoginResult(token: "synthetic-token", account: try account(7))
    }
    func currentAccount(token: String) async throws -> Account {
        reads += 1
        if let readError { throw readError }
        return try account(verifiedID)
    }
}

@MainActor private final class QueuedIntentHost {
    var snapshot = AuthChannelSessionSnapshot(epoch: 1, accountID: nil)
    var commits: [LoginResult] = []
    let service = QueuedIntentService()
    lazy var coordinator = AuthChannelCoordinator(service: service,
        appleConfigurationVerified: true, currentSession: { self.snapshot },
        commitLogin: { result, expected in
            guard self.snapshot == expected else { return false }
            self.commits.append(result)
            self.snapshot = .init(epoch: expected.epoch + 1, accountID: result.account.id)
            return true
        })
}

@MainActor final class AuthChannelQueuedIntentTests: XCTestCase {
    func testCloseBeforeQueuedPhoneOrSMSRunsHasNoDispatchOrCooldown() async throws {
        for work in [AuthChannelWork.phoneLogin, .sendingSMS] {
            let host = QueuedIntentHost()
            let intent = try XCTUnwrap(host.coordinator.captureIntent(for: work))
            host.coordinator.cancel()
            if work == .phoneLogin {
                await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
            } else {
                await host.coordinator.sendSMSCode(phone: "10000000000", intent: intent)
            }
            XCTAssertEqual(host.service.phones, 0); XCTAssertEqual(host.service.sms, 0)
            XCTAssertEqual(host.service.reads, 0); XCTAssertTrue(host.commits.isEmpty)
            XCTAssertEqual(host.coordinator.smsCooldownRemaining, 0)
            XCTAssertNil(host.coordinator.state.issue)
        }
    }

    func testQueuedIntentRejectsLogoutAndSameGuestABAByEpoch() async throws {
        for changed in [AuthChannelSessionSnapshot(epoch: 2, accountID: nil),
                        .init(epoch: 3, accountID: 99), .init(epoch: 1, accountID: nil, isBusy: true)] {
            let host = QueuedIntentHost()
            let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
            host.snapshot = changed
            await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
            XCTAssertEqual(host.service.phones, 0); XCTAssertTrue(host.commits.isEmpty)
            XCTAssertEqual(host.snapshot, changed); XCTAssertNil(host.coordinator.state.issue)
        }
    }

    func testIntentCannotChangeOperationAndConsumesOnlyOnce() async throws {
        let host = QueuedIntentHost()
        let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .sendingSMS))
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
        XCTAssertEqual(host.service.phones, 0)
        await host.coordinator.sendSMSCode(phone: "10000000000", intent: intent)
        await host.coordinator.sendSMSCode(phone: "10000000000", intent: intent)
        XCTAssertEqual(host.service.sms, 1); XCTAssertTrue(host.coordinator.state.smsSent)
        XCTAssertNil(host.coordinator.state.issue, "A replay must not replace success with rateLimited")
    }

    func testValidationFailureStillConsumesOriginalIntent() async throws {
        let host = QueuedIntentHost()
        let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
        await host.coordinator.loginWithPhone(phone: "invalid", code: "123456", intent: intent)
        XCTAssertEqual(host.coordinator.state.issue, .invalidPhone)
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
        XCTAssertEqual(host.service.phones, 0); XCTAssertTrue(host.commits.isEmpty)
    }

    func testNewIntentAfterReentryUsesVerifiedAccountAndRetiresOldIntent() async throws {
        let host = QueuedIntentHost()
        let old = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
        host.coordinator.cancel()
        let fresh = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: old)
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "654321", intent: fresh)
        XCTAssertEqual(host.service.phones, 1); XCTAssertEqual(host.service.reads, 1)
        XCTAssertEqual(host.commits.first?.account.nickname, "Verified")
        XCTAssertEqual(host.snapshot.accountID, 7); XCTAssertTrue(host.coordinator.state.signedIn)
    }

    func testReadbackMismatchOrUnauthorizedNeverCommitsQueuedLogin() async throws {
        for unauthorized in [false, true] {
            let host = QueuedIntentHost()
            host.service.verifiedID = 8
            if unauthorized { host.service.readError = APIError.unauthorized }
            let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
            await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
            XCTAssertEqual(host.service.phones, 1); XCTAssertEqual(host.service.reads, 1)
            XCTAssertTrue(host.commits.isEmpty); XCTAssertNil(host.snapshot.accountID)
            XCTAssertEqual(host.coordinator.state.issue, unauthorized ? .unauthorized : .invalidResponse)
        }
    }

    func testCancelledQueuedTaskCannotDispatch() async throws {
        let host = QueuedIntentHost()
        let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .sendingSMS))
        let task = Task { await host.coordinator.sendSMSCode(phone: "10000000000", intent: intent) }
        task.cancel()
        await task.value
        XCTAssertEqual(host.service.sms, 0); XCTAssertEqual(host.coordinator.smsCooldownRemaining, 0)
    }

    func testAppleOriginalAttemptRemainsFencedBeforeReplacingPhoneQueue() async throws {
        let host = QueuedIntentHost()
        let phone = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
        let apple = try XCTUnwrap(host.coordinator.beginAppleAuthorization())
        XCTAssertTrue(host.coordinator.canCompleteAppleAuthorization(apple))
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: phone)
        XCTAssertEqual(host.service.phones, 0)
        host.coordinator.cancel()
        XCTAssertFalse(host.coordinator.canCompleteAppleAuthorization(apple))
        await host.coordinator.completeAppleAuthorization(apple, identityToken: "synthetic.apple.token")
        XCTAssertEqual(host.service.apples, 0); XCTAssertTrue(host.commits.isEmpty)
        XCTAssertNil(host.coordinator.captureIntent(for: .appleExchange))
    }
}
