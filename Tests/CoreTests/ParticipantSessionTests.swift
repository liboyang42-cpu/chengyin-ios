import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor
final class ParticipantSessionTests: XCTestCase {
    private func session(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "fixture-token") throws -> ParticipantWriteSession {
        try ParticipantWriteSession(accountID: id, epoch: epoch, token: token)
    }
    private func service(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> ParticipantService {
        ParticipantService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
                           transport: ParticipantClosureTransport(operation))
    }
    func testUnconfiguredGuestAndStaleExpectedIdentityDoNotDispatch() async throws {
        var providerCalls = 0
        let expected = ProfileReadIdentity(accountID: 1, epoch: 1)
        let absent = ParticipantSessionWriter(service: nil, currentSession: { providerCalls += 1; return nil })
        do { try await absent.perform(.delete(id: 7), expectedIdentity: expected); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .notSent(.notConfigured)) }
        XCTAssertEqual(providerCalls, 0)
        var calls = 0
        let service = try service { _ in calls += 1; return (Data(#"{"code":200}"#.utf8), 200) }
        for current in [nil, try session(2), try session(1, 2)] as [ParticipantWriteSession?] {
            let writer = ParticipantSessionWriter(service: service, currentSession: { current })
            do { try await writer.perform(.delete(id: 7), expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ParticipantWriteError, .notSent(.unauthorized)) }
        }
        XCTAssertEqual(calls, 0)
    }
    func testAccountEpochAndTokenReplacementDuringResponseRemainUnknown() async throws {
        for replacement in [try session(2), try session(1, 2), try session(1, 1, "replacement-token")] {
            var current: ParticipantWriteSession? = try session()
            let expected = current!.identity
            var calls = 0
            let service = try service { _ in
                calls += 1; current = replacement
                return (Data(#"{"code":200}"#.utf8), 200)
            }
            let writer = ParticipantSessionWriter(service: service, currentSession: { current })
            do { try await writer.perform(.save(participantDraftFixture()), expectedIdentity: expected); XCTFail() }
            catch { XCTAssertEqual(error as? ParticipantWriteError, .outcomeUnknown(.accountChanged)) }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(current, replacement)
        }
    }
    func testStale401CannotExpireNewAccount() async throws {
        var current: ParticipantWriteSession? = try session()
        let expected = current!.identity
        let replacement = try session(2, 2)
        var expired = 0
        let service = try service { _ in
            current = replacement
            return (Data(#"{"code":401,"msg":"Old session"}"#.utf8), 401)
        }
        let writer = ParticipantSessionWriter(service: service, currentSession: { current }, onUnauthorized: { _ in expired += 1 })
        do { try await writer.perform(.delete(id: 7), expectedIdentity: expected); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .outcomeUnknown(.accountChanged)) }
        XCTAssertEqual(expired, 0)
        XCTAssertEqual(current, replacement)
    }
    func testMatchingUnauthorizedCallbackUsesCapturedSessionOnly() async throws {
        var current: ParticipantWriteSession? = try session()
        let original = current!
        var expired: [ParticipantWriteSession] = []
        let service = try service { _ in (Data(#"{"code":401,"msg":"Expired"}"#.utf8), 200) }
        let writer = ParticipantSessionWriter(service: service, currentSession: { current }, onUnauthorized: { value in
            expired.append(value)
            if value == current { current = nil }
        })
        do { try await writer.perform(.delete(id: 7), expectedIdentity: original.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .rejected(.init(code: 401, message: "Expired"))) }
        XCTAssertEqual(expired, [original])
        XCTAssertNil(current)
    }
    func testLogoutDuringDispatchCannotDeliverPrivateResult() async throws {
        var current: ParticipantWriteSession? = try session()
        let expected = current!.identity
        let service = try service { _ in
            current = nil
            return (Data(#"{"code":200}"#.utf8), 200)
        }
        let writer = ParticipantSessionWriter(service: service, currentSession: { current })
        do { try await writer.perform(.delete(id: 7), expectedIdentity: expected); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .outcomeUnknown(.accountChanged)) }
    }
    func testSessionRejectsInvalidIdentityAndHeaderInjection() {
        XCTAssertThrowsError(try session(0))
        XCTAssertThrowsError(try session(1, 1, ""))
        XCTAssertThrowsError(try session(1, 1, "token\r\nHeader"))
    }
}

private final class ParticipantClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
