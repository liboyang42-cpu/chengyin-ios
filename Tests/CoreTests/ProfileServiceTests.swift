import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ProfileServiceTests: XCTestCase {
    private func service(_ transport: ProfileTestTransport) throws -> ProfileService {
        ProfileService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testOwnOrdersUseAllOwnerScopeAndRawAuthorization() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200,"data":[{"id":1,"ownerType":1},{"id":2,"ownerType":2}]}"#)])
        let result = try await service(transport).orders(token: "fixture-token")
        XCTAssertEqual(result.map(\.id), [1, 2])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/registration/list")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"owner_type\"\r\n\r\n3\r\n"))
        XCTAssertFalse(body.contains("name=\"status\""))
        XCTAssertFalse(body.contains("memberId"))
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testOrdersAlsoAcceptDataRowsEnvelope() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200,"data":{"rows":[{"id":7}]}}"#)])
        let rows = try await service(transport).orders(token: "fixture-token")
        XCTAssertEqual(rows.map(\.id), [7])
    }
    func testParticipantsUseBodylessPostAndDataRows() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200,"data":{"rows":[{"id":5,"fullName":"Fixture"}]}}"#)])
        let result = try await service(transport).participants(token: "fixture-token")
        XCTAssertEqual(result.first?.fullName, "Fixture")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/user/address/list")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.httpBody)
    }
    func testDetailRequestsUseKnownIDAndVerifyReturnedIdentity() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":200,"data":{"id":7}}"#), .json(#"{"code":200,"data":{"id":8}}"#)])
        let api = try service(transport)
        let order = try await api.order(id: 7, token: "fixture-token")
        let participant = try await api.participant(id: 8, token: "fixture-token")
        XCTAssertEqual(order.id, 7)
        XCTAssertEqual(participant.id, 8)
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["info", "info"])
        for (index, id) in [7, 8].enumerated() {
            XCTAssertTrue(String(data: transport.requests[index].httpBody!, encoding: .utf8)!.contains("name=\"id\"\r\n\r\n\(id)\r\n"))
        }
    }
    func testMismatchedDetailIDFailsClosed() async throws {
        for participant in [false, true] {
            let transport = ProfileTestTransport([.json(#"{"code":200,"data":{"id":8}}"#)])
            do {
                if participant { _ = try await service(transport).participant(id: 7, token: "fixture-token") }
                else { _ = try await service(transport).order(id: 7, token: "fixture-token") }
                XCTFail("Wrong record must not render")
            } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testInvalidIDOrCredentialNeverHitsTransport() async throws {
        let transport = ProfileTestTransport([])
        let api = try service(transport)
        do { _ = try await api.order(id: 0, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.participants(token: "\nsecret"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.badgeWall(token: ""); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testHTTPAndBusinessFailuresPreserveServerMessage() async throws {
        for reply in [ProfileTestReply.json(#"{"code":403,"msg":"Record unavailable"}"#), .json(#"{"code":503,"msg":"Service unavailable"}"#, status: 503)] {
            let transport = ProfileTestTransport([reply])
            do { _ = try await service(transport).participants(token: "fixture-token"); XCTFail() }
            catch let error as ProfileReadFailure {
                XCTAssertNotNil(error.message)
                XCTAssertEqual(error.code, reply.status == 503 ? 503 : 403)
                XCTAssertEqual(error.httpStatus, reply.status == 503 ? 503 : nil)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testMissingOrMalformedSuccessDataIsNotAnEmptySuccess() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"rows":"wrong"}}"#, #"{"code":200,"data":[{"id":0}]}"#] {
            let transport = ProfileTestTransport([.json(json)])
            do { _ = try await service(transport).orders(token: "fixture-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testBadgesUseDistinctJSONReadEndpointsAndKeepFamilies() async throws {
        let transport = ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[{"badgeCode":"ID","unlocked":false}],"growth":[{"badgeCode":"not-rendered"}]}}"#),
            .json(#"{"code":200,"data":{"count":1,"medals":[{"kind":"achievement","medalName":"Fixture medal"}]}}"#)
        ])
        let wall = try await service(transport).badgeWall(token: "fixture-token")
        XCTAssertEqual(wall.identities.count, 1)
        XCTAssertEqual(wall.medals?.count, 1)
        XCTAssertFalse(wall.isPartial)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/fixture/api/badge/wall-v2", "/fixture/api/medal/wall"])
        for request in transport.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
        }
    }
    func testMedalFailurePreservesIdentityAndReportsPartial() async throws {
        let transport = ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[{"badgeCode":"ID"}]}}"#),
            .json(#"{"code":500,"msg":"Medals temporarily unavailable"}"#)
        ])
        let wall = try await service(transport).badgeWall(token: "fixture-token")
        XCTAssertEqual(wall.identities.count, 1)
        XCTAssertNil(wall.medals)
        XCTAssertTrue(wall.isPartial)
        XCTAssertEqual(wall.medalFailureMessage, "Medals temporarily unavailable")
    }
    func testIdentityFailureDoesNotPresentMedalsAsCompleteWall() async throws {
        let transport = ProfileTestTransport([.json(#"{"code":500,"msg":"Identity unavailable"}"#)])
        do { _ = try await service(transport).badgeWall(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual((error as? ProfileReadFailure)?.code, 500) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnauthorizedMedalsCannotBecomePartialSuccess() async throws {
        for status in [200, 401] {
            let transport = ProfileTestTransport([
                .json(#"{"code":200,"data":{"identity":[]}}"#),
                .json(#"{"code":401,"msg":"Sign in again"}"#, status: status)
            ])
            do { _ = try await service(transport).badgeWall(token: "fixture-token"); XCTFail() }
            catch { XCTAssertTrue((error as? ProfileReadFailure)?.isUnauthorized == true) }
        }
    }
    func testCancelledMedalReadDoesNotBecomePartialSuccess() async throws {
        let transport = ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[]}}"#), .failure(CancellationError())
        ])
        do { _ = try await service(transport).badgeWall(token: "fixture-token"); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testPlatformWallKeepsServerScopeWithoutClubBackfill() async throws {
        // BK-BADGE: the platform wall drops unowned club_id definitions; owned club rows still arrive
        // from the server. The client renders exactly those rows and never queries a club scope to pad counts.
        let transport = ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[{"badgeCode":"PLATFORM-ID","unlocked":false},{"badgeCode":"OWNED-CLUB-ID","unlocked":true,"unlockTime":"2026-10-01 09:00:00"}],"growth":[{"badgeCode":"CLUB-GROWTH"}]}}"#),
            .json(#"{"code":200,"data":{"count":0,"medals":[]}}"#)
        ])
        let wall = try await service(transport).badgeWall(token: "fixture-token")
        XCTAssertEqual(wall.identities.map(\.badgeCode), ["PLATFORM-ID", "OWNED-CLUB-ID"])
        XCTAssertEqual(wall.identities.map(\.unlocked), [false, true])
        XCTAssertEqual(wall.medals, []); XCTAssertFalse(wall.isEmpty); XCTAssertFalse(wall.isPartial)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/fixture/api/badge/wall-v2", "/fixture/api/medal/wall"])
    }
    func testEmptyDeniedAndFailedWallsRemainDistinct() async throws {
        let empty = try await service(ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[]}}"#), .json(#"{"code":200,"data":{"medals":[]}}"#)
        ])).badgeWall(token: "fixture-token")
        XCTAssertTrue(empty.isEmpty); XCTAssertFalse(empty.isPartial)
        // A refused medal read keeps the established identity cards as a partial wall.
        let deniedMedals = try await service(ProfileTestTransport([
            .json(#"{"code":200,"data":{"identity":[{"badgeCode":"ID","unlocked":true}]}}"#),
            .json(#"{"code":403,"msg":"Not visible"}"#, status: 403)
        ])).badgeWall(token: "fixture-token")
        XCTAssertEqual(deniedMedals.identities.map(\.badgeCode), ["ID"])
        XCTAssertTrue(deniedMedals.isPartial); XCTAssertFalse(deniedMedals.isEmpty)
        for reply in [ProfileTestReply.json(#"{"code":403,"msg":"Not visible"}"#, status: 403), .json(#"{"code":403,"msg":"Not visible"}"#)] {
            do { _ = try await service(ProfileTestTransport([reply])).badgeWall(token: "fixture-token"); XCTFail() }
            catch {
                let failure = try XCTUnwrap(error as? ProfileReadFailure)
                XCTAssertTrue(failure.isDenied); XCTAssertFalse(failure.isUnauthorized)
            }
        }
        for failure in [ProfileReadFailure(httpStatus: 401), ProfileReadFailure(code: 401), ProfileReadFailure(httpStatus: 500, code: 500)] {
            XCTAssertFalse(failure.isDenied)
        }
    }
    @MainActor func testBadgeWallReadIsNotCarriedAcrossAccounts() async throws {
        let transport = ProfileSuspendedTransport()
        let first = try ProfileReadSession(accountID: 31, epoch: 1, token: "fixture-token-a")
        let second = try ProfileReadSession(accountID: 32, epoch: 2, token: "fixture-token-b")
        var current: ProfileReadSession? = first
        var unauthorized: [Int] = []
        let service = ProfileService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
        let reader = ProfileSessionReader(service: service, currentSession: { current },
                                          onUnauthorized: { unauthorized.append($0.identity.accountID) })
        let stale = Task { try await reader.profileBadges() }
        await transport.waitForRequests(1)
        current = second
        await transport.reply(#"{"code":200,"data":{"identity":[{"badgeCode":"ACCOUNT-A","unlocked":true}]}}"#)
        await transport.waitForRequests(2)
        await transport.reply(#"{"code":200,"data":{"medals":[]}}"#)
        do { _ = try await stale.value; XCTFail("Account A's wall must not surface under account B") }
        catch { XCTAssertTrue(error is CancellationError) }
        let fresh = Task { try await reader.profileBadges() }
        await transport.waitForRequests(3)
        await transport.reply(#"{"code":200,"data":{"identity":[{"badgeCode":"ACCOUNT-B","unlocked":false}]}}"#)
        await transport.waitForRequests(4)
        await transport.reply(#"{"code":200,"data":{"medals":[]}}"#)
        let wall = try await fresh.value
        XCTAssertEqual(wall.identities.map(\.badgeCode), ["ACCOUNT-B"])
        let tokens = await transport.tokens
        XCTAssertEqual(tokens, ["fixture-token-a", "fixture-token-a", "fixture-token-b", "fixture-token-b"])
        XCTAssertTrue(unauthorized.isEmpty)
    }
}

private actor ProfileSuspendedTransport: HTTPTransport {
    private var pending: [CheckedContinuation<(Data, Int), Error>] = []
    private(set) var tokens: [String] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        tokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func waitForRequests(_ count: Int) async { while tokens.count < count || pending.isEmpty { await Task.yield() } }
    func reply(_ json: String) { pending.removeFirst().resume(returning: (Data(json.utf8), 200)) }
}

struct ProfileTestReply {
    let data: Data
    let status: Int
    let error: Error?
    static func json(_ value: String, status: Int = 200) -> Self { Self(data: Data(value.utf8), status: status, error: nil) }
    static func failure(_ error: Error) -> Self { Self(data: Data(), status: 0, error: error) }
}
final class ProfileTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var replies: [ProfileTestReply]
    init(_ replies: [ProfileTestReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        let reply = replies.removeFirst()
        if let error = reply.error { throw error }
        return (reply.data, reply.status)
    }
}
