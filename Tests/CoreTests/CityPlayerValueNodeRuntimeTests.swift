import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class CityPlayerValueNodeRuntimeTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func grant() throws -> CityPlayerValueNodeApproval {
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "node-fixture", token: "synthetic-token"))
        let endpoints = try OperationEndpointApproval(baseURL: base, namespace: context.session.namespace,
            accountID: 7, paths: ["api/city/nodes/2", "api/city/nodes/2/complete"])
        return try CityPlayerValueNodeApproval(context: context, poiID: 2, endpoints: endpoints,
            foregroundLocation: true, camera: true, expiresAt: Date().addingTimeInterval(600))
    }
    private func response(completed: Bool = false, pending: Bool = false, id: Int = 2) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["poiId": id, "name": "Fixture",
            "status": 1, "validationMethod": 4, "completed": completed, "needRedeem": pending]])
    }
    private func runtime(_ grant: CityPlayerValueNodeApproval, _ wire: Wire, _ journal: Journal,
                         current: @escaping () -> Bool = { true }) throws -> CityPlayerValueNodeRuntime {
        let boundary = CityPlayerValueNodeTransport(underlying: wire, approval: grant, verification: nil, current: current)
        return try CityPlayerValueNodeRuntime(grant: grant, verification: nil, transport: boundary,
            location: Device(), journal: journal, current: current)
    }
    func testPositiveActorScopedCompletionClearsOnlyOriginalLock() async throws {
        for pending in [false, true] {
            let grant = try grant(), wire = Wire(), journal = Journal()
            wire.data = try response(completed: !pending, pending: pending)
            let model = try runtime(grant, wire, journal)
            let node = try await model.recoverCompletion()
            XCTAssertTrue(node.completed || node.needRedeem)
            XCTAssertNil(journal.record); XCTAssertEqual(journal.clears, 1)
            XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests.first?.httpMethod, "GET")
            XCTAssertEqual(journal.lastOwner, "roam-poster:node-fixture:https://example.test/native:7")
            XCTAssertEqual(journal.lastTarget, "poi:2")
        }
    }
    func testAbsenceAnd404NeverClearLock() async throws {
        for status in [200, 404, 410, 503] {
            let grant = try grant(), wire = Wire(), journal = Journal()
            wire.data = try response(); wire.status = status
            let model = try runtime(grant, wire, journal)
            do { _ = try await model.recoverCompletion(); XCTFail("Missing positive evidence must stay locked") } catch {}
            XCTAssertNotNil(journal.record); XCTAssertEqual(journal.clears, 0)
        }
    }
    func testDifferentPOIPositiveEvidenceCannotClearLock() async throws {
        let grant = try grant(), wire = Wire(), journal = Journal()
        wire.data = try response(completed: true, id: 3)
        let model = try runtime(grant, wire, journal)
        do { _ = try await model.recoverCompletion(); XCTFail() } catch {}
        XCTAssertEqual(journal.clears, 0); XCTAssertNotNil(journal.record)
    }
    func testLateRevocationDiscardsPositiveEvidence() async throws {
        let grant = try grant(), wire = Wire(), journal = Journal()
        wire.data = try response(completed: true); wire.onSend = { grant.revoke() }
        let model = try runtime(grant, wire, journal)
        do { _ = try await model.recoverCompletion(); XCTFail() } catch {}
        XCTAssertFalse(model.isCurrent); XCTAssertEqual(journal.clears, 0)
    }
    func testClosedContextDoesNotReadOrClear() async throws {
        let grant = try grant(), wire = Wire(), journal = Journal()
        let model = try runtime(grant, wire, journal, current: { false })
        do { _ = try await model.recoverCompletion(); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertEqual(journal.clears, 0)
    }
    func testNodeGrantCannotIssueVoucherOrReadOtherPOI() async throws {
        let grant = try grant(), wire = Wire()
        let boundary = CityPlayerValueNodeTransport(underlying: wire, approval: grant, verification: nil, current: { true })
        let issue = try RoamExperienceMutation.issueVoucher(poiID: 2).request(
            configuration: APIConfiguration(baseURL: base), token: grant.context.session.token)
        do { _ = try await boundary.send(issue); XCTFail() } catch {}
        var request = URLRequest(url: base.appendingPathComponent("api/city/nodes/3"))
        request.httpMethod = "GET"; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(grant.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await boundary.send(request); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExistingCoarseLockSurvivesNewRuntimeAndPreventsScan() async throws {
        let grant = try grant(), wire = Wire(), journal = Journal()
        wire.data = try response()
        let first = try runtime(grant, wire, journal)
        let node = try await first.detail()
        let poster = try first.poster(node: node)
        XCTAssertEqual(poster.phase, .unknown)
        await poster.scanned("synthetic-scan", purposeAccepted: true)
        XCTAssertEqual(poster.phase, .unknown)
        let reopened = try runtime(grant, wire, journal)
        XCTAssertEqual(try reopened.poster(node: node).phase, .unknown)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(journal.clears, 0)
    }
    private final class Wire: HTTPTransport {
        var data = Data(); var status = 200; var requests: [URLRequest] = []; var onSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); onSend?(); return (data, status)
        }
    }
    private final class Device: RoamDeviceLocationProviding {
        func currentFix() async throws -> RoamDeviceFix { throw APIError.notConfigured }
        func stop() {}
    }
    private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord? = .init(ownerKey: "roam-poster:node-fixture:https://example.test/native:7", targetKey: "poi:2")
        var clears = 0; var lastOwner: String?; var lastTarget: String?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            lastOwner = ownerKey; lastTarget = targetKey
            return record?.ownerKey == ownerKey && record?.targetKey == targetKey ? record : nil
        }
        func write(_ record: OperationPendingRecord) throws { self.record = record }
        func clear(_ record: OperationPendingRecord) throws {
            guard self.record == record else { throw APIError.invalidRequest }
            clears += 1; self.record = nil
        }
    }
}
