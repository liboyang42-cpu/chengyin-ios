import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Offline regression sources. All network work uses this in-memory dispatch fake.
@MainActor final class ClubWelcomeNoteOriginalRecoveryTests: XCTestCase {
    private final class Pending: OperationPendingJournal {
        var values: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            values.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey }
        }
        func write(_ record: OperationPendingRecord) throws { values.removeAll { $0.operationID == record.operationID }; values.append(record) }
        func clear(_ record: OperationPendingRecord) throws { values.removeAll { $0.operationID == record.operationID } }
    }
    private final class Dispatch: ClubWelcomeNoteDispatching {
        var isConfigured = true
        var requests: [URLRequest] = []
        var beforeForward: (() -> Void)?
        var afterForward: (() -> Void)?
        var response: (URLRequest) throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
        func send(_ request: URLRequest, authorization: ClubWelcomeNoteDispatchAuthorization) async throws -> (Data, Int) {
            beforeForward?()
            try authorization.forward(request) { requests.append(request) }
            afterForward?()
            return try response(request)
        }
    }
    private final class Access: ClubOperationsAccess {
        var identity: ClubReadIdentity? = .init(accountID: 7, epoch: 1)
        var welcomeNote: ClubWelcomeNoteService?
        var isConfigured: Bool { true }
        var writeAvailability: ClubOperationsWriteAvailability { .approved }
        var owner = true, failRead = false, reads = 0, writes = 0
        var note: String? = "before"
        func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
            reads += 1
            if failRead { throw APIError.unauthorized }
            var fields: [String: Any] = ["id": 9, "name": "Synthetic club", "isOwner": owner]
            if let note { fields["welcomeNote"] = note }
            let profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: JSONSerialization.data(withJSONObject: fields))
            return .init(target: target, profile: profile)
        }
        func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
            writes += 1; throw APIError.invalidRequest
        }
    }
    private final class Fixture {
        let base = URL(string: "https://example.test/native")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("welcome-test-" + UUID().uuidString)
        let pending = Pending(), write = Dispatch(), read = Dispatch(), access = Access()
        var session: ClubOperationsSession?
        var revision: UInt64 = 1
        var writeGrant: OperationEndpointApproval?, readGrant: OperationEndpointApproval?
        let original: ClubWelcomeNoteOriginalJournal
        lazy var service: ClubWelcomeNoteService = makeService()
        init() throws {
            session = try .init(accountID: 7, epoch: 1, token: "synthetic-token", storageNamespace: "synthetic-scope")
            original = ClubWelcomeNoteOriginalJournal(directory: directory)
            writeGrant = try .init(baseURL: base, namespace: "synthetic-scope", accountID: 7, paths: [ClubWelcomeNoteService.path])
            readGrant = try .init(baseURL: base, namespace: "synthetic-scope", accountID: 7, paths: [ClubWelcomeNoteService.receiptPath])
            access.welcomeNote = service
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
        func makeService() -> ClubWelcomeNoteService {
            ClubWelcomeNoteService(configuration: try! .init(baseURL: base), runtime: .init(
                transport: write, journal: pending, approval: { [weak self] in self?.writeGrant }, originalJournal: original,
                receiptTransport: read, receiptApproval: { [weak self] in self?.readGrant }),
                currentSession: { [weak self] in self?.session }, revision: { [weak self] in self?.revision ?? 0 })
        }
        func save(_ text: String = "original text") async throws -> String {
            try await service.save(clubID: 9, note: text, previous: access.note, identity: access.identity!, access: access, ownerCurrent: { true })
        }
        func recover(_ using: ClubWelcomeNoteService? = nil) async throws -> [ClubWelcomeNoteOriginalHistory] {
            try await (using ?? service).recoverOriginal(clubID: 9, identity: access.identity!, viewCurrent: { true })
        }
        func receipt(_ request: URLRequest, state: String = "APPLIED", note: String = "original text",
                     actor: Int = 7, audit: Int = 71, extras: [String: Any] = [:]) throws -> (Data, Int) {
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let requestID = request.value(forHTTPHeaderField: "X-Club-Welcome-Request-Id") ?? (fields["requestId"] as? String)
            let source = request.value(forHTTPHeaderField: "X-Club-Welcome-Source-SHA256") ?? (fields["sourceSHA256"] as? String)
            var data: [String: Any] = ["protocolVersion": 1, "actorMemberId": actor, "clubId": 9,
                "requestId": try XCTUnwrap(requestID), "sourceSHA256": try XCTUnwrap(source), "state": state]
            if state == "APPLIED" { data["welcomeNote"] = note; data["auditId"] = audit; data["recordedAt"] = 1000 }
            if state == "REJECTED" { data["message"] = "Original moderation refused"; data["auditId"] = audit; data["recordedAt"] = 1000 }
            data.merge(extras) { _, new in new }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    func testWriteApprovalAloneCannotSendOriginalRequest() async throws {
        let f = try Fixture(); defer { f.cleanup() }; f.readGrant = nil
        do { _ = try await f.save(); XCTFail("Independent receipt authority is required") } catch {}
        XCTAssertTrue(f.write.requests.isEmpty); XCTAssertTrue(f.read.requests.isEmpty)
        XCTAssertFalse(f.service.available(identity: f.access.identity!))
    }
    func testUnknownColdLaunchRecoversHistoricalTextAfterOwnerLossWithoutSnapshotOrReplay() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        do { _ = try await f.save(); XCTFail() } catch {}
        XCTAssertEqual(f.write.requests.count, 1)
        XCTAssertTrue(f.service.pending(clubID: 9, identity: f.access.identity!))
        f.access.owner = false; f.access.failRead = true; f.access.note = "later owner's text"; f.writeGrant = nil
        f.read.response = { try f.receipt($0) }
        let readsBefore = f.access.reads
        let restarted = f.makeService()
        let rows = try await f.recover(restarted)
        XCTAssertEqual(rows.first?.receipt?.welcomeNote, "original text")
        XCTAssertEqual(rows.first?.receipt?.state, "APPLIED")
        XCTAssertEqual(f.access.reads, readsBefore); XCTAssertEqual(f.access.writes, 0)
        XCTAssertEqual(f.write.requests.count, 1); XCTAssertEqual(f.read.requests.count, 1)
        XCTAssertFalse(restarted.pending(clubID: 9, identity: f.access.identity!))
    }
    func testNoCurrentTextOrGenericSuccessCanUnlockUnknownRequest() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.write.response = { _ in (Data(#"{"code":200,"data":{"welcomeNote":"original text"}}"#.utf8), 200) }
        do { _ = try await f.save(); XCTFail() } catch {}
        f.access.note = "original text"
        let flow = ClubWelcomeNoteFlow(clubID: 9, identity: f.access.identity!, access: f.access)
        await flow.load()
        XCTAssertEqual(flow.state, .unknown); XCTAssertFalse(flow.canSave)
        await flow.save(); XCTAssertEqual(f.write.requests.count, 1)
        XCTAssertTrue(f.service.pending(clubID: 9, identity: f.access.identity!))
    }
    func testExactReceiptClearAndMetadataOnlyJournal() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.write.response = { try f.receipt($0, note: "") }
        let result = try await f.save(" \n ")
        XCTAssertEqual(result, "")
        let request = try XCTUnwrap(f.write.requests.first)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Club-Welcome-Request-Id"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Club-Welcome-Source-SHA256")?.count, 64)
        let files = try FileManager.default.contentsOfDirectory(at: f.directory, includingPropertiesForKeys: nil)
        let bytes = try Data(contentsOf: XCTUnwrap(files.first))
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
        XCTAssertEqual(metadata.first?["state"] as? String, "APPLIED")
        XCTAssertNil(metadata.first?["welcomeNote"]); XCTAssertNil(metadata.first?["token"])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("synthetic-token"))
    }
    func testForeignActorSourceExtraFieldsAndChangedTerminalAuditStayLocked() async throws {
        for variant in 0..<4 {
            let f = try Fixture(); defer { f.cleanup() }
            f.write.response = { request in
                if variant == 0 { return try f.receipt(request, actor: 8) }
                if variant == 1 { return try f.receipt(request, note: "different") }
                if variant == 2 { return try f.receipt(request, extras: ["currentWelcomeNote": "original text"]) }
                return try f.receipt(request)
            }
            if variant == 3 {
                _ = try await f.save()
                f.read.response = { try f.receipt($0, audit: 72) }
                do { _ = try await f.recover(); XCTFail("Terminal audit must not change") } catch {}
            } else {
                do { _ = try await f.save(); XCTFail() } catch {}
                XCTAssertTrue(f.service.pending(clubID: 9, identity: f.access.identity!))
            }
            XCTAssertEqual(f.write.requests.count, 1)
        }
    }
    func testExplicitRejectedReceiptSettlesButGenericBusinessErrorDoesNot() async throws {
        for explicit in [true, false] {
            let f = try Fixture(); defer { f.cleanup() }
            f.write.response = { request in
                if explicit { return try f.receipt(request, state: "REJECTED") }
                return (Data(#"{"code":500,"msg":"ambiguous"}"#.utf8), 200)
            }
            do { _ = try await f.save(); XCTFail() } catch {}
            XCTAssertEqual(f.service.pending(clubID: 9, identity: f.access.identity!), !explicit)
            XCTAssertEqual(f.write.requests.count, 1)
        }
    }
    func testPreForwardRetirementIsNotSentAndPostForwardRevisionChangeStaysUnknown() async throws {
        for before in [true, false] {
            let f = try Fixture(); defer { f.cleanup() }
            if before { f.write.beforeForward = { f.revision += 1 } }
            else { f.write.afterForward = { f.revision += 1 }; f.write.response = { try f.receipt($0) } }
            do { _ = try await f.save(); XCTFail() } catch {}
            XCTAssertEqual(f.write.requests.count, before ? 0 : 1)
            XCTAssertEqual(f.service.pending(clubID: 9, identity: f.access.identity!), !before)
        }
    }
    func testReceiptOnlyRecoveryCannotBeBorrowedForWriteAndReadRevocationDropsReply() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        do { _ = try await f.save(); XCTFail() } catch {}
        f.writeGrant = nil
        XCTAssertTrue(f.service.canRecover(identity: f.access.identity!))
        XCTAssertFalse(f.service.available(identity: f.access.identity!))
        f.read.afterForward = { f.readGrant = nil }; f.read.response = { try f.receipt($0) }
        do { _ = try await f.recover(); XCTFail() } catch {}
        XCTAssertTrue(f.service.pending(clubID: 9, identity: f.access.identity!))
        XCTAssertEqual(f.write.requests.count, 1); XCTAssertEqual(f.read.requests.count, 1)
    }
}
