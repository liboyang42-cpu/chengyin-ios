import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class AssetLedgerTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let result: Result<String, Error>
    init(_ payload: String) { result = .success(payload) }
    init(failure: Error) { result = .failure(failure) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(try result.get().utf8), 200)
    }
}

/// Sanitized BK-ASSET (B03 CLAUDE_CONTRACT) fixture values; no real account or ledger.
@MainActor final class AssetPointsLedgerReadbackTests: XCTestCase {
    private func rows(_ json: String) throws -> [WalletLedgerRow] { try JSONDecoder().decode([WalletLedgerRow].self, from: Data(json.utf8)) }
    private func key(_ type: Int, _ id: Int) throws -> AssetPointsEventKey { try XCTUnwrap(AssetPointsEventKey(eventType: type, eventID: id)) }

    func testAwardAfterUnrelatedDeductionIsRecordedOnceAgainstCurrentBalance() throws {
        // Balance 100, another business deducts 30, then award 5: the ledger row is 70 → 75.
        let ledger = try rows(#"[{"id":11,"currentPoints":70,"changePoints":5,"afterPoints":75,"changeType":1,"eventType":1,"eventId":501}]"#)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 501), rows: ledger), .recordedOnce(ledger[0]))
    }
    func testTwoDistinctEventsAreEachRecordedOnce() throws {
        let ledger = try rows(#"[{"id":21,"currentPoints":100,"changePoints":5,"afterPoints":105,"changeType":1,"eventType":1,"eventId":601},{"id":22,"currentPoints":105,"changePoints":5,"afterPoints":110,"changeType":1,"eventType":1,"eventId":602}]"#)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 601), rows: ledger), .recordedOnce(ledger[0]))
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 602), rows: ledger), .recordedOnce(ledger[1]))
        XCTAssertEqual(ledger.last?.afterPoints?.value, 110)
    }
    func testSameEventTwiceIsDuplicatedNotNetted() throws {
        let ledger = try rows(#"[{"id":31,"currentPoints":100,"changePoints":5,"afterPoints":105,"changeType":1,"eventType":1,"eventId":701},{"id":32,"currentPoints":105,"changePoints":5,"afterPoints":110,"changeType":1,"eventType":1,"eventId":701}]"#)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 701), rows: ledger), .duplicated(ledger))
        // A page that repeats the same row id is not a second asset change.
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 701), rows: [ledger[0], ledger[0]]), .recordedOnce(ledger[0]))
    }
    func testNullBalanceIsUnknownNeverZero() throws {
        let ledger = try rows(#"[{"id":41,"currentPoints":null,"changePoints":5,"afterPoints":5,"changeType":1,"eventType":1,"eventId":801},{"id":42,"changePoints":5,"changeType":1,"eventType":1,"eventId":802}]"#)
        XCTAssertNil(ledger[0].currentPoints)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 801), rows: ledger), .balanceUnknown(ledger[0]))
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 802), rows: ledger), .balanceUnknown(ledger[1]))
    }
    func testDirectionArithmeticAndUnknownDirection() throws {
        let ledger = try rows(#"[{"id":51,"currentPoints":100,"changePoints":30,"afterPoints":70,"changeType":2,"eventType":4,"eventId":77},{"id":52,"currentPoints":100,"changePoints":30,"afterPoints":130,"changeType":2,"eventType":4,"eventId":78},{"id":53,"currentPoints":100,"changePoints":-30,"afterPoints":70,"eventType":4,"eventId":79},{"id":54,"currentPoints":100,"changePoints":30,"afterPoints":130,"changeType":9,"eventType":4,"eventId":80}]"#)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(4, 77), rows: ledger), .recordedOnce(ledger[0]))
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(4, 78), rows: ledger), .inconsistent(ledger[1]))
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(4, 79), rows: ledger), .recordedOnce(ledger[2]))
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(4, 80), rows: ledger), .inconsistent(ledger[3]))
    }
    func testMissingRowStaysNotObservedAndNullEventHasNoKey() throws {
        let ledger = try rows(#"[{"id":61,"currentPoints":100,"changePoints":5,"afterPoints":105,"changeType":1,"eventType":1}]"#)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(1, 901), rows: ledger), .notObserved)
        XCTAssertEqual(AssetPointsLedgerReadback.outcome(for: try key(2, 901), rows: []), .notObserved)
        XCTAssertNil(AssetPointsEventKey(eventType: 1, eventID: nil))
        XCTAssertNil(AssetPointsEventKey(eventType: 1, eventID: 0))
        XCTAssertNil(AssetPointsEventKey(eventType: nil, eventID: 5))
    }
    func testRegistrationPointsUseKeyFollowsSourceOwnerType() {
        XCTAssertEqual(AssetPointsEventKey.registrationPointsUse(ownerType: 1, registrationID: 77), AssetPointsEventKey(eventType: 3, eventID: 77))
        XCTAssertEqual(AssetPointsEventKey.registrationPointsUse(ownerType: 2, registrationID: 77), AssetPointsEventKey(eventType: 4, eventID: 77))
        XCTAssertNil(AssetPointsEventKey.registrationPointsUse(ownerType: nil, registrationID: 77))
        XCTAssertNil(AssetPointsEventKey.registrationPointsUse(ownerType: 3, registrationID: 77))
        XCTAssertNil(AssetPointsEventKey.registrationPointsUse(ownerType: 2, registrationID: 0))
    }
    func testReaderUsesOneExistingLedgerReadAndRethrowsFailure() async throws {
        let scope = WalletCommerceScope(namespace: "synthetic", accountID: 9, epoch: UUID())
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let ok = AssetLedgerTransport(#"{"code":200,"data":[{"id":71,"currentPoints":100,"changePoints":20,"afterPoints":80,"changeType":2,"eventType":4,"eventId":77}]}"#)
        let reader = WalletCommerceReader(service: WalletCommerceService(configuration: config, transport: ok), session: { (scope, "fake") })
        let outcome = try await reader.readBackPoints(try key(4, 77))
        guard case .recordedOnce(let row) = outcome else { return XCTFail("expected one ledger row") }
        XCTAssertEqual(row.id, 71)
        XCTAssertEqual(ok.requests.count, 1)
        XCTAssertEqual(ok.requests.first?.url?.path, "/api/points/list")

        let failing = AssetLedgerTransport(failure: URLError(.timedOut))
        let failingReader = WalletCommerceReader(service: WalletCommerceService(configuration: config, transport: failing), session: { (scope, "fake") })
        do { _ = try await failingReader.readBackPoints(try key(4, 77)); XCTFail("a failed read is never an observation") } catch { }
        XCTAssertEqual(failing.requests.count, 1)
    }
    func testCancellationPointsReturnRequiresAgreeingCounts() throws {
        func observation(_ json: String) throws -> OrderCancellationObservation {
            try JSONDecoder().decode(OrderCancellationObservation.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"NOT_NEEDED","pointsUsed":0,"pointsReturned":0}"#).pointsReturn, .notNeeded)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"NOT_NEEDED"}"#).pointsReturn, .notNeeded)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"NOT_NEEDED","pointsUsed":20}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"RETURNED","pointsUsed":20,"pointsReturned":20}"#).pointsReturn, .returned)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"RETURNED","pointsUsed":20,"pointsReturned":null}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"RETURNED","pointsUsed":20,"pointsReturned":10}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"PARTIAL","pointsUsed":20,"pointsReturned":10}"#).pointsReturn, .partial)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"PARTIAL","pointsUsed":20,"pointsReturned":20}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"UNCONFIRMED","pointsUsed":null,"pointsReturned":null}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{"pointsRefundStatus":"SOMETHING_NEW"}"#).pointsReturn, .unconfirmed)
        XCTAssertEqual(try observation(#"{}"#).pointsReturn, .unconfirmed)
    }
}
