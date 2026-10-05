import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class ClubSessionTests: XCTestCase {
    private func session(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "fixture-token") throws -> ClubReadSession {
        try ClubReadSession(accountID: id, epoch: epoch, token: token)
    }
    private func service(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> ClubService {
        try ClubService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: ClubClosureTransport(operation))
    }
    func testNoConfigurationDoesNotReadCredentialSnapshot() async throws {
        var snapshots = 0
        let reader = ClubSessionReader(service: nil, currentSession: { snapshots += 1; return ClubReadSession(guestEpoch: 0) })
        do { _ = try await reader.clubHome(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(snapshots, 0)
    }
    func testGuestOwnedAndMembersRequireSignInWithoutTransportOrExpiration() async throws {
        var requests = 0, expirations = 0
        let s = try service { _ in requests += 1; return (Data(), 500) }
        let reader = ClubSessionReader(service: s, currentSession: { .init(guestEpoch: 1) }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.clubOwned(); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .unauthorized(message: nil)) }
        do { _ = try await reader.clubMembers(id: 7); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .unauthorized(message: nil)) }
        XCTAssertEqual(requests, 0); XCTAssertEqual(expirations, 0)
    }
    func testGuestDirectoryUsesNoTokenAndDoesNotExpireAnAccountOn401() async throws {
        var expirations = 0
        let s = try service { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (Data(#"{"code":401,"msg":"Sign in"}"#.utf8), 200)
        }
        let reader = ClubSessionReader(service: s, currentSession: { .init(guestEpoch: 1) }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.clubDirectory(name: nil); XCTFail() }
        catch { XCTAssertTrue((error as? ClubReadFailure)?.isUnauthorized == true) }
        XCTAssertEqual(expirations, 0)
    }
    func testSameAccountNewEpochDiscardsOldHome() async throws {
        var current = try session()
        let replacement = try session(1, 2)
        let s = try service { _ in current = replacement; return (Data(#"{"code":200,"data":{"owned":[{"id":7}]}}"#.utf8), 200) }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubHome(); XCTFail("Old epoch leaked") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testTokenReplacementDiscardsOldDirectoryEvenWithoutEpochChange() async throws {
        var current = try session()
        let replacement = try session(1, 1, "second-fixture-token")
        let s = try service { _ in current = replacement; return (Data(#"{"code":200,"data":[{"id":7}]}"#.utf8), 200) }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubDirectory(name: nil); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testLogoutDiscardsOldDetail() async throws {
        var current = try session()
        let s = try service { _ in current = .init(guestEpoch: 2); return (Data(#"{"code":200,"data":{"id":7}}"#.utf8), 200) }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubDetail(id: 7); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(reader.clubIdentity.isSignedIn)
    }
    func testOld401CannotExpireReplacementAccount() async throws {
        var current = try session()
        let replacement = try session(2, 2, "second-fixture-token")
        var expirations = 0
        let s = try service { _ in current = replacement; return (Data(#"{"code":401}"#.utf8), 401) }
        let reader = ClubSessionReader(service: s, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.clubOwned(); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0); XCTAssertEqual(current, replacement)
    }
    func testMatching401ExpiresExactlyTheCapturedSession() async throws {
        var current = try session()
        let original = current
        var expired: [ClubReadSession] = []
        let s = try service { _ in (Data(#"{"code":401,"msg":"Server expiry"}"#.utf8), 200) }
        let reader = ClubSessionReader(service: s, currentSession: { current }, onUnauthorized: { snapshot in
            expired.append(snapshot)
            if current == snapshot { current = .init(guestEpoch: 2) }
        })
        do { _ = try await reader.clubOwned(); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .unauthorized(message: "Server expiry")) }
        XCTAssertEqual(expired, [original]); XCTAssertFalse(current.identity.isSignedIn)
    }
    func test403DoesNotExpireTheCurrentSession() async throws {
        let current = try session()
        var expirations = 0
        let s = try service { _ in (Data(#"{"code":403}"#.utf8), 200) }
        let reader = ClubSessionReader(service: s, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.clubHome(); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .forbidden(message: nil)) }
        XCTAssertEqual(expirations, 0)
    }
    func testMemberListFetchesFreshDetailThenMembersWithSameCredential() async throws {
        let current = try session()
        var paths: [String] = []
        let s = try service { request in
            let path = request.url!.path; paths.append(path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
            return (Data((path.hasSuffix("detail") ? #"{"code":200,"data":{"id":7,"isJoined":true,"memberCount":1}}"# : #"{"code":200,"data":[{"memberId":9}]}"#).utf8), 200)
        }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        let value = try await reader.clubMembers(id: 7)
        XCTAssertEqual(paths, ["/fixture/api/club/detail", "/fixture/api/club/members"])
        XCTAssertEqual(value.members.first?.memberId, 9); XCTAssertEqual(value.club.id, 7)
    }
    func testAccountSwitchBetweenMemberReadsPreventsSecondRequest() async throws {
        var current = try session()
        var requests = 0
        let replacement = try session(2, 2, "second-fixture-token")
        let s = try service { _ in
            requests += 1; current = replacement
            return (Data(#"{"code":200,"data":{"id":7,"isOwner":true}}"#.utf8), 200)
        }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubMembers(id: 7); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(requests, 1)
    }
    func testMembershipRevocationPreventsMemberRequest() async throws {
        let current = try session()
        var requests = 0
        let s = try service { _ in
            requests += 1
            return (Data(#"{"code":200,"data":{"id":7,"isJoined":false,"viewerIsAdmin":true}}"#.utf8), 200)
        }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubMembers(id: 7); XCTFail() }
        catch { XCTAssertEqual(error as? ClubReadFailure, .membershipRequired) }
        XCTAssertEqual(requests, 1)
    }
    func testLogoutDuringMembersDiscardsReturnedRows() async throws {
        var current = try session()
        var requests = 0
        let s = try service { request in
            requests += 1
            if request.url!.path.hasSuffix("detail") {
                return (Data(#"{"code":200,"data":{"id":7,"isOwner":true}}"#.utf8), 200)
            }
            current = .init(guestEpoch: 2)
            return (Data(#"{"code":200,"data":[{"memberId":9,"nickname":"Private row"}]}"#.utf8), 200)
        }
        let reader = ClubSessionReader(service: s, currentSession: { current })
        do { _ = try await reader.clubMembers(id: 7); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(requests, 2)
    }
    func testInvalidSessionCredentialsAreRejected() {
        XCTAssertThrowsError(try session(0))
        XCTAssertThrowsError(try session(1, 1, ""))
        XCTAssertThrowsError(try session(1, 1, "unsafe\r\nheader"))
        XCTAssertFalse(ClubReadSession(guestEpoch: 1).identity.isSignedIn)
    }
}

private final class ClubClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
