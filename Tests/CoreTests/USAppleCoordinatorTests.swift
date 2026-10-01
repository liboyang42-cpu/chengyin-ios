#if DEBUG
import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
private final class USAppleSuspension<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    var isWaiting: Bool { continuation != nil }
    func wait() async throws -> Value { try await withCheckedThrowingContinuation { continuation = $0 } }
    func resume(_ value: Value) { let pending = continuation; continuation = nil; pending?.resume(returning: value) }
}
@MainActor
private final class USAppleControlledService: USAppleServing {
    var challengeCalls = 0
    var exchangeCalls: [(id: String, state: String, token: String)] = []
    var onChallenge: (() async throws -> USAppleChallenge)?
    var onExchange: (() async throws -> LoginResult)?
    func challenge() async throws -> USAppleChallenge {
        challengeCalls += 1
        if let onChallenge { return try await onChallenge() }
        return try USAppleFixtures.challenge()
    }
    func exchange(challengeId: String, state: String, identityToken: String) async throws -> LoginResult {
        exchangeCalls.append((challengeId, state, identityToken))
        if let onExchange { return try await onExchange() }
        return LoginResult(token: "synthetic-session", account: try USAppleFixtures.account(nickname: "Exchange"))
    }
}
@MainActor
private final class USAppleControlledAuthorizer: USAppleAuthorizing {
    var requests: [USAppleAuthorizationRequest] = []
    var onAuthorize: (() async throws -> USAppleCredential)?
    var cancelCount = 0
    func authorize(_ request: USAppleAuthorizationRequest) async throws -> USAppleCredential {
        requests.append(request)
        if let onAuthorize { return try await onAuthorize() }
        return USAppleCredential(identityToken: "fixture.jwt.token", state: request.state)
    }
    // Deliberately ignore cancellation: tests must prove the coordinator fences late callbacks.
    func cancel() { cancelCount += 1 }
}
@MainActor
private final class USAppleHost {
    let service = USAppleControlledService()
    let authorizer = USAppleControlledAuthorizer()
    var epoch: UInt64 = 1
    var market: RegionalMarket = .unitedStates
    var realm = "fixture-US"
    var accountID: Int?
    var busy = false
    var time: TimeInterval = 100
    var verifiedCalls: [String] = []
    var commits: [LoginResult] = []
    var verify: (() async throws -> USAppleVerifiedCurrentAccount)?
    var commitAccepted = true
    var commitThrows = false
    var hash: (String) throws -> String = { _ in USAppleFixtures.digest }
    var snapshot: USAppleSessionSnapshot { USAppleSessionSnapshot(epoch: epoch, market: market, realm: realm, accountID: accountID, isBusy: busy) }
    func currentAccount(_ token: String) async throws -> USAppleVerifiedCurrentAccount {
        verifiedCalls.append(token)
        if let verify { return try await verify() }
        return USAppleVerifiedCurrentAccount(account: try USAppleFixtures.account(), market: .unitedStates, realm: "fixture-US")
    }
    func commit(_ result: LoginResult, expected: USAppleSessionSnapshot) throws -> Bool {
        guard snapshot == expected, commitAccepted else { return false }
        if commitThrows { throw USAppleClientError.storage }
        commits.append(result); epoch += 1; accountID = result.account.id
        return true
    }
    func coordinator(production: Bool = false) throws -> USAppleCoordinator {
        let deployment = try USAppleFixtures.deployment()
        if production {
            return USAppleCoordinator(deployment: deployment, service: service, authorizer: authorizer,
                currentSession: { self.snapshot }, verifyCurrentAccount: currentAccount, commitLogin: commit, now: { self.time })
        }
        return USAppleCoordinator(offlineDeployment: deployment, service: service, authorizer: authorizer,
            currentSession: { self.snapshot }, verifyCurrentAccount: currentAccount, commitLogin: commit, now: { self.time }, nonceDigest: hash)
    }
}

@MainActor
final class USAppleCoordinatorTests: XCTestCase {
    private func wait(until condition: @escaping () -> Bool) async {
        for _ in 0..<1_000 { if condition() { return }; await Task.yield() }
        XCTFail("Synthetic continuation was not reached")
    }
    func testProductionCoordinatorDoesNotProbeEvenWithAllDependenciesInjected() async throws {
        let host = USAppleHost(), coordinator = try host.coordinator(production: true)
        XCTAssertFalse(coordinator.isAvailable); XCTAssertFalse(coordinator.canStart)
        await coordinator.signIn()
        XCTAssertEqual(coordinator.state.issue, .unavailable)
        XCTAssertEqual(host.service.challengeCalls, 0); XCTAssertTrue(host.authorizer.requests.isEmpty)
    }
    func testFullAttemptUsesHashAndStateThenVerifiedAccountAndAtomicCommit() async throws {
        let host = USAppleHost()
        var hashInputs: [String] = []
        host.hash = { hashInputs.append($0); return USAppleFixtures.digest }
        let coordinator = try host.coordinator()
        await coordinator.signIn()
        XCTAssertEqual(hashInputs, [USAppleFixtures.rawNonce])
        XCTAssertEqual(host.authorizer.requests.first?.nonce, USAppleFixtures.digest)
        XCTAssertEqual(host.authorizer.requests.first?.state, USAppleFixtures.state)
        XCTAssertEqual(host.service.exchangeCalls.first?.id, USAppleFixtures.challengeID)
        XCTAssertEqual(host.service.exchangeCalls.first?.state, USAppleFixtures.state)
        XCTAssertEqual(host.service.exchangeCalls.first?.token, "fixture.jwt.token")
        XCTAssertEqual(host.verifiedCalls, ["synthetic-session"])
        XCTAssertEqual(host.commits.first?.account.nickname, "Verified")
        XCTAssertEqual(host.commits.count, 1); XCTAssertTrue(coordinator.state.signedIn); XCTAssertNil(coordinator.state.work)
        await coordinator.signIn()
        XCTAssertEqual(host.service.challengeCalls, 1)
    }
    func testMissingOrIncorrectEchoStateNeverExchanges() async throws {
        let states: [String?] = [nil, "", USAppleFixtures.challengeID]
        for state in states {
            let host = USAppleHost()
            host.authorizer.onAuthorize = { USAppleCredential(identityToken: "fixture.jwt.token", state: state) }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertEqual(coordinator.state.issue, .invalidChallenge)
            XCTAssertTrue(host.service.exchangeCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty)
        }
    }
    func testMissingOversizedOrInvalidCredentialNeverExchanges() async throws {
        for token in ["", "bad\nvalue", String(repeating: "x", count: 16_385)] {
            let host = USAppleHost()
            host.authorizer.onAuthorize = { USAppleCredential(identityToken: token, state: USAppleFixtures.state) }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertEqual(coordinator.state.issue, .invalidIdentity); XCTAssertTrue(host.service.exchangeCalls.isEmpty)
        }
    }
    func testDuplicateTapCannotStartSecondChallengeWhileProviderIsPending() async throws {
        let host = USAppleHost(), gate = USAppleSuspension<USAppleCredential>()
        host.authorizer.onAuthorize = { try await gate.wait() }
        let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
        await wait { gate.isWaiting }
        await coordinator.signIn()
        XCTAssertEqual(host.service.challengeCalls, 1); XCTAssertEqual(host.authorizer.requests.count, 1)
        gate.resume(USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state))
        await task.value
        XCTAssertEqual(host.service.exchangeCalls.count, 1); XCTAssertEqual(host.commits.count, 1)
    }
    func testCancellationDuringChallengeRejectsLateChallenge() async throws {
        let host = USAppleHost(), gate = USAppleSuspension<USAppleChallenge>()
        host.service.onChallenge = { try await gate.wait() }
        let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
        await wait { gate.isWaiting }; coordinator.cancel()
        gate.resume(try USAppleFixtures.challenge()); await task.value
        XCTAssertTrue(host.authorizer.requests.isEmpty); XCTAssertTrue(host.commits.isEmpty); XCTAssertNil(coordinator.state.issue)
    }
    func testCancelledProviderAndLateCallbackCannotExchange() async throws {
        let host = USAppleHost(), gate = USAppleSuspension<USAppleCredential>()
        host.authorizer.onAuthorize = { try await gate.wait() }
        let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
        await wait { gate.isWaiting }; coordinator.cancel()
        gate.resume(USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state)); await task.value
        XCTAssertTrue(host.service.exchangeCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty); XCTAssertFalse(coordinator.state.isWorking)
    }
    func testTaskCancellationWithoutExplicitHostCancelFencesLateProvider() async throws {
        let host = USAppleHost(), gate = USAppleSuspension<USAppleCredential>()
        host.authorizer.onAuthorize = { try await gate.wait() }
        let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
        await wait { gate.isWaiting }; task.cancel()
        gate.resume(USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state)); await task.value
        XCTAssertTrue(host.service.exchangeCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty)
    }
    func testLateOldCallbackCannotAffectReplacementAttempt() async throws {
        let host = USAppleHost(), old = USAppleSuspension<USAppleCredential>(), fresh = USAppleSuspension<USAppleCredential>()
        host.authorizer.onAuthorize = { try await old.wait() }
        let coordinator = try host.coordinator(), first = Task { await coordinator.signIn() }
        await wait { old.isWaiting }; coordinator.cancel()
        host.authorizer.onAuthorize = { try await fresh.wait() }
        let second = Task { await coordinator.signIn() }; await wait { fresh.isWaiting }
        let cancels = host.authorizer.cancelCount
        old.resume(USAppleCredential(identityToken: "old.jwt.token", state: USAppleFixtures.state)); await first.value
        XCTAssertEqual(coordinator.state.work, .authorizing); XCTAssertEqual(host.authorizer.cancelCount, cancels)
        XCTAssertTrue(host.service.exchangeCalls.isEmpty)
        fresh.resume(USAppleCredential(identityToken: "fresh.jwt.token", state: USAppleFixtures.state)); await second.value
        XCTAssertEqual(host.service.exchangeCalls.map { $0.token }, ["fresh.jwt.token"]); XCTAssertEqual(host.commits.count, 1)
        XCTAssertEqual(host.service.challengeCalls, 2)
    }
    func testTTLIncludesChallengeLatencyAndRejectsAtExactDeadline() async throws {
        let host = USAppleHost()
        host.service.onChallenge = { host.time = 400; return try USAppleFixtures.challenge() }
        let coordinator = try host.coordinator(); await coordinator.signIn()
        XCTAssertEqual(coordinator.state.issue, .invalidChallenge); XCTAssertTrue(host.authorizer.requests.isEmpty)
    }
    func testExpiryAndClockRollbackCancelActiveProviderAndFenceLateResult() async throws {
        for time in [TimeInterval(400), 99, .infinity, .nan] {
            let host = USAppleHost(), gate = USAppleSuspension<USAppleCredential>()
            host.authorizer.onAuthorize = { try await gate.wait() }
            let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
            await wait { gate.isWaiting }; host.time = time; coordinator.expireIfNeeded()
            XCTAssertFalse(coordinator.state.isWorking); XCTAssertEqual(coordinator.state.issue, .invalidChallenge)
            gate.resume(USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state)); await task.value
            XCTAssertTrue(host.service.exchangeCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty)
        }
    }
    func testCancellationOrExpiryDuringExchangeNeverVerifiesOrCommits() async throws {
        for expiry in [false, true] {
            let host = USAppleHost(), gate = USAppleSuspension<LoginResult>()
            host.service.onExchange = { try await gate.wait() }
            let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
            await wait { gate.isWaiting }
            if expiry { host.time = 400; coordinator.expireIfNeeded() } else { coordinator.cancel() }
            gate.resume(LoginResult(token: "synthetic-session", account: try USAppleFixtures.account())); await task.value
            XCTAssertTrue(host.verifiedCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty)
        }
    }
    func testCancellationOrSessionEpochChangeDuringVerificationNeverCommits() async throws {
        for cancel in [false, true] {
            let host = USAppleHost(), gate = USAppleSuspension<USAppleVerifiedCurrentAccount>()
            host.verify = { try await gate.wait() }
            let coordinator = try host.coordinator(), task = Task { await coordinator.signIn() }
            await wait { gate.isWaiting }
            if cancel { coordinator.cancel() } else { host.epoch += 1 }
            gate.resume(USAppleVerifiedCurrentAccount(account: try USAppleFixtures.account(), market: .unitedStates, realm: "fixture-US")); await task.value
            XCTAssertTrue(host.commits.isEmpty); XCTAssertFalse(coordinator.state.signedIn)
        }
    }
    func testCurrentAccountMustMatchIDMarketAndIndependentlyVerifiedRealm() async throws {
        for (id, market, realm) in [(8, RegionalMarket.unitedStates, "fixture-US"), (7, .china, "fixture-US"), (7, .unitedStates, "other-realm")] {
            let host = USAppleHost()
            host.verify = { USAppleVerifiedCurrentAccount(account: try USAppleFixtures.account(id), market: market, realm: realm) }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertTrue(host.commits.isEmpty); XCTAssertEqual(coordinator.state.issue, .invalidResponse)
        }
    }
    func testSessionAdmissionRejectsCNWrongRealmBusyAndExistingAccountBeforeChallenge() async throws {
        for variant in 0..<4 {
            let host = USAppleHost()
            if variant == 0 { host.market = .china }; if variant == 1 { host.realm = "other" }
            if variant == 2 { host.busy = true }; if variant == 3 { host.accountID = 7 }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertEqual(host.service.challengeCalls, 0); XCTAssertEqual(coordinator.state.issue, .sessionChanged)
        }
    }
    func testServerFailuresDoNotRetryOrAutolinkAndFreshTapStartsNewChallenge() async throws {
        for failure in USAppleError.allCases {
            let host = USAppleHost()
            host.service.onExchange = { throw failure }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertEqual(host.service.challengeCalls, 1); XCTAssertEqual(host.service.exchangeCalls.count, 1)
            XCTAssertTrue(host.verifiedCalls.isEmpty); XCTAssertTrue(host.commits.isEmpty)
            XCTAssertEqual(coordinator.state.issue?.localizationKey, "usApple." + [USAppleError.invalidRequest: "invalidRequest", .invalidChallenge: "invalidChallenge", .invalidIdentity: "invalidIdentity", .rateLimited: "rateLimited", .unavailable: "unavailable"][failure]!)
            await coordinator.signIn()
            XCTAssertEqual(host.service.challengeCalls, 2); XCTAssertEqual(host.service.exchangeCalls.count, 2)
        }
    }
    func testProviderCancelFailsQuietlyAndHashFailureDoesNotLaunchProvider() async throws {
        let host = USAppleHost()
        host.authorizer.onAuthorize = { throw CancellationError() }
        let coordinator = try host.coordinator(); await coordinator.signIn()
        XCTAssertNil(coordinator.state.issue); XCTAssertTrue(host.service.exchangeCalls.isEmpty)
        let invalidHashHost = USAppleHost(); invalidHashHost.hash = { _ in "RAW-NONCE" }
        let invalidHash = try invalidHashHost.coordinator(); await invalidHash.signIn()
        XCTAssertEqual(invalidHash.state.issue, .invalidResponse); XCTAssertTrue(invalidHashHost.authorizer.requests.isEmpty)
    }
    func testAtomicCommitRefusalAndStorageFailureNeverPublishSignedIn() async throws {
        for storage in [false, true] {
            let host = USAppleHost(); host.commitThrows = storage; host.commitAccepted = storage
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertFalse(coordinator.state.signedIn); XCTAssertTrue(host.commits.isEmpty)
            XCTAssertEqual(coordinator.state.issue, storage ? .storage : .sessionChanged)
        }
    }
    func testSessionChangeAtEveryPreVerificationBoundaryPreventsCommit() async throws {
        for phase in 0..<3 {
            let host = USAppleHost()
            if phase == 0 { host.service.onChallenge = { host.epoch += 1; return try USAppleFixtures.challenge() } }
            if phase == 1 { host.authorizer.onAuthorize = { host.epoch += 1; return USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state) } }
            if phase == 2 { host.service.onExchange = { host.epoch += 1; return LoginResult(token: "synthetic-session", account: try USAppleFixtures.account()) } }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertTrue(host.commits.isEmpty); XCTAssertTrue(host.verifiedCalls.isEmpty)
            XCTAssertEqual(coordinator.state.issue, .sessionChanged)
            if phase == 0 { XCTAssertTrue(host.authorizer.requests.isEmpty) }
            if phase < 2 { XCTAssertTrue(host.service.exchangeCalls.isEmpty) }
        }
    }
    func testTTLIsRecheckedAfterProviderExchangeAndVerificationWithoutTimer() async throws {
        for phase in 0..<3 {
            let host = USAppleHost()
            if phase == 0 { host.authorizer.onAuthorize = { host.time = 400; return USAppleCredential(identityToken: "fixture.jwt.token", state: USAppleFixtures.state) } }
            if phase == 1 { host.service.onExchange = { host.time = 400; return LoginResult(token: "synthetic-session", account: try USAppleFixtures.account()) } }
            if phase == 2 { host.verify = { host.time = 400; return USAppleVerifiedCurrentAccount(account: try USAppleFixtures.account(), market: .unitedStates, realm: "fixture-US") } }
            let coordinator = try host.coordinator(); await coordinator.signIn()
            XCTAssertTrue(host.commits.isEmpty); XCTAssertEqual(coordinator.state.issue, .invalidChallenge)
            if phase == 0 { XCTAssertTrue(host.service.exchangeCalls.isEmpty) }
        }
    }
    func testProtectedAccountVerificationFailureNeverPersistsCandidate() async throws {
        let host = USAppleHost()
        host.verify = { throw USAppleError.unavailable }
        let coordinator = try host.coordinator(); await coordinator.signIn()
        XCTAssertEqual(host.verifiedCalls, ["synthetic-session"])
        XCTAssertTrue(host.commits.isEmpty); XCTAssertFalse(coordinator.state.signedIn)
        XCTAssertEqual(coordinator.state.issue, .unavailable)
    }
    func testReentrantDismissalOnStateNotificationPreventsDispatch() async throws {
        let host = USAppleHost(), coordinator = try host.coordinator()
        coordinator.onStateChange = { if coordinator.state.work == .requestingChallenge { coordinator.cancel() } }
        await coordinator.signIn()
        XCTAssertEqual(host.service.challengeCalls, 0); XCTAssertTrue(host.commits.isEmpty)
        coordinator.onStateChange = nil
    }
}
#endif
