import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Mini-program subpackageRoam history / session / poi-detail / citynode-code / citystamp rules.
@MainActor final class RoamSubpageParityTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func records(_ json: String) throws -> [RoamHistoryRecord] { try JSONDecoder().decode([RoamHistoryRecord].self, from: Data(json.utf8)) }
    private func node(_ json: String) throws -> RoamNodeDetail { try JSONDecoder().decode(RoamNodeDetail.self, from: Data(json.utf8)) }

    func testRunCardFormatsShortDateTitleStatsStampsAndMedals() throws {
        let row = try records(#"[{"ts":1760857200000,"zone":"West Lake","distance":2.5,"shops":3,"durSec":125,"photos":["a","b"],"medal":"Walker","shopMedalName":"Taster","pois":[],"track":[]}]"#)[0]
        let card = RoamRunCardPresentation(row, calendar: utc)
        XCTAssertEqual(card.title, .zone("West Lake"))
        XCTAssertEqual(card.dateShort, "10/19/25")
        XCTAssertEqual(card.distanceText, "2.5")
        XCTAssertEqual(card.shopsText, "3")
        XCTAssertEqual(card.timeText, "02:05")
        XCTAssertEqual(card.stamps, 2)
        XCTAssertEqual(card.medals, ["Walker", "Taster"])
    }

    func testRunCardPlaceholderZoneAndUnknownValues() throws {
        let row = try records(#"[{"ts":1760857200000,"zone":"这片街区","photos":[],"pois":[],"track":[]}]"#)[0]
        let card = RoamRunCardPresentation(row, calendar: utc)
        XCTAssertEqual(card.title, .city)
        XCTAssertEqual(card.distanceText, "0", "UI-04: an unread distance renders 0 on the card")
        XCTAssertEqual(card.shopsText, "—")
        XCTAssertEqual(card.timeText, "—")
        XCTAssertEqual(card.stamps, 0)
        XCTAssertTrue(card.medals.isEmpty)
    }

    func testStripSummaryNeverShowsAPartialSum() throws {
        let known = try records(#"[{"ts":1,"distance":1.2,"shops":1},{"ts":2,"distance":"0.3","shops":2}]"#)
        let strip = RoamHistoryStripSummary(known)
        XCTAssertEqual(strip.trips, 2); XCTAssertEqual(strip.kilometersText, "1.5"); XCTAssertEqual(strip.shopsText, "3")
        let partial = RoamHistoryStripSummary(try records(#"[{"ts":1,"distance":1.2,"shops":1},{"ts":2}]"#))
        XCTAssertEqual(partial.kilometersText, "—"); XCTAssertEqual(partial.shopsText, "—")
    }

    func testRouteNameFollowsSessionPageOrder() throws {
        let zone = try records(#"[{"ts":1760857200000,"zone":"Old Town","pois":[{"name":"A","lat":1,"lng":1}]}]"#)[0]
        XCTAssertEqual(RoamSessionRouteName(zone, calendar: utc), .zone("Old Town"))
        let many = try records(#"[{"ts":1760857200000,"zone":"这片街区","pois":[{"name":" Cafe ","lat":1,"lng":1},{"name":"","lat":1,"lng":1},{"name":"Park","lat":1,"lng":1}]}]"#)[0]
        XCTAssertEqual(RoamSessionRouteName(many, calendar: utc), .places(first: "Cafe", count: 2))
        let one = try records(#"[{"ts":1760857200000,"pois":[{"name":"Cafe","lat":1,"lng":1}]}]"#)[0]
        XCTAssertEqual(RoamSessionRouteName(one, calendar: utc), .place("Cafe"))
        let none = try records(#"[{"ts":1760857200000}]"#)[0]
        XCTAssertEqual(RoamSessionRouteName(none, calendar: utc), .date(month: 10, day: 19))
        let undated = try records(#"[{"ts":0}]"#)[0]
        XCTAssertEqual(RoamSessionRouteName(undated, calendar: utc), .generic)
    }

    func testShareTokenIsStrictAndRequestIsAnonymousGet() throws {
        XCTAssertNil(RoamShareToken("ABCDEF0123456789abcdef0123456789"))
        XCTAssertNil(RoamShareToken("0123"))
        XCTAssertNil(RoamShareToken("0123456789abcdef0123456789abcdeg"))
        let token = try XCTUnwrap(RoamShareToken(RoamShareSnapshotFixtureReader.readyToken))
        let request = try token.request(baseURL: URL(string: "https://example.invalid/base/")!)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/base/api/roam/share/snapshot?token=" + token.value)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testShareSnapshotOutcomeSeparatesGoneFromRetryableErrors() async throws {
        let ready = RoamShareSnapshotOutcome.resolve(data: Data(RoamShareSnapshotFixtureReader.readyBody.utf8), status: 200)
        guard case .ready(let snapshot) = ready else { return XCTFail("\(ready)") }
        XCTAssertEqual(snapshot.routeName, "Demo lane footprints"); XCTAssertEqual(snapshot.shops, 3); XCTAssertEqual(snapshot.track.count, 2)
        XCTAssertEqual(RoamShareSnapshotOutcome.resolve(data: Data(#"{"code":500,"msg":"这条足迹已不再公开"}"#.utf8), status: 200), .gone)
        XCTAssertEqual(RoamShareSnapshotOutcome.resolve(data: Data(#"{"code":200,"data":{"ts":-1}}"#.utf8), status: 200), .gone)
        XCTAssertEqual(RoamShareSnapshotOutcome.resolve(data: Data(#"{"code":200,"data":{"ts":1,"explorePct":140}}"#.utf8), status: 200), .gone)
        XCTAssertEqual(RoamShareSnapshotOutcome.resolve(data: Data(), status: 502), .error)
        let empty = RoamShareSnapshotOutcome.resolve(data: Data(#"{"code":200,"data":{"ts":1,"routeName":""}}"#.utf8), status: 200)
        guard case .ready(let fallback) = empty else { return XCTFail() }
        XCTAssertEqual(fallback.routeName, "城市漫游足迹"); XCTAssertNil(fallback.distance); XCTAssertNil(fallback.shops)
        let reader = RoamShareSnapshotFixtureReader()
        let gone = await reader.snapshot(try XCTUnwrap(RoamShareToken(RoamShareSnapshotFixtureReader.goneToken)))
        XCTAssertEqual(gone, .gone)
    }

    func testCouponIdDecodeAndNodeCardStates() throws {
        let offline = try node(#"{"poiId":7,"name":"N","status":0,"validationMethod":1,"needRedeem":true,"couponId":"88"}"#)
        XCTAssertEqual(offline.couponId, 88)
        let card = RoamPOINodePresentation(offline)
        XCTAssertTrue(card.offline); XCTAssertTrue(card.offlineKeepsVoucher); XCTAssertTrue(card.grantsCoupon)
        XCTAssertEqual(card.primary, .showVoucher)
        XCTAssertEqual(card.validationKey, "roamSub.w208.poi.method.1")
        let done = RoamPOINodePresentation(try node(#"{"poiId":7,"status":1,"validationMethod":3,"completed":true,"needRedeem":true,"couponId":0}"#))
        XCTAssertEqual(done.primary, .completed); XCTAssertFalse(done.grantsCoupon)
        XCTAssertEqual(RoamPOINodePresentation(try node(#"{"poiId":7,"status":1,"validationMethod":3}"#)).primary, .interact)
        XCTAssertEqual(RoamPOINodePresentation(try node(#"{"poiId":7,"status":1,"validationMethod":7}"#)).primary, .unavailable)
        XCTAssertEqual(RoamPOINodePresentation(try node(#"{"poiId":7,"status":1,"validationMethod":3,"canInteract":false}"#)).primary, .unavailable)
        let unknown = RoamPOINodePresentation(try node(#"{"poiId":7,"status":1}"#))
        XCTAssertEqual(unknown.validationKey, "roamSub.w208.poi.method.unknown"); XCTAssertEqual(unknown.primary, .unavailable)
        XCTAssertEqual(RoamPOINodePresentation.chargeKey(1), "roamSub.w208.poi.charge.paid")
        XCTAssertEqual(RoamPOINodePresentation.chargeKey(0), "roamSub.w208.poi.charge.free")
        XCTAssertEqual(RoamPOINodePresentation.chargeKey(nil), "roamSub.w208.poi.charge.unknown")
    }

    func testNodeDetail410IsUnavailableNotRetryableFailure() async throws {
        for (status, body) in [(410, "{}"), (200, #"{"code":410,"msg":"据点未开放"}"#)] {
            let transport = RoamParityTransport(status: status, body: body)
            let service = RoamService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
            do { _ = try await service.nodeDetail(id: 7, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? RoamReadFailure, .nodeUnavailable) }
        }
        let other = RoamService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: RoamParityTransport(status: 503, body: "{}"))
        do { _ = try await other.nodeDetail(id: 7, token: "fixture-token"); XCTFail() }
        catch { XCTAssertNotEqual(error as? RoamReadFailure, .nodeUnavailable) }
    }

    func testCityVoucherCopyMapsFailuresAndName() {
        XCTAssertEqual(RoamCityVoucherCopy.phaseKey(.failed), "roamSub.w208.voucher.issueFailed")
        XCTAssertEqual(RoamCityVoucherCopy.phaseKey(.invalid), "roamSub.w208.voucher.issueFailed")
        XCTAssertEqual(RoamCityVoucherCopy.phaseKey(.unavailable), "roamSub.w208.voucher.unavailable")
        XCTAssertNil(RoamCityVoucherCopy.phaseKey(.disabled))
        XCTAssertNil(RoamCityVoucherCopy.phaseKey(.login))
        XCTAssertNil(RoamCityVoucherCopy.displayName("  "))
        XCTAssertEqual(RoamCityVoucherCopy.displayName(" Demo "), "Demo")
    }

    func testStampSlipSerialBarsAndNoExchange() throws {
        let receipt = try JSONDecoder().decode(RoamStampExchangeReceipt.self, from: Data(#"{"exchanged":true,"stamp":{"id":12345,"picUrl":"https://example.invalid/a.jpg","caption":"","checkState":1,"createTime":"2026-10-18T09:30:00"}}"#.utf8))
        let slip = RoamStampSlip(receipt)
        XCTAssertTrue(slip.got); XCTAssertEqual(slip.serial, "NO. 2345"); XCTAssertNil(slip.caption)
        XCTAssertEqual(slip.leftAt, "2026-10-18 09:30")
        XCTAssertEqual(slip.bars.count, 46)
        XCTAssertEqual(slip.bars, RoamStampSlip.bars(12345), "Same serial, same bars")
        XCTAssertNotEqual(slip.bars, RoamStampSlip.bars(12346))
        XCTAssertTrue(slip.bars.allSatisfy { [1, 2, 3].contains($0.width) && [1, 2].contains($0.gap) })
        let none = RoamStampSlip(try JSONDecoder().decode(RoamStampExchangeReceipt.self, from: Data(#"{"exchanged":false,"reason":" 暂时没有 "}"#.utf8)))
        XCTAssertFalse(none.got); XCTAssertEqual(none.reason, "暂时没有"); XCTAssertEqual(none.serial, "NO. 0000")
        XCTAssertEqual(RoamStampSlip.titleKey(kind: "sticker"), "roamSub.w208.stamp.title.sticker")
        XCTAssertEqual(RoamStampSlip.titleKey(kind: nil), "roamSub.w208.stamp.title.sign")
        XCTAssertEqual(RoamStampSlip.dateLabel(Date(timeIntervalSince1970: 1760857200), calendar: utc), "10.19")
    }

    func testMerchantChargeTypeDecodes() throws {
        struct Envelope: Decodable { let data: RoamPublicMerchant }
        let merchant = try JSONDecoder().decode(Envelope.self, from: Data(#"{"data":{"id":5,"chargeType":"1","cityRole":"Guide"}}"#.utf8)).data
        XCTAssertEqual(merchant.chargeType, 1); XCTAssertEqual(merchant.cityRole, "Guide")
        let missing = try JSONDecoder().decode(Envelope.self, from: Data(#"{"data":{"id":5}}"#.utf8)).data
        XCTAssertNil(missing.chargeType)
    }
}

private final class RoamParityTransport: HTTPTransport, @unchecked Sendable {
    let status: Int; let body: String
    init(status: Int, body: String) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(body.utf8), status) }
}
