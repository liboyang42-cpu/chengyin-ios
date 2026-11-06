import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityParticipationCommandRecoveryTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 202
        var body = #"{"code":202,"errorCode":"OUTCOME_UNKNOWN","data":{"requestId":"original-1","requestStatus":"UNKNOWN"}}"#
        var lost = false
        var inspect: ((URLRequest) throws -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); try inspect?(request)
            if lost { throw URLError(.timedOut) }
            return (Data(body.utf8), status)
        }
    }
    @MainActor private final class Harness {
        let api: APIConfiguration
        let original: CityParticipationCommandScope
        let directory: URL
        let journal: CityParticipationCommandJournal
        let wire = Wire()
        var current: CityParticipationCommandScope?
        var approved: CityParticipationCommandGrant?
        var readApproved: CityOriginalReceiptReadGrant?
        init() throws {
            api = try .init(baseURL: URL(string: "https://city.example.test/native/")!)
            original = try .init(market: .china, baseURL: api.baseURL, namespace: "participation-test", accountID: 7, epoch: 1, token: "fake-token")
            current = original
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            journal = try .init(directory: directory)
        }
        func model(read: Bool = true) -> CityParticipationCommandRecovery {
            let reader = CityOriginalReceiptReader(configuration: api, transport: wire,
                currentSession: { self.current?.session }, grant: { self.readApproved })
            return .init(configuration: api, transport: wire, journal: journal, currentScope: { self.current },
                grant: { self.approved }, receiptReader: read ? reader : nil)
        }
        func approve(_ command: CityParticipationCommand) throws {
            approved = try .init(scope: original, command: command)
            readApproved = .init(reference: try .init(session: original.session, domain: .participation, requestID: command.requestId))
        }
    }
    private func command(_ kind: CityParticipationCommand.Kind = .create, id: String = "original-1") throws -> CityParticipationCommand {
        try .init(kind: kind, requestID: id, regionID: "region", releaseID: 1, contentHash: String(repeating: "a", count: 64),
                  expectedVersion: kind == .create ? 0 : 1,
                  teamID: kind == .create ? nil : "00000000-0000-0000-0000-000000000001",
                  inviteCode: kind == .join ? "00000000-0000-0000-0000-000000000002" : nil)
    }
    func testExactSixKindFieldsDoNotTranslateLegacyIntent() throws {
        for kind in [CityParticipationCommand.Kind.create, .join, .lock, .confirm, .exit, .resume] {
            let c = try command(kind), bytes = try c.wireBytes()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var keys: Set<String> = ["kind", "requestId", "regionId", "releaseId", "contentHash", "expectedVersion"]
            if kind != .create { keys.insert("teamId") }; if kind == .join { keys.insert("inviteCode") }
            XCTAssertEqual(Set(json.keys), keys); XCTAssertEqual(json["kind"] as? String, kind.rawValue)
        }
    }
    func testDefaultGrantNeverSavesOrSends() async throws {
        let h = try Harness(), model = h.model(); model.open(); await model.submit(try command())
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(try h.journal.load(h.original)); XCTAssertEqual(model.display, .unavailable)
    }
    func testExactBytesAreDurableBeforePostAndLostReplyNeverReposts() async throws {
        let h = try Harness(), c = try command(); try h.approve(c); h.wire.lost = true
        h.wire.inspect = { request in
            let saved = try XCTUnwrap(h.journal.load(h.original))
            XCTAssertEqual(request.httpBody, saved.bytes); XCTAssertEqual(saved.bytes, try c.wireBytes()); XCTAssertNil(saved.terminalStatus)
        }
        let model = h.model(); model.open(); await model.submit(c); await model.submit(c)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests.first?.httpMethod, "POST")
        XCTAssertNil(try h.journal.load(h.original)?.terminalStatus)
        let restarted = h.model(); restarted.open(); XCTAssertEqual(restarted.display, .unknown)
    }
    func testRestartRechecksOnlyOriginalGetAnd404PreservesLock() async throws {
        let h = try Harness(), c = try command(); try h.approve(c)
        let initial = h.model(); initial.open(); await initial.submit(c)
        h.wire.status = 404; h.wire.body = #"{"code":404,"msg":"NOT_FOUND"}"#
        let restarted = h.model(); restarted.open(); await restarted.recheck()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertTrue(try XCTUnwrap(h.wire.requests.last?.url).path.hasSuffix("/team-participation/request/original-1"))
        XCTAssertEqual(restarted.display, .unknown); XCTAssertNil(try h.journal.load(h.original)?.terminalStatus)
    }
    func testLateAccountChangeCannotExposeOrCompleteOriginalRecord() async throws {
        let h = try Harness(), c = try command(); try h.approve(c)
        h.wire.status = 200; h.wire.body = #"{"code":200,"data":{"requestId":"original-1","requestStatus":"COMPLETE","kind":"CREATE"}}"#
        h.wire.inspect = { _ in h.current = nil }
        let model = h.model(); model.open(); await model.submit(c)
        XCTAssertEqual(model.display, .hidden); XCTAssertNil(try h.journal.load(h.original)?.terminalStatus)
        let other = try CityParticipationCommandScope(market: .china, baseURL: h.api.baseURL, namespace: "participation-test", accountID: 8, epoch: 1, token: "other-token")
        XCTAssertNil(try h.journal.load(other))
    }
    func testVerifiedCompleteIsArchivedBeforeNextDistinctCommandAndNeverReused() throws {
        let h = try Harness(), first = try command(), next = try command(.confirm, id: "original-2")
        let record = try h.journal.begin(first.wireBytes(), scope: h.original)
        XCTAssertThrowsError(try h.journal.begin(next.wireBytes(), scope: h.original))
        try h.journal.complete(record, status: 409, scope: h.original)
        _ = try h.journal.begin(next.wireBytes(), scope: h.original)
        XCTAssertThrowsError(try h.journal.begin(first.wireBytes(), scope: h.original))
        XCTAssertEqual(try h.journal.load(h.original)?.command.requestId, "original-2")
    }
    func testRevokedGrantAndWrongReplyCannotSetComplete() async throws {
        let h = try Harness(), c = try command(); try h.approve(c)
        h.wire.status = 200; h.wire.body = #"{"code":200,"data":{"requestId":"other","requestStatus":"COMPLETE","kind":"CREATE"}}"#
        let model = h.model(); model.open(); await model.submit(c)
        XCTAssertEqual(model.display, .unknown); XCTAssertNil(try h.journal.load(h.original)?.terminalStatus)
        h.readApproved?.revoke(); await model.recheck(); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertNil(try h.journal.load(h.original)?.terminalStatus)
    }
    func testJournalReconstructionBindsDeploymentAndDoesNotPersistCredential() throws {
        let h = try Harness(), c = try command()
        _ = try h.journal.begin(c.wireBytes(), scope: h.original)
        let reopened = try CityParticipationCommandJournal(directory: h.directory)
        XCTAssertEqual(try reopened.load(h.original)?.bytes, try c.wireBytes())
        let changedBackend = try CityParticipationCommandScope(market: .china, baseURL: URL(string: "https://other.example.test/native/")!, namespace: "participation-test", accountID: 7, epoch: 1, token: "fake-token")
        XCTAssertNil(try reopened.load(changedBackend))
        let changedMarket = try CityParticipationCommandScope(market: .unitedStates, baseURL: h.api.baseURL, namespace: "participation-test", accountID: 7, epoch: 1, token: "fake-token")
        XCTAssertNil(try reopened.load(changedMarket))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: h.directory, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("fake-token"))
        }
    }
    func testInvalidOriginalIdentifiersAndUnexpectedInviteAreRejected() throws {
        XCTAssertThrowsError(try CityParticipationCommand(kind: .create, requestID: "original\n", regionID: "region", releaseID: 1, contentHash: String(repeating: "a", count: 64), expectedVersion: 0))
        XCTAssertThrowsError(try CityParticipationCommand(kind: .create, requestID: "original", regionID: "region", releaseID: 1, contentHash: String(repeating: "a", count: 64) + "\n", expectedVersion: 0))
        XCTAssertThrowsError(try CityParticipationCommand(kind: .create, requestID: "original", regionID: "region", releaseID: 1, contentHash: String(repeating: "a", count: 64), expectedVersion: 0, inviteCode: "00000000-0000-0000-0000-000000000002"))
    }

    func testCompletePostKeepsOriginalEvidenceAndAllowsOnlyNewExplicitGrant() async throws {
        let h = try Harness(), first = try command(); try h.approve(first)
        h.wire.status = 200; h.wire.body = #"{"code":200,"data":{"requestId":"original-1","requestStatus":"COMPLETE","kind":"CREATE"}}"#
        let model = h.model(); model.open(); await model.submit(first)
        XCTAssertEqual(model.display, .complete(200)); XCTAssertEqual(try h.journal.load(h.original)?.terminalStatus, 200)
        await model.submit(first); XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(model.display, .complete(200))
        let next = try command(.join, id: "original-2")
        await model.submit(next); XCTAssertEqual(h.wire.requests.count, 1)
        try h.approve(next)
        h.wire.status = 202; h.wire.body = #"{"code":202,"errorCode":"OUTCOME_UNKNOWN","data":{"requestId":"original-2","requestStatus":"UNKNOWN"}}"#
        await model.submit(next); XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(try h.journal.load(h.original)?.command.requestId, "original-2")
    }

    func testUSImplementationGateCannotBeBypassedByConstructingGrant() async throws {
        let h = try Harness(), c = try command()
        let us = try CityParticipationCommandScope(market: .unitedStates, baseURL: h.api.baseURL, namespace: "participation-test", accountID: 7, epoch: 1, token: "fake-token")
        h.current = us; h.approved = try .init(scope: us, command: c)
        let model = h.model(); model.open(); await model.submit(c)
        XCTAssertEqual(model.display, .unavailable); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(try h.journal.load(us))
    }

}
