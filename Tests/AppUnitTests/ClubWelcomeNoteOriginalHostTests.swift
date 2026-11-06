import Foundation
import XCTest
@testable import Questify

/// Source-only native host tests. No live endpoint or installed production grant.
@MainActor final class ClubWelcomeNoteOriginalHostTests: XCTestCase {
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        var role = "club"
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/phone") == true {
                return (Data("{\"code\":200,\"token\":\"synthetic-token\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
            }
            if request.url?.path.hasSuffix("/userInfo") == true {
                return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
            }
            beforeReply?(); return (Data(#"{"code":200,"data":null}"#.utf8), 200)
        }
    }
    private final class Scope {
        var viewer: CompositionHTTPTransport.SessionIdentity?
        var write: OperationEndpointApproval?, receipt: OperationEndpointApproval?
    }
    private final class Fixture {
        let base = URL(string: "https://example.test/native")!
        let wire = Wire(), scope = Scope()
        let deployment: ReviewedAppDeployment, context: RuntimeDependencyContext
        lazy var transport: CompositionHTTPTransport = {
            let result = CompositionHTTPTransport(deployment: deployment, underlying: wire)
            result.current = { self.scope.viewer }; return result
        }()
        init() throws {
            deployment = try .init(market: .china, baseURL: base.absoluteString,
                approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.welcome-original", realm: "synthetic")
            context = .init(market: .china, baseURL: base, role: "club", session: try .init(accountID: 7, epoch: 1,
                namespace: deployment.storageScope.service, token: "synthetic-token", role: "club"))
            scope.viewer = .init(epoch: 1, accountID: 7, role: "club", token: "synthetic-token", viewerRevision: 1)
        }
        func enable(write: Bool = true, read: Bool = true) throws {
            scope.write = write ? try .init(baseURL: base, namespace: context.session.namespace, accountID: 7, paths: [ClubWelcomeNoteService.path]) : nil
            scope.receipt = read ? try .init(baseURL: base, namespace: context.session.namespace, accountID: 7, paths: [ClubWelcomeNoteService.receiptPath]) : nil
        }
        func adapter(write: Bool) -> any ClubWelcomeNoteDispatching {
            transport.clubWelcomeNoteDispatchTransport(path: write ? ClubWelcomeNoteService.path : ClubWelcomeNoteService.receiptPath,
                approval: { write ? self.scope.write : self.scope.receipt })
        }
        func request(write: Bool = true) throws -> URLRequest {
            let requestID = "00000000-0000-0000-0000-000000000001"
            let source = ClubWelcomeNoteOriginalWire.source(clubID: "9", note: "original text")
            var request = URLRequest(url: base.appendingPathComponent(write ? ClubWelcomeNoteService.path : ClubWelcomeNoteService.receiptPath))
            request.httpMethod = "POST"; request.httpShouldHandleCookies = false
            request.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let fields: [String: Any] = write ? ["id": 9, "welcomeNote": "original text"]
                : ["clubId": 9, "requestId": requestID, "sourceSHA256": source]
            request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
            if write {
                request.setValue(requestID, forHTTPHeaderField: "X-Club-Welcome-Request-Id")
                request.setValue(source, forHTTPHeaderField: "X-Club-Welcome-Source-SHA256")
            }
            return request
        }
    }
    private func reject(_ request: URLRequest, adapter: any ClubWelcomeNoteDispatching, wire: Wire) async {
        let before = wire.requests.count
        let authorization = ClubWelcomeNoteDispatchAuthorization(request: request, current: { true })
        do { _ = try await adapter.send(request, authorization: authorization); XCTFail("Unexpected welcome forwarding") } catch {}
        XCTAssertFalse(authorization.didForward); XCTAssertEqual(wire.requests.count, before)
    }
    func testDefaultStorageSelectorsAndRuntimeStayNil() throws {
        let f = try Fixture(), root = AppCompositionRoot()
        XCTAssertNil(root.storage.clubWelcomeNoteOriginalJournalDirectory)
        XCTAssertNil(root.storage.clubWelcomeNoteOriginalJournalFactory)
        XCTAssertNil(root.clubWelcomeNoteWriteApproval(f.context)); XCTAssertNil(root.clubWelcomeNoteReceiptApproval(f.context))
        XCTAssertNil(root.makeClubWelcomeNoteRuntime(transport: f.transport, current: { f.context }))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testExplicitUnavailableFactoryNeverFallsBackToDirectory() throws {
        let f = try Fixture()
        var storage = AppScopedStorageFactory()
        storage.clubWelcomeNoteOriginalJournalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("not-created-" + UUID().uuidString)
        storage.clubWelcomeNoteOriginalJournalFactory = { nil }
        let root = AppCompositionRoot(storage: storage)
        XCTAssertNil(root.makeClubWelcomeNoteRuntime(transport: f.transport, current: { f.context }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.clubWelcomeNoteOriginalJournalDirectory!.path))
    }
    func testOptInJournalFactoryUsesOriginalAndNeverCreatesLegacyRuntime() throws {
        let f = try Fixture(), directory = FileManager.default.temporaryDirectory.appendingPathComponent("not-created-" + UUID().uuidString)
        let original = ClubWelcomeNoteOriginalJournal(directory: directory)
        var storage = AppScopedStorageFactory(); storage.clubWelcomeNoteOriginalJournalFactory = { original }
        let root = AppCompositionRoot(storage: storage)
        let runtime = try XCTUnwrap(root.makeClubWelcomeNoteRuntime(transport: f.transport, current: { f.context }))
        XCTAssertTrue(runtime.originalJournal === original); XCTAssertNotNil(runtime.receiptTransport)
        XCTAssertNil(runtime.approval()); XCTAssertNil(runtime.receiptApproval())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testIndependentApprovalsAndGenericRouteDenial() async throws {
        let f = try Fixture(); try f.enable(write: false)
        await reject(try f.request(), adapter: f.adapter(write: true), wire: f.wire)
        let receipt = try f.request(write: false)
        let authorization = ClubWelcomeNoteDispatchAuthorization(request: receipt, current: { true })
        _ = try await f.adapter(write: false).send(receipt, authorization: authorization)
        XCTAssertTrue(authorization.didForward); XCTAssertEqual(f.wire.requests.count, 1)
        for write in [true, false] {
            do { _ = try await f.transport.send(f.request(write: write)); XCTFail("Generic route was widened") } catch {}
        }
        XCTAssertEqual(f.wire.requests.count, 1)
        try f.enable(write: true, read: false)
        f.scope.receipt = f.scope.write
        await reject(receipt, adapter: f.adapter(write: false), wire: f.wire)
    }
    func testStrictWriterRejectsLegacyPayloadAndForgedSource() async throws {
        let f = try Fixture(); try f.enable()
        for variant in 0..<11 {
            var request = try f.request()
            switch variant {
            case 0: request.setValue(nil, forHTTPHeaderField: "X-Club-Welcome-Request-Id")
            case 1: request.setValue(String(repeating: "a", count: 64), forHTTPHeaderField: "X-Club-Welcome-Source-SHA256")
            case 2: request.url = URL(string: request.url!.absoluteString + "?extra=1")
            case 3: request.httpShouldHandleCookies = true
            case 4: request.setValue("x", forHTTPHeaderField: "Cookie")
            case 5: request.setValue("foreign-token", forHTTPHeaderField: "Authorization")
            case 6: request.httpBody = Data(#"{"id":true,"welcomeNote":"original text"}"#.utf8)
            case 7: request.httpBody = Data(#"{"id":9,"id":9,"welcomeNote":"original text"}"#.utf8)
            case 8: request.httpBody = Data(#"{"id":9,"welcomeNote":"original text","role":"owner"}"#.utf8)
            case 9: request.httpBody = Data(#"{"id":9,"welcomeNote":" original text "}"#.utf8)
            default: request.httpMethod = "GET"
            }
            await reject(request, adapter: f.adapter(write: true), wire: f.wire)
        }
    }
    func testBroadForeignAndMissingApprovalCannotForward() async throws {
        let f = try Fixture(); try f.enable()
        for variant in 0..<4 {
            f.scope.write = variant == 3 ? nil : try .init(
                baseURL: variant == 0 ? URL(string: "https://foreign.test/native")! : f.base,
                namespace: variant == 1 ? "foreign-scope" : f.context.session.namespace,
                accountID: 7, paths: variant == 2 ? [ClubWelcomeNoteService.path, ClubWelcomeNoteService.receiptPath] : [ClubWelcomeNoteService.path])
            await reject(try f.request(), adapter: f.adapter(write: true), wire: f.wire)
        }
    }
    func testReceiptRouteRejectsWriterHeadersExtraKeysAndBooleanClub() async throws {
        let f = try Fixture(); try f.enable()
        for variant in 0..<3 {
            var request = try f.request(write: false)
            if variant == 0 { request.setValue("00000000-0000-0000-0000-000000000001", forHTTPHeaderField: "X-Club-Welcome-Request-Id") }
            else {
                var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                if variant == 1 { fields["welcomeNote"] = "current text is not evidence" } else { fields["clubId"] = true }
                request.httpBody = try JSONSerialization.data(withJSONObject: fields)
            }
            await reject(request, adapter: f.adapter(write: false), wire: f.wire)
        }
    }
    func testOneShotAuthorizationAndPostForwardViewerRevocation() async throws {
        let f = try Fixture(); try f.enable()
        let request = try f.request(), adapter = f.adapter(write: true)
        let authorization = ClubWelcomeNoteDispatchAuthorization(request: request, current: { true })
        f.wire.beforeReply = { f.scope.viewer = .init(epoch: 1, accountID: 7, role: "club", token: "synthetic-token", viewerRevision: 3) }
        do { _ = try await adapter.send(request, authorization: authorization); XCTFail("Role ABA must retire response") } catch {}
        XCTAssertTrue(authorization.didForward); XCTAssertEqual(f.wire.requests.count, 1)
        do { _ = try await adapter.send(request, authorization: authorization); XCTFail("Authorization reused") } catch {}
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    private final class Access: ClubOperationsAccess {
        var identity: ClubReadIdentity? = .init(accountID: 7, epoch: 1)
        var welcomeNoteRevision: UInt64 = 1
        var isConfigured: Bool { true }
        var writeAvailability: ClubOperationsWriteAvailability { .approved }
        var afterSnapshot: (() -> Void)?
        var profile: ClubOperationsProfile?
        var calls = 0
        func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
            calls += 1; afterSnapshot?(); return .init(target: target, profile: profile)
        }
        func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt { XCTFail("Ordinary write passthrough"); throw APIError.invalidRequest }
    }
    func testRepeatedVisitRetirementCannotAffectNewVisitOrAcceptOldCallback() {
        let access = Access(), identity = access.identity!
        let first = ClubWelcomeNoteVisit(clubID: 9, identity: identity, access: access)
        first.retire()
        let second = ClubWelcomeNoteVisit(clubID: 9, identity: identity, access: access)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(first.matches(clubID: 9, identity: identity, access: access))
        XCTAssertTrue(second.matches(clubID: 9, identity: identity, access: access))
        first.retire(); XCTAssertTrue(second.isCurrent)
        XCTAssertFalse(second.matches(clubID: 9, identity: identity, access: Access()))
        access.welcomeNoteRevision += 1; XCTAssertFalse(second.isCurrent); XCTAssertNil(second.access.identity)
    }
    func testVisitDropsLateSnapshotAndRetiresFlowOnSameAccountRevisionChange() async throws {
        let access = Access(), visit = ClubWelcomeNoteVisit(clubID: 9, identity: access.identity!, access: access)
        let flow = ClubWelcomeNoteFlow(clubID: 9, identity: access.identity!, access: visit.access)
        access.afterSnapshot = { access.welcomeNoteRevision += 1 }
        await flow.load()
        XCTAssertFalse(flow.current); XCTAssertNil(visit.access.identity); XCTAssertFalse(flow.canSave)
        await flow.load(); XCTAssertEqual(access.calls, 1)
        visit.retire(); flow.close(); XCTAssertTrue(flow.draft.isEmpty)
    }
    func testConfirmedReturnRefreshNoticeSurvivesSheetCloseButNotSourceReplacementOrRevisionChange() async throws {
        let access = Access(), identity = access.identity!
        let visit = ClubWelcomeNoteVisit(clubID: 9, identity: identity, access: access)
        let notice = try XCTUnwrap(ClubWelcomeNoteConfirmedReturn(visit: visit, access: access))
        visit.retire()
        XCTAssertTrue(notice.matches(target: .club(9), identity: identity, access: access))
        XCTAssertFalse(notice.matches(target: .club(10), identity: identity, access: access))
        XCTAssertFalse(notice.matches(target: .club(9), identity: identity, access: Access()))
        let fresh = try await ClubWelcomeNoteCurrentReadback.read(notice, access: access, current: { true })
        XCTAssertEqual(fresh.target, .club(9)); XCTAssertEqual(access.calls, 1)
        access.afterSnapshot = { access.welcomeNoteRevision += 1 }
        do { _ = try await ClubWelcomeNoteCurrentReadback.read(notice, access: access, current: { true }); XCTFail("Late parent snapshot") } catch {}
        XCTAssertEqual(access.calls, 2)
        do { _ = try await ClubWelcomeNoteCurrentReadback.read(notice, access: access, current: { true }); XCTFail("Stale notice") } catch {}
        XCTAssertEqual(access.calls, 2)
    }
    func testParentReadbackDropsEarlierGenerationAndNeverReplaysWelcomeWrite() async throws {
        let access = Access(), visit = ClubWelcomeNoteVisit(clubID: 9, identity: access.identity!, access: access)
        let notice = try XCTUnwrap(ClubWelcomeNoteConfirmedReturn(visit: visit, access: access))
        var current = true
        access.afterSnapshot = { current = false }
        do { _ = try await ClubWelcomeNoteCurrentReadback.read(notice, access: access, current: { current }); XCTFail("Retired readback") } catch {}
        XCTAssertEqual(access.calls, 1)
    }
    func testParentReadbackKeepsUnchangedCurrentTextRatherThanHistoricalAcknowledgement() async throws {
        let access = Access(), visit = ClubWelcomeNoteVisit(clubID: 9, identity: access.identity!, access: access)
        access.profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: Data(#"{"id":9,"name":"Synthetic","isOwner":true,"welcomeNote":"old current value"}"#.utf8))
        let notice = try XCTUnwrap(ClubWelcomeNoteConfirmedReturn(visit: visit, access: access))
        // A concurrent writer may have restored the old value after our APPLIED request.
        // The notice deliberately carries no note string, and the Entry uses only this snapshot.
        let fresh = try await ClubWelcomeNoteCurrentReadback.read(notice, access: access, current: { true })
        XCTAssertEqual(fresh.profile?.club.welcomeNote, "old current value")
        XCTAssertEqual(access.calls, 1)
    }
    private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ token: String) throws { self.token = token }
        func clear() throws { token = nil }
    }
    func testAppSessionWiresIndependentServiceAndLiveRevisionWithoutDefaultIssuance() async throws {
        for configured in [false, true] {
            let f = try Fixture(), vault = Vault(), suite = "welcome-app-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var storage = AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault })
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { try? FileManager.default.removeItem(at: directory) }
            if configured { storage.clubWelcomeNoteOriginalJournalDirectory = directory }
            var root = AppCompositionRoot(deployment: .reviewed(f.deployment), storage: storage, makeTransport: { f.wire })
            if configured {
                root.clubWelcomeNoteReceiptApproval = { context in
                    try? .init(baseURL: context.baseURL, namespace: context.session.namespace,
                        accountID: context.session.accountID, paths: [ClubWelcomeNoteService.receiptPath])
                }
            }
            let session = root.makeSession()
            session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            let access = session.clubOperationsAccess, identity = try XCTUnwrap(access.identity)
            if configured {
                let service = try XCTUnwrap(access.welcomeNote)
                XCTAssertTrue(service.canRecover(identity: identity)); XCTAssertFalse(service.available(identity: identity))
                let visit = ClubWelcomeNoteVisit(clubID: 9, identity: identity, access: access)
                let oldRevision = access.welcomeNoteRevision
                f.wire.role = "player"; await session.refreshOwnAccount()
                f.wire.role = "club"; await session.refreshOwnAccount()
                XCTAssertGreaterThan(access.welcomeNoteRevision, oldRevision); XCTAssertFalse(visit.isCurrent)
            } else { XCTAssertNil(access.welcomeNote) }
            XCTAssertFalse(f.wire.requests.contains { $0.url?.path.contains("welcome-note") == true })
        }
    }
}
