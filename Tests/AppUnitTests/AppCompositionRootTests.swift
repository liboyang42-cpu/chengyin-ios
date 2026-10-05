import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class AppCompositionRootTests: XCTestCase {
    /// Synthetic OTP exchange plus authoritative session read; never exercises a provider.
    private func signIn(_ session: AppSession, recorder: CompositionRecorder, expectSuccess: Bool = true,
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

    private func deployment(reads: Set<ReviewedAppDeployment.ReadGrant> = [.homeAndSearch],
                            capabilities: Set<RegionalCapability> = [.domesticChinaPhone],
                            realm: String = "recorder") throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://example.test/native",
            approvedBaseURLs: [.china: ["https://example.test/native"]], verifiedCapabilities: capabilities,
            bundleIdentifier: "test.questify.composition", realm: realm, reads: reads)
    }
    private func storage(_ vault: CompositionMemoryVault) -> AppScopedStorageFactory {
        let suite = "composition-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return .init(defaults: defaults, tokenStore: { _ in vault })
    }
    func testNormalRootLoginReadLogoutAndColdRestoreTombstone() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let storage = storage(vault), deployment = try deployment()
        var contexts: [RuntimeDependencyContext] = []
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage,
            makeTransport: { recorder }, sessionDependencies: { contexts.append($0); return .dormant })
        let container = AppSessionContainer(composition: root)
        let session = try XCTUnwrap(container.session)
        // Mount the same root type used by QuestifyApp; no feature fixture or alternate root.
        let host = UIHostingController(rootView: SessionRootView(session: session))
        host.loadViewIfNeeded()
        await session.bootstrap()
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 7)
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.role, "player")
        _ = try await session.homeFeedReader.categories()
        _ = try await session.searchMapReader.search(GlobalSearchQuery(keyword: "synthetic"))
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/native/api/category/list" })
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/native/api/topic/list" })
        XCTAssertTrue(recorder.requests.filter { $0.url?.path.hasSuffix("/list") == true }.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7"
        })
        await session.logout()
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertTrue(storage.defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(recorder.requests.last?.url?.path, "/native/api/logout")
        let count = recorder.requests.count
        await root.makeSession().bootstrap()
        XCTAssertEqual(recorder.requests.count, count)
    }
    func testRestoreRebuildsAndRoleAccountChangesNeverCreateMixedContext() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        vault.value = "synthetic-7"
        var contexts: [RuntimeDependencyContext] = []
        let root = AppCompositionRoot(deployment: .reviewed(try deployment()), storage: storage(vault),
            makeTransport: { recorder }, sessionDependencies: { contexts.append($0); return .dormant })
        let session = root.makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.account?.id, 7)
        XCTAssertEqual(recorder.requests.first?.url?.path, "/native/api/userInfo")
        recorder.accountID = 8; recorder.role = "merchant"
        await signIn(session, recorder: recorder)
        XCTAssertEqual(contexts.map { $0.session.accountID }, [7, 8])
        XCTAssertEqual(contexts.map { $0.role }, ["player", "merchant"])
        await session.logout()
        recorder.role = "player"
        await signIn(session, recorder: recorder)
        XCTAssertEqual(contexts.map { $0.role }, ["player", "merchant", "player"])
        XCTAssertNotEqual(contexts[1].session, contexts[2].session)
    }
    func testMissingReviewOrGrantsMakesZeroRecorderCalls() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let unconfigured = AppCompositionRoot(storage: storage(vault), makeTransport: { recorder }).makeSession()
        await unconfigured.bootstrap(); await signIn(unconfigured, recorder: recorder, expectSuccess: false)
        do { _ = try await unconfigured.homeFeedReader.categories(); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
        let session = AppCompositionRoot(deployment: .reviewed(try deployment(reads: [], capabilities: [])),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        await session.bootstrap(); await signIn(session, recorder: recorder, expectSuccess: false)
        do { _ = try await session.homeFeedReader.categories(); XCTFail() } catch {}
        do { _ = try await session.searchMapReader.categories(); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertThrowsError(try ReviewedAppDeployment(market: .china, baseURL: "https://unreviewed.test",
            approvedBaseURLs: [:], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.app", realm: "test"))
    }
    func testLogoutRejectsLateHomeReadAndOldClientBeforeDispatch() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let root = AppCompositionRoot(deployment: .reviewed(try deployment()), storage: storage(vault), makeTransport: { recorder })
        let session = root.makeSession()
        await signIn(session, recorder: recorder)
        recorder.pauseCategories = true
        let started = expectation(description: "Recorder receives suspended category read")
        recorder.onPausedRead = { started.fulfill() }
        let read = Task { try await session.homeFeedReader.categories() }
        await fulfillment(of: [started], timeout: 2)
        guard recorder.hasPausedRead else { read.cancel(); return }
        await session.logout()
        recorder.finishPausedRead()
        do { _ = try await read.value; XCTFail("Late response crossed logout") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let transport = root.transport()
        transport.current = { .init(epoch: 2, accountID: nil, role: nil, token: nil) }
        var request = URLRequest(url: URL(string: "https://example.test/native/api/category/list")!)
        request.httpMethod = "POST"; request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
        let before = recorder.requests.count
        do { _ = try await transport.send(request); XCTFail() } catch {}
        XCTAssertEqual(recorder.requests.count, before)
    }
    func testAuthenticatedSessionWithoutReadGrantMakesNoReadCalls() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let session = AppCompositionRoot(deployment: .reviewed(try deployment(reads: [])),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 7)
        let before = recorder.requests.count
        do { _ = try await session.homeFeedReader.categories(); XCTFail() } catch {}
        do { _ = try await session.searchMapReader.categories(); XCTFail() } catch {}
        XCTAssertEqual(recorder.requests.count, before)
    }
    func testExplicitFactoryTransportCannotEscapeFirstSliceRouteGrant() async throws {
        let recorder = CompositionRecorder(), escapeRecorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let deployment = try deployment()
        // Fixed synthetic approval created independently of authentication, solely for boundary testing.
        let approval = try OperationEndpointApproval(baseURL: XCTUnwrap(deployment.regional.apiConfiguration).baseURL,
            namespace: deployment.storageScope.service, accountID: 7, paths: ["api/wallet/stages"])
        let session = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage(vault), makeTransport: { recorder }).makeSession()
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 7)
        let reader = session.makeWalletCommerceReader(readApproval: approval, transport: escapeRecorder)
        XCTAssertTrue(reader.isConfigured)
        do { _ = try await reader.read { try await $0.stages(token: $1) }; XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(escapeRecorder.requests.isEmpty)
        XCTAssertEqual(recorder.requests.count, 2)
    }
    func testUnknownJournalRecordsKeepCanonicalKeysAcrossLogoutAndAccounts() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let storage = storage(vault), deployment = try deployment()
        let owner = "registration|\(deployment.storageScope.service)|CN|https://example.test/native|7"
        let pending = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        // Seed the pre-composition journal format, as after an interrupted previous app version.
        try OperationDefaultsJournal(defaults: storage.defaults).write(pending)
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage, makeTransport: { recorder })
        let session = root.makeSession()
        await signIn(session, recorder: recorder); await session.logout()
        recorder.accountID = 8
        await signIn(session, recorder: recorder)
        let journal = storage.operationJournal()
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: pending.targetKey), pending)
        XCTAssertNil(try journal.pending(ownerKey: owner.dropLast() + "8", targetKey: pending.targetKey))
        XCTAssertThrowsError(try journal.write(.init(ownerKey: owner, targetKey: pending.targetKey)))
        let other = try self.deployment(realm: "other")
        XCTAssertNotEqual(deployment.storageScope, other.storageScope)
    }
    func testPasswordVerificationFlagCannotMountLegacyWeChatCodeRoute() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        vault.value = "synthetic-old-session"
        let session = AppCompositionRoot(deployment: .reviewed(try deployment(capabilities: [.usernamePassword])),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        XCTAssertFalse(session.canUsePassword)
        await session.bootstrap()
        await session.login(username: "synthetic", password: "synthetic")
        await session.authChannels.sendSMSCode(phone: "10000000000")
        XCTAssertNil(session.account); XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(vault.value, "synthetic-old-session")
    }
    func testProviderUnavailableWrongOTPAndRateLimitNeverCommitOrRetry() async throws {
        let failures: [(String, String, Int)] = [
            ("send", #"{"code":500,"msg":"provider unavailable"}"#, 200),
            ("send", #"{"code":500,"msg":"rate limit"}"#, 200),
            ("send", #"{"code":429}"#, 200), ("send", "{}", 429),
            ("phone", #"{"code":500,"msg":"wrong or expired OTP"}"#, 200),
            ("userInfo", #"{"code":401}"#, 200)]
        for (path, json, status) in failures {
            let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
            recorder.overrides[path] = (json, status)
            let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
                storage: storage(vault), makeTransport: { recorder }).makeSession()
            if path == "send" { await session.authChannels.sendSMSCode(phone: "10000000000") }
            else { await signIn(session, recorder: recorder, expectSuccess: false) }
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
            XCTAssertFalse(session.authChannels.state.signedIn)
            XCTAssertEqual(recorder.requests.count, path == "userInfo" ? 2 : 1)
        }
    }
    func testMerchantEntryIntentDoesNotGrantMerchantRoleOrWriteAccess() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        let host = UIHostingController(rootView: LoginView(intent: .merchant).environmentObject(session))
        host.loadViewIfNeeded()
        await session.authChannels.sendSMSCode(phone: "10000000000")
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.role, "player")
        XCTAssertEqual(session.socialActionCoordinator.availability, .disabled)
        XCTAssertEqual(recorder.requests.map { $0.url!.lastPathComponent }, ["send", "phone", "userInfo"])
        XCTAssertTrue(recorder.requests.prefix(2).allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertEqual(recorder.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        let fields = String(data: try XCTUnwrap(recorder.requests[1].httpBody), encoding: .utf8)!
        XCTAssertFalse(fields.contains("merchant")); XCTAssertFalse(fields.contains("username"))
    }
    func testColdRestoreRejectsLegacyRolelessProjectionWithoutDestroyingCredential() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        vault.value = "synthetic-old-session"
        recorder.overrides["userInfo"] = (#"{"code":200,"appUser":{"userId":7,"userType":2}}"#, 200)
        let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        await session.bootstrap()
        XCTAssertNil(session.account); XCTAssertEqual(vault.value, "synthetic-old-session")
        XCTAssertEqual(session.errorKey, "auth.invalidResponse")
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testCancelPendingPhoneExchangeCannotStartReadbackAndReentryWorks() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        recorder.pauseAuthPath = "phone"
        let started = expectation(description: "Phone exchange is suspended")
        recorder.onPausedAuth = { started.fulfill() }
        let pending = Task { await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
        await fulfillment(of: [started], timeout: 2)
        guard recorder.hasPausedAuth else { pending.cancel(); return }
        session.cancelPendingLogin()
        XCTAssertFalse(session.authChannels.state.isWorking)
        recorder.finishPausedAuth()
        await pending.value
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(vault.writeAttempts, 0)
        XCTAssertEqual(recorder.requests.map { $0.url!.lastPathComponent }, ["phone"])
        recorder.pauseAuthPath = nil
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 7)
        XCTAssertEqual(vault.writeAttempts, 1)
    }
    func testCloseDuringReadbackFencesLateSuccessAndUnauthorized() async throws {
        for unauthorized in [false, true] {
            let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
            let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
                storage: storage(vault), makeTransport: { recorder }).makeSession()
            recorder.pauseAuthPath = "userInfo"
            if unauthorized { recorder.overrides["userInfo"] = (#"{"code":401}"#, 200) }
            let started = expectation(description: "Current account readback is suspended")
            recorder.onPausedAuth = { started.fulfill() }
            let pending = Task { await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
            await fulfillment(of: [started], timeout: 2)
            guard recorder.hasPausedAuth else { pending.cancel(); return }
            session.cancelPendingLogin()
            recorder.finishPausedAuth()
            await pending.value
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
            XCTAssertEqual(vault.writeAttempts, 0)
            XCTAssertNil(session.authChannels.state.issue)
            XCTAssertFalse(session.authChannels.state.signedIn)
            XCTAssertEqual(recorder.requests.count, 2)
        }
    }
    func testMismatchedRolelessOrUnknownCurrentAccountNeverPersists() async throws {
        for projection in [#"{"id":8,"role":"player"}"#,
                           #"{"id":7,"userType":2}"#,
                           #"{"id":7,"role":"admin"}"#] {
            let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
            recorder.overrides["userInfo"] = ("{\"code\":200,\"appUser\":\(projection)}", 200)
            let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
                storage: storage(vault), makeTransport: { recorder }).makeSession()
            await signIn(session, recorder: recorder, expectSuccess: false)
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
            XCTAssertEqual(vault.writeAttempts, 0)
            XCTAssertEqual(session.authChannels.state.issue, .invalidResponse)
            XCTAssertEqual(recorder.requests.map { $0.url!.lastPathComponent }, ["phone", "userInfo"])
        }
    }
    func testColdRestoreUnauthorizedTombstonesWhileTransientFailuresPreserveCredential() async throws {
        for (json, status, clears) in [("{}", 401, true), (#"{"code":401}"#, 200, true),
                                       ("{}", 503, false), (#"{"code":500}"#, 200, false)] {
            let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
            vault.value = "synthetic-saved"
            recorder.overrides["userInfo"] = (json, status)
            let storage = storage(vault), deployment = try deployment()
            let session = AppCompositionRoot(deployment: .reviewed(deployment),
                storage: storage, makeTransport: { recorder }).makeSession()
            await session.bootstrap()
            XCTAssertNil(session.account)
            XCTAssertEqual(vault.value, clears ? nil : "synthetic-saved")
            XCTAssertEqual(storage.defaults.bool(forKey: deployment.storageScope.restoreBlockedKey), clears)
            XCTAssertEqual(recorder.requests.map { $0.url!.lastPathComponent }, ["userInfo"])
            XCTAssertEqual(recorder.requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic-saved")
        }
    }
    func testVaultWriteFailureDoesNotPublishLoginOrClearRestoreTombstone() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        vault.failWrite = true
        let storage = storage(vault), deployment = try deployment()
        storage.defaults.set(true, forKey: deployment.storageScope.restoreBlockedKey)
        let session = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: storage, makeTransport: { recorder }).makeSession()
        await signIn(session, recorder: recorder, expectSuccess: false)
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(vault.writeAttempts, 1)
        XCTAssertEqual(session.authChannels.state.issue, .storage)
        XCTAssertFalse(session.authChannels.state.signedIn)
        XCTAssertTrue(storage.defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
    }
    func testLogoutClearFailureCannotRestoreTheOldCredential() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let storage = storage(vault), deployment = try deployment()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: storage, makeTransport: { recorder })
        let session = root.makeSession()
        await signIn(session, recorder: recorder)
        vault.failClear = true
        await session.logout()
        XCTAssertNil(session.account); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertEqual(session.errorKey, "auth.storageError")
        XCTAssertTrue(storage.defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(recorder.requests.last?.url?.lastPathComponent, "logout")
        XCTAssertEqual(recorder.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        let before = recorder.requests.count
        let recreated = root.makeSession()
        await recreated.bootstrap()
        XCTAssertNil(recreated.account)
        XCTAssertEqual(recorder.requests.count, before)
    }
    func testLateLogoutFailureCannotClearNewAuthenticatedSession() async throws {
        let recorder = CompositionRecorder(), vault = CompositionMemoryVault()
        let session = AppCompositionRoot(deployment: .reviewed(try deployment()),
            storage: storage(vault), makeTransport: { recorder }).makeSession()
        await signIn(session, recorder: recorder)
        recorder.pauseAuthPath = "logout"
        recorder.overrides["logout"] = (#"{"code":401}"#, 200)
        let started = expectation(description: "Old logout is suspended")
        recorder.onPausedAuth = { started.fulfill() }
        let oldLogout = Task { await session.logout() }
        await fulfillment(of: [started], timeout: 2)
        guard recorder.hasPausedAuth else { oldLogout.cancel(); return }
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        recorder.accountID = 8; recorder.role = "merchant"
        await signIn(session, recorder: recorder)
        XCTAssertEqual(session.account?.id, 8)
        recorder.finishPausedAuth()
        await oldLogout.value
        XCTAssertEqual(session.account?.id, 8); XCTAssertEqual(session.account?.role, "merchant")
        XCTAssertEqual(vault.value, "synthetic-8")
        XCTAssertNil(session.errorKey)
        XCTAssertEqual(recorder.requests.first { $0.url?.lastPathComponent == "logout" }?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
    }

}

@MainActor private final class CompositionMemoryVault: AppTokenStorage {
    var value: String?
    var failWrite = false, failClear = false
    private(set) var writeAttempts = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws {
        writeAttempts += 1
        if failWrite { throw CocoaError(.fileWriteNoPermission) }
        value = token
    }
    func clear() throws {
        if failClear { throw CocoaError(.fileWriteNoPermission) }
        value = nil
    }
}
@MainActor private final class CompositionRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var accountID = 7, role = "player"
    var overrides: [String: (String, Int)] = [:]
    var pauseCategories = false
    var pauseAuthPath: String?
    var onPausedAuth: (() -> Void)?
    private var pendingAuth: CheckedContinuation<(Data, Int), Error>?
    private var pendingAuthReply: (Data, Int)?
    var hasPausedAuth: Bool { pendingAuth != nil }
    func finishPausedAuth() {
        guard let continuation = pendingAuth, let reply = pendingAuthReply else { return }
        pendingAuth = nil; pendingAuthReply = nil
        continuation.resume(returning: reply)
    }
    private var pending: CheckedContinuation<(Data, Int), Error>?
    var onPausedRead: (() -> Void)?
    var hasPausedRead: Bool { pending != nil }
    func finishPausedRead() { pending?.resume(returning: (Data("{\"code\":200,\"data\":[]}".utf8), 200)); pending = nil }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url!.lastPathComponent
        if path == "list", request.url!.path.contains("category"), pauseCategories {
            return try await withCheckedThrowingContinuation { pending = $0; onPausedRead?() }
        }
        let json: String
        if path == "phone" { json = "{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
        else if path == "userInfo" { json = "{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
        else { json = "{\"code\":200,\"data\":[],\"rows\":[],\"total\":0}" }
        let response = overrides[path] ?? (json, 200)
        let reply = (Data(response.0.utf8), response.1)
        if pauseAuthPath == path {
            pendingAuthReply = reply
            return try await withCheckedThrowingContinuation { pendingAuth = $0; onPausedAuth?() }
        }
        return reply
    }
}
