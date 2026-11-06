import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline transport only. No SMS, login provider, vault or production endpoint.
private final class UpgradeResponseTransport: HTTPTransport {
    var responses: [(Data, Int)]
    var requests: [URLRequest] = []
    var deferred = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var requested: CheckedContinuation<Void, Never>?
    init(status: Int, body: String = "not JSON") {
        responses = [(Data(body.utf8), status)]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if deferred {
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                requested?.resume(); requested = nil
            }
        }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
}

@MainActor
final class AuthChannelUpgradeRequiredTests: XCTestCase {
    private func service(_ transport: UpgradeResponseTransport) throws -> AuthChannelService {
        try AuthChannelService(configuration: APIConfiguration(
            baseURL: URL(string: "https://api.example.com/gateway")!), transport: transport)
    }
    private let phone = "10000000000"
    private let code = "123456"
    private let fixedNow = Date(timeIntervalSince1970: 1_000)

    func testPhone426ShowsUpgradeWithoutDecodingOrCommittingIdentity() async throws {
        let transport = UpgradeResponseTransport(status: 426)
        var commits = 0
        let coordinator = AuthChannelCoordinator(service: try service(transport),
            currentSession: { .init(epoch: 1, accountID: nil) },
            commitLogin: { _, _ in commits += 1; return true })
        await coordinator.loginWithPhone(phone: phone, code: code)
        XCTAssertEqual(coordinator.state.issue, .upgradeRequired)
        XCTAssertEqual(coordinator.state.issue?.localizationKey, "auth.channels.upgradeRequired")
        XCTAssertTrue(coordinator.state.requiresAppUpdate)
        XCTAssertFalse(coordinator.state.signedIn)
        XCTAssertFalse(coordinator.state.isWorking)
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testSMS426KeepsUnknownAndCooldownWithoutAutomaticOrImmediateResend() async throws {
        let transport = UpgradeResponseTransport(status: 426)
        let coordinator = AuthChannelCoordinator(service: try service(transport),
            currentSession: { .init(epoch: 1, accountID: nil) },
            commitLogin: { _, _ in XCTFail("SMS must never commit identity"); return false },
            now: { self.fixedNow })
        await coordinator.sendSMSCode(phone: phone)
        XCTAssertEqual(coordinator.state.issue, .smsOutcomeUnknown)
        XCTAssertTrue(coordinator.state.requiresAppUpdate)
        XCTAssertFalse(coordinator.state.smsSent)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 60)
        let originalDeadline = coordinator.state.nextSMSAllowedAt
        await coordinator.sendSMSCode(phone: phone)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(coordinator.state.nextSMSAllowedAt, originalDeadline)
        coordinator.cancel()
        XCTAssertEqual(coordinator.state.nextSMSAllowedAt, originalDeadline)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 60)
        XCTAssertFalse(coordinator.state.requiresAppUpdate)
    }

    func testOtherHTTPStatusesAndBusiness426DoNotAcquireUpgradeMeaning() async throws {
        for (status, body, expected) in [
            (503, "", AuthChannelIssue.network),
            (401, "", .unauthorized),
            (429, "", .rateLimited),
            (200, #"{"code":426}"#, .rejected)
        ] {
            let transport = UpgradeResponseTransport(status: status, body: body)
            let coordinator = AuthChannelCoordinator(service: try service(transport),
                currentSession: { .init(epoch: 1, accountID: nil) }, commitLogin: { _, _ in false })
            await coordinator.loginWithPhone(phone: phone, code: code)
            XCTAssertEqual(coordinator.state.issue, expected)
            XCTAssertFalse(coordinator.state.requiresAppUpdate)
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testStale426AfterAccountSwitchDoesNotAttachErrorToNewIdentity() async throws {
        let transport = UpgradeResponseTransport(status: 426)
        transport.deferred = true
        var snapshot = AuthChannelSessionSnapshot(epoch: 1, accountID: nil)
        var commits = 0
        let coordinator = AuthChannelCoordinator(service: try service(transport),
            currentSession: { snapshot }, commitLogin: { _, _ in commits += 1; return true })
        let task = Task { await coordinator.loginWithPhone(phone: phone, code: code) }
        await transport.waitUntilRequested()
        snapshot = .init(epoch: 2, accountID: 42)
        transport.pending?.resume(returning: (Data(), 426)); transport.pending = nil
        await task.value
        XCTAssertNil(coordinator.state.issue)
        XCTAssertFalse(coordinator.state.requiresAppUpdate)
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(snapshot.accountID, 42)
    }

    func testDismissedSMS426DoesNotReviveFeedbackOrClearCooldown() async throws {
        let transport = UpgradeResponseTransport(status: 426)
        transport.deferred = true
        let coordinator = AuthChannelCoordinator(service: try service(transport),
            currentSession: { .init(epoch: 1, accountID: nil) }, commitLogin: { _, _ in false },
            now: { self.fixedNow })
        let task = Task { await coordinator.sendSMSCode(phone: phone) }
        await transport.waitUntilRequested()
        coordinator.cancel()
        transport.pending?.resume(returning: (Data(), 426)); transport.pending = nil
        await task.value
        XCTAssertNil(coordinator.state.issue)
        XCTAssertFalse(coordinator.state.requiresAppUpdate)
        XCTAssertEqual(coordinator.smsCooldownRemaining, 60)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCurrentAccount426DoesNotCommitLoginToken() async throws {
        let transport = UpgradeResponseTransport(status: 200,
            body: #"{"code":200,"token":"synthetic-token","data":{"id":7,"nickname":"Synthetic"}}"#)
        transport.responses.append((Data(), 426))
        var commits = 0
        let coordinator = AuthChannelCoordinator(service: try service(transport),
            currentSession: { .init(epoch: 1, accountID: nil) },
            commitLogin: { _, _ in commits += 1; return true })
        await coordinator.loginWithPhone(phone: phone, code: code)
        XCTAssertEqual(coordinator.state.issue, .upgradeRequired)
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(coordinator.state.signedIn)
        XCTAssertEqual(transport.requests.map { $0.url?.path },
                       ["/gateway/api/login/phone", "/gateway/api/userInfo"])
    }
}
