import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor MemberHomeWire: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(json.utf8), status)
    }
}

@MainActor final class MemberHomeTests: XCTestCase {
    private let base = URL(string: "https://member.example/native")!
    private func service(_ wire: any HTTPTransport) throws -> MemberHomeService {
        .init(configuration: try APIConfiguration(baseURL: base), transport: wire)
    }
    private func identity(_ json: String) throws -> MemberIdentitySnapshot {
        try JSONDecoder().decode(MemberIdentitySnapshot.self, from: Data(json.utf8))
    }

    func testIdentityMapsSourceHeaderFieldsAndJoinDate() throws {
        let value = try identity(#"{"id":7,"nickname":"Synthetic","avatar":"https://cdn.example/a.png","role":"player","levelId":3,"city":"上海","friendNum":2,"followNum":"5","fansNum":9,"topicNum":0,"activityNum":1,"likeNum":4,"balance":12.5,"createTime":"2026-03-04 10:00:00","introduction":" 慢慢走 ","sysCategoryList":[{"categoryName":"骑行"},{"categoryName":" "}],"casePics":"https://cdn.example/1.png; ;https://cdn.example/2.png"}"#)
        XCTAssertEqual(value.nickname, "Synthetic"); XCTAssertEqual(value.city, "上海"); XCTAssertEqual(value.levelID, 3)
        XCTAssertEqual([value.friendCount, value.followCount, value.fansCount], [2, 5, 9])
        XCTAssertTrue(value.countersReady)
        XCTAssertEqual(value.balanceText, "12.50"); XCTAssertEqual(value.joinDate, "2026.03.04")
        XCTAssertEqual(value.introduction, "慢慢走"); XCTAssertEqual(value.interests, ["骑行"])
        XCTAssertEqual(value.casePictures.count, 2)
    }
    func testMissingCountersAreDisplayZeroButNotReadyAndBalanceIsNeverInvented() throws {
        let value = try identity(#"{"nickname":"","followNum":-1,"fansNum":"x","balance":null}"#)
        XCTAssertEqual([value.friendCount, value.followCount, value.fansCount], [0, 0, 0])
        XCTAssertFalse(value.countersReady)
        XCTAssertNil(value.balanceText); XCTAssertNil(value.joinDate); XCTAssertEqual(value.city, "")
        XCTAssertNil(try identity(#"{"balance":"abc"}"#).balanceText)
        XCTAssertEqual(try identity(#"{"balance":"0"}"#).balanceText, "0.00")
    }
    func testBenefitsFollowBuildBenefitsExactly() throws {
        let unlimited = MemberBenefit.rows(for: .init())
        XCTAssertEqual(unlimited.map(\.kind), MemberBenefit.Kind.allCases)
        XCTAssertEqual(unlimited.first?.routeLimit, .unlimited); XCTAssertEqual(unlimited.first?.unlocked, true)
        XCTAssertEqual(unlimited.dropFirst().filter(\.unlocked).count, 0)
        let zero = MemberBenefit.rows(for: .init(maxThemes: 0, canBranch: true, withdrawable: true))
        XCTAssertEqual(zero[0].routeLimit, .limited(0)); XCTAssertFalse(zero[0].unlocked)
        XCTAssertTrue(zero.first { $0.kind == .branching }!.unlocked)
        XCTAssertTrue(zero.last!.opensEarnings)
        XCTAssertFalse(unlimited.last!.opensEarnings)
    }
    func testRoleInfoOnlyExplicitTrueUnlocksAndRoleIsRequired() throws {
        let json = #"{"role":"merchant","isClubLeader":false,"ownedClubs":[{"id":1},{"id":2}],"permission":{"maxThemes":3,"canPublishCoupon":true,"canRedeemCoupon":"true","withdrawable":1}}"#
        let info = try JSONDecoder().decode(MemberRoleInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.role, "merchant"); XCTAssertEqual(info.ownedClubCount, 2); XCTAssertFalse(info.isClubLeader)
        let unlocked = info.benefits.filter(\.unlocked).map(\.kind)
        XCTAssertEqual(unlocked, [.publishRoutes, .publishCoupons])
        XCTAssertEqual(info.benefits[0].routeLimit, .limited(3))
        XCTAssertTrue(try JSONDecoder().decode(MemberRoleInfo.self, from: Data(#"{"role":"club"}"#.utf8)).isClubLeader)
        for bad in ["{}", #"{"role":""}"#, #"{"role":null}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MemberRoleInfo.self, from: Data(bad.utf8)), bad)
        }
    }
    func testIdentityReadIsTheBodylessSessionUserInfoRequest() async throws {
        let wire = MemberHomeWire(#"{"code":200,"data":{"nickname":"Synthetic"}}"#)
        let configuration = try APIConfiguration(baseURL: base)
        _ = try await service(wire).identity(token: "synthetic-member")
        let requests = await wire.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, configuration.url(for: .userInfo)); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(CNAccountSessionService.accepts(request, configuration: configuration))
    }
    func testRoleInfoRequestMatchesItsExactRoute() async throws {
        let wire = MemberHomeWire(#"{"code":200,"data":{"role":"player","permission":{}}}"#)
        let info = try await service(wire).roleInfo(token: "synthetic-member")
        XCTAssertEqual(info.role, "player")
        let requests = await wire.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, base.appendingPathComponent(MemberRoleInfoReadRoute.path))
        XCTAssertTrue(MemberRoleInfoReadRoute.accepts(request, baseURL: base))
        var query = request; query.url = URL(string: request.url!.absoluteString + "?role=club")
        var body = request; body.httpBody = Data("x".utf8)
        var get = request; get.httpMethod = "GET"
        var anonymous = request; anonymous.setValue(nil, forHTTPHeaderField: "Authorization")
        for candidate in [query, body, get, anonymous] { XCTAssertFalse(MemberRoleInfoReadRoute.accepts(candidate, baseURL: base)) }
        XCTAssertFalse(MemberRoleInfoReadRoute.accepts(request, baseURL: URL(string: "https://other.example/native")!))
    }
    func testAuthFailuresAndRejectionsAreDistinct() async throws {
        for wire in [MemberHomeWire("{}", status: 401), MemberHomeWire(#"{"code":401}"#), MemberHomeWire(#"{"code":2}"#)] {
            do { _ = try await service(wire).identity(token: "synthetic-member"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
        do { _ = try await service(MemberHomeWire(#"{"code":500,"msg":"当前身份权限配置缺失"}"#)).roleInfo(token: "synthetic-member"); XCTFail() }
        catch { XCTAssertEqual(error as? MemberHomeReadFailure, .rejected(code: 500, message: "当前身份权限配置缺失")) }
        do { _ = try await service(MemberHomeWire(#"{"code":200,"data":[]}"#)).identity(token: "synthetic-member"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testReaderNeverReadsRoleInfoWithoutApprovalAndFencesSessionChanges() async throws {
        let wire = MemberHomeWire(#"{"code":200,"data":{"role":"player"}}"#)
        var session = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-member", roleInfoApproval: nil)
        var expired = 0
        let reader = MemberHomeSessionReader(service: try service(wire), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        XCTAssertFalse(reader.roleInfoAvailable)
        do { _ = try await reader.roleInfo(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let none = await wire.requests.count; XCTAssertEqual(none, 0)
        let firstScope = reader.scope
        session = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-member", roleInfoApproval: UUID())
        XCTAssertTrue(reader.roleInfoAvailable); XCTAssertNotEqual(reader.scope, firstScope)
        _ = try await reader.roleInfo()
        let one = await wire.requests.count; XCTAssertEqual(one, 1)
        let unauthorized = MemberHomeSessionReader(service: try service(MemberHomeWire("{}", status: 401)), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await unauthorized.identity(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, 1)
        let guest = MemberHomeSessionReader(service: try service(wire), currentSession: { nil })
        XCTAssertFalse(guest.isSignedIn)
        do { _ = try await guest.identity(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
