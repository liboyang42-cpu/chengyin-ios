import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantPerkValiditySubmissionTests: XCTestCase {
    private let beforeMidnight = ISO8601DateFormatter().date(from: "2026-10-12T15:59:59Z")!
    private let midnight = ISO8601DateFormatter().date(from: "2026-10-12T16:00:00Z")!
    private func template(_ value: String?) throws -> CoopFlowPerkTemplate {
        try .init(name: "Synthetic perk", type: 0, retailValue: 10, unitCost: nil, quota: 3, validEnd: value)
    }
    func testPastAndTodayCannotGenerateCreateRequest() throws {
        for day in ["2000-01-01", "2026-10-11", "2026-10-12"] {
            let historical = try template(day)
            XCTAssertEqual(historical.validEnd, day) // Reading/representing old values remains legal.
            XCTAssertThrowsError(try CoopFlowMutation.createTemplate(historical).body(now: beforeMidnight)) {
                XCTAssertEqual($0 as? CoopFlowFailure, .invalid("validEnd"))
            }
        }
    }
    func testTomorrowAndFutureProduceExactExistingPayload() throws {
        for day in ["2026-10-13", "2028-02-29"] {
            let body = try CoopFlowMutation.createTemplate(template(day)).body(now: beforeMidnight)
            XCTAssertEqual(body["validEnd"], .string(day)); XCTAssertEqual(body["name"], .string("Synthetic perk"))
            XCTAssertEqual(body["quota"], .id(3)); XCTAssertEqual(body["id"], .null)
        }
    }
    func testNoExpiryStillSerializesNull() throws {
        let body = try CoopFlowMutation.createTemplate(template(nil)).body(now: beforeMidnight)
        XCTAssertEqual(body["validEnd"], .null)
    }
    func testChinaMidnightInvalidatesPreviouslyValidFrozenDraft() throws {
        let op = CoopFlowMutation.createTemplate(try template("2026-10-13"))
        XCTAssertNoThrow(try op.body(now: beforeMidnight))
        XCTAssertThrowsError(try op.body(now: midnight))
        XCTAssertNoThrow(try CoopFlowMutation.createTemplate(template("2026-10-14")).body(now: midnight))
    }
    func testTomorrowBoundaryIsChinaMidnight() {
        let parsed = MerchantPerkValidityDraft.parse("2026-10-13")
        XCTAssertEqual(parsed, midnight)
        XCTAssertEqual(MerchantPerkValidityDraft.minimum(now: beforeMidnight), midnight)
    }
    func testExplicitCalendarChangeToExpiredValueFailsButUntouchedHistoricalValueSurvives() throws {
        var draft = MerchantPerkValidityDraft(value: "2000-01-01", now: beforeMidnight)
        XCTAssertEqual(try draft.value(now: beforeMidnight), "2000-01-01")
        draft.choose(try XCTUnwrap(MerchantPerkValidityDraft.parse("2026-10-12")))
        XCTAssertThrowsError(try draft.value(now: beforeMidnight))
    }
    func testUnchangedUnknownLegacyTextIsNotNormalizedOrRejectedByReadback() throws {
        let draft = MerchantPerkValidityDraft(value: "legacy-source-text", now: beforeMidnight)
        XCTAssertEqual(try draft.value(now: beforeMidnight), "legacy-source-text")
        XCTAssertTrue(draft.preservesExistingValue(now: beforeMidnight))
    }
    func testExplicitClearFromExpiredCalendarBecomesNoExpiry() throws {
        var draft = MerchantPerkValidityDraft(value: "2000-01-01", now: beforeMidnight)
        draft.setEnabled(false, now: beforeMidnight)
        let value = try draft.value(now: beforeMidnight)
        XCTAssertEqual(value, "")
        XCTAssertNoThrow(try CoopFlowMutation.createTemplate(template(value.isEmpty ? nil : value)).body(now: beforeMidnight))
    }
    func testMalformedDatesCannotPassSubmissionValidator() {
        for value in ["", "2026-2-03", "2026-02-30", "2026-10-13T00:00:00", " 2026-10-13", "2026-10-13\n"] {
            XCTAssertThrowsError(try MerchantPerkValidityDraft.validateForCreation(value, now: beforeMidnight))
        }
    }
    func testUnrelatedExistingMutationsIgnoreCalendarClock() throws {
        let op = CoopFlowMutation.deleteTemplate(id: 7)
        XCTAssertEqual(try op.body(now: beforeMidnight), try op.body(now: midnight))
        XCTAssertEqual(try op.body(now: midnight)["id"], .id(7))
    }
}

private final class PerkExpiryFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data("{\"code\":200,\"data\":{\"id\":71}}".utf8), 200)
    }
}
@MainActor final class MerchantPerkValiditySubmissionServiceTests: XCTestCase {
    func testExpiredCreateIsRejectedBeforeEvenFakeTransport() async throws {
        let transport = PerkExpiryFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, dormantWritesEnabled: true)
        let session = try CoopFlowSession(accountID: 2, epoch: 1, token: "fixture-token")
        let historical = try CoopFlowPerkTemplate(name: "Historical", type: 0, retailValue: 10, unitCost: nil, quota: 1, validEnd: "2000-01-01")
        do { _ = try await service.perform(.createTemplate(historical), session: session); XCTFail("Expired create sent") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .invalid("validEnd")) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testProductionDefaultRemainsDisabledBeforeValidationOrIO() async throws {
        let transport = PerkExpiryFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        let session = try CoopFlowSession(accountID: 2, epoch: 1, token: "fixture-token")
        let draft = try CoopFlowPerkTemplate(name: "No expiry", type: 0, retailValue: 10, unitCost: nil, quota: 1, validEnd: nil)
        do { _ = try await service.perform(.createTemplate(draft), session: session); XCTFail("Approval bypass") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
