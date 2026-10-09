import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WorkspaceRequestTransport: HTTPTransport {
    var replies: [(String, Int)] = []
    var requests: [URLRequest] = []
    var onRequest: ((Int) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onRequest?(requests.count)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst(); return (Data(reply.0.utf8), reply.1)
    }
    func append(_ payload: String) { replies.append(("{\"code\":200,\"data\":" + payload + "}", 200)) }
}
@MainActor final class MerchantProjectWorkspaceScopeTests: XCTestCase {
    private final class Session {
        var value: MerchantContentSession? = try? .init(accountID: 902, epoch: 1, storageScope: "fixture://workspace", token: "synthetic-token")
    }
    private func service(_ transport: WorkspaceRequestTransport, session: Session) throws -> MerchantContentService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://workspace.example")!), transport: transport, currentSession: { session.value })
    }
    private func body(_ request: URLRequest) throws -> [String: MerchantContentValue] {
        try JSONDecoder().decode([String: MerchantContentValue].self, from: XCTUnwrap(request.httpBody))
    }
    func testEmployeeWorkspaceUsesExactMerchantScopeAndExistingRoute() async throws {
        let t = WorkspaceRequestTransport(), session = Session()
        t.append(MerchantContentFixtureData.access.replacingOccurrences(of: "MERCHANT_OWNER", with: "MERCHANT_MANAGER"))
        t.append(#"{"topic":{"id":70},"host":{"recruit":{}}}"#)
        let result = try await service(t, session: session).load(.project(topicID: 70))
        XCTAssertEqual(result.access.role, .manager)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/project/home"])
        let request = try XCTUnwrap(t.requests.last)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try body(request), ["topicId": .integer(70), "scope": .string("MERCHANT")])
        XCTAssertNil(request.url?.query); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testOwnerWorkspaceUsesSameScopedBodyWithoutOwnerOrMerchantInjection() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access); t.append(#"{"topic":{"id":70},"join":{}}"#)
        _ = try await service(t, session: session).load(.project(topicID: 70))
        XCTAssertEqual(Set(try body(t.requests[1]).keys), ["topicId", "scope"])
    }
    func testOptionalLegacyTopicStillOmitsIDButHasMerchantScope() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access); t.append("{}")
        _ = try await service(t, session: session).load(.project(topicID: nil))
        XCTAssertEqual(try body(t.requests[1]), ["scope": .string("MERCHANT")])
    }
    func testMissingPermissionStopsBeforeWorkspaceRequest() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_MANAGER","permissions":[]}"#)
        do { _ = try await service(t, session: session).load(.project(topicID: 70)); XCTFail("Expected denial") }
        catch { XCTAssertEqual(error as? MerchantContentFailure, .denied) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testServerEmployeeDenialIsNeverConvertedIntoMembership() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access)
        t.replies.append((#"{"code":403,"msg":"Synthetic denial"}"#, 200))
        do { _ = try await service(t, session: session).load(.project(topicID: 70)); XCTFail("Expected server denial") }
        catch { XCTAssertEqual(error as? MerchantContentFailure, .denied) }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testInvalidTopicDoesNotSendAnyRequest() async throws {
        let t = WorkspaceRequestTransport(), session = Session()
        do { _ = try await service(t, session: session).load(.project(topicID: 0)); XCTFail("Expected invalid topic") }
        catch { XCTAssertEqual(error as? MerchantContentFailure, .invalid) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testAccountChangeDuringAccessPreventsWorkspaceDispatch() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access)
        t.onRequest = { _ in session.value = nil }
        do { _ = try await service(t, session: session).load(.project(topicID: 70)); XCTFail("Expected changed session") } catch { }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testAccountChangeDuringHomeReadDiscardsResponse() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access); t.append(#"{"topic":{"id":70}}"#)
        t.onRequest = { count in if count == 2 { session.value = nil } }
        do { _ = try await service(t, session: session).load(.project(topicID: 70)); XCTFail("Expected changed session") } catch { }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testExistingSensitivePlayersRequestRemainsByteEquivalent() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access); t.append(#"{"rows":[]}"#)
        _ = try await service(t, session: session).load(.players(topicID: 70))
        XCTAssertEqual(t.requests[1].url?.path, "/api/project/players"); XCTAssertEqual(try body(t.requests[1]), ["topicId": .integer(70)])
    }
    func testWorkspaceReadDoesNotActivateWrites() async throws {
        let t = WorkspaceRequestTransport(), session = Session(); t.append(MerchantContentFixtureData.access); t.append(#"{"topic":{"id":70},"host":{}}"#)
        let source = try service(t, session: session); XCTAssertFalse(source.permitsWrites)
        _ = try await source.load(.project(topicID: 70)); XCTAssertFalse(source.permitsWrites)
    }
}
