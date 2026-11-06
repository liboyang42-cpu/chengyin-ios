import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor OfficialTimeSafetyWire: HTTPTransport {
    var requests: [URLRequest] = []
    var failures = 0
    var rawTime = "1e308"
    func configure(failures: Int = 0, rawTime: String) { self.failures = failures; self.rawTime = rawTime }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if failures > 0 { failures -= 1; throw URLError(.notConnectedToInternet) }
        let event = "{\"id\":71,\"title\":\"Synthetic official event\",\"status\":3,\"activityStart\":\(rawTime),\"activityEnd\":\(rawTime)}"
        let data = request.url?.lastPathComponent == "71" ? event : "[\(event)]"
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
    }
}

final class OfficialEventTimeSafetyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_783_211_400)
    private func event(status: Int = 3, start: String = "1783211400000", end: String = "1783297800000") throws -> OfficialEvent {
        try JSONDecoder().decode(OfficialEvent.self, from: Data("{\"id\":71,\"title\":\"Synthetic\",\"status\":\(status),\"activityStart\":\(start),\"activityEnd\":\(end)}".utf8))
    }
    private func value(_ event: OfficialEvent, _ id: String) -> OfficialDetailFactValue? {
        OfficialEventDetailPresentation(event: event, now: now).facts.first { $0.id == id }?.value
    }

    func testFiniteOutOfRangeJSONIsRetainedButNeverPresentedAsDate() throws {
        for raw in ["1e308", "1e30", "1000000000000000", "-1", "0"] {
            let time = try JSONDecoder().decode(OfficialEventTime.self, from: Data(raw.utf8))
            guard case .milliseconds(let original) = time else { return XCTFail() }
            XCTAssertEqual(original, try XCTUnwrap(Double(raw))); XCTAssertNil(time.displayMilliseconds); XCTAssertNil(time.displayDate)
        }
    }

    func testExistingPositiveDisplayBoundaryRemainsExclusiveAndUnclamped() throws {
        let edge = OfficialEventTime.milliseconds(1e15 - 1)
        XCTAssertEqual(edge.displayMilliseconds, 1e15 - 1)
        XCTAssertNotNil(edge.displayDate)
        XCTAssertNil(OfficialEventTime.milliseconds(1e15).displayDate)
        XCTAssertNotNil(OfficialEventTime.milliseconds(1).displayDate)
        let row = try event(start: "999999999999999", end: "999999999999999")
        XCTAssertNotNil(row.countdown(now: now))
    }

    func testDirectNonFiniteAndNegativeSpanDoesNotTrapOrClamp() {
        for milliseconds in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 1e308, -1] {
            XCTAssertEqual(OfficialCountdownSpan(milliseconds: milliseconds), .unknown)
        }
    }

    func testFloatingPointIntBoundaryIsRejectedWithoutFabricatedMaximum() {
        let roundedOutOfRangeHours = Double(Int.max)
        XCTAssertNil(Int(exactly: roundedOutOfRangeHours))
        XCTAssertEqual(OfficialCountdownSpan(milliseconds: roundedOutOfRangeHours * 3_600_000), .unknown)
    }

    func testOriginalValidCountdownRoundingIsUnchanged() {
        for (milliseconds, expected) in [(0.0, OfficialCountdownSpan.minutes(1)), (20_000, .minutes(1)),
            (120_000, .minutes(2)), (3_600_000, .hours(1)), (23 * 3_600_000, .hours(23)),
            (86_400_000, .days(1)), (3 * 86_400_000 + 5, .days(3))] {
            XCTAssertEqual(OfficialCountdownSpan(milliseconds: milliseconds), expected)
        }
    }

    func testCardCountdownRejectsInvalidStartAndEndWithoutDroppingServerRecord() throws {
        for raw in ["1e308", "1000000000000000", "-1", "0"] {
            for status in [1, 2, 3] {
                let row = try event(status: status, start: raw, end: raw)
                XCTAssertTrue(row.isCompleteRecord); XCTAssertEqual(row.status, status)
                XCTAssertNil(row.countdown(now: now)); XCTAssertEqual(row.activityStart, .milliseconds(Double(raw)!))
            }
        }
    }

    func testNonFiniteClockAndOverflowingDifferenceCannotTrap() throws {
        let row = try event()
        for seconds in [Double.nan, .infinity, -.infinity, -.greatestFiniteMagnitude, -1e300] {
            XCTAssertNil(row.countdown(now: Date(timeIntervalSince1970: seconds)))
        }
    }

    func testDurationRequiresBothOriginalInstantsInsideExistingDisplayBoundary() {
        let valid = OfficialEventTime.milliseconds(1_783_211_400_000)
        for invalid in [OfficialEventTime.milliseconds(.nan), .milliseconds(.infinity), .milliseconds(1e308),
                        .milliseconds(1e15), .milliseconds(-1), .milliseconds(0), .text("2026-07-04")] {
            XCTAssertEqual(OfficialEventDetailPresentation.duration(start: invalid, end: valid), .key("official.notAnnounced"))
            XCTAssertEqual(OfficialEventDetailPresentation.duration(start: valid, end: invalid), .key("official.notAnnounced"))
        }
        XCTAssertEqual(OfficialEventDetailPresentation.duration(start: .milliseconds(-3_600_001), end: .milliseconds(-1)), .key("official.notAnnounced"))
    }

    func testDetailUsesUnknownDateAndDurationWithoutAlteringStatusOrCTA() throws {
        let row = try event(start: "1e308", end: "1e308")
        let presentation = OfficialEventDetailPresentation(event: row, now: now)
        XCTAssertEqual(value(row, "dates"), .key("official.notAnnounced"))
        XCTAssertEqual(value(row, "duration"), .key("official.notAnnounced"))
        XCTAssertEqual(presentation.cta, row.detailCTA); XCTAssertEqual(row.statusKey, "official.status.live")
        XCTAssertEqual(presentation.facts.first { $0.id == "scope" }?.sub, .key(row.statusKey))
    }

    func testNormalDeviceDatesAndCountdownRemainIndependent() throws {
        let row = try event()
        let cn = OfficialEventDetailPresentation(event: row, now: now, displayTimeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")))
        let us = OfficialEventDetailPresentation(event: row, now: now, displayTimeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        XCTAssertEqual(cn.facts.first { $0.id == "dates" }?.value, .verbatim("7.5–7.6"))
        XCTAssertEqual(us.facts.first { $0.id == "dates" }?.value, .verbatim("7.4–7.5"))
        XCTAssertEqual(cn.facts.filter { $0.id != "dates" }, us.facts.filter { $0.id != "dates" })
        XCTAssertEqual(row.countdown(now: now), .endsIn(.days(1)))
        XCTAssertEqual(row.activityStart?.displayDate, now)
    }

    func testTextStaysVerbatimDataAndNeverAcquiresNumericDateAuthority() throws {
        let row = try event(start: "\"2026-07-04 12:00:00\"", end: "\"unconfirmed\"")
        XCTAssertEqual(row.activityStart, .text("2026-07-04 12:00:00")); XCTAssertEqual(row.activityEnd, .text("unconfirmed"))
        XCTAssertNil(row.activityStart?.displayDate); XCTAssertNil(row.countdown(now: now))
        XCTAssertEqual(value(row, "dates"), .key("official.notAnnounced"))
    }

    @MainActor func testGuestServiceListDetailAndExplicitRetryUseOnlyOriginalGETs() async throws {
        let wire = OfficialTimeSafetyWire()
        let service = try OfficialEventService(configuration: APIConfiguration(baseURL: URL(string: "https://example.test/time-safety")!), transport: wire)
        let reader = OfficialSessionReader(service: service, currentContext: { .init(guestEpoch: 1) })
        let rows = try await reader.events(city: "Synthetic city")
        let invalid = try await reader.detail(id: XCTUnwrap(rows.first).id)
        XCTAssertNil(invalid.countdown(now: now)); XCTAssertEqual(value(invalid, "dates"), .key("official.notAnnounced"))
        await wire.configure(failures: 1, rawTime: "1783297800000")
        do { _ = try await reader.detail(id: 71); XCTFail() }
        catch { XCTAssertEqual(OfficialDetailLoadFailure(error), .network) }
        let recovered = try await reader.detail(id: 71)
        XCTAssertNotNil(recovered.activityEnd?.displayDate); XCTAssertEqual(recovered.countdown(now: now), .endsIn(.days(1)))
        let requests = await wire.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["events", "71", "71", "71"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }
}
