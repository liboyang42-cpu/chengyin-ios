import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real AppSession + production journal adapter, over synthetic token/Keychain/HTTP primitives.
/// No URLSession, OS Keychain, permission prompts, real credentials or real coordinates.
@MainActor final class PrivateHomeCompositionTests: XCTestCase {
    /// Synthetic OTP exchange plus authoritative session read; never exercises a provider.
    private func signIn(_ session: AppSession, recorder: HomeCompositionRecorder, expectSuccess: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) async {
        if session.account != nil { await session.logout() }
        session.authChannels.cancel()
        let before = recorder.requests.count
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        guard expectSuccess else { return }
        XCTAssertNotNil(session.account, "Synthetic login must succeed before feature assertions", file: file, line: line)
        XCTAssertTrue(session.authChannels.state.signedIn, file: file, line: line)
        XCTAssertEqual(recorder.requests.dropFirst(before).map { $0.url?.path },
            ["/native/api/login/phone", "/native/api/userInfo"], file: file, line: line)
    }

    private func deployment(granted: Bool = true, realm: String = "synthetic-home") throws -> ReviewedAppDeployment {
        func make(_ grant: PrivateHomeTransportGrant?) throws -> ReviewedAppDeployment {
            try .init(market: .china, baseURL: "https://home.example.test/native",
                approvedBaseURLs: [.china: ["https://home.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.questify.privateHome", realm: realm, privateHome: grant)
        }
        let base = try make(nil)
        return try make(granted ? PrivateHomeTransportGrant(storageScope: base.storageScope, accountID: 7, role: "player") : nil)
    }
    private func root(_ recorder: HomeCompositionRecorder, _ vault: HomeCompositionVault?,
                      granted: Bool = true, realm: String = "synthetic-home") throws -> AppCompositionRoot {
        let suite = "private-home-composition-" + UUID().uuidString, token = HomeCompositionToken()
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(try deployment(granted: granted, realm: realm)),
            storage: .init(defaults: defaults, tokenStore: { _ in token }, privateHomeKeychain: vault), makeTransport: { recorder })
    }
    private func login(_ session: AppSession, recorder: HomeCompositionRecorder) async {
        await session.bootstrap(); await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 7)
    }
    private func setReview(_ model: PrivateHomeCoordinator) throws {
        model.prepareSet(label: "Synthetic", point: try PrivateHomePoint(latitude: 12.345, longitude: 45.678))
        XCTAssertTrue(model.canConfirm)
    }
    func testNormalRootInjectsStableSessionCoordinatorAndDurableJournal() async throws {
        let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
        let container = AppSessionContainer(composition: try root(recorder, vault))
        let session = try XCTUnwrap(container.session)
        await login(session, recorder: recorder)
        let host = UIHostingController(rootView: SessionRootView(session: session))
        host.loadViewIfNeeded()
        let model = try XCTUnwrap(session.privateHomeCoordinator)
        XCTAssertTrue(session.privateHomeCoordinator === model)
        let account = AccountView(account: try XCTUnwrap(session.account), privateHomeCoordinator: session.privateHomeCoordinator)
        XCTAssertTrue(account.privateHomeCoordinator === model)
        await model.load(); XCTAssertTrue(model.canEdit)
        try setReview(model); let reviewed = try XCTUnwrap(model.review)
        await model.confirm()
        XCTAssertEqual(model.decision, .saved); XCTAssertTrue(model.canEdit)
        XCTAssertEqual(recorder.homeRequests.map(\.httpMethod), ["GET", "PUT", "GET"])
        let sent = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(recorder.homeRequests[1].httpBody))
        XCTAssertEqual(sent, reviewed); XCTAssertEqual(sent.expectedVersion, 0)
        XCTAssertTrue(recorder.homeRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7-a" })
        let pending = await vault.count(); XCTAssertEqual(pending, 0)
    }
    func testDeleteUsesExactDurableContractAndCancelDoesNotSend() async throws {
        let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
        let session = try root(recorder, vault).makeSession(); await login(session, recorder: recorder)
        let model = try XCTUnwrap(session.privateHomeCoordinator)
        await model.load(); try setReview(model); await model.confirm()
        model.prepareDelete(); XCTAssertTrue(model.canConfirm)
        model.cancelReview(); await model.confirm()
        XCTAssertEqual(recorder.homeRequests.filter { $0.httpMethod == "DELETE" }.count, 0)
        model.prepareDelete(); let reviewed = try XCTUnwrap(model.review)
        XCTAssertEqual(reviewed.expectedVersion, 1); XCTAssertNil(reviewed.label); XCTAssertNil(reviewed.latitude)
        await model.confirm(); XCTAssertEqual(model.decision, .deleted)
        let sent = try XCTUnwrap(recorder.homeRequests.first { $0.httpMethod == "DELETE" }?.httpBody)
        XCTAssertEqual(try JSONDecoder().decode(PrivateHomeMutation.self, from: sent), reviewed)
        let count = await vault.count(); XCTAssertEqual(count, 0)
    }
    func testAuthenticatedNoGrantAndMissingDurableStorageMakeZeroHomeHTTP() async throws {
        for granted in [false, true] {
            let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
            let session = try root(recorder, granted ? nil : vault, granted: granted).makeSession()
            await login(session, recorder: recorder)
            XCTAssertNil(session.privateHomeCoordinator)
            XCTAssertTrue(recorder.homeRequests.isEmpty)
            let reads = await vault.reads; XCTAssertEqual(reads, 0)
        }
    }
    func testLockedStorageBlocksLoadBeforeHTTPAndSaveBeforeMutation() async throws {
        let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
        let session = try root(recorder, vault).makeSession(); await login(session, recorder: recorder)
        let model = try XCTUnwrap(session.privateHomeCoordinator)
        await vault.setLocked(true); await model.load()
        XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.issue, .storageUnavailable)
        XCTAssertTrue(recorder.homeRequests.isEmpty)
        await vault.setLocked(false); await model.load(); try setReview(model)
        await vault.setLocked(true); await model.confirm()
        XCTAssertEqual(model.phase, .blocked)
        XCTAssertEqual(recorder.homeRequests.map(\.httpMethod), ["GET"])
    }
    func testLogoutAndSameOwnerReentryReloadExactUnknownDurableRequest() async throws {
        let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
        let composition = try root(recorder, vault), session = composition.makeSession()
        await login(session, recorder: recorder)
        let old = try XCTUnwrap(session.privateHomeCoordinator)
        await old.load(); try setReview(old)
        recorder.loseNextMutation = true
        await old.confirm(); XCTAssertEqual(old.phase, .unknown)
        let original = try XCTUnwrap(recorder.homeRequests.last?.httpBody)
        let pendingBefore = await vault.snapshot()
        await session.logout()
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home); XCTAssertNil(old.review)
        XCTAssertNil(session.privateHomeCoordinator)
        let before = recorder.homeRequests.count
        await old.load(); await old.retryExact(); await old.confirm()
        XCTAssertEqual(recorder.homeRequests.count, before)
        let pendingAfter = await vault.snapshot(); XCTAssertEqual(pendingAfter, pendingBefore)
        await signIn(session, recorder: recorder)
        let restored = try XCTUnwrap(session.privateHomeCoordinator)
        XCTAssertFalse(restored === old)
        await restored.load(); XCTAssertTrue(restored.canRetry); XCTAssertFalse(restored.canEdit)
        let countBeforeRetry = await vault.count(); XCTAssertEqual(countBeforeRetry, 1)
        await restored.retryExact()
        let puts = recorder.homeRequests.filter { $0.httpMethod == "PUT" }
        XCTAssertEqual(puts.count, 2); XCTAssertEqual(puts.last?.httpBody, original)
        XCTAssertEqual(recorder.version, 1); XCTAssertTrue(restored.canEdit)
        let count = await vault.count(); XCTAssertEqual(count, 0)
    }
    func testColdRecreationRecoversSameOwnerButDifferentAccountAndRealmDoNot() async throws {
        let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault(), composition = try root(recorder, vault)
        let first = composition.makeSession(); await login(first, recorder: recorder)
        let old = try XCTUnwrap(first.privateHomeCoordinator)
        await old.load(); try setReview(old); recorder.loseNextMutation = true; await old.confirm()
        first.setPrivateHomePresentationActive(false) // Root teardown before immutable deployment/realm replacement.
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home)
        let same = composition.makeSession(); await same.bootstrap()
        let recovered = try XCTUnwrap(same.privateHomeCoordinator); await recovered.load()
        XCTAssertTrue(recovered.canRetry)
        let otherRealm = try root(recorder, vault, realm: "other-synthetic-realm").makeSession()
        await login(otherRealm, recorder: recorder)
        let other = try XCTUnwrap(otherRealm.privateHomeCoordinator); await other.load()
        XCTAssertTrue(other.canEdit); XCTAssertFalse(other.canRetry)
        recorder.accountID = 8
        await signIn(same, recorder: recorder)
        XCTAssertEqual(recovered.phase, .invalidated); XCTAssertNil(recovered.home)
        XCTAssertNil(same.privateHomeCoordinator) // Grant is explicitly owner 7 only.
        let count = await vault.count(); XCTAssertEqual(count, 1)
    }
    func testRoleTokenAndRootChangesSynchronouslyClearRetainedDisplay() async throws {
        let recorder = HomeCompositionRecorder(), session = try root(recorder, HomeCompositionVault()).makeSession()
        await login(session, recorder: recorder)
        let player = try XCTUnwrap(session.privateHomeCoordinator); await player.load(); try setReview(player)
        recorder.role = "merchant"
        await session.refreshOwnAccount()
        XCTAssertEqual(player.phase, .invalidated); XCTAssertNil(player.home); XCTAssertNil(player.review)
        XCTAssertNil(session.privateHomeCoordinator)
        recorder.role = "player"; await session.refreshOwnAccount()
        let restored = try XCTUnwrap(session.privateHomeCoordinator); await restored.load()
        XCTAssertFalse(restored === player)
        recorder.tokenRevision = "b"; await signIn(session, recorder: recorder)
        XCTAssertEqual(restored.phase, .invalidated); XCTAssertNil(restored.home)
        let newToken = try XCTUnwrap(session.privateHomeCoordinator); await newToken.load()
        XCTAssertEqual(recorder.homeRequests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7-b")
        session.setPrivateHomePresentationActive(false)
        XCTAssertNil(session.privateHomeCoordinator)
        XCTAssertEqual(newToken.phase, .invalidated); XCTAssertNil(newToken.home)
        let count = recorder.homeRequests.count; await newToken.load(); XCTAssertEqual(recorder.homeRequests.count, count)
        session.setPrivateHomePresentationActive(true)
        let reopened = try XCTUnwrap(session.privateHomeCoordinator)
        XCTAssertFalse(reopened === newToken); await reopened.load(); XCTAssertTrue(reopened.canEdit)
    }
    func testLate401AndMutationSuccessCannotExpireOrPopulateReplacement() async throws {
        for status in [401, 200] {
            let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
            let session = try root(recorder, vault).makeSession(); await login(session, recorder: recorder)
            let old = try XCTUnwrap(session.privateHomeCoordinator); await old.load(); try setReview(old)
            recorder.pauseMutation = true
            let started = expectation(description: "Mutation suspended after durable save")
            recorder.onPaused = { started.fulfill() }
            let operation = Task { await old.confirm() }
            await fulfillment(of: [started], timeout: 2)
            guard recorder.hasPaused else { operation.cancel(); XCTFail("Mutation did not suspend"); return }
            await session.logout(); recorder.tokenRevision = "b"
            await signIn(session, recorder: recorder)
            let replacement = try XCTUnwrap(session.privateHomeCoordinator)
            recorder.resume(status: status); await operation.value
            XCTAssertTrue(session.isSignedIn); XCTAssertNil(session.errorKey)
            XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home); XCTAssertNil(old.review)
            XCTAssertEqual(replacement.phase, .idle); XCTAssertNil(replacement.home)
            let count = await vault.count(); XCTAssertEqual(count, 1)
            await replacement.load(); XCTAssertTrue(replacement.canRetry)
        }
    }
    func testSameEpochRoleAndRootABACannotApplyLateMutationOrClearPendingEvidence() async throws {
        for roleChange in [true, false] {
            for status in [401, 200] {
                let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
                let session = try root(recorder, vault).makeSession(); await login(session, recorder: recorder)
                let old = try XCTUnwrap(session.privateHomeCoordinator); await old.load(); try setReview(old)
                let epoch = session.sessionRevision
                recorder.pauseMutation = true
                let started = expectation(description: "Mutation waits across same-epoch ABA")
                recorder.onPaused = { started.fulfill() }
                let operation = Task { await old.confirm() }
                await fulfillment(of: [started], timeout: 2)
                guard recorder.hasPaused else { operation.cancel(); XCTFail("Mutation did not suspend"); return }
                let pendingBefore = await vault.snapshot()
                XCTAssertEqual(pendingBefore.count, 1)
                await cycleIdentity(session, recorder: recorder, roleChange: roleChange)
                XCTAssertEqual(session.sessionRevision, epoch) // Restore the exact same role/token/epoch tuple.
                XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home); XCTAssertNil(old.review)
                let replacement = try XCTUnwrap(session.privateHomeCoordinator)
                XCTAssertFalse(replacement === old)
                await replacement.load(); XCTAssertTrue(replacement.canRetry)
                let replacementHome = replacement.home, before = recorder.homeRequests.count
                await old.load(); await old.confirm(); await old.retryExact()
                XCTAssertEqual(recorder.homeRequests.count, before)
                recorder.resume(status: status); await operation.value
                XCTAssertTrue(session.isSignedIn); XCTAssertNil(session.errorKey)
                XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home); XCTAssertNil(old.decision)
                XCTAssertEqual(replacement.home, replacementHome); XCTAssertTrue(replacement.canRetry)
                XCTAssertEqual(recorder.homeRequests.count, before) // No old-owner readback.
                let pendingAfter = await vault.snapshot(); XCTAssertEqual(pendingAfter, pendingBefore)
                await replacement.retryExact()
                XCTAssertTrue(replacement.canEdit)
                let puts = recorder.homeRequests.filter { $0.httpMethod == "PUT" }
                XCTAssertEqual(puts.count, 2); XCTAssertEqual(puts.first?.httpBody, puts.last?.httpBody)
                let count = await vault.count(); XCTAssertEqual(count, 0)
            }
        }
    }
    func testSameEpochRoleAndRootABACannotApplyLatePrivateHomeRead() async throws {
        for roleChange in [true, false] {
            for status in [401, 200] {
                let recorder = HomeCompositionRecorder(), vault = HomeCompositionVault()
                let session = try root(recorder, vault).makeSession(); await login(session, recorder: recorder)
                let old = try XCTUnwrap(session.privateHomeCoordinator), epoch = session.sessionRevision
                recorder.pauseRead = true
                let started = expectation(description: "GET waits across same-epoch ABA")
                recorder.onPaused = { started.fulfill() }
                let operation = Task { await old.load() }
                await fulfillment(of: [started], timeout: 2)
                guard recorder.hasPaused else { operation.cancel(); XCTFail("GET did not suspend"); return }
                await cycleIdentity(session, recorder: recorder, roleChange: roleChange)
                XCTAssertEqual(session.sessionRevision, epoch)
                let replacement = try XCTUnwrap(session.privateHomeCoordinator)
                XCTAssertFalse(replacement === old)
                await replacement.load(); XCTAssertTrue(replacement.canEdit)
                let replacementHome = replacement.home, before = recorder.homeRequests.count
                recorder.resume(status: status); await operation.value
                XCTAssertTrue(session.isSignedIn); XCTAssertNil(session.errorKey)
                XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.home); XCTAssertNil(old.review)
                XCTAssertEqual(replacement.home, replacementHome); XCTAssertTrue(replacement.canEdit)
                XCTAssertEqual(recorder.homeRequests.count, before)
                let count = await vault.count(); XCTAssertEqual(count, 0)
            }
        }
    }
    private func cycleIdentity(_ session: AppSession, recorder: HomeCompositionRecorder, roleChange: Bool) async {
        if roleChange {
            recorder.role = "merchant"; await session.refreshOwnAccount()
            XCTAssertNil(session.privateHomeCoordinator)
            recorder.role = "player"; await session.refreshOwnAccount()
        } else {
            session.setPrivateHomePresentationActive(false)
            XCTAssertNil(session.privateHomeCoordinator)
            session.setPrivateHomePresentationActive(true)
        }
    }
    func testExactFeatureTransportGrantCannotAuthorizeUnrelatedMethodsRoutesOrOwners() async throws {
        let recorder = HomeCompositionRecorder(), composition = try root(recorder, HomeCompositionVault())
        let transport = composition.transport()
        var identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7-a")
        transport.current = { identity }
        for (method, suffix) in [("POST", "api/native/home"), ("PATCH", "api/native/home"), ("GET", "api/native/home/restore"),
                                 ("PUT", "api/wallet/stages"), ("POST", "api/category/list"), ("GET", "api/native/home?ownerId=7")] {
            var request = URLRequest(url: URL(string: "https://home.example.test/native/" + suffix)!)
            request.httpMethod = method; request.setValue("synthetic-7-a", forHTTPHeaderField: "Authorization")
            do { _ = try await transport.send(request); XCTFail("Unexpected grant: \(method) \(suffix)") } catch {}
        }
        var request = URLRequest(url: URL(string: "https://home.example.test/native/api/native/home")!)
        request.httpMethod = "GET"; request.setValue("synthetic-7-a", forHTTPHeaderField: "Authorization")
        for wrong in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7-a"),
                      .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7-a"),
                      .init(epoch: 1, accountID: nil, role: nil, token: nil)] {
            identity = wrong; do { _ = try await transport.send(request); XCTFail() } catch {}
        }
        XCTAssertTrue(recorder.requests.isEmpty)
        let noGrant = try root(recorder, HomeCompositionVault(), granted: false).transport()
        noGrant.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7-a") }
        do { _ = try await noGrant.send(request); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
        let foreign = try deployment(realm: "foreign")
        XCTAssertThrowsError(try ReviewedAppDeployment(market: .china, baseURL: "https://home.example.test/native",
            approvedBaseURLs: [.china: ["https://home.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.privateHome", realm: "synthetic-home", privateHome: foreign.privateHome))
    }
}

@MainActor private final class HomeCompositionToken: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
private actor HomeCompositionVault: PrivateHomeKeychainPrimitive {
    private var items: [String: PrivateHomeKeychainItem] = [:]
    private var locked = false
    private(set) var reads = 0
    func setLocked(_ value: Bool) { locked = value }
    func count() -> Int { items.count }
    func snapshot() -> [String: Data] { items.mapValues(\.bytes) }
    func read(key: String) throws -> PrivateHomeKeychainItem? {
        reads += 1; if locked { throw PrivateHomeIssue.storageUnavailable }; return items[key]
    }
    func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
        if locked { throw PrivateHomeIssue.storageUnavailable }
        guard items[key] == nil else { return false }; items[key] = item; return true
    }
    func remove(key: String, matchingTag: Data) throws -> Bool {
        if locked { throw PrivateHomeIssue.storageUnavailable }
        guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
    }
}
@MainActor private final class HomeCompositionRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var homeRequests: [URLRequest] { requests.filter { $0.url?.path == "/native/api/native/home" } }
    var accountID = 7, role = "player", tokenRevision = "a", version: Int64 = 0
    var loseNextMutation = false, pauseMutation = false, pauseRead = false
    var onPaused: (() -> Void)?
    private var pending: CheckedContinuation<(Data, Int), Error>?
    private var pausedReply: Data?
    private var receipts: [String: Data] = [:]
    private var active = false
    var hasPaused: Bool { pending != nil }
    func resume(status: Int) {
        let data = status == 200 ? pausedReply! : Data("{\"code\":401}".utf8)
        pending?.resume(returning: (data, status)); pending = nil; pausedReply = nil
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url!.lastPathComponent {
        case "phone": return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)-\(tokenRevision)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
        case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
        case "home":
            if request.httpMethod == "GET" {
                let data: Data
                if active {
                    data = Data("{\"code\":200,\"data\":{\"version\":\(version),\"status\":\"ACTIVE\",\"label\":\"Synthetic\",\"latitude\":12.345,\"longitude\":45.678,\"datum\":\"WGS84\",\"changedAt\":1,\"effectiveAt\":1}}".utf8)
                } else {
                    data = Data("{\"code\":200,\"data\":{\"version\":\(version),\"status\":\"DELETED\"}}".utf8)
                }
                if pauseRead {
                    pauseRead = false; pausedReply = data
                    return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
                }
                return (data, 200)
            }
            let mutation = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody))
            let result: Data
            if let previous = receipts[mutation.requestId] { result = previous }
            else {
                version = mutation.expectedVersion + 1; active = mutation.method == "PUT"
                let decision = active ? "SAVED" : "DELETED"
                result = Data("{\"code\":200,\"data\":{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"\(decision)\",\"version\":\(version)}}".utf8)
                receipts[mutation.requestId] = result
            }
            if pauseMutation {
                pauseMutation = false; pausedReply = result
                return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            if loseNextMutation { loseNextMutation = false; throw URLError(.timedOut) }
            return (result, 200)
        default: return (Data("{\"code\":200,\"data\":[]}".utf8), 200)
        }
    }
}
