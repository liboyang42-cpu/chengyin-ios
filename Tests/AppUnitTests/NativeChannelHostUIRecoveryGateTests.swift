import XCTest
import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

/// Additional integration regressions; existing recovery tests stay byte-identical.
/// All data, HTTP responses and credentials below are synthetic in-memory fixtures.
@MainActor final class NativeChannelHostUIRecoveryGateTests: XCTestCase {
    func testExactIndependentGETUsesOriginalJournalWithoutHistoryOrPOSTGrant() async throws {
        let h = try HostUIRecoveryHarness(); try await h.seed()
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        XCTAssertFalse(owner.canSubmit); XCTAssertTrue(owner.canRecover)
        await owner.recover(); await owner.submit()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(h.wire.requests.last?.url?.path, "/report-recovery/" + h.path)
        XCTAssertEqual(owner.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertEqual(h.store.removes, 1)
    }
    func testObservedWithdrawalThenIdenticalRegrantCannotReviveOldOwner() async throws {
        let h = try HostUIRecoveryHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner), issued = h.configuration
        h.configuration = try h.makeConfiguration(routes: [:])
        XCTAssertFalse(directory.isCurrent)
        h.configuration = issued
        XCTAssertFalse(directory.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty)
        await owner.recover(); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
        let replacement = try XCTUnwrap(h.makeDirectory()); replacement.reload()
        XCTAssertTrue(replacement.isCurrent); XCTAssertEqual(replacement.visibleEntries.count, 1)
    }
    func testBackgroundRetirementKeepsJournalAndDoesNotReviveOnForeground() async throws {
        let h = try HostUIRecoveryHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        directory.retire(); h.viewerCurrent = false; h.viewerCurrent = true
        XCTAssertFalse(directory.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty)
        await owner.recover(); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
    }
    func testFinalForwardRejectsLateRevocationWithoutPublishingOrDeletingOriginal() async throws {
        let h = try HostUIRecoveryHarness(); try await h.seed(); let bytes = h.store.rows
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.wire.beforeGET = { h.configuration = try h.makeConfiguration(routes: [:]) }
        await owner.recover()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertFalse(owner.isCurrent); XCTAssertEqual(owner.state, .unknown)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.expired, 0)
    }
    func testMissingOrWrongExactGETNeverConsumesOriginalOrBorrowsReportWrite() async throws {
        let h = try HostUIRecoveryHarness(); try await h.seed(); let bytes = h.store.rows
        let absent: [[BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]] = [[:], [.imReport: [try .post("api/im/report")]]]
        for routes in absent {
            h.configuration = try h.makeConfiguration(routes: routes)
            XCTAssertNil(h.makeDirectory()); XCTAssertEqual(h.keyReads, 0)
        }
        h.configuration = try h.makeConfiguration(routes: [.imChannelReportReceipt: [try .init(method: "GET", path:
            "api/channel-platform/governance/reports/requests/22222222-2222-4222-8222-222222222222")]])
        let directory = try XCTUnwrap(h.makeDirectory()); directory.reload()
        let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        XCTAssertFalse(owner.canRecover); XCTAssertFalse(owner.canSubmit)
        await owner.recover(); await owner.submit()
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.store.rows, bytes)
    }
}

@MainActor private final class HostUIRecoveryStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0, removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class HostUIRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = [], receipt: [String: Any] = [:]
    var status = 200; var beforeGET: (() throws -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" {
            let bytes = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: String])
            receipt = ["state": "APPLIED", "request_id": body["submit_request_id"]!, "reporter_member_id": "17",
                       "target_type": "MESSAGE", "target_id": body["target_id"]!, "channel_id": "2",
                       "body_digest": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                       "report_id": "61", "audit_task_id": "71", "status": "PENDING"]
            throw URLError(.timedOut)
        }
        try beforeGET?()
        return (try JSONSerialization.data(withJSONObject: ["code": status, "data": receipt]), status)
    }
}
@MainActor private final class HostUIRecoveryHarness {
    let scope: RegionalSessionStorageScope
    let base = URL(string: "https://api.example.test/report-recovery")!
    let requestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let store = HostUIRecoveryStore(), wire = HostUIRecoveryWire()
    var context: RuntimeDependencyContext?, configuration: BusinessRuntimeConfiguration?
    var viewerCurrent = true, keyReads = 0, expired = 0
    var path: String { "api/channel-platform/governance/reports/requests/" + requestID.uuidString }
    init() throws {
        let baseText = "https://api.example.test/report-recovery"
        let regional = try RegionalConfiguration(market: .china, baseURL: baseText, approvedBaseURLs: [.china: [baseText]])
        scope = try RegionalSessionStorageScope(configuration: regional, bundleIdentifier: "example.report-recovery-tests", realm: "mock-only")
        context = try makeContext()
        configuration = try makeConfiguration(routes: [.imChannelReportReceipt: [try .init(method: "GET", path: path)]])
    }
    func makeContext(account: Int = 17, epoch: UInt64 = 3, token: String = "synthetic-token", namespace: String? = nil,
                     role: String = "player") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace ?? scope.service, token: token))
    }
    func makeConfiguration(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws -> BusinessRuntimeConfiguration {
        try .init(market: .china, baseURL: base, namespace: scope.service, accountID: 17, routes: routes)
    }
    func factory() -> BusinessRuntimeFactory? {
        BusinessRuntimeFactory(configuration: configuration, api: try! APIConfiguration(baseURL: base), transport: wire, current: { self.context })
    }
    func makeDirectory() -> NativeChannelReportRecoveryDirectory? {
        guard let issued = factory(), let gate = NativeChannelHostRuntimeTransport(context: issued.captured,
            issued: issued.configuration, features: [.imChannelReportReceipt], underlying: wire,
            runtime: { self.context }, configuration: { self.configuration }, presentation: { self.viewerCurrent }),
            let factory = BusinessRuntimeFactory(configuration: issued.configuration,
                api: try! APIConfiguration(baseURL: base), transport: gate,
                current: { gate.isCurrent ? self.context : nil }) else { return nil }
        return NativeChannelReportRecoveryAssembly.make(factory: factory, currentFactory: { self.factory() }, storage: store,
            journalKeys: { self.keyReads += 1; return Array(self.store.rows.keys) }, current: { gate.isCurrent && self.viewerCurrent },
            unauthorized: { self.expired += 1 })
    }
    func seed() async throws {
        let flow = try NativeChannelReportFlow(context: XCTUnwrap(context), conversationID: 2, transport: wire, storage: store,
            current: { true }, permitsWrite: { true }, permitsRead: { $0 == self.path }, unauthorized: {}, makeRequestID: { self.requestID })
        XCTAssertTrue(flow.prepare(messageID: 81)); flow.select(reason: .privacy, note: "PRIVATE original note")
        await flow.submit(); XCTAssertEqual(flow.state, .unknown)
    }
    func key(account: Int = 17, base: String? = nil) -> String {
        let values = [scope.service, base ?? self.base.absoluteString, String(account), "2"]
        return "native-channel-report.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
}
