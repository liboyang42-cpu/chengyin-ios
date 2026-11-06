import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor RoamToolsWire: HTTPTransport {
    var bodies: [String]
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ bodies: [String], status: Int = 200) { self.bodies = bodies; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(bodies.removeFirst().utf8), status)
    }
}

@MainActor final class RoamPassportToolsTests: XCTestCase {
    private let base = URL(string: "https://tools.example/native")!
    /// 2026-10-19 12:00 Asia/Shanghai.
    private let asOf: Int64 = 1_792_382_400_000
    private func service(_ wire: any HTTPTransport, now: Date? = nil) throws -> RoamPassportToolsService {
        let fixed = now ?? Date(timeIntervalSince1970: TimeInterval(asOf) / 1000)
        return .init(configuration: try APIConfiguration(baseURL: base), transport: wire, now: { fixed })
    }
    private func anniversary(month: Int = 10, day: Int = 19, items: [String] = [], hasMore: Bool = false, cursor: String? = nil,
                             coverage: String = "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE") -> String {
        #"{"code":200,"data":{"month":\#(month),"day":\#(day),"referenceYear":2026,"timeZone":"Asia/Shanghai","asOfMs":\#(asOf),"items":[\#(items.joined(separator: ","))],"hasMore":\#(hasMore),"nextCursor":\#(cursor.map { "\"\($0)\"" } ?? "null"),"leapDayRule":"EXACT_MONTH_DAY_ONLY","coverage":"\#(coverage)","metadataMode":"CURRENT_ROUTE_METADATA"}}"#
    }
    private func memory(_ id: String, year: Int, time: String = "08:00:00.000", month: Int = 10, day: Int = 19, yearsAgo: Int? = nil) -> String {
        #"{"id":"\#(id)","topicId":"88","title":"Route \#(id)","completedAt":"\#(String(format: "%04d-%02d-%02d ", year, month, day))\#(time)","year":\#(year),"yearsAgo":\#(yearsAgo ?? 2026 - year)}"#
    }
    private func recap(month: String = "2026-10", kind: String = "routes", items: [String], hasMore: Bool = false, next: String? = nil) -> String {
        #"{"code":200,"data":{"month":"\#(month)","kind":"\#(kind)","timeZone":"Asia/Shanghai","generatedAtMs":\#(asOf),"counts":{"routes":4,"places":1,"stamps":0},"items":[\#(items.joined(separator: ","))],"hasMore":\#(hasMore),"nextBeforeId":\#(next.map { "\"\($0)\"" } ?? "null")}}"#
    }
    private func record(_ id: String, _ at: String) -> String { #"{"id":"\#(id)","objectId":"5","title":"T\#(id)","occurredAt":"\#(at)"}"# }

    func testShanghaiDayCrossesUTCMidnightAndMonthShiftAcrossYears() {
        // 2026-10-18 16:30 UTC is already 10-19 in Shanghai.
        XCTAssertEqual(RoamShanghaiCalendar.day(atMilliseconds: 1_792_341_000_000), .init(year: 2026, month: 10, day: 19))
        XCTAssertEqual(RoamShanghaiCalendar.shift("2026-01", by: -1), "2025-12")
        XCTAssertEqual(RoamShanghaiCalendar.shift("2025-12", by: 1), "2026-01")
        XCTAssertNil(RoamShanghaiCalendar.parseMonth("2026-13"))
        XCTAssertNil(RoamShanghaiCalendar.wallTime("2026-02-30 10:00:00", requireMilliseconds: false))
        XCTAssertNil(RoamShanghaiCalendar.wallTime("2026-10-19T10:00:00.000", requireMilliseconds: true))
        XCTAssertTrue(RoamShanghaiCalendar.isValidMonthDay(month: 2, day: 29))
    }

    func testTodayAnniversaryOmitsMonthDayAndSendsAuthorizedGET() async throws {
        let wire = RoamToolsWire([anniversary(items: [memory("9", year: 2024), memory("4", year: 2021)])])
        let page = try await service(wire).anniversary(.init(), token: "token-a")
        XCTAssertEqual(page.items.map(\.id), ["9", "4"])
        XCTAssertEqual(page.items.map(\.yearsAgo), [2, 5])
        XCTAssertEqual(page.items[0].completedMinuteText, "2024-10-19 08:00")
        let request = await wire.requests[0]
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://tools.example/native/api/exploration-anniversary?limit=20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-a")
    }

    func testExplicitDayAndContinuationCarryCursorAndBoundary() async throws {
        let first = anniversary(month: 2, day: 29, items: [memory("7", year: 2024, month: 2, day: 29)], hasMore: true, cursor: "abc_1")
        let second = anniversary(month: 2, day: 29, items: [memory("3", year: 2020, month: 2, day: 29)])
        let wire = RoamToolsWire([first, second])
        let tools = try service(wire)
        let page = try await tools.anniversary(.init(month: 2, day: 29, limit: 1), token: "t")
        XCTAssertTrue(page.hasMore)
        let next = try await tools.anniversary(.init(month: 2, day: 29, limit: 1, cursor: page.nextCursor, referenceYear: page.referenceYear),
                                               boundary: page.items.last, token: "t")
        XCTAssertEqual(next.items.map(\.id), ["3"])
        let urls = await wire.requests.map { $0.url?.absoluteString ?? "" }
        XCTAssertEqual(urls[0], "https://tools.example/native/api/exploration-anniversary?day=29&limit=1&month=2")
        XCTAssertEqual(urls[1], "https://tools.example/native/api/exploration-anniversary?cursor=abc_1&day=29&limit=1&month=2")
    }

    func testAnniversaryRejectsUnconfirmedProjections() async throws {
        let cases = [
            anniversary(items: [memory("1", year: 2024)], coverage: "ANY"),
            anniversary(day: 18, items: []),                                            // not today
            anniversary(items: [memory("1", year: 2024, yearsAgo: 3)]),                  // yearsAgo mismatch
            anniversary(items: [memory("1", year: 2026)]),                               // not a past year
            anniversary(items: [memory("1", year: 2024, day: 18)]),                      // different day
            anniversary(items: [memory("1", year: 2021), memory("2", year: 2024)]),      // not newest first
            anniversary(items: [memory("1", year: 2024), memory("1", year: 2023)]),      // duplicate id
            anniversary(items: [memory("1", year: 2024)], hasMore: true, cursor: "x"),   // more with short page
            anniversary(items: [], cursor: "x"),                                         // cursor without more
        ]
        for body in cases {
            do { _ = try await service(RoamToolsWire([body])).anniversary(.init(), token: "t"); XCTFail(body) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse, body) }
        }
    }

    func testAnniversaryAcceptsNumericIdentifiersAndValidatesQueryLocally() async throws {
        let numeric = anniversary(items: [#"{"id":12,"topicId":5,"title":null,"completedAt":"2025-10-19 21:00:00.500","year":2025,"yearsAgo":1}"#])
        let page = try await service(RoamToolsWire([numeric])).anniversary(.init(), token: "t")
        XCTAssertEqual(page.items.first?.id, "12"); XCTAssertNil(page.items.first?.title)
        let wire = RoamToolsWire([])
        for query in [RoamAnniversaryQuery(month: 2, day: 30), RoamAnniversaryQuery(month: 3), RoamAnniversaryQuery(limit: 51), RoamAnniversaryQuery(cursor: "bad cursor")] {
            do { _ = try await service(wire).anniversary(query, token: "t"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let sent = await wire.requests.count
        XCTAssertEqual(sent, 0)
    }

    func testRecapRequestFieldsWeeksAndDuplicateCollapse() async throws {
        let wire = RoamToolsWire([recap(items: [record("9", "2026-10-02 09:00:00"), record("8", "2026-10-09 10:00:00"),
                                                record("8", "2026-10-09 10:00:00"), record("7", "2026-10-31 23:59:59")])])
        let page = try await service(wire).monthlyRecap(.init(month: "2026-10"), token: "t")
        XCTAssertEqual(page.items.map(\.id), ["9", "8", "7"])
        XCTAssertEqual(page.items.map(\.dateText), ["10/2", "10/9", "10/31"])
        XCTAssertEqual(page.weeks.map(\.count), [1, 1, 0, 0, 1])
        XCTAssertEqual(page.weeks.filter(\.isMax).map(\.index), [1, 2, 5])
        XCTAssertEqual(page.counts, RoamRecapCounts(routes: 4, places: 1, stamps: 0))
        let url = await wire.requests[0].url?.absoluteString
        XCTAssertEqual(url, "https://tools.example/native/api/monthly-recap?kind=routes&limit=20&month=2026-10")
    }

    func testRecapPartialMonthHasNoWeeksAndNextPageSendsBeforeID() async throws {
        let wire = RoamToolsWire([recap(kind: "places", items: [record("50", "2026-10-03 08:00:00")], hasMore: true, next: "50"),
                                  recap(kind: "places", items: [record("20", "2026-10-01 08:00:00")])])
        let tools = try service(wire)
        let page = try await tools.monthlyRecap(.init(month: "2026-10", kind: .places), token: "t")
        XCTAssertTrue(page.weeks.isEmpty)
        let next = try await tools.monthlyRecap(.init(month: "2026-10", kind: .places, beforeID: page.nextBeforeID), token: "t")
        XCTAssertEqual(next.items.map(\.id), ["20"])
        let url = await wire.requests[1].url?.absoluteString
        XCTAssertEqual(url, "https://tools.example/native/api/monthly-recap?beforeId=50&kind=places&limit=20&month=2026-10")
    }

    func testRecapRejectsFutureMonthAndMismatchedResponses() async throws {
        let idle = RoamToolsWire([])
        do { _ = try await service(idle).monthlyRecap(.init(month: "2026-11"), token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let sent = await idle.requests.count
        XCTAssertEqual(sent, 0)
        let bad = [recap(month: "2026-09", items: []), recap(kind: "stamps", items: []),
                   recap(items: [record("1", "2026-09-30 23:00:00")]), recap(items: [record("1", "2026-10-01 08:00:00")], hasMore: true),
                   recap(items: [], next: "3")]
        for body in bad {
            do { _ = try await service(RoamToolsWire([body])).monthlyRecap(.init(month: "2026-10"), token: "t"); XCTFail(body) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse, body) }
        }
    }

    func testUnauthorizedAndBusinessFailuresAreDistinct() async throws {
        do { _ = try await service(RoamToolsWire([#"{"code":401}"#])).anniversary(.init(), token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await service(RoamToolsWire([#"{"code":500,"msg":"x"}"#])).monthlyRecap(.init(month: "2026-10"), token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .businessCode(500)) }
        do { _ = try await service(RoamToolsWire(["{}"], status: 503)).anniversary(.init(), token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
    }

    func testFixtureReaderScenarios() async throws {
        let content = RoamPassportToolsFixtureReader()
        let memories = try await content.anniversary(.init(), boundary: nil)
        XCTAssertEqual(memories.items.map(\.yearsAgo), [1, 3])
        let recap = try await content.monthlyRecap(.init(month: "2026-10"))
        XCTAssertEqual(recap.weeks.map(\.count), [1, 2, 0, 0, 0])
        let empty = RoamPassportToolsFixtureReader(scenario: .empty)
        let none = try await empty.anniversary(.init(), boundary: nil)
        XCTAssertTrue(none.items.isEmpty)
        let noStamps = try await empty.monthlyRecap(.init(month: "2026-09", kind: .stamps))
        XCTAssertTrue(noStamps.items.isEmpty)
        let signedOut = RoamPassportToolsFixtureReader(scenario: .unauthorized)
        XCTAssertNil(signedOut.identity)
        do { _ = try await signedOut.monthlyRecap(.init(month: "2026-10")); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
