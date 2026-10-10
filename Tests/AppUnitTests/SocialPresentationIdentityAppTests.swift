import XCTest
import Observation
@testable import Questify

@MainActor final class SocialPresentationIdentityAppTests: XCTestCase {
    func testFixtureChangeIsObservableThroughErasedReaderAndReplacesArticleIdentity() async throws {
        let fixture = SocialAccountFixtureReader(.articleHTML), reader: any SocialAccountReading = fixture
        let first = try await reader.information(id: 91)
        XCTAssertTrue(first.contents?.contains("示例正文标题") == true)
        let changed = expectation(description: "Pushed reader presentation invalidated")
        let previous = withObservationTracking {
            SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false)
        } onChange: { changed.fulfill() }
        fixture.switchAccount()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertNotEqual(previous, SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false))
        let replacement = try await reader.information(id: 91)
        XCTAssertTrue(replacement.contents?.contains("替换正文标题") == true)
        XCTAssertFalse(replacement.contents?.contains("示例正文标题") == true)
    }
    func testReaderReplacementRequestAndSignInRequirementEachRetirePresentationKey() {
        let first = SocialAccountSessionReader(service: nil, currentSession: { .init(guestEpoch: 1) })
        let second = SocialAccountSessionReader(service: nil, currentSession: { .init(guestEpoch: 1) })
        let old = SocialReadPresentationKey(reader: first, request: "information-91", requiresSignIn: false)
        XCTAssertNotEqual(old, .init(reader: second, request: "information-91", requiresSignIn: false))
        XCTAssertNotEqual(old, .init(reader: first, request: "information-92", requiresSignIn: false))
        XCTAssertNotEqual(old, .init(reader: first, request: "information-91", requiresSignIn: true))
        first.invalidatePresentation(); first.invalidatePresentation()
        XCTAssertNotEqual(old, .init(reader: first, request: "information-91", requiresSignIn: false))
    }
    func testNormalSessionLoginRoleABAAndLogoutInvalidateSameSocialReaderWithoutGrantingReads() async throws {
        let wire = Wire(), vault = Vault(), base = "https://example.com/native"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base, approvedBaseURLs: [.china: [base]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.social.presentation", realm: "synthetic")
        let suite = "social-presentation-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let session = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }).makeSession()
        let reader = session.socialAccountReader, initial = reader.presentationRevision
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7); XCTAssertGreaterThan(reader.presentationRevision, initial)
        let old = SocialReadPresentationKey(reader: reader, request: "information-91", requiresSignIn: false)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNotEqual(old, .init(reader: reader, request: "information-91", requiresSignIn: false))
        let revision = reader.presentationRevision
        await session.logout()
        XCTAssertTrue(reader === session.socialAccountReader)
        XCTAssertGreaterThan(reader.presentationRevision, revision); XCTAssertNil(reader.identity.accountID); XCTAssertNil(vault.token)
        let before = wire.requests.count
        do { _ = try await reader.information(id: 91); XCTFail("No social grant is installed") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, before)
        XCTAssertTrue(wire.requests.allSatisfy { ["phone", "userInfo", "logout"].contains($0.url?.lastPathComponent ?? "") })
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let json: String
            switch request.url?.lastPathComponent {
            case "phone": json = #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#
            case "userInfo": json = "{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}"
            case "logout": json = #"{"code":200}"#
            default: throw APIError.invalidRequest
            }
            return (Data(json.utf8), 200)
        }
    }
}

/// Deliberately ignores task cancellation until the test releases each read.
@MainActor private final class InvitationHistoryHeldReader: SocialAccountReading {
    var identity = SocialAccountIdentity(accountID: 7, epoch: 1, role: "player")
    var presentationRevision: UInt64 = 0
    var isConfigured = true
    var isOfflineExample = true
    private(set) var pages: [Int] = []
    private var pending: [Int: CheckedContinuation<SocialInviteHistory, Error>] = [:]
    func invitationHistory(page: Int) async throws -> SocialInviteHistory {
        pages.append(page); let id = pages.count
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func waitForRead(_ id: Int) async throws {
        for _ in 0..<2_000 {
            if pending[id] != nil { return }
            await Task.yield()
        }
        XCTFail("Expected held invitation read \(id)")
        throw APIError.invalidRequest
    }
    func finish(_ id: Int, _ value: SocialInviteHistory) { pending.removeValue(forKey: id)?.resume(returning: value) }
    func fail(_ id: Int, _ error: Error) { pending.removeValue(forKey: id)?.resume(throwing: error) }
    func finishPending() {
        let reads = pending; pending.removeAll()
        for continuation in reads.values { continuation.resume(throwing: CancellationError()) }
    }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.invalidRequest }
    func informationList() async throws -> [SocialInformation] { throw APIError.invalidRequest }
    func information(id: Int) async throws -> SocialInformation { throw APIError.invalidRequest }
}

@MainActor final class SocialInvitationHistoryLifetimeAppTests: XCTestCase {
    private func history(_ ids: [Int], page: Int = 1, total: Int? = nil, completeRewards: Bool = true) throws -> SocialInviteHistory {
        let members = try ids.map { id in
            try JSONDecoder().decode(SocialInvitedMember.self, from: Data("{\"id\":\(id),\"nickname\":\"Fixture \(id)\"}".utf8))
        }
        let scan = try completeRewards ? JSONDecoder().decode(SocialRewardScan.self, from: Data(#"{"rows":[],"total":0}"#.utf8)) : nil
        return .init(page: .init(members: members, total: total, pageNumber: page, pageSize: 100), rewardScan: scan)
    }
    private func release(_ reader: InvitationHistoryHeldReader, id: Int, outcome: Int) throws {
        switch outcome {
        case 0: reader.finish(id, try history([90], total: 1))
        case 1: reader.fail(id, APIError.httpStatus(503))
        default: reader.fail(id, APIError.unauthorized)
        }
    }
    func testCurrentSuccessPreservesUnknownRewardAndSeparateTotal() async throws {
        let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
        defer { reader.finishPending(); model.suspend() }
        let read = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
        reader.finish(1, try history([8], total: 204, completeRewards: false)); await read.value
        XCTAssertTrue(model.matches(reader)); XCTAssertEqual(model.pagination.members.map(\.id), [8])
        XCTAssertEqual(model.pagination.total, 204); XCTAssertEqual(model.pagination.nextPage, 2)
        XCTAssertTrue(model.pagination.hasMore); XCTAssertNil(model.scan); XCTAssertNil(model.error); XCTAssertFalse(model.loading)
    }
    func testSameIdentityCloseReopenRejectsOldSuccessFailure401AndCompletion() async throws {
        for outcome in 0..<3 {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { reader.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
            let permit = try XCTUnwrap(model.permit(reader)); model.suspend()
            XCTAssertNil(model.permit(reader)); XCTAssertFalse(model.loading)
            XCTAssertNil(model.start(reader, permit: permit, reset: true))
            let current = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(2)
            XCTAssertNotEqual(permit, model.permit(reader))
            XCTAssertNil(model.start(reader, permit: permit, reset: true))
            try release(reader, id: 1, outcome: outcome); await old.value
            XCTAssertTrue(model.loading); XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertNil(model.error)
            reader.finish(2, try history([8], total: 1)); await current.value
            XCTAssertEqual(model.pagination.members.map(\.id), [8]); XCTAssertNil(model.error); XCTAssertFalse(model.loading)
            XCTAssertEqual(reader.pages, [1, 1])
        }
    }
    func testSameIdentityReaderReplacementRejectsOldResultsAndQueuedActions() async throws {
        for outcome in 0..<3 {
            let first = InvitationHistoryHeldReader(), second = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { first.finishPending(); second.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(first)); try await first.waitForRead(1)
            let permit = try XCTUnwrap(model.permit(first))
            XCTAssertFalse(model.matches(second)); XCTAssertNil(model.permit(second))
            model.bind(second)
            let current = try XCTUnwrap(model.replaceReader(second)); try await second.waitForRead(1)
            XCTAssertFalse(model.matches(first)); XCTAssertNil(model.start(first, permit: permit, reset: true))
            XCTAssertNil(model.start(second, permit: permit, reset: true))
            try release(first, id: 1, outcome: outcome); await old.value
            XCTAssertTrue(model.loading); XCTAssertNil(model.error); XCTAssertTrue(model.pagination.members.isEmpty)
            second.finish(1, try history([9], total: 1)); await current.value
            XCTAssertEqual(model.pagination.members.map(\.id), [9]); XCTAssertTrue(model.matches(second))
            XCTAssertFalse(model.loading); XCTAssertEqual(first.pages, [1]); XCTAssertEqual(second.pages, [1])
        }
    }
    func testSamePresentationRefreshSupersedesOldRequestWithoutOldDeferClearingBusy() async throws {
        for outcome in 0..<3 {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { reader.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
            let current = try XCTUnwrap(model.start(reader, permit: model.permit(reader), reset: true)); try await reader.waitForRead(2)
            try release(reader, id: 1, outcome: outcome); await old.value
            XCTAssertTrue(model.loading); XCTAssertNil(model.error); XCTAssertTrue(model.pagination.members.isEmpty)
            reader.finish(2, try history([10], total: 1)); await current.value
            XCTAssertEqual(model.pagination.members.map(\.id), [10]); XCTAssertFalse(model.loading)
        }
    }
    func testLateSuccessAndErrorsWhileClosedCannotPublishOrRestart() async throws {
        for outcome in 0..<3 {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { reader.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
            let permit = model.permit(reader); model.suspend()
            try release(reader, id: 1, outcome: outcome); await old.value
            await model.refresh(reader, permit: permit)
            XCTAssertNil(model.replaceReader(reader)); XCTAssertNil(model.start(reader, permit: permit, reset: false))
            XCTAssertEqual(reader.pages, [1]); XCTAssertTrue(model.pagination.members.isEmpty)
            XCTAssertNil(model.error); XCTAssertFalse(model.loading)
        }
    }
    func testCoveredNavigationRetainsRowsButNoActionsAndReappearanceReloadsPageOne() async throws {
        let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
        defer { reader.finishPending(); model.suspend() }
        let first = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
        reader.finish(1, try history([8], total: 200)); await first.value
        let permit = model.permit(reader); model.suspend()
        XCTAssertEqual(model.pagination.members.map(\.id), [8]); XCTAssertTrue(model.matches(reader)); XCTAssertNil(model.permit(reader))
        XCTAssertTrue(model.scan?.isComplete == true)
        XCTAssertNil(model.start(reader, permit: permit, reset: true))
        let second = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(2)
        XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertNil(model.scan)
        reader.finish(2, try history([9], total: 1)); await second.value
        XCTAssertEqual(model.pagination.members.map(\.id), [9]); XCTAssertEqual(reader.pages, [1, 1])
    }
    func testForeignOwnerCannotUsePermitEvenWithSameReader() async throws {
        let reader = InvitationHistoryHeldReader(), first = SocialInviteHistoryModel(), second = SocialInviteHistoryModel()
        defer { reader.finishPending(); first.suspend(); second.suspend() }
        let a = try XCTUnwrap(first.appear(reader)); try await reader.waitForRead(1)
        let b = try XCTUnwrap(second.appear(reader)); try await reader.waitForRead(2)
        XCTAssertNil(second.start(reader, permit: first.permit(reader), reset: true))
        XCTAssertNil(first.start(reader, permit: second.permit(reader), reset: true)); XCTAssertEqual(reader.pages, [1, 1])
        reader.finish(1, try history([8], total: 1)); reader.finish(2, try history([9], total: 1))
        await a.value; await b.value
        XCTAssertEqual(first.pagination.members.map(\.id), [8]); XCTAssertEqual(second.pagination.members.map(\.id), [9])
    }
    func testAccountRoleEpochRevisionAndConfigurationChangesImmediatelyHideOldPresentation() async throws {
        for change in 0..<6 { for outcome in 0..<3 {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { reader.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
            let permit = model.permit(reader)
            switch change {
            case 0: reader.identity = .init(accountID: 8, epoch: 1, role: "player")
            case 1: reader.identity = .init(accountID: 7, epoch: 2, role: "player")
            case 2: reader.identity = .init(accountID: 7, epoch: 1, role: "merchant")
            case 3: reader.presentationRevision += 2 // Token/role ABA can repeat the visible identity.
            case 4: reader.isConfigured = false
            default: reader.identity = .init(accountID: nil, epoch: 2)
            }
            XCTAssertFalse(model.matches(reader)); XCTAssertNil(model.permit(reader))
            XCTAssertNil(model.start(reader, permit: permit, reset: true))
            // No suspend/replace/cancel has run: the key fence must reject this result by itself.
            try release(reader, id: 1, outcome: outcome); await old.value
            XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertNil(model.error)
            model.bind(reader)
            let replacement = model.replaceReader(reader)
            if change < 4 {
                let current = try XCTUnwrap(replacement); try await reader.waitForRead(2)
                reader.finish(2, try history([8], total: 1)); await current.value
                XCTAssertEqual(model.pagination.members.map(\.id), [8])
            } else {
                XCTAssertNil(replacement); XCTAssertFalse(model.loading); XCTAssertEqual(reader.pages, [1])
            }
        } }
    }
    func testGuestAndUnconfiguredReadersNeverDispatch() async {
        for guest in [true, false] {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            if guest { reader.identity = .init(accountID: nil, epoch: 1) } else { reader.isConfigured = false }
            XCTAssertNil(model.appear(reader)); XCTAssertNil(model.permit(reader)); XCTAssertFalse(model.matches(reader))
            await model.refresh(reader, permit: nil)
            XCTAssertTrue(reader.pages.isEmpty); XCTAssertFalse(model.loading); model.suspend()
        }
    }
    func testDuplicateAppearAndLoadMoreDispatchOnceAndRetryKeepsExactPage() async throws {
        let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
        defer { reader.finishPending(); model.suspend() }
        let first = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
        XCTAssertNil(model.appear(reader)); XCTAssertNil(model.replaceReader(reader))
        reader.finish(1, try history([8], total: 2)); await first.value
        let permit = model.permit(reader)
        let next = try XCTUnwrap(model.start(reader, permit: permit, reset: false)); try await reader.waitForRead(2)
        XCTAssertNil(model.start(reader, permit: permit, reset: false))
        reader.fail(2, APIError.httpStatus(503)); await next.value
        XCTAssertEqual(model.pagination.members.map(\.id), [8]); XCTAssertEqual(model.pagination.nextPage, 2)
        XCTAssertEqual(model.error as? APIError, .httpStatus(503)); XCTAssertFalse(model.loading)
        let retry = try XCTUnwrap(model.start(reader, permit: permit, reset: false)); try await reader.waitForRead(3)
        reader.finish(3, try history([8, 9], page: 2, total: 2)); await retry.value
        XCTAssertEqual(model.pagination.members.map(\.id), [8, 9]); XCTAssertFalse(model.pagination.hasMore)
        XCTAssertNil(model.error); XCTAssertNil(model.start(reader, permit: permit, reset: false))
        XCTAssertEqual(reader.pages, [1, 2, 2])
    }
    func testCurrentUnauthorizedClearsPrivateRowsWhileOrdinaryFailureDoesNot() async throws {
        let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
        defer { reader.finishPending(); model.suspend() }
        let first = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
        reader.finish(1, try history([8], total: 2)); await first.value
        let next = try XCTUnwrap(model.start(reader, permit: model.permit(reader), reset: false)); try await reader.waitForRead(2)
        reader.fail(2, APIError.unauthorized); await next.value
        XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertNil(model.scan); XCTAssertFalse(model.loading)
        XCTAssertEqual(model.error as? APIError, .unauthorized)
    }
    func testCancelledRefreshCannotPublishLateUnauthorizedOrOrdinaryError() async throws {
        for failure in [APIError.unauthorized, APIError.httpStatus(503)] {
            let reader = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
            defer { reader.finishPending(); model.suspend() }
            let initial = try XCTUnwrap(model.appear(reader)); try await reader.waitForRead(1)
            reader.finish(1, try history([8], total: 1)); await initial.value
            let permit = model.permit(reader)
            let refresh = Task { await model.refresh(reader, permit: permit) }; try await reader.waitForRead(2)
            refresh.cancel(); reader.fail(2, failure); await refresh.value
            XCTAssertNil(model.error); XCTAssertFalse(model.loading); XCTAssertTrue(model.pagination.members.isEmpty)
        }
    }
    func testClosedReadCannotExpireSessionFromLateHTTPOrEnvelope401() async throws {
        for status in [200, 401] {
            let wire = InvitationWire(), model = SocialInviteHistoryModel()
            let session = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-token")
            var expirations = 0
            let reader = SocialAccountSessionReader(
                service: .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire),
                currentSession: { session }, onUnauthorized: { _ in expirations += 1 })
            defer { wire.cancelPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(reader)); try await wire.waitForRead()
            model.suspend(); wire.finish(status: status); await old.value
            XCTAssertEqual(expirations, 0); XCTAssertEqual(wire.reads, 1)
            XCTAssertNil(model.error); XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertFalse(model.loading)
        }
    }
    func testCurrentHTTPOrEnvelope401StillExpiresSessionAndShowsSignInError() async throws {
        for status in [200, 401] {
            let wire = InvitationWire(), model = SocialInviteHistoryModel()
            let session = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-token")
            var expirations = 0
            let reader = SocialAccountSessionReader(
                service: .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire),
                currentSession: { session }, onUnauthorized: { _ in expirations += 1 })
            defer { wire.cancelPending(); model.suspend() }
            let current = try XCTUnwrap(model.appear(reader)); try await wire.waitForRead()
            wire.finish(status: status); await current.value
            XCTAssertEqual(expirations, 1); XCTAssertEqual(model.error as? APIError, .unauthorized)
            XCTAssertTrue(model.pagination.members.isEmpty); XCTAssertFalse(model.loading)
        }
    }

    func testRenderBindingRetiresOldReaderBeforeOnChangeIncludingSession401SideEffects() async throws {
        for status in [200, 401] {
            let wire = InvitationWire(), model = SocialInviteHistoryModel()
            let session = try SocialAccountSession(accountID: 7, epoch: 1, role: "player", token: "synthetic-token")
            var expirations = 0
            let first = SocialAccountSessionReader(
                service: .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: wire),
                currentSession: { session }, onUnauthorized: { _ in expirations += 1 })
            let second = InvitationHistoryHeldReader()
            defer { wire.cancelPending(); second.finishPending(); model.suspend() }
            let old = try XCTUnwrap(model.appear(first)); try await wire.waitForRead()
            let permit = model.permit(first)
            model.bind(second) // New SwiftUI body, but no replaceReader/onChange yet.
            XCTAssertFalse(model.matches(first)); XCTAssertFalse(model.matches(second))
            XCTAssertNil(model.permit(first)); XCTAssertNil(model.start(first, permit: permit, reset: true))
            XCTAssertNil(model.appear(first)) // A delayed old lifecycle callback cannot restore its reader.
            wire.finish(status: status); await old.value
            XCTAssertEqual(expirations, 0); XCTAssertNil(model.error); XCTAssertTrue(model.pagination.members.isEmpty)
            let current = try XCTUnwrap(model.replaceReader(second)); try await second.waitForRead(1)
            second.finish(1, try history([9], total: 1)); await current.value
            XCTAssertTrue(model.matches(second)); XCTAssertEqual(model.pagination.members.map(\.id), [9])
        }
    }
    func testRenderBindingABAReplacesLifetimeEvenBeforeAnyOnChangeRuns() async throws {
        let first = InvitationHistoryHeldReader(), second = InvitationHistoryHeldReader(), model = SocialInviteHistoryModel()
        defer { first.finishPending(); second.finishPending(); model.suspend() }
        let old = try XCTUnwrap(model.appear(first)); try await first.waitForRead(1)
        let oldBinding = model.bind(first), oldPermit = model.permit(first)
        model.bind(second); let newBinding = model.bind(first)
        XCTAssertNotEqual(oldBinding, newBinding); XCTAssertNil(model.permit(first)); XCTAssertFalse(model.matches(first))
        XCTAssertNil(model.start(first, permit: oldPermit, reset: true))
        let current = try XCTUnwrap(model.replaceReader(first)); try await first.waitForRead(2)
        first.fail(1, APIError.unauthorized); await old.value
        XCTAssertTrue(model.loading); XCTAssertNil(model.error)
        first.finish(2, try history([8], total: 1)); await current.value
        XCTAssertEqual(model.pagination.members.map(\.id), [8]); XCTAssertEqual(first.pages, [1, 1]); XCTAssertTrue(second.pages.isEmpty)
    }
    @MainActor private final class InvitationWire: HTTPTransport {
        private(set) var reads = 0
        private var pending: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            reads += 1
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func waitForRead() async throws {
            for _ in 0..<2_000 {
                if pending != nil { return }
                await Task.yield()
            }
            XCTFail("Expected a held source-backed invitation request")
            throw APIError.invalidRequest
        }
        func finish(status: Int) {
            let continuation = pending; pending = nil
            continuation?.resume(returning: (Data(#"{"code":401}"#.utf8), status))
        }
        func cancelPending() {
            let continuation = pending; pending = nil
            continuation?.resume(throwing: CancellationError())
        }
    }

}
