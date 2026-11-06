import XCTest
@testable import QuestifyCore

@MainActor final class CoopSettlementReadJourneyTests: XCTestCase {
    private let host = #"{"topics":[{"topicId":7,"topicName":"Walk","settled":true,"myIncome":20,"myIncomeArrived":false,"totalSales":100,"verifiedSales":80,"platformAmount":5,"merchantTotal":40}]}"#
    private func reader() throws -> Reader { try .init(host) }
    func testReadRefreshTransientFailureAndRetry() async throws {
        let reader = try reader(), journey = CoopSettlementReadJourney()
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertEqual(journey.detail(reader: reader, source: .finance, id: 7)?.amount, 20)
        reader.failure = CoopFlowFailure.server(503, "Retry later")
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertEqual(journey.detail(reader: reader, source: .finance, id: 7)?.amount, 20)
        XCTAssertEqual(journey.issue(reader: reader, source: .finance, id: 7), .failed("Retry later"))
        reader.failure = nil
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertNil(journey.issue(reader: reader, source: .finance, id: 7)); XCTAssertEqual(reader.sources.count, 3)
    }
    func testPermissionMissingMalformedAndAmbiguousResponsesClearOldFinancialDetail() async throws {
        for failure in [CoopFlowFailure.permission, .unavailable, .malformed, .ambiguous, .server(403, "Denied")] {
            let reader = try reader(), journey = CoopSettlementReadJourney()
            await journey.load(reader: reader, source: .finance, id: 7)
            reader.failure = failure
            await journey.load(reader: reader, source: .finance, id: 7)
            XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 7))
            XCTAssertNotNil(journey.issue(reader: reader, source: .finance, id: 7))
        }
    }
    func testScopeReaderSourceAndRecordCannotReuseDetail() async throws {
        let reader = try reader(), other = try self.reader(), journey = CoopSettlementReadJourney()
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertNil(journey.detail(reader: other, source: .finance, id: 7))
        XCTAssertNil(journey.detail(reader: reader, source: .mybiz, id: 7))
        XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 8))
        reader.scope = UUID()
        XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 7))
        await journey.load(reader: reader, source: .finance, id: 7)
        reader.scope = nil
        XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 7))
    }
    func testInvalidParameterAndSignedOutNeverRead() async throws {
        let reader = try reader(), journey = CoopSettlementReadJourney()
        await journey.load(reader: reader, source: .finance, id: 0)
        reader.scope = nil
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertTrue(reader.sources.isEmpty); XCTAssertFalse(journey.isLoading)
    }
    func testDismissalDuringReadCannotRepopulateState() async throws {
        let reader = try reader(), journey = CoopSettlementReadJourney()
        reader.beforeReturn = { journey.invalidate() }
        await journey.load(reader: reader, source: .finance, id: 7)
        XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 7))
        XCTAssertNil(journey.issue(reader: reader, source: .finance, id: 7)); XCTAssertFalse(journey.isLoading)
    }
    func testCancelledRefreshClearsDetailWithoutPublishingFailure() async throws {
        let reader = try reader(), journey = CoopSettlementReadJourney()
        await journey.load(reader: reader, source: .finance, id: 7)
        reader.beforeReturn = { withUnsafeCurrentTask { $0?.cancel() } }
        await Task { await journey.load(reader: reader, source: .finance, id: 7) }.value
        XCTAssertNil(journey.detail(reader: reader, source: .finance, id: 7))
        XCTAssertNil(journey.issue(reader: reader, source: .finance, id: 7)); XCTAssertFalse(journey.isLoading)
    }
    func testRepeatedIdentityRejectsWholeHostAndMerchantPayloads() async throws {
        let rows = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(host.utf8))["topics"].rows!
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .finance, data: .object(["topics": .array(rows + rows)]), id: 7)) {
            XCTAssertEqual($0 as? CoopFlowFailure, .ambiguous)
        }
        let raw = #"{"id":31,"verifiedSales":120,"verifiedHeads":6,"amount":30,"status":1,"shareMode":0}"#
        let row = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(raw.utf8))
        XCTAssertThrowsError(try CoopSettlementDetailModel.resolve(source: .mybiz, data: .object(["settlements": .array([row, row])]), id: 31)) {
            XCTAssertEqual($0 as? CoopFlowFailure, .ambiguous)
        }
    }
    func testUnknownIncomeRemainsUnavailableWithoutZeroFallback() async throws {
        let reader = try reader(), journey = CoopSettlementReadJourney()
        reader.payload = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(host.replacingOccurrences(of: "\"settled\":true,\"myIncome\":20", with: "\"settled\":false,\"myIncome\":null").utf8))
        await journey.load(reader: reader, source: .finance, id: 7)
        let detail = journey.detail(reader: reader, source: .finance, id: 7)
        XCTAssertEqual(detail?.status, .unsettled); XCTAssertNil(detail?.amount)
        XCTAssertEqual(detail?.lines.last?.value, .unavailable)
    }
    private final class Reader: CoopSettlementJourneyReading {
        var scope: UUID? = UUID()
        var payload: CoopFlowJSON
        var failure: Error?
        var beforeReturn: (() -> Void)?
        var sources: [CoopFlowSettlement.Source] = []
        init(_ json: String) throws { payload = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(json.utf8)) }
        func data(source: CoopFlowSettlement.Source) async throws -> CoopFlowJSON {
            sources.append(source); beforeReturn?()
            if let failure { throw failure }; return payload
        }
    }
}
