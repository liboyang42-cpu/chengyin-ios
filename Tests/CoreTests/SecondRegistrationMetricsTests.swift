import XCTest
@testable import QuestifyCore

final class SecondRegistrationMetricsTests: XCTestCase {
    private func report(_ json: String) throws -> SecondRegistrationReport {
        try JSONDecoder().decode(SecondRegistrationReport.self, from: Data(json.utf8))
    }
    private func cell(_ json: String) throws -> SecondRegistrationCell {
        try JSONDecoder().decode(SecondRegistrationCell.self, from: Data(json.utf8))
    }
    func testMatureRateUsesIntegerHalfUpPercent() throws {
        let display = SecondRegistrationRateDisplay(try cell(#"{"days":28,"mature":true,"denominator":40,"numerator":3}"#))
        XCTAssertEqual(display, .rate(numerator: 3, denominator: 40, percent: "7.5%"))
        XCTAssertEqual(SecondRegistrationRateDisplay.percentText(numerator: 1, denominator: 3), "33.3%")
        XCTAssertEqual(SecondRegistrationRateDisplay.percentText(numerator: 2, denominator: 3), "66.7%")
        XCTAssertEqual(SecondRegistrationRateDisplay.percentText(numerator: 5, denominator: 5), "100.0%")
    }
    func testZeroDenominatorIsNoMatureSampleNeverZeroPercent() throws {
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":7,"mature":true,"denominator":0,"numerator":0}"#)), .noMatureSample)
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":7,"mature":true,"denominator":0}"#)), .noMatureSample)
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":7,"mature":true,"denominator":0,"numerator":2}"#)), .unavailable)
    }
    func testImmatureCohortShowsObservedTotalOnly() throws {
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":56,"mature":false,"denominator":10,"numerator":4,"observedCumulative":4}"#)), .observedOnly(4))
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":56,"mature":false,"denominator":10,"numerator":4}"#)), .unavailable)
    }
    func testInvalidCellsAreUnavailable() throws {
        XCTAssertEqual(SecondRegistrationRateDisplay(nil), .unavailable)
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":28,"mature":true,"denominator":3,"numerator":4}"#)), .unavailable)
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":28,"mature":true,"denominator":-1,"numerator":0}"#)), .unavailable)
        XCTAssertEqual(SecondRegistrationRateDisplay(try cell(#"{"days":28,"mature":true,"numerator":1}"#)), .unavailable)
        XCTAssertThrowsError(try cell(#"{"days":30,"mature":true,"denominator":3,"numerator":1}"#))
    }
    func testReportRequiresVersionAsOfAndUniqueWindows() throws {
        let value = try report(#"{"metricVersion":"v1","asOf":"2026-10-01","windows":[{"days":56,"mature":false,"observedCumulative":1},{"days":7,"mature":true,"denominator":2,"numerator":1}],"transitions":[{"from":"FREE","to":"PAID","days":28,"mature":true,"denominator":4,"numerator":1}],"supplyGapMembers":-3}"#)
        XCTAssertEqual(value.sortedWindows.map(\.window), [.days7, .days56])
        XCTAssertEqual(value.transitions.first?.from, .free); XCTAssertEqual(value.transitions.first?.to, .paid)
        XCTAssertEqual(value.transitions.first?.cell.numerator, 1)
        XCTAssertFalse(value.isTest); XCTAssertNil(value.supplyGapMembers); XCTAssertNil(value.exclusions)
        XCTAssertThrowsError(try report(#"{"metricVersion":" ","asOf":"2026-10-01"}"#))
        XCTAssertThrowsError(try report(#"{"metricVersion":"v1","asOf":""}"#))
        XCTAssertThrowsError(try report(#"{"metricVersion":"v1","asOf":"x","windows":[{"days":7,"mature":false},{"days":7,"mature":false}]}"#))
        XCTAssertThrowsError(try report(#"{"metricVersion":"v1","asOf":"x","transitions":[{"from":"FREE","to":"GIFT","days":7,"mature":false}]}"#))
    }
    func testClientEventEnvelopeCarriesRequiredW10Fields() throws {
        let visit = UUID()
        let event = try SecondRegistrationClientEvent(name: .offerViewed, visit: visit, activityID: 12, isTest: true,
                                                      clientVersion: "1.0", occurredAt: Date(timeIntervalSince1970: 1.5))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertEqual(object["event"] as? String, "offer_viewed")
        XCTAssertEqual(object["occurred_at"] as? Int, 1500)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1); XCTAssertEqual(object["source"] as? String, "ios")
        XCTAssertEqual(object["is_test"] as? Bool, true); XCTAssertEqual(object["client_version"] as? String, "1.0")
        XCTAssertEqual(object["trace"] as? String, visit.uuidString.lowercased())
        XCTAssertEqual(object["idempotency_key"] as? String, "offer_viewed:activity-12:" + visit.uuidString.lowercased())
        XCTAssertNotNil(object["event_id"] as? String); XCTAssertEqual(object["activity_id"] as? Int, 12)
        XCTAssertNil(object["received_at"], "received_at is a server fact")
    }
    func testClientEventRejectsMissingOrUnsafeSubject() {
        XCTAssertThrowsError(try SecondRegistrationClientEvent(name: .secondContentExposed, visit: UUID(), activityID: nil, isTest: false, clientVersion: "1", occurredAt: Date()))
        XCTAssertThrowsError(try SecondRegistrationClientEvent(name: .secondContentExposed, visit: UUID(), activityID: 0, isTest: false, clientVersion: "1", occurredAt: Date()))
        XCTAssertThrowsError(try SecondRegistrationClientEvent(name: .secondContentExposed, visit: UUID(), activityID: nil, contentFamilyID: "a b", isTest: false, clientVersion: "1", occurredAt: Date()))
        XCTAssertNoThrow(try SecondRegistrationClientEvent(name: .secondContentExposed, visit: UUID(), activityID: nil, contentFamilyID: "family_2-b", isTest: false, clientVersion: "1", occurredAt: Date()))
    }
    @MainActor func testExposureLogDeduplicatesPerVisitAndStaysBounded() throws {
        let log = SecondRegistrationExposureLog(), visit = UUID()
        let first = try SecondRegistrationClientEvent(name: .offerViewed, visit: visit, activityID: 5, isTest: true, clientVersion: "1", occurredAt: Date())
        let repeated = try SecondRegistrationClientEvent(name: .offerViewed, visit: visit, activityID: 5, isTest: true, clientVersion: "1", occurredAt: Date())
        XCTAssertTrue(log.record(first)); XCTAssertFalse(log.record(repeated)); XCTAssertEqual(log.events.count, 1)
        for index in 1...(SecondRegistrationExposureLog.capacity + 5) {
            log.record(try SecondRegistrationClientEvent(name: .offerViewed, visit: UUID(), activityID: index, isTest: true, clientVersion: "1", occurredAt: Date()))
        }
        XCTAssertEqual(log.events.count, SecondRegistrationExposureLog.capacity)
        XCTAssertTrue(log.record(first), "an evicted key may be recorded again")
        log.reset(); XCTAssertTrue(log.events.isEmpty)
    }
}
