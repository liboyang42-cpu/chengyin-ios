import XCTest
import Combine
@testable import Questify

@MainActor final class MerchantAcceptedProjectEntryTests: XCTestCase {
    private static let row: CoopFlowJSON = .object(["id": .id(71), "topicId": .id(70), "inviteType": .id(0), "status": .id(1)])
    @MainActor private final class Merchant: MerchantReading {
        @Published var isConfigured = true
        @Published var isSignedIn = true
        @Published var sessionRevision: UInt64 = 1
        var allowed = true, reads = 0
        var afterAccess: (() -> Void)?
        func merchantAccess() async throws -> MerchantAccess {
            reads += 1; afterAccess?()
            let raw = "{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":\(allowed ? "[\"merchant:project:manage\"]" : "[]")}"
            return try JSONDecoder().decode(MerchantAccess.self, from: Data(raw.utf8))
        }
        func merchantDashboard(access: MerchantAccess) async throws -> MerchantDashboard { throw APIError.invalidRequest }
        func merchantTodo(access: MerchantAccess) async throws -> MerchantTodo { throw APIError.invalidRequest }
        func merchantEvents(access: MerchantAccess) async throws -> [MerchantEvent] { throw APIError.invalidRequest }
        func merchantOrders(access: MerchantAccess, filter: MerchantOrderFilter) async throws -> [MerchantOrder] { throw APIError.invalidRequest }
        func merchantProjects(access: MerchantAccess) async throws -> MerchantProjectPage { throw APIError.invalidRequest }
    }
    @MainActor private final class Flow: CoopFlowReading {
        var session: CoopFlowSession? = try! .init(accountID: 2, epoch: 1, token: "fixture-token")
        var rows = [MerchantAcceptedProjectEntryTests.row]
        var reads = 0, fail = false
        var afterRead: (() -> Void)?
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            reads += 1; XCTAssertEqual(resource, .invitations); afterRead?()
            if fail { throw URLError(.notConnectedToInternet) }
            return .object(["received": .array(rows), "sent": .array([])])
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw APIError.invalidRequest }
    }
    @MainActor private final class Service: MerchantContentServing {
        var scope = UUID(), isConfigured = true, isAuthenticated = true
        let permitsWrites = false
        var reads = 0, writes = 0
        var result: MerchantContentSnapshot?
        func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot { reads += 1; if let result { return result }; throw APIError.invalidRequest }
        func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt { writes += 1; throw MerchantContentFailure.disabled }
        func pending() throws -> [MerchantContentPendingRecord] { [] }
        func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { throw MerchantContentFailure.disabled }
        func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { throw MerchantContentFailure.disabled }
    }
    @MainActor private final class Snapshot {
        var rows = [MerchantAcceptedProjectEntryTests.row]
        var current = true, host = true
    }
    @MainActor private final class Harness {
        let merchant = Merchant(), flow = Flow(), service = Service(), snapshot = Snapshot()
        let source: MerchantAcceptedProjectSource
        let gate: MerchantAcceptedProjectGate<Merchant>
        init() throws {
            let capturedSnapshot = snapshot
            source = try XCTUnwrap(.init(reader: flow, row: MerchantAcceptedProjectEntryTests.row, direction: .received,
                currentRows: { capturedSnapshot.current ? capturedSnapshot.rows : nil }))
            gate = .init(source: source, merchant: merchant, service: service, hostIsCurrent: { capturedSnapshot.host })
        }
    }
    func testFreshMerchantAccessThenSameInvitationPermitsOnlyNavigation() async throws {
        let h = try Harness(); await h.gate.load()
        XCTAssertEqual(h.merchant.reads, 1); XCTAssertEqual(h.flow.reads, 1)
        XCTAssertTrue(h.gate.canPresent); XCTAssertEqual(h.gate.destination?.merchantID, 31)
        XCTAssertEqual(h.source.route.topicID, 70); XCTAssertEqual(h.service.reads, 0); XCTAssertEqual(h.service.writes, 0)
    }
    func testDeniedProjectPermissionDoesNotReadInvitations() async throws {
        let h = try Harness(); h.merchant.allowed = false; await h.gate.load()
        XCTAssertEqual(h.flow.reads, 0); XCTAssertFalse(h.gate.canPresent); XCTAssertEqual(h.gate.issue, "merchant.access.denied")
    }
    func testStaleSourceAndReplacedHostCannotRead() async throws {
        for host in [false,true] {
            let h = try Harness(); if host { h.snapshot.host = false } else { h.snapshot.current = false }
            await h.gate.load(); XCTAssertEqual(h.merchant.reads, 0); XCTAssertEqual(h.flow.reads, 0); XCTAssertFalse(h.gate.canPresent)
        }
    }
    func testAccountRevisionDuringAccessStopsReadAndNavigation() async throws {
        let h = try Harness(); h.merchant.afterAccess = { h.merchant.sessionRevision += 1 }; await h.gate.load()
        XCTAssertEqual(h.flow.reads, 0); XCTAssertFalse(h.gate.canPresent)
    }
    func testMissingRevokedAndDuplicateInvitationCannotOpenProject() async throws {
        for rows in [[CoopFlowJSON](), [Self.row,Self.row], [.object(["id": .id(71), "topicId": .id(70), "inviteType": .id(0), "status": .id(3)])]] {
            let h = try Harness(); h.flow.rows = rows; await h.gate.load()
            XCTAssertFalse(h.gate.canPresent); XCTAssertEqual(h.service.reads, 0)
        }
    }
    func testServiceScopeOrCooperationSessionChangesAfterFreshReadRejects() async throws {
        for service in [true,false] {
            let h = try Harness(); h.flow.afterRead = { if service { h.service.scope = UUID() } else { h.flow.session = nil } }
            await h.gate.load(); XCTAssertFalse(h.gate.canPresent); XCTAssertNil(h.gate.destination)
        }
    }
    func testRetirementDuringAccessRejectsLateCallback() async throws {
        let h = try Harness(); h.merchant.afterAccess = { h.gate.retire() }; await h.gate.load()
        XCTAssertFalse(h.gate.canPresent); XCTAssertNil(h.gate.destination); XCTAssertEqual(h.flow.reads, 0)
    }
    func testNetworkFailureCanRetryWithFreshAccessAndNoWrite() async throws {
        let h = try Harness(); h.flow.fail = true; await h.gate.load()
        XCTAssertEqual(h.gate.issue, "merchant.loadFailed"); XCTAssertFalse(h.gate.canPresent)
        h.flow.fail = false; await h.gate.load(); XCTAssertTrue(h.gate.canPresent)
        XCTAssertEqual(h.merchant.reads, 2); XCTAssertEqual(h.flow.reads, 2); XCTAssertEqual(h.service.writes, 0)
    }
    func testBackgroundRetiresPermitAndReturnRequiresFreshReads() async throws {
        let h = try Harness(); await h.gate.load(); let old = try XCTUnwrap(h.gate.destination?.id)
        h.gate.retire(); XCTAssertFalse(h.gate.canPresent); h.gate.activate(); await h.gate.load()
        XCTAssertTrue(h.gate.canPresent); XCTAssertNotEqual(h.gate.destination?.id, old); XCTAssertEqual(h.merchant.reads, 2)
    }
    func testChangedSourceRowsImmediatelyHideAuthorizedDestination() async throws {
        let h = try Harness(); await h.gate.load(); XCTAssertTrue(h.gate.canPresent)
        h.snapshot.rows = []; XCTAssertFalse(h.gate.canPresent)
    }
    func testUnknownOrUnauthenticatedContentServiceNeverStartsGate() async throws {
        for auth in [true,false] {
            let h = try Harness(); if auth { h.service.isAuthenticated = false } else { h.service.isConfigured = false }
            await h.gate.load(); XCTAssertFalse(h.gate.canPresent); XCTAssertEqual(h.merchant.reads, 0)
        }
    }
    func testExistingProjectDocumentLoadsExactMerchantAndTopicThenStopsWhenRetired() async throws {
        let h = try Harness(); await h.gate.load()
        let access = try await h.merchant.merchantAccess()
        h.service.result = .init(query: .project(topicID: 70), scope: h.service.scope, access: access,
            value: .object(["topic": .object(["id": .integer(70)]), "join": .object([:])]), observedAt: Date())
        let model = MerchantContentViewModel(service: h.service, query: .project(topicID: 70), focusedTopicID: 70,
            focusedMerchantID: 31, projectEntryIsCurrent: { h.gate.canPresent })
        await model.load(); XCTAssertTrue(model.projectPresentationIsCurrent); XCTAssertEqual(h.service.reads, 1)
        h.gate.retire(); await model.load(); XCTAssertFalse(model.projectPresentationIsCurrent)
        XCTAssertEqual(h.service.reads, 1); XCTAssertEqual(h.service.writes, 0)
    }
    func testMismatchedProjectProjectionCannotBecomeWorkspace() async throws {
        let h = try Harness(); await h.gate.load()
        let access = try await h.merchant.merchantAccess()
        h.service.result = .init(query: .project(topicID: 70), scope: h.service.scope, access: access,
            value: .object(["topic": .object(["id": .integer(72)]), "join": .object([:])]), observedAt: Date())
        let model = MerchantContentViewModel(service: h.service, query: .project(topicID: 70), focusedTopicID: 70,
            focusedMerchantID: 31, projectEntryIsCurrent: { h.gate.canPresent })
        await model.load(); XCTAssertFalse(model.projectPresentationIsCurrent); XCTAssertEqual(h.service.writes, 0)
    }

}
