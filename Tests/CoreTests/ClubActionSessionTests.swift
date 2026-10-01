import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class ClubActionSessionTests: XCTestCase {
    private func session(id: Int = 1, epoch: UInt64 = 1, token: String = "fixture-token", role: String = "player") throws -> ClubActionSession {
        let account = try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: ["id": id, "role": role]))
        return try ClubActionSession(account: account, epoch: epoch, token: token)
    }
    private func service(_ body: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> ClubActionService {
        ClubActionService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: ClubActionClosureTransport(body))
    }
    func testUnconfiguredGuestAndWrongEpochNeverReadOrWrite() async throws {
        let expected = ClubReadIdentity(accountID: 1, epoch: 1)
        let unavailable = ClubActionSessionWriter(service: nil, currentSession: { nil })
        do { _ = try await unavailable.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.notConfigured)) }
        var calls = 0
        let service = try service { _ in calls += 1; return (Data(#"{"code":200}"#.utf8), 200) }
        for snapshot in [nil, try session(id: 2), try session(epoch: 2)] as [ClubActionSession?] {
            let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.unauthorized)) }
        }
        XCTAssertEqual(calls, 0)
    }
    func testFreshDetailPrecedesEveryMembershipWrite() async throws {
        let snapshot = try session()
        var paths: [String] = []
        let service = try service { request in
            paths.append(request.url!.path)
            let json = paths.count == 1 ? #"{"code":200,"data":{"id":7,"joinPolicy":1}}"# : #"{"code":200,"data":{"state":"pending"}}"#
            return (Data(json.utf8), 200)
        }
        let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
        let receipt = try await writer.perform(.apply, clubID: 7, expectedIdentity: snapshot.identity)
        XCTAssertEqual(receipt.state, "pending")
        XCTAssertEqual(paths, ["/fixture/api/club/detail", "/fixture/api/club/join"])
    }
    func testNewOwnerPendingMemberOrApprovalPolicyNeverDispatchesStaleJoin() async throws {
        let snapshot = try session()
        for fields in ["\"isOwner\":true", "\"isJoined\":true", "\"myJoinStatus\":0", "\"joinPolicy\":1", "\"myJoinStatus\":9"] {
            var calls = 0
            let service = try service { _ in calls += 1; return (Data("{\"code\":200,\"data\":{\"id\":7,\(fields)}}".utf8), 200) }
            let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: snapshot.identity); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .eligibilityChanged) }
            XCTAssertEqual(calls, 1)
        }
    }
    func testMerchantCannotJoinButExistingMerchantMemberCanLeave() async throws {
        let snapshot = try session(role: "merchant")
        var calls = 0, joined = false
        let service = try service { _ in
            calls += 1
            return (Data("{\"code\":200,\"data\":{\"id\":7,\"isJoined\":\(joined)}}".utf8), 200)
        }
        let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
        do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: snapshot.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .eligibilityChanged) }
        XCTAssertEqual(calls, 1)
        joined = true
        _ = try await writer.perform(.leave, clubID: 7, expectedIdentity: snapshot.identity)
        XCTAssertEqual(calls, 3)
    }
    func testOwnerCannotLeaveEvenWhenJoinedOrAdministrator() async throws {
        let snapshot = try session()
        var calls = 0
        let service = try service { _ in calls += 1; return (Data(#"{"code":200,"data":{"id":7,"isOwner":true,"isJoined":true,"viewerIsAdmin":true}}"#.utf8), 200) }
        let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
        do { _ = try await writer.perform(.leave, clubID: 7, expectedIdentity: snapshot.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .eligibilityChanged) }
        XCTAssertEqual(calls, 1)
    }
    func testAccountEpochTokenAndLogoutDuringPreflightNeverMutate() async throws {
        for replacement in [nil, try session(id: 2), try session(epoch: 2), try session(token: "new-token")] as [ClubActionSession?] {
            var current: ClubActionSession? = try session()
            let expected = current!.identity
            var calls = 0, expired = 0
            let service = try service { _ in
                calls += 1; current = replacement
                return (Data(#"{"code":200,"data":{"id":7}}"#.utf8), 200)
            }
            let writer = ClubActionSessionWriter(service: service, currentSession: { current }, onUnauthorized: { _ in expired += 1 })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.unauthorized)) }
            XCTAssertEqual(calls, 1); XCTAssertEqual(expired, 0)
        }
    }
    func testAccountEpochTokenAndLogoutAfterDispatchAreUnknown() async throws {
        for replacement in [nil, try session(id: 2), try session(epoch: 2), try session(token: "new-token")] as [ClubActionSession?] {
            var current: ClubActionSession? = try session()
            let expected = current!.identity
            var calls = 0, expired = 0
            let service = try service { _ in
                calls += 1
                if calls == 1 { return (Data(#"{"code":200,"data":{"id":7}}"#.utf8), 200) }
                current = replacement
                return (Data(#"{"code":401,"msg":"Old session"}"#.utf8), 401)
            }
            let writer = ClubActionSessionWriter(service: service, currentSession: { current }, onUnauthorized: { _ in expired += 1 })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.accountChanged)) }
            XCTAssertEqual(calls, 2); XCTAssertEqual(expired, 0)
        }
    }
    func testPreflightAuthFailureExpiresOnlyMatchingSnapshot() async throws {
        var current: ClubActionSession? = try session()
        let original = current!
        var expired: [ClubActionSession] = []
        let service = try service { _ in (Data(#"{"code":401}"#.utf8), 200) }
        let writer = ClubActionSessionWriter(service: service, currentSession: { current }, onUnauthorized: { value in
            expired.append(value); if value == current { current = nil }
        })
        do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: original.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .preflightFailed) }
        XCTAssertEqual(expired, [original]); XCTAssertNil(current)
    }
    func testMatchingMutation401ExpiresOnlyCapturedSession() async throws {
        var current: ClubActionSession? = try session()
        let original = current!
        var calls = 0, expired: [ClubActionSession] = []
        let service = try service { _ in
            calls += 1
            if calls == 1 { return (Data(#"{"code":200,"data":{"id":7}}"#.utf8), 200) }
            return (Data(#"{"code":401,"msg":"Expired"}"#.utf8), 200)
        }
        let writer = ClubActionSessionWriter(service: service, currentSession: { current }, onUnauthorized: { value in
            expired.append(value); if value == current { current = nil }
        })
        do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: original.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .rejected(.init(code: 401, message: "Expired"))) }
        XCTAssertEqual(calls, 2); XCTAssertEqual(expired, [original]); XCTAssertNil(current)
    }
    func testWrongClubIDAndReadFailureNeverDispatch() async throws {
        let snapshot = try session()
        for json in [#"{"code":200,"data":{"id":8}}"#, #"{"code":403,"msg":"Denied"}"#, "malformed"] {
            var calls = 0
            let service = try service { _ in calls += 1; return (Data(json.utf8), 200) }
            let writer = ClubActionSessionWriter(service: service, currentSession: { snapshot })
            do { _ = try await writer.perform(.join, clubID: 7, expectedIdentity: snapshot.identity); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .preflightFailed) }
            XCTAssertEqual(calls, 1)
        }
    }
    func testSessionRejectsBadAccountAndHeaderAndUsesVerifiedRole() throws {
        XCTAssertThrowsError(try session(id: 0))
        XCTAssertThrowsError(try session(token: ""))
        XCTAssertThrowsError(try session(token: "bad\r\nheader"))
        XCTAssertTrue(try session(role: "merchant").viewerIsMerchant)
        XCTAssertFalse(try session(role: "player").viewerIsMerchant)
    }
}

private final class ClubActionClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
