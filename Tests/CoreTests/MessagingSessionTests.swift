import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class MessagingSessionTests: XCTestCase {
    private func service(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> MessagingService {
        MessagingService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: MessagingClosureTransport(operation))
    }
    private func session(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "synthetic-token") throws -> MessagingReadSession {
        try MessagingReadSession(accountID: id, epoch: epoch, token: token)
    }
    func testUnconfiguredAndGuestHaveNoCredentialOrNetworkSideEffects() async throws {
        var credentialReads = 0, requests = 0
        let missing = MessagingSessionReader(service: nil, currentSession: { credentialReads += 1; return nil })
        do { _ = try await missing.messagingConversations(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(credentialReads, 0)
        let api = try service { _ in requests += 1; return (Data(), 200) }
        let guest = MessagingSessionReader(service: api, currentSession: { nil })
        do { _ = try await guest.messagingMessages(conversationID: 9, cursor: 0); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(requests, 0)
    }
    func testSameAccountReloginDiscardsPreviousTranscript() async throws {
        var current: MessagingReadSession? = try session()
        let replacement = try session(1, 2)
        let api = try service { _ in
            current = replacement
            return (Data(#"{"code":200,"data":{"list":[{"id":10,"conversationId":9}],"hasMore":false}}"#.utf8), 200)
        }
        let reader = MessagingSessionReader(service: api, currentSession: { current })
        do { _ = try await reader.messagingMessages(conversationID: 9, cursor: 0); XCTFail("Stale transcript leaked") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.identity, replacement.identity)
    }
    func testChangedTokenDiscardsOldCompletionEvenWithSameAccountAndEpoch() async throws {
        var current: MessagingReadSession? = try session()
        let replacement = try session(1, 1, "replacement-synthetic-token")
        let api = try service { _ in current = replacement; return (Data(#"{"code":200,"data":[]}"#.utf8), 200) }
        let reader = MessagingSessionReader(service: api, currentSession: { current })
        do { _ = try await reader.messagingConversations(); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testLogoutDropsPrivateConversationList() async throws {
        var current: MessagingReadSession? = try session()
        let api = try service { _ in
            current = nil
            return (Data(#"{"code":200,"data":[{"conversationId":9,"lastMsgText":"Synthetic private text"}]}"#.utf8), 200)
        }
        let reader = MessagingSessionReader(service: api, currentSession: { current })
        do { _ = try await reader.messagingConversations(); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(reader.identity)
    }
    func testStale401CannotExpireReplacementAccount() async throws {
        for status in [200, 401] {
            var current: MessagingReadSession? = try session()
            let replacement = try session(2, 2, "replacement-synthetic-token")
            var expirations = 0
            let api = try service { _ in
                current = replacement
                return (Data(#"{"code":401,"msg":"Old session expired"}"#.utf8), status)
            }
            let reader = MessagingSessionReader(service: api, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
            do { _ = try await reader.messagingConversations(); XCTFail() }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expirations, 0)
            XCTAssertEqual(current, replacement)
        }
    }
    func testMatching401ExpiresOnlyCapturedSession() async throws {
        var current: MessagingReadSession? = try session()
        let original = try XCTUnwrap(current)
        var expired: [MessagingReadSession] = []
        let api = try service { _ in (Data(#"{"code":401}"#.utf8), 401) }
        let reader = MessagingSessionReader(service: api, currentSession: { current }, onUnauthorized: { snapshot in
            expired.append(snapshot)
            if current == snapshot { current = nil }
        })
        do { _ = try await reader.messagingMessages(conversationID: 9, cursor: 0); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [original])
        XCTAssertNil(current)
    }
    func testClosedAndOrdinaryServerFailuresDoNotExpireSession() async throws {
        for code in ["HANGOUT_CLOSED", "OTHER"] {
            let current = try session()
            var expirations = 0
            let api = try service { _ in (Data("{\"code\":409,\"errorCode\":\"\(code)\"}".utf8), 200) }
            let reader = MessagingSessionReader(service: api, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
            do { _ = try await reader.messagingMessages(conversationID: 9, cursor: 42); XCTFail() }
            catch let failure as MessagingReadFailure { XCTAssertEqual(failure.errorCode, code) }
            XCTAssertEqual(expirations, 0)
        }
    }
    func testCancellationIgnoringTransportCannotReturnPrivateDataOrExpireSession() async throws {
        let current = try session()
        for unauthorized in [false, true] {
            var expirations = 0
            let api = try service { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return (Data((unauthorized ? #"{"code":401}"# : #"{"code":200,"data":[]}"#).utf8), unauthorized ? 401 : 200)
            }
            let reader = MessagingSessionReader(service: api, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
            let task = Task { @MainActor in try await reader.messagingConversations() }
            do { _ = try await task.value; XCTFail() }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expirations, 0)
        }
    }
    func testInvalidSessionInputsFailBeforeUse() {
        XCTAssertThrowsError(try session(0))
        XCTAssertThrowsError(try session(1, 1, ""))
        XCTAssertThrowsError(try session(1, 1, "bad\nheader"))
    }
}

private final class MessagingClosureTransport: HTTPTransport {
    private let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
