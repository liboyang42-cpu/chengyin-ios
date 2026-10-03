import XCTest
@testable import Questify

@MainActor final class SocialMemberActionAppTests: XCTestCase {
    func testNormalSessionFactoryHasNoMemberWriteGrants() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertTrue(dependencies.socialMemberActionApprovals.isEmpty)
        let session = AppSession(runtimeDependencies: dependencies)
        XCTAssertEqual(session.socialActionAccess.availability, .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .toggleFollow, target: .member(82)), .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .startChat, target: .member(82)), .disabled)
        XCTAssertEqual(session.socialActionCoordinator.availability(for: .communityComment(text: "hello", requestID: "abcdefghijklmnop"), target: .post(82)), .disabled)
    }
}

@MainActor final class SocialMemberActionLifecycleAppTests: XCTestCase {
    /// Synthetic OTP exchange plus authoritative session read; never exercises a provider.
    private func signIn(_ session: AppSession, recorder: SocialLifecycleRecorder, expectSuccess: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) async {
        if session.account != nil { await session.logout() }
        session.authChannels.cancel()
        let before = recorder.requests.count
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        guard expectSuccess else { return }
        XCTAssertNotNil(session.account, "Synthetic login must succeed before feature assertions", file: file, line: line)
        XCTAssertTrue(session.authChannels.state.signedIn, file: file, line: line)
        XCTAssertEqual(recorder.requests.dropFirst(before).map { $0.url?.path },
            ["/social-lifecycle/api/login/phone", "/social-lifecycle/api/userInfo"], file: file, line: line)
    }

    private func deployment(realm: String = "social-lifecycle") throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://example.test/social-lifecycle",
            approvedBaseURLs: [.china: ["https://example.test/social-lifecycle"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.questify.social", realm: realm)
    }
    private func isolatedStorage(_ vault: SocialLifecycleVault) -> AppScopedStorageFactory {
        let suite = "social-lifecycle-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return .init(defaults: defaults, tokenStore: { _ in vault })
    }
    private func grant(_ deployment: ReviewedAppDeployment, accountID: Int, epoch: UInt64, role: String) throws -> SocialMemberActionApproval {
        try .init(endpoint: OperationEndpointApproval(baseURL: XCTUnwrap(deployment.regional.apiConfiguration).baseURL,
            namespace: deployment.storageScope.service, accountID: accountID,
            paths: ["api/user/follow/action", "api/user/public-info"]),
            identity: .init(accountID: accountID, epoch: epoch, role: role), market: .china,
            operation: .follow, memberID: 82, expiresAt: .distantFuture)
    }
    func testGuestFirstAccessThenLoginLogoutReloginRebuildsExactApprovedPairWithoutOpeningTransport() async throws {
        let deployment = try deployment(), recorder = SocialLifecycleRecorder(), vault = SocialLifecycleVault()
        // All synthetic grants are authored before authentication, never derived from a server reply.
        let registry = try [grant(deployment, accountID: 81, epoch: 1, role: "player"),
                            grant(deployment, accountID: 83, epoch: 3, role: "merchant")]
        var contexts: [RuntimeDependencyContext] = []
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: isolatedStorage(vault),
            makeTransport: { recorder }, sessionDependencies: { context in
                contexts.append(context)
                return .init(socialMemberActionApprovals: registry.filter { $0.matches(context, now: Date()) })
            })
        let session = root.makeSession(), guestAccess = session.socialActionAccess, guest = session.socialActionCoordinator
        await signIn(session, recorder: recorder)
        let first = session.socialActionCoordinator, firstAccess = session.socialActionAccess
        XCTAssertFalse(first === guest); XCTAssertTrue(first === session.socialActionCoordinator)
        XCTAssertEqual(first.availability(for: .toggleFollow, target: .member(82)), .approved)
        XCTAssertEqual(first.availability(for: .startChat, target: .member(82)), .disabled)
        XCTAssertNil(guestAccess.identity.accountID)
        do { _ = try await firstAccess.snapshot(target: .member(82)); XCTFail("Social route escaped composition") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(recorder.requests.count, 2)
        await session.logout()
        XCTAssertNil(first.identity.accountID); XCTAssertEqual(firstAccess.availability, .disabled)
        recorder.accountID = 83; recorder.role = "merchant"
        await signIn(session, recorder: recorder)
        let current = session.socialActionCoordinator
        XCTAssertFalse(current === first); XCTAssertEqual(current.identity.accountID, 83)
        XCTAssertEqual(current.availability(for: .toggleFollow, target: .member(82)), .approved)
        do { _ = try await firstAccess.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        XCTAssertEqual(contexts.map { $0.session.accountID }, [81, 83])
        XCTAssertEqual(contexts.map { $0.session.epoch }, [1, 3])
        XCTAssertEqual(contexts.map { $0.session.token }, ["synthetic-81-player", "synthetic-83-merchant"])
        XCTAssertEqual(recorder.requests.count, 5)
    }
    func testReleasedCompositionSessionCannotReviveEscapedPairWithEqualReplacementIdentity() async throws {
        let deployment = try deployment(), recorder = SocialLifecycleRecorder(), vault = SocialLifecycleVault()
        let approved = try grant(deployment, accountID: 81, epoch: 1, role: "player")
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: isolatedStorage(vault),
            makeTransport: { recorder }, sessionDependencies: { _ in .init(socialMemberActionApprovals: [approved]) })
        var previous: AppSession? = root.makeSession()
        if let previous { await signIn(previous, recorder: recorder) }
        weak var releasedSession = previous
        let old = try XCTUnwrap(previous).socialActionCoordinator
        let oldAccess = try XCTUnwrap(previous).socialActionAccess
        let originalIdentity = old.identity
        previous = nil
        XCTAssertNil(releasedSession)
        let replacement = root.makeSession()
        await signIn(replacement, recorder: recorder)
        XCTAssertEqual(replacement.socialActionCoordinator.identity, originalIdentity)
        XCTAssertEqual(replacement.socialActionCoordinator.availability, .approved)
        XCTAssertFalse(replacement.socialActionCoordinator === old)
        XCTAssertNil(old.identity.accountID); XCTAssertEqual(oldAccess.availability, .disabled)
        do { _ = try await oldAccess.snapshot(target: .member(82)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialActionBlock, .cancelled) }
        XCTAssertEqual(recorder.requests.count, 4)
    }
    func testAuthenticatedAccountAndRoleReplacementCannotRetainPriorGrantsOrReviews() async throws {
        let deployment = try deployment(), recorder = SocialLifecycleRecorder(), vault = SocialLifecycleVault()
        let onlyFirstGrant = try grant(deployment, accountID: 81, epoch: 1, role: "player")
        let session = AppCompositionRoot(deployment: .reviewed(deployment), storage: isolatedStorage(vault),
            makeTransport: { recorder }, sessionDependencies: { _ in .init(socialMemberActionApprovals: [onlyFirstGrant]) }).makeSession()
        await signIn(session, recorder: recorder)
        let old = session.socialActionCoordinator
        recorder.role = "merchant"
        await signIn(session, recorder: recorder)
        let changedRole = session.socialActionCoordinator
        XCTAssertFalse(changedRole === old); XCTAssertEqual(changedRole.availability, .disabled)
        XCTAssertNil(old.identity.accountID)
        recorder.accountID = 83
        await signIn(session, recorder: recorder)
        XCTAssertFalse(session.socialActionCoordinator === changedRole)
        XCTAssertEqual(session.socialActionCoordinator.identity.accountID, 83)
        XCTAssertEqual(session.socialActionCoordinator.availability, .disabled)
        XCTAssertEqual(recorder.requests.count, 8)
    }
    func testRestorationKeepsOldUnknownOwnerKeyAndDifferentRealmCannotUseApprovalOrLock() async throws {
        let deployment = try deployment(), other = try self.deployment(realm: "other-realm")
        let recorder = SocialLifecycleRecorder(), vault = SocialLifecycleVault()
        let storage = isolatedStorage(vault), approved = try grant(deployment, accountID: 81, epoch: 1, role: "player")
        let parts = ["social-member-v1", "CN", try XCTUnwrap(deployment.regional.apiConfiguration).baseURL.absoluteString,
                     deployment.storageScope.service, "81"]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        let record = OperationPendingRecord(ownerKey: key, targetKey: "member|82")
        try OperationDefaultsJournal(defaults: storage.defaults).write(record)
        vault.value = "synthetic-81-player"
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage,
            makeTransport: { recorder }, sessionDependencies: { _ in .init(socialMemberActionApprovals: [approved]) })
        let restored = root.makeSession(), guest = restored.socialActionCoordinator
        await restored.bootstrap()
        XCTAssertFalse(restored.socialActionCoordinator === guest)
        XCTAssertEqual(restored.socialActionCoordinator.availability, .approved)
        XCTAssertEqual(restored.socialActionCoordinator.state(target: .member(82)), .outcomeUnknown)
        await restored.logout()
        recorder.role = "merchant"
        await signIn(restored, recorder: recorder)
        XCTAssertEqual(restored.socialActionCoordinator.state(target: .member(82)), .outcomeUnknown)
        let different = AppCompositionRoot(deployment: .reviewed(other), storage: storage,
            makeTransport: { recorder }, sessionDependencies: { _ in .init(socialMemberActionApprovals: [approved]) }).makeSession()
        await signIn(different, recorder: recorder)
        XCTAssertEqual(different.socialActionCoordinator.availability, .disabled)
        XCTAssertEqual(different.socialActionCoordinator.state(target: .member(82)), .idle)
        XCTAssertEqual(try storage.operationJournal().pending(ownerKey: key, targetKey: "member|82"), record)
    }
}

@MainActor private final class SocialLifecycleVault: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class SocialLifecycleRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var accountID = 81
    var role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let json: String
        switch request.url!.lastPathComponent {
        case "phone": json = "{\"code\":200,\"token\":\"synthetic-\(accountID)-\(role)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}"
        case "userInfo": json = "{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}"
        case "logout": json = "{\"code\":200}"
        default: XCTFail("Unapproved route reached recorder"); throw APIError.notConfigured
        }
        return (Data(json.utf8), 200)
    }
}
