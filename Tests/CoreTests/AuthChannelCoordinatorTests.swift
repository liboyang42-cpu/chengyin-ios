import Foundation
import XCTest
@testable import QuestifyCore

/// In-memory, deterministic continuations. These fixtures never send SMS or contact
/// Apple/backend services, and deliberately ignore Task cancellation to test stale work.
@MainActor
private final class ControlledAuthChannelService: AuthChannelServing {
    enum Kind { case sms, phone, apple, current }
    var calls: [Kind] = []
    var sms: [CheckedContinuation<Void, Error>] = []
    var logins: [CheckedContinuation<LoginResult, Error>] = []
    var accounts: [CheckedContinuation<Account, Error>] = []
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func sendSMSCode(phone: String) async throws {
        try await withCheckedThrowingContinuation { sms.append($0); calls.append(.sms); notify() }
    }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult {
        try await withCheckedThrowingContinuation { logins.append($0); calls.append(.phone); notify() }
    }
    func loginWithApple(identityToken: String) async throws -> LoginResult {
        try await withCheckedThrowingContinuation { logins.append($0); calls.append(.apple); notify() }
    }
    func currentAccount(token: String) async throws -> Account {
        try await withCheckedThrowingContinuation { accounts.append($0); calls.append(.current); notify() }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    private func notify() {
        let ready = waiters.filter { calls.count >= $0.0 }
        waiters.removeAll { calls.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

@MainActor
private final class AuthChannelHost {
    var snapshot = AuthChannelSessionSnapshot(epoch: 1, accountID: nil)
    var commits: [LoginResult] = []
    var shouldFailStorage = false
    var rejectCommit = false
    var now = Date(timeIntervalSince1970: 1_000)
    func coordinator(_ service: (any AuthChannelServing)?, apple: Bool = false) -> AuthChannelCoordinator {
        AuthChannelCoordinator(service: service, appleConfigurationVerified: apple, currentSession: { self.snapshot }, commitLogin: { result, expected in
            guard self.snapshot == expected, !self.rejectCommit else { return false }
            if self.shouldFailStorage { throw CocoaError(.fileWriteUnknown) }
            self.commits.append(result)
            self.snapshot = AuthChannelSessionSnapshot(epoch: self.snapshot.epoch + 1, accountID: result.account.id)
            return true
        }, now: { self.now })
    }
}

@MainActor
final class AuthChannelCoordinatorTests: XCTestCase {
    private func account(_ id: Int = 7, nickname: String = "Verified") throws -> Account {
        try JSONDecoder().decode(Account.self, from: Data("{\"id\":\(id),\"nickname\":\"\(nickname)\"}".utf8))
    }
    private func login(_ id: Int = 7) throws -> LoginResult {
        LoginResult(token: "synthetic-token", account: try account(id, nickname: "Login"))
    }
    func testPhoneReadbackAndAtomicHostCommit() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        await service.waitForCalls(1)
        XCTAssertEqual(coordinator.state.work, .phoneLogin)
        service.logins.removeFirst().resume(returning: try login())
        await service.waitForCalls(2)
        XCTAssertTrue(host.commits.isEmpty)
        service.accounts.removeFirst().resume(returning: try account())
        await task.value
        XCTAssertEqual(host.commits.count, 1)
        XCTAssertEqual(host.commits.first?.account.nickname, "Verified")
        XCTAssertTrue(coordinator.state.signedIn); XCTAssertFalse(coordinator.state.isWorking)
    }
    func testDuplicateLoginAndSMSDuringLoginAreIgnored() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service, apple: true)
        let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        await service.waitForCalls(1)
        await coordinator.loginWithPhone(phone: "10000000000", code: "123456")
        await coordinator.sendSMSCode(phone: "10000000000")
        XCTAssertNil(coordinator.beginAppleAuthorization())
        XCTAssertEqual(service.calls.count, 1)
        coordinator.cancel()
        service.logins.removeFirst().resume(returning: try login())
        await task.value
        XCTAssertTrue(host.commits.isEmpty); XCTAssertEqual(service.calls.count, 1)
    }
    func testCancellationThenReentryRejectsOldResponse() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let old = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        await service.waitForCalls(1)
        coordinator.cancel()
        let newer = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "654321") }
        await service.waitForCalls(2)
        service.logins.removeFirst().resume(throwing: APIError.unauthorized)
        await old.value
        XCTAssertEqual(coordinator.state.work, .phoneLogin); XCTAssertNil(coordinator.state.issue)
        service.logins.removeFirst().resume(returning: try login())
        await service.waitForCalls(3)
        service.accounts.removeFirst().resume(returning: try account())
        await newer.value
        XCTAssertEqual(host.commits.count, 1)
    }
    func testSessionChangesDuringReadbackPreventCommitAndStaleErrors() async throws {
        for error in [false, true] {
            let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
            let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
            await service.waitForCalls(1)
            service.logins.removeFirst().resume(returning: try login())
            await service.waitForCalls(2)
            host.snapshot = AuthChannelSessionSnapshot(epoch: 3, accountID: 99)
            if error { service.accounts.removeFirst().resume(throwing: APIError.unauthorized) }
            else { service.accounts.removeFirst().resume(returning: try account()) }
            await task.value
            XCTAssertTrue(host.commits.isEmpty); XCTAssertNil(coordinator.state.issue)
            XCTAssertFalse(coordinator.state.isWorking); XCTAssertEqual(host.snapshot.accountID, 99)
        }
    }
    func testMismatchedCurrentAccountCannotCommit() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        await service.waitForCalls(1)
        service.logins.removeFirst().resume(returning: try login())
        await service.waitForCalls(2)
        service.accounts.removeFirst().resume(returning: try account(8))
        await task.value
        XCTAssertTrue(host.commits.isEmpty); XCTAssertEqual(coordinator.state.issue, .invalidResponse)
    }
    func testCancelledTaskCannotCommitEvenIfTransportCompletes() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
        await service.waitForCalls(1)
        task.cancel()
        service.logins.removeFirst().resume(returning: try login())
        await task.value
        XCTAssertTrue(host.commits.isEmpty); XCTAssertEqual(service.calls.count, 1)
        XCTAssertFalse(coordinator.state.isWorking); XCTAssertNil(coordinator.state.issue)
    }
    func testStorageAndCommitRejectionDoNotReportSignedIn() async throws {
        for storageFailure in [true, false] {
            let service = ControlledAuthChannelService(), host = AuthChannelHost()
            host.shouldFailStorage = storageFailure; host.rejectCommit = !storageFailure
            let coordinator = host.coordinator(service)
            let task = Task { await coordinator.loginWithPhone(phone: "10000000000", code: "123456") }
            await service.waitForCalls(1)
            service.logins.removeFirst().resume(returning: try login())
            await service.waitForCalls(2)
            service.accounts.removeFirst().resume(returning: try account())
            await task.value
            XCTAssertFalse(coordinator.state.signedIn); XCTAssertTrue(host.commits.isEmpty)
            XCTAssertEqual(coordinator.state.issue, storageFailure ? .storage : .sessionUnavailable)
        }
    }
    func testSMSDuplicateTapCooldownDismissalAndExplicitResend() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let first = Task { await coordinator.sendSMSCode(phone: "10000000000") }
        await service.waitForCalls(1)
        await coordinator.sendSMSCode(phone: "10000000000")
        XCTAssertEqual(service.calls.count, 1); XCTAssertEqual(coordinator.smsCooldownRemaining, 60)
        service.sms.removeFirst().resume()
        await first.value
        XCTAssertTrue(coordinator.state.smsSent)
        coordinator.cancel()
        await coordinator.sendSMSCode(phone: "10000000001")
        XCTAssertEqual(service.calls.count, 1); XCTAssertEqual(coordinator.state.issue, .rateLimited)
        host.now = host.now.addingTimeInterval(60)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 0); XCTAssertEqual(service.calls.count, 1)
        let resend = Task { await coordinator.sendSMSCode(phone: "10000000000") }
        await service.waitForCalls(2)
        service.sms.removeFirst().resume()
        await resend.value
        XCTAssertTrue(coordinator.state.smsSent)
    }
    func testSMSUncertainResponseDoesNotAutoRetryOrClaimSent() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let task = Task { await coordinator.sendSMSCode(phone: "10000000000") }
        await service.waitForCalls(1)
        service.sms.removeFirst().resume(throwing: URLError(.timedOut))
        await task.value
        XCTAssertEqual(coordinator.state.issue, .smsOutcomeUnknown); XCTAssertFalse(coordinator.state.smsSent)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 60); XCTAssertEqual(service.calls.count, 1)
    }
    func testCancelledSMSCompletionCannotShowSuccess() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        let task = Task { await coordinator.sendSMSCode(phone: "10000000000") }
        await service.waitForCalls(1)
        task.cancel()
        service.sms.removeFirst().resume()
        await task.value
        XCTAssertFalse(coordinator.state.smsSent); XCTAssertEqual(coordinator.state.issue, .smsOutcomeUnknown)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 60)
    }
    func testInvalidInputAndUnavailableSessionNeverDispatch() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service)
        await coordinator.sendSMSCode(phone: "invalid")
        XCTAssertEqual(coordinator.state.issue, .invalidPhone)
        await coordinator.loginWithPhone(phone: "10000000000", code: "")
        XCTAssertEqual(coordinator.state.issue, .invalidCode)
        for snapshot in [AuthChannelSessionSnapshot(epoch: 2, accountID: 7), AuthChannelSessionSnapshot(epoch: 3, accountID: nil, isBusy: true)] {
            host.snapshot = snapshot
            await coordinator.loginWithPhone(phone: "10000000000", code: "123456")
            XCTAssertEqual(coordinator.state.issue, .sessionUnavailable)
        }
        XCTAssertTrue(service.calls.isEmpty)
        let missing = host.coordinator(nil)
        await missing.sendSMSCode(phone: "10000000000")
        XCTAssertEqual(missing.state.issue, .notConfigured)
    }
    func testAppleDefaultsDisabledAndCancellationIsNeutral() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost()
        let disabled = host.coordinator(service)
        XCTAssertNil(disabled.beginAppleAuthorization()); XCTAssertEqual(disabled.state.issue, .appleNotConfigured)
        let enabled = host.coordinator(service, apple: true)
        let attempt = try XCTUnwrap(enabled.beginAppleAuthorization())
        XCTAssertNil(enabled.beginAppleAuthorization())
        enabled.failAppleAuthorization(attempt, issue: .appleIncomplete)
        XCTAssertEqual(enabled.state.issue, .appleIncomplete); XCTAssertFalse(enabled.state.isWorking)
        XCTAssertTrue(service.calls.isEmpty)
    }
    func testAppleExchangeReadbackAndDuplicateCompletion() async throws {
        let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service, apple: true)
        let attempt = try XCTUnwrap(coordinator.beginAppleAuthorization())
        let task = Task { await coordinator.completeAppleAuthorization(attempt, identityToken: "synthetic.apple.token") }
        await service.waitForCalls(1)
        await coordinator.completeAppleAuthorization(attempt, identityToken: "synthetic.apple.token")
        XCTAssertEqual(service.calls.count, 1)
        service.logins.removeFirst().resume(returning: try login())
        await service.waitForCalls(2)
        service.accounts.removeFirst().resume(returning: try account())
        await task.value
        XCTAssertTrue(coordinator.state.signedIn); XCTAssertEqual(host.commits.count, 1)
    }
    func testLateAppleCallbackAfterDismissalOrSessionChangeNeverExchanges() async throws {
        for dismiss in [true, false] {
            let service = ControlledAuthChannelService(), host = AuthChannelHost(), coordinator = host.coordinator(service, apple: true)
            let attempt = try XCTUnwrap(coordinator.beginAppleAuthorization())
            if dismiss { coordinator.cancel() }
            else { host.snapshot = AuthChannelSessionSnapshot(epoch: 3, accountID: 7) }
            await coordinator.completeAppleAuthorization(attempt, identityToken: "synthetic.apple.token")
            XCTAssertTrue(service.calls.isEmpty); XCTAssertFalse(coordinator.state.isWorking)
        }
    }
}
