import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class PresentationOwnerService: AuthChannelServing {
    var smsCalls = 0, phoneCalls = 0, appleCalls = 0, readCalls = 0
    var holdPhone = false
    var phonePending: CheckedContinuation<LoginResult, Error>?
    func account() throws -> Account {
        try JSONDecoder().decode(Account.self, from: Data("{\"id\":7,\"role\":\"player\",\"nickname\":\"Verified\"}".utf8))
    }
    func login() throws -> LoginResult { LoginResult(token: "synthetic-token", account: try account()) }
    func sendSMSCode(phone: String) async throws { smsCalls += 1 }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult {
        phoneCalls += 1
        if holdPhone { return try await withCheckedThrowingContinuation { phonePending = $0 } }
        return try login()
    }
    func loginWithApple(identityToken: String) async throws -> LoginResult { appleCalls += 1; return try login() }
    func currentAccount(token: String) async throws -> Account { readCalls += 1; return try account() }
}

@MainActor private final class PresentationOwnerHost {
    let service = PresentationOwnerService()
    var snapshot = AuthChannelSessionSnapshot(epoch: 1, accountID: nil)
    var commits = 0
    var now = Date(timeIntervalSince1970: 1_000)
    lazy var coordinator = AuthChannelCoordinator(service: service, appleConfigurationVerified: true,
        currentSession: { self.snapshot }, commitLogin: { _, expected in
            guard self.snapshot == expected else { return false }
            self.commits += 1
            self.snapshot = .init(epoch: expected.epoch + 1, accountID: 7)
            return true
        }, now: { self.now })
}

@MainActor final class AuthChannelPresentationOwnershipTests: XCTestCase {
    func testReplacementIsLocalOnlyAndCannotGrantIdentity() {
        let host = PresentationOwnerHost()
        let old = host.coordinator.beginPresentation(), fresh = host.coordinator.beginPresentation()
        XCTAssertNotEqual(old, fresh)
        XCTAssertFalse(host.coordinator.ownsPresentation(old)); XCTAssertTrue(host.coordinator.ownsPresentation(fresh))
        XCTAssertEqual(host.snapshot, .init(epoch: 1, accountID: nil))
        XCTAssertEqual(host.service.smsCalls + host.service.phoneCalls + host.service.appleCalls + host.service.readCalls, 0)
        XCTAssertEqual(host.commits, 0); XCTAssertEqual(host.coordinator.smsCooldownRemaining, 0)
    }

    func testOldCleanupCannotRetireFreshQueuedIntent() async throws {
        let host = PresentationOwnerHost()
        let old = host.coordinator.beginPresentation(), fresh = host.coordinator.beginPresentation()
        let intent = try XCTUnwrap(host.coordinator.captureIntent(for: .phoneLogin))
        host.coordinator.cancel(presentation: old)
        XCTAssertTrue(host.coordinator.ownsPresentation(fresh))
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
        XCTAssertEqual(host.service.phoneCalls, 1); XCTAssertEqual(host.service.readCalls, 1)
        XCTAssertEqual(host.commits, 1); XCTAssertEqual(host.snapshot.accountID, 7)
    }

    func testReplacementRetiresBothKindsOfOldQueuedIntentWithoutDispatch() async throws {
        for work in [AuthChannelWork.sendingSMS, .phoneLogin] {
            let host = PresentationOwnerHost()
            _ = host.coordinator.beginPresentation()
            let old = try XCTUnwrap(host.coordinator.captureIntent(for: work))
            _ = host.coordinator.beginPresentation()
            if work == .sendingSMS { await host.coordinator.sendSMSCode(phone: "10000000000", intent: old) }
            else { await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: old) }
            XCTAssertEqual(host.service.smsCalls + host.service.phoneCalls + host.service.readCalls, 0)
            XCTAssertEqual(host.commits, 0); XCTAssertNil(host.coordinator.state.issue)
            XCTAssertEqual(host.coordinator.smsCooldownRemaining, 0)
        }
    }

    func testLateOldPhoneResultCannotReadBackOrClearNewPresentationIssue() async throws {
        let host = PresentationOwnerHost()
        let old = host.coordinator.beginPresentation()
        host.service.holdPhone = true
        let task = Task { await host.coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        for _ in 0..<1_000 { if host.service.phonePending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(host.service.phonePending)
        let fresh = host.coordinator.beginPresentation()
        await host.coordinator.loginWithPhone(phone: "10000000000", code: "bad")
        host.coordinator.cancel(presentation: old)
        pending.resume(returning: try host.service.login()); await task.value
        XCTAssertTrue(host.coordinator.ownsPresentation(fresh)); XCTAssertEqual(host.coordinator.state.issue, .invalidCode)
        XCTAssertEqual(host.service.phoneCalls, 1); XCTAssertEqual(host.service.readCalls, 0); XCTAssertEqual(host.commits, 0)
    }

    func testReplacementAndOldCleanupPreserveGlobalSMSCooldown() async throws {
        let host = PresentationOwnerHost()
        let old = host.coordinator.beginPresentation()
        await host.coordinator.sendSMSCode(phone: "10000000000")
        XCTAssertEqual(host.service.smsCalls, 1); XCTAssertTrue(host.coordinator.state.smsSent)
        let fresh = host.coordinator.beginPresentation()
        await host.coordinator.sendSMSCode(phone: "10000000001")
        XCTAssertEqual(host.coordinator.state.issue, .rateLimited)
        host.coordinator.cancel(presentation: old)
        XCTAssertEqual(host.coordinator.state.issue, .rateLimited); XCTAssertEqual(host.coordinator.smsCooldownRemaining, 60)
        host.now = host.now.addingTimeInterval(60)
        XCTAssertEqual(host.service.smsCalls, 1, "Time alone never sends a new SMS")
        await host.coordinator.sendSMSCode(phone: "10000000001")
        host.coordinator.cancel(presentation: old)
        XCTAssertTrue(host.coordinator.ownsPresentation(fresh)); XCTAssertTrue(host.coordinator.state.smsSent)
        XCTAssertEqual(host.service.smsCalls, 2)
    }

    func testCurrentCleanupAndGlobalCancellationKeepSamePresentationReusable() async throws {
        let host = PresentationOwnerHost(), coordinator = host.coordinator
        let owner = coordinator.beginPresentation()
        let old = try XCTUnwrap(coordinator.captureIntent(for: .phoneLogin))
        coordinator.cancel(presentation: owner)
        await coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: old)
        XCTAssertEqual(host.service.phoneCalls, 0); XCTAssertTrue(coordinator.ownsPresentation(owner))
        let cancelled = try XCTUnwrap(coordinator.captureIntent(for: .phoneLogin))
        coordinator.cancel()
        await coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: cancelled)
        XCTAssertEqual(host.service.phoneCalls, 0); XCTAssertTrue(coordinator.ownsPresentation(owner))
        await coordinator.loginWithPhone(phone: "10000000000", code: "654321")
        XCTAssertEqual(host.commits, 1)
    }

    func testOldAppleCleanupAndCallbackCannotCancelNewAppleAttempt() async throws {
        let host = PresentationOwnerHost(), coordinator = host.coordinator
        let old = coordinator.beginPresentation()
        let oldAttempt = try XCTUnwrap(coordinator.beginAppleAuthorization())
        _ = coordinator.beginPresentation()
        let freshAttempt = try XCTUnwrap(coordinator.beginAppleAuthorization())
        coordinator.cancel(presentation: old)
        coordinator.failAppleAuthorization(oldAttempt, issue: .appleIncomplete)
        await coordinator.completeAppleAuthorization(oldAttempt, identityToken: "synthetic.old.apple")
        XCTAssertTrue(coordinator.canCompleteAppleAuthorization(freshAttempt)); XCTAssertNil(coordinator.state.issue)
        XCTAssertEqual(host.service.appleCalls, 0)
        await coordinator.completeAppleAuthorization(freshAttempt, identityToken: "synthetic.new.apple")
        XCTAssertEqual(host.service.appleCalls, 1); XCTAssertEqual(host.service.readCalls, 1); XCTAssertEqual(host.commits, 1)
    }

    func testSessionIdentityFenceStillRejectsCurrentPresentationIntent() async throws {
        let host = PresentationOwnerHost(), coordinator = host.coordinator
        let owner = coordinator.beginPresentation()
        let intent = try XCTUnwrap(coordinator.captureIntent(for: .phoneLogin))
        host.snapshot = .init(epoch: 3, accountID: 8)
        await coordinator.loginWithPhone(phone: "10000000000", code: "123456", intent: intent)
        XCTAssertTrue(coordinator.ownsPresentation(owner)); XCTAssertFalse(coordinator.canStart)
        XCTAssertEqual(host.service.phoneCalls, 0); XCTAssertEqual(host.snapshot.accountID, 8)
    }
}
