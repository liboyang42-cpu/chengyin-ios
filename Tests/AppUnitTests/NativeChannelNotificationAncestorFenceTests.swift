import XCTest
import Foundation
import SwiftUI
@testable import Questify

@MainActor private final class AncestorNotificationBindingStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows.removeValue(forKey: key) }
}
@MainActor private final class AncestorNotificationBindingSource: NativeChannelNotificationAuthorizing {
    var currentContext: RuntimeDependencyContext?; var authorizationVersion: UUID? = UUID()
    var revision = UUID()
    var operations: Set<NativeChannelNotificationOperation> = [.directory, .preference, .save, .mute, .receipt, .unread]
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(currentContext, context), self.authorizationVersion == authorizationVersion else { return }
        self.authorizationVersion = nil
    }
    func authorizationRevision(for operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> UUID? {
        operations.contains(operation) && authorizationVersion != nil ? revision : nil
    }
}
@MainActor private final class AncestorNotificationBindingWire: HTTPTransport {
    var requests: [URLRequest] = []; var journal: NativeChannelNotificationJournal?
    var status = 200
    var beforeResponse: (() -> Void)?
    var redactAck = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?()
        if status != 200 { return (try JSONSerialization.data(withJSONObject: ["code": status]), status) }
        let original = try XCTUnwrap(try journal?.restore())
        if request.httpMethod == "POST" {
            XCTAssertEqual(request.url?.path, "/api/im/read")
            XCTAssertEqual(original.operation, .ack)
            XCTAssertEqual(request.httpBody, original.body)
            var body: [String: Any] = ["request_id": original.requestID, "status": "APPLIED", "operation": "ACK",
                "scope_type": original.scope.type, "scope_id": original.scope.value,
                "result_redacted": redactAck, "must_refresh_state": true]
            if !redactAck { body["result"] = ["version": 2] }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
        }
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/im/notification-requests/" + original.requestID)
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "request_id": original.requestID, "status": "APPLIED", "operation": original.operation.rawValue,
            "scope_type": original.scope.type, "scope_id": original.scope.value,
            "result_redacted": true, "must_refresh_state": true]]), 200)
    }
}
@MainActor private final class AncestorNotificationBindingHarness {
    let context: RuntimeDependencyContext
    let storage = AncestorNotificationBindingStorage(); var source = AncestorNotificationBindingSource(); let wire = AncestorNotificationBindingWire()
    let seedJournal: NativeChannelNotificationJournal
    var currentVisit: () -> Bool
    init(currentVisit: @escaping () -> Bool) throws {
        self.currentVisit = currentVisit
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:binding", token: "fixture-token"))
        source.currentContext = context
        seedJournal = .init(storage: NativeChannelNotificationProtectedStorage(existing: storage), owner: .init(context: context))
    }
    func seed() throws -> NativeChannelNotificationCommand {
        let original = try NativeChannelNotificationCommand(scope: .init(type: 1, value: "9012"), minutes: 480,
                                                            requestID: "original-binding-0001")
        try seedJournal.persist(original); return original
    }
    func make(scope: NativeChannelNotificationScope?) throws -> NativeChannelNotificationCoordinator {
        try NativeChannelAncestorNotificationBinding.make(context: context, storage: storage, scope: scope, makeDispatcher: { journal in
            self.wire.journal = journal
            return try .init(context: self.context, viewerRevision: 2, source: self.source, journal: journal,
                             underlying: self.wire, current: { self.currentVisit() ? self.context : nil }, viewer: { 2 }, selected: { self.source })
        })
    }
}


@MainActor final class NativeChannelNotificationAncestorFenceTests: XCTestCase {
    func testAncestorExitBlocksAckWithoutWaitingForNotificationDeactivate() async throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let visit = root.binding
        let h = try AncestorNotificationBindingHarness(currentVisit: { visit.wrappedValue })
        h.source.operations = [.ack]
        let flow = try h.make(scope: .init(type: 1, value: "9012")); await flow.activate()
        XCTAssertTrue(flow.canAck); XCTAssertTrue(h.wire.requests.isEmpty)
        root.isPresented = false
        await flow.acknowledge(lastMessageID: 4)
        XCTAssertFalse(flow.canAck); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testRevocationBlocksAckWithParentStillInNavigation() async throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let visit = root.binding
        let h = try AncestorNotificationBindingHarness(currentVisit: { visit.wrappedValue })
        h.source.operations = [.ack]
        let flow = try h.make(scope: .init(type: 1, value: "9012")); await flow.activate()
        h.source.operations = []
        await flow.acknowledge(lastMessageID: 4)
        XCTAssertFalse(flow.canAck); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testOldReceiptOr401CannotSettleJournalOrRetireReplacementOwner() async throws {
        for status in [200, 401] {
            let root = NativeChannelManagementRouteState(); root.isPresented = true
            let visit = root.binding
            let h = try AncestorNotificationBindingHarness(currentVisit: { visit.wrappedValue })
            let original = try h.seed(); h.source.operations = [.receipt]
            let bytes = h.storage.rows, oldSource = h.source
            let old = try h.make(scope: nil)
            var fresh: NativeChannelNotificationCoordinator?
            h.wire.status = status
            h.wire.beforeResponse = {
                root.isPresented = false; root.isPresented = true
                let nextVisit = root.binding
                h.currentVisit = { nextVisit.wrappedValue }
                let next = AncestorNotificationBindingSource(); next.currentContext = h.context; next.operations = [.receipt]
                h.source = next
                fresh = try? h.make(scope: nil)
            }
            await old.activate()
            XCTAssertEqual(h.storage.rows, bytes); XCTAssertNotNil(h.source.authorizationVersion)
            XCTAssertFalse(h.source === oldSource); XCTAssertEqual(h.wire.requests.count, 1)
            h.wire.beforeResponse = nil; h.wire.status = 200
            await fresh?.activate()
            XCTAssertEqual(fresh?.state, .appliedRedacted); XCTAssertNil(try h.seedJournal.restore())
            XCTAssertEqual(h.wire.requests.count, 2)
            XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.path.hasSuffix(original.requestID) == true })
        }
    }
    func testReceiptApprovalIsNotInferredFromAnAckGrant() throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let visit = root.binding
        let h = try AncestorNotificationBindingHarness(currentVisit: { visit.wrappedValue })
        _ = try h.seed(); let bytes = h.storage.rows; h.source.operations = [.ack]
        XCTAssertThrowsError(try h.make(scope: nil)); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
}
