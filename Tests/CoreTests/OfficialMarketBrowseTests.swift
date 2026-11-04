import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport fixtures exercise the production GET builder, decoder and projection.
/// These are not evidence of a deployed test backend or of a device journey.
private actor OfficialMarketTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var failuresRemaining: Int
    static let event = #"{"id":71,"title":"Market browse","status":3,"activityStart":1783211400000,"activityEnd":1783297800000}"#
    init(failures: Int = 0) { failuresRemaining = failures }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        let value = request.url?.path.hasSuffix("/71") == true ? Self.event : "[\(Self.event)]"
        return (Data("{\"code\":200,\"data\":\(value)}".utf8), 200)
    }
}

final class OfficialMarketBrowseTests: XCTestCase {
    private func zone(_ id: String) throws -> TimeZone { try XCTUnwrap(TimeZone(identifier: id)) }
    private func service(_ transport: any HTTPTransport) throws -> OfficialEventService {
        try OfficialEventService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func dates(_ event: OfficialEvent, _ zone: TimeZone) -> OfficialDetailFactValue? {
        OfficialEventDetailPresentation(event: event, now: Date(timeIntervalSince1970: 1_783_211_400), displayTimeZone: zone)
            .facts.first { $0.id == "dates" }?.value
    }

    func testGuestListThenDetailUsesServerInstantsInCNAndUSWithoutCredentialsOrWrites() async throws {
        let transport = OfficialMarketTransport(), reader = try service(transport)
        let rows = try await reader.events(city: "Example city")
        let event = try await reader.detail(id: XCTUnwrap(rows.first).id)
        XCTAssertEqual(dates(event, try zone("Asia/Shanghai")), .verbatim("7.5–7.6"))
        XCTAssertEqual(dates(event, try zone("America/Los_Angeles")), .verbatim("7.4–7.5"))
        XCTAssertEqual(dates(event, try zone("America/New_York")), .verbatim("7.4–7.5"))
        XCTAssertEqual(event.activityStart, .milliseconds(1_783_211_400_000))
        XCTAssertEqual(event.status, 3)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertEqual(requests.map { $0.url?.path }, ["/test/api/official/events", "/test/api/official/events/71"])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "city", value: "Example city")])
        for request in requests { XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")) }
    }

    func testNetworkFailureRetriesSameReadAndReopeningUsesCurrentDeviceZone() async throws {
        let transport = OfficialMarketTransport(failures: 1), reader = try service(transport)
        do { _ = try await reader.detail(id: 71); XCTFail("failure must propagate") }
        catch { XCTAssertEqual(OfficialDetailLoadFailure(error), .network) }
        let recovered = try await reader.detail(id: 71)
        XCTAssertEqual(dates(recovered, try zone("America/Los_Angeles")), .verbatim("7.4–7.5"))
        let reopened = try await service(transport).detail(id: 71)
        XCTAssertEqual(dates(reopened, try zone("Asia/Shanghai")), .verbatim("7.5–7.6"))
        XCTAssertEqual(recovered, reopened)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.url == requests.first?.url })
    }

    func testDSTYearBoundaryAndHalfHourZonesUseActualInstant() throws {
        for (instant, id, expected) in [
            ("2026-01-01T00:30:00Z", "America/Los_Angeles", "12.31"),
            ("2026-01-01T00:30:00Z", "Asia/Shanghai", "1.1"),
            ("2026-11-01T05:30:00Z", "America/New_York", "11.1"),
            ("2026-11-01T06:30:00Z", "America/New_York", "11.1"),
            ("2026-07-04T20:00:00Z", "Asia/Kolkata", "7.5")
        ] {
            let date = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
            XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: .milliseconds(date.timeIntervalSince1970 * 1000), end: nil,
                displayTimeZone: try zone(id)), .verbatim(expected))
        }
    }

    func testTextAndInvalidEpochNeverGainAnInventedTime() throws {
        for value in [OfficialEventTime.text("2026-07-04 12:00:00"), .milliseconds(.nan), .milliseconds(.infinity), .milliseconds(-1)] {
            XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: value, end: nil,
                displayTimeZone: try zone("America/Los_Angeles")), .key("official.notAnnounced"))
        }
    }

    func testDisplayZoneCannotChangeCountdownOrServerCTA() throws {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(OfficialMarketTransport.event.utf8))
        let now = Date(timeIntervalSince1970: 1_783_211_400)
        let cn = OfficialEventDetailPresentation(event: event, now: now, displayTimeZone: try zone("Asia/Shanghai"))
        let us = OfficialEventDetailPresentation(event: event, now: now, displayTimeZone: try zone("America/Los_Angeles"))
        XCTAssertEqual(cn.cta, us.cta)
        XCTAssertEqual(cn.facts.filter { $0.id != "dates" }, us.facts.filter { $0.id != "dates" })
    }
}
