import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class NearbyReadHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); onSend?(); return (Data("{\"code\":200,\"data\":[]}".utf8), 200) }
}
@MainActor final class NearbyTeamHTTPReadTests: XCTestCase {
    private let session = NearbyTeamSyntheticFixtures.session
    private func adapter(_ transport: NearbyReadHTTPFake, paths: Set<String>, accountID: Int? = nil, current: (() -> NearbyTeamSession?)? = nil) throws -> NearbyTeamHTTPReadTransport {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: accountID ?? session.accountID, paths: paths)
        return .init(configuration: configuration, transport: transport, approval: approval, currentSession: current ?? { self.session }, token: { _ in "synthetic-token" })
    }
    func testScopedReadSendsExactGetQuery() async throws {
        let transport = NearbyReadHTTPFake(); let reader = try adapter(transport, paths: ["api/team/nearby"])
        _ = try await reader.sendRead(try .nearby(NearbyTeamSyntheticFixtures.context), session: session)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/team/nearby")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertNil(request.httpBody); XCTAssertTrue(request.url?.query?.contains("radius=3000") == true)
    }
    func testWrongAccountGrantSendsNothing() async throws {
        let transport = NearbyReadHTTPFake(); let reader = try adapter(transport, paths: ["api/team/nearby"], accountID: 9)
        do { _ = try await reader.sendRead(try .nearby(NearbyTeamSyntheticFixtures.context), session: session); XCTFail() } catch { XCTAssertEqual(error as? NearbyTeamFailure, .unconfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testEvenGrantedMutationCannotUseReadAdapter() async throws {
        let transport = NearbyReadHTTPFake(); let reader = try adapter(transport, paths: ["api/team/apply"])
        do { _ = try await reader.sendRead(try .action(.apply(.init(501))), session: session); XCTFail() } catch { XCTAssertEqual(error as? NearbyTeamFailure, .unconfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testEpochChangeDuringReadRejectsResponse() async throws {
        var current: NearbyTeamSession? = session
        let transport = NearbyReadHTTPFake(); transport.onSend = { current = nil }
        let reader = try adapter(transport, paths: ["api/team/my-applications"], current: { current })
        do { _ = try await reader.sendRead(.myApplications(), session: session); XCTFail() } catch { XCTAssertEqual(error as? NearbyTeamFailure, .stale) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
