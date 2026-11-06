import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// In-memory read/host probes, not a claim that the normal root authorizes official GETs.
@MainActor private final class OfficialTimeSafetyAppWire: HTTPTransport {
    var requests: [URLRequest] = []
    var rawTime = "1e308"
    var failNext = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if failNext { failNext = false; throw URLError(.notConnectedToInternet) }
        let event = "{\"id\":71,\"title\":\"Synthetic official event\",\"status\":3,\"activityStart\":\(rawTime),\"activityEnd\":\(rawTime)}"
        let data = request.url?.lastPathComponent == "71" ? event : "[\(event)]"
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
    }
}
@MainActor private final class OfficialTimeSafetyEmptyVault: AppTokenStorage {
    private(set) var reads = 0
    func read() throws -> String? { reads += 1; return nil }
    func write(_ token: String) throws { XCTFail("Display safety must not save a credential") }
    func clear() throws { XCTFail("Display safety must not delete a credential") }
}

@MainActor final class OfficialEventTimeSafetyViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_783_211_400)
    private func reader(_ wire: OfficialTimeSafetyAppWire) throws -> OfficialSessionReader {
        let service = OfficialEventService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/time-safety")!), transport: wire)
        return OfficialSessionReader(service: service, currentContext: { OfficialReadContext(guestEpoch: 1) })
    }
    private func render<V: View>(_ view: V, locale: String = "en", timeZone: TimeZone = .current) {
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale))
            .environment(\.timeZone, timeZone).environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }

    func testServiceListAndDetailKeepInvalidTimeRecordBrowsableAndCardRenderable() async throws {
        let wire = OfficialTimeSafetyAppWire(), reader = try self.reader(wire)
        let rows = try await reader.events(city: nil)
        let row = try XCTUnwrap(rows.first)
        let detail = try await reader.detail(id: row.id)
        XCTAssertEqual(row, detail); XCTAssertEqual(row.activityEnd, .milliseconds(1e308))
        XCTAssertNil(row.countdown(now: now))
        XCTAssertEqual(OfficialEventDetailPresentation(event: detail, now: now).facts.first { $0.id == "dates" }?.value,
                       .key("official.notAnnounced"))
        for locale in ["en", "zh-Hans"] {
            render(OfficialEventCard(event: row), locale: locale)
            render(OfficialEventTimeValue(value: detail.activityEnd), locale: locale)
        }
        XCTAssertEqual(wire.requests.map { $0.url?.path }, ["/time-safety/api/official/events", "/time-safety/api/official/events/71"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    func testRenderingInvalidTimeDoesNotAutoRetryAndExplicitReadCanRecover() async throws {
        let wire = OfficialTimeSafetyAppWire(), reader = try self.reader(wire)
        let invalid = try await reader.detail(id: 71)
        render(OfficialEventCard(event: invalid))
        XCTAssertEqual(wire.requests.count, 1)
        wire.rawTime = "1783297800000"; wire.failNext = true
        do { _ = try await reader.detail(id: 71); XCTFail("Synthetic network failure was hidden") }
        catch { XCTAssertEqual(OfficialDetailLoadFailure(error), .network) }
        render(OfficialEventTimeValue(value: invalid.activityEnd))
        XCTAssertEqual(wire.requests.count, 2)
        let recovered = try await reader.detail(id: 71)
        XCTAssertEqual(recovered.countdown(now: now), .endsIn(.days(1)))
        XCTAssertEqual(recovered.activityEnd?.displayDate, now.addingTimeInterval(86_400))
        render(OfficialEventCard(event: recovered))
        render(OfficialEventTimeValue(value: recovered.activityEnd))
        XCTAssertEqual(wire.requests.count, 3)
    }

    func testDirectInvalidDateAndUnknownSpanComponentsRenderBothLocales() {
        let values: [OfficialEventTime?] = [nil, .milliseconds(.nan), .milliseconds(.infinity),
            .milliseconds(-.infinity), .milliseconds(1e308), .milliseconds(1e15),
            .milliseconds(-1), .milliseconds(0)]
        for locale in ["en", "zh-Hans"] {
            for value in values {
                XCTAssertNil(value?.displayDate)
                render(OfficialEventTimeValue(value: value), locale: locale)
            }
            render(OfficialCountdownText(value: .startsIn(.unknown)), locale: locale)
            render(OfficialCountdownText(value: .endsIn(.unknown)), locale: locale)
        }
    }

    func testDeviceTimezonePresentationDoesNotRewriteServerTimestampOrStatus() async throws {
        let wire = OfficialTimeSafetyAppWire(); wire.rawTime = "1783211400000"
        let reader = try self.reader(wire), row = try await reader.detail(id: 71)
        for (identifier, expected) in [("Asia/Shanghai", "7.5–7.5"), ("America/Los_Angeles", "7.4–7.4")] {
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: row.activityStart, end: row.activityEnd, displayTimeZone: zone), .verbatim(expected))
            render(OfficialEventTimeValue(value: row.activityEnd), timeZone: zone)
        }
        XCTAssertEqual(row.activityEnd, .milliseconds(1_783_211_400_000))
        XCTAssertEqual(row.status, 3); XCTAssertEqual(row.statusKey, "official.status.live")
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testUnknownTimeDoesNotGrantGuestPrivateReadOrPublisherPermission() async throws {
        let wire = OfficialTimeSafetyAppWire(), reader = try self.reader(wire)
        let row = try await reader.detail(id: 71)
        render(OfficialEventCard(event: row))
        do { _ = try await reader.myEvents(); XCTFail("Guest private read was allowed") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let canPublish = try await reader.canPublish()
        XCTAssertFalse(canPublish); XCTAssertFalse(reader.isAuthenticated)
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testNormalCompositionStillRejectsUnreviewedOfficialGETBeforeWire() async throws {
        let wire = OfficialTimeSafetyAppWire(), vault = OfficialTimeSafetyEmptyVault()
        let suite = "official-time-safety-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://example.test/time-safety",
            approvedBaseURLs: [.china: ["https://example.test/time-safety"]], verifiedCapabilities: [],
            bundleIdentifier: "test.questify.official-time", realm: "synthetic", reads: [.homeAndSearch])
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        let session = root.makeSession()
        do { _ = try await session.officialEventReader.events(city: nil); XCTFail("Leaf fix expanded an unreviewed GET grant") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await session.officialEventReader.detail(id: 71); XCTFail("Leaf fix expanded an unreviewed detail GET grant") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(session.account)
        XCTAssertEqual(vault.reads, 0)
    }
}
