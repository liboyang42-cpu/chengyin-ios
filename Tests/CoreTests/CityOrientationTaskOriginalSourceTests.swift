import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityOrientationTaskOriginalSourceTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func command(_ answer: String = "原答案") throws -> CityOrientationTaskCommand {
        try .init(sessionID: 10, nodeID: 20, requestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, expectedVersion: 3, answer: answer)
    }
    private func receipt(_ command: CityOrientationTaskCommand, applied: Bool = true) -> CityOrientationTaskReceipt {
        .init(contract: "CITY_ORIENTATION_ANSWER_V1", sessionId: command.sessionId, nodeId: command.nodeId,
              requestId: command.requestId, payloadHash: command.payloadHash, configVersion: 1, revision: applied ? 4 : 3,
              outcome: applied ? "APPLIED" : "FAILED",
              response: .object(["code": .int(applied ? 200 : 409), "data": .object(["nodeId": .int(command.nodeId)])]))
    }
    private func service(_ wire: Wire, receipt: Bool = false, answer: Bool = false) throws -> CityOrientationTaskService {
        .init(configuration: try .init(baseURL: base), transport: wire,
              receiptTransport: receipt ? wire : nil, answerTransport: answer ? wire : nil,
              receiptSessionID: receipt ? 10 : nil, answerSessionID: answer ? 10 : nil)
    }
    func testIndependentTransportsDefaultClosed() async throws {
        let wire = Wire(), command = try self.command(), closed = try self.service(wire)
        XCTAssertFalse(closed.receiptReadsEnabled); XCTAssertFalse(closed.writesEnabled)
        do { _ = try await closed.submit(command, token: "synthetic-token"); XCTFail() } catch {}
        do { _ = try await closed.original(command, token: "synthetic-token"); XCTFail() } catch {}
        let readOnly = try self.service(wire, receipt: true)
        XCTAssertTrue(readOnly.receiptReadsEnabled); XCTAssertFalse(readOnly.writesEnabled)
        do { _ = try await readOnly.submit(command, token: "synthetic-token"); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactCommandAndReceiptUseOriginalTwoRoutes() async throws {
        let wire = Wire(), command = try self.command(), value = receipt(try self.command())
        wire.data = try envelope(value)
        let service = try self.service(wire, receipt: true, answer: true)
        let submitted = try await service.submit(command, token: "synthetic-token")
        XCTAssertEqual(submitted, value)
        let original = try await service.original(command, token: "synthetic-token")
        XCTAssertEqual(original, value)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/play/city-orientation/answer", "/native/api/play/city-orientation/receipt"])
        XCTAssertEqual(try JSONDecoder().decode(CityOrientationTaskCommand.self, from: XCTUnwrap(wire.requests.first?.httpBody)), command)
        XCTAssertEqual(wire.requests.last?.httpMethod, "GET"); XCTAssertNil(wire.requests.last?.httpBody)
        let fields = URLComponents(url: wire.requests.last!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(Set(fields.map(\.name)), ["sessionId", "nodeId", "requestId"])
        XCTAssertTrue(wire.requests.allSatisfy { !$0.httpShouldHandleCookies })
    }
    func testPendingDoesNotChangeStoredOriginal() async throws {
        let box = Store(), journal = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        let owner = PlayRecoveryOwner(session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-token"))
        let command = try self.command(), pending = CityOrientationTaskPending(owner: owner, command: try self.command(), receipt: nil, settled: false)
        try journal.replace(pending, expected: nil, binding: "original-binding")
        let wire = Wire(); wire.data = Data("{\"code\":200,\"data\":{\"outcome\":\"PENDING\",\"sessionId\":10,\"nodeId\":20,\"requestId\":\"\(command.requestId)\"}}".utf8)
        let result = try await service(wire, receipt: true).original(command, token: "synthetic-token")
        XCTAssertNil(result); XCTAssertEqual(try journal.load("original-binding", owner: owner), pending)
        let reopened = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        XCTAssertEqual(try reopened.load("original-binding", owner: owner)?.command, command)
    }
    func testJournalRejectsWrongOwnerAndStaleReplacement() throws {
        let box = Store(), journal = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        let owner = PlayRecoveryOwner(session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-token"))
        let pending = CityOrientationTaskPending(owner: owner, command: try self.command(), receipt: nil, settled: false)
        try journal.replace(pending, expected: nil, binding: "binding")
        XCTAssertThrowsError(try journal.replace(pending, expected: nil, binding: "binding"))
        let other = PlayRecoveryOwner(session: try .init(accountID: 8, epoch: 2, namespace: "fixture", token: "other-token"))
        XCTAssertThrowsError(try journal.load("binding", owner: other))
        XCTAssertEqual(try journal.load("binding", owner: owner), pending)
    }
    func testOriginalBytesAndReceiptScopeCannotDrift() throws {
        let composed = try self.command("é"), decomposed = try self.command("e\u{301}")
        XCTAssertNotEqual(composed, decomposed); XCTAssertNotEqual(composed.payloadHash, decomposed.payloadHash)
        XCTAssertThrowsError(try receipt(composed).validate(decomposed))
        XCTAssertNoThrow(try receipt(composed, applied: false).validate(composed))
        XCTAssertThrowsError(try self.command(String(repeating: "😀", count: 151)))
    }
    func testMismatchedPendingAndGenericSuccessAreNotReceipts() async throws {
        let wire = Wire(), service = try self.service(wire, receipt: true)
        for raw in [#"{"code":200,"data":{"outcome":"PENDING","sessionId":11,"nodeId":20,"requestId":"x"}}"#, #"{"code":200,"data":{}}"#] {
            wire.data = Data(raw.utf8)
            do { _ = try await service.original(self.command(), token: "synthetic-token"); XCTFail() } catch {}
        }
    }
    func testAuthenticationEvidenceIsBoundedAndExact() {
        XCTAssertTrue(CityOrientationTaskService.isAuthenticationFailure((Data(), 401)))
        XCTAssertTrue(CityOrientationTaskService.isAuthenticationFailure((Data(#"{"code":401}"#.utf8), 200)))
        XCTAssertFalse(CityOrientationTaskService.isAuthenticationFailure((Data(#"{"code":401}"#.utf8), 503)))
        XCTAssertFalse(CityOrientationTaskService.isAuthenticationFailure((Data("not-json".utf8), 200)))
    }
    func testUnknownCannotBeReplacedEvenWithMatchingCAS() throws {
        let box = Store(), journal = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        let owner = PlayRecoveryOwner(session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-token"))
        let original = CityOrientationTaskPending(owner: owner, command: try command("é"), receipt: nil, settled: false)
        try journal.replace(original, expected: nil, binding: "binding")
        let before = box.values
        let changed = CityOrientationTaskPending(owner: owner, command: try command("e\u{301}"), receipt: nil, settled: false)
        XCTAssertThrowsError(try journal.replace(changed, expected: original, binding: "binding"))
        XCTAssertEqual(box.values, before)
    }
    func testInvalidReplacementNeverWrites() throws {
        let box = Store(), journal = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        let owner = PlayRecoveryOwner(session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-token"))
        let original = CityOrientationTaskPending(owner: owner, command: try command(), receipt: nil, settled: false)
        try journal.replace(original, expected: nil, binding: "binding")
        let before = box.values
        var changed = original; changed.settled = true
        XCTAssertThrowsError(try journal.replace(changed, expected: original, binding: "binding"))
        changed.settled = false; changed.receipt = receipt(try command("different"))
        XCTAssertThrowsError(try journal.replace(changed, expected: original, binding: "binding"))
        XCTAssertEqual(box.values, before)
    }
    func testTerminalEvidenceIsMonotonicAndSettledAllowsFreshPending() throws {
        let box = Store(), journal = CityOrientationTaskJournal(read: { box.values[$0] }, write: { box.values[$1] = $0 })
        let owner = PlayRecoveryOwner(session: try .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic-token"))
        let original = CityOrientationTaskPending(owner: owner, command: try command(), receipt: nil, settled: false)
        try journal.replace(original, expected: nil, binding: "binding")
        var known = original; known.receipt = receipt(original.command, applied: false)
        try journal.replace(known, expected: original, binding: "binding")
        XCTAssertThrowsError(try journal.replace(original, expected: known, binding: "binding"))
        var contradictory = known; contradictory.receipt = receipt(original.command)
        XCTAssertThrowsError(try journal.replace(contradictory, expected: known, binding: "binding"))
        var settled = known; settled.settled = true
        try journal.replace(settled, expected: known, binding: "binding")
        XCTAssertThrowsError(try journal.replace(known, expected: settled, binding: "binding"))
        let reusedID = CityOrientationTaskPending(owner: owner, command: try command("changed"), receipt: nil, settled: false)
        XCTAssertThrowsError(try journal.replace(reusedID, expected: settled, binding: "binding"))
        let next = CityOrientationTaskPending(owner: owner,
            command: try .init(sessionID: 10, nodeID: 20, expectedVersion: 3, answer: "next"), receipt: nil, settled: false)
        try journal.replace(next, expected: settled, binding: "binding")
        XCTAssertEqual(try journal.load("binding", owner: owner), next)
    }
    private func envelope(_ receipt: CityOrientationTaskReceipt) throws -> Data {
        let data = try JSONEncoder().encode(receipt)
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": JSONSerialization.jsonObject(with: data)])
    }
    private final class Store { var values: [String: Data] = [:] }
    private final class Wire: HTTPTransport {
        var data = Data(); var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
    }
}
