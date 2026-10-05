import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class ProfileSessionTests: XCTestCase {
    private func makeService(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> ProfileService {
        ProfileService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: ProfileClosureTransport(operation))
    }
    private func session(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "fixture-token") throws -> ProfileReadSession {
        try ProfileReadSession(accountID: id, epoch: epoch, token: token)
    }
    func testNotConfiguredDoesNotCallCredentialProvider() async throws {
        var reads = 0
        let reader = ProfileSessionReader(service: nil, currentSession: { reads += 1; return nil })
        do { _ = try await reader.profileOrders(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(reads, 0)
    }
    func testGuestDoesNotSendAuthenticatedRead() async throws {
        var requests = 0
        let service = try makeService { _ in requests += 1; return (Data(), 500) }
        let reader = ProfileSessionReader(service: service, currentSession: { nil })
        XCTAssertNil(reader.identity)
        do { _ = try await reader.profileOrders(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(requests, 0)
    }
    func testSameAccountNewEpochDiscardsOldSuccess() async throws {
        var current: ProfileReadSession? = try session()
        let replacement = try session(1, 2)
        let service = try makeService { _ in
            current = replacement
            return (Data(#"{"code":200,"data":[{"id":7}]}"#.utf8), 200)
        }
        let reader = ProfileSessionReader(service: service, currentSession: { current })
        do { _ = try await reader.profileOrders(); XCTFail("Old account epoch result leaked") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.identity, replacement.identity)
    }
    func testAccountSwitchDiscardsOld401WithoutExpiringNewAccount() async throws {
        var current: ProfileReadSession? = try session()
        let replacement = try session(2, 2, "second-fixture-token")
        var expirations = 0
        let service = try makeService { _ in
            current = replacement
            return (Data(#"{"code":401,"msg":"Old session expired"}"#.utf8), 401)
        }
        let reader = ProfileSessionReader(service: service, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.profileParticipants(); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
        XCTAssertEqual(current, replacement)
    }
    func testTokenChangeAlsoDiscardsOldCompletion() async throws {
        var current: ProfileReadSession? = try session()
        let replacement = try session(1, 1, "replacement-fixture-token")
        let service = try makeService { _ in
            current = replacement
            return (Data(#"{"code":200,"data":{"id":7}}"#.utf8), 200)
        }
        let reader = ProfileSessionReader(service: service, currentSession: { current })
        do { _ = try await reader.profileOrder(id: 7); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testMatchingUnauthorizedExpiresExactlyCapturedSession() async throws {
        var current: ProfileReadSession? = try session()
        let original = current
        var expired: [ProfileReadSession] = []
        let service = try makeService { _ in (Data(#"{"code":401,"msg":"Sign in again"}"#.utf8), 200) }
        let reader = ProfileSessionReader(service: service, currentSession: { current }, onUnauthorized: { value in
            expired.append(value)
            if current == value { current = nil }
        })
        do { _ = try await reader.profileOrders(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [try XCTUnwrap(original)])
        XCTAssertNil(current)
    }
    func testBusinessFailureDoesNotExpireCurrentSession() async throws {
        let current = try session()
        var expirations = 0
        let service = try makeService { _ in (Data(#"{"code":403,"msg":"Unavailable"}"#.utf8), 200) }
        let reader = ProfileSessionReader(service: service, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.profileOrders(); XCTFail() }
        catch { XCTAssertEqual((error as? ProfileReadFailure)?.code, 403) }
        XCTAssertEqual(expirations, 0)
    }
    func testLogoutDuringReadDropsPrivateRecords() async throws {
        var current: ProfileReadSession? = try session()
        let service = try makeService { _ in
            current = nil
            return (Data(#"{"code":200,"data":{"rows":[{"id":7,"fullName":"Fixture"}]}}"#.utf8), 200)
        }
        let reader = ProfileSessionReader(service: service, currentSession: { current })
        do { _ = try await reader.profileParticipants(); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(reader.identity)
    }
    func testSessionInputValidation() {
        XCTAssertThrowsError(try ProfileReadSession(accountID: 0, epoch: 0, token: "fixture"))
        XCTAssertThrowsError(try ProfileReadSession(accountID: 1, epoch: 0, token: ""))
        XCTAssertThrowsError(try ProfileReadSession(accountID: 1, epoch: 0, token: "fixture\r\nheader"))
    }
}

private final class ProfileClosureTransport: HTTPTransport {
    private let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
