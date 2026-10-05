import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class PlayEndingReadProtocolTests: XCTestCase {
    /// Separate protocol correction: this GET adapter remains outside the normal root bridge.
    func testEndingMatchesExistingGETControllerWithOneCanonicalScope() async throws {
        for (scope, query) in [(PlaySessionScope.activity(41), "activityId=41"), (.topic(71), "topicId=71")] {
            let wire = PlayEndingProtocolWire()
            let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
                transport: wire, enabled: [.reads])
            let ending = try await service.ending(scope: scope, token: "synthetic")
            XCTAssertFalse(ending.hasStory)
            let request = try XCTUnwrap(wire.requests.first)
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/native/api/play/ending")
            XCTAssertEqual(request.url?.query, query); XCTAssertNil(request.httpBody); XCTAssertNil(request.httpBodyStream)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type")); XCTAssertEqual(wire.requests.count, 1)
            XCTAssertNil(PlayReadRoute(request: request, baseURL: URL(string: "https://example.test/native")!))
        }
    }
    func testEndingDisabledOrInvalidScopeDoesNotDispatch() async throws {
        let wire = PlayEndingProtocolWire(), api = try APIConfiguration(baseURL: URL(string: "https://example.test/native")!)
        do { _ = try await PlayExperienceService(configuration: api, transport: wire).ending(scope: .topic(71), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        do { _ = try await PlayExperienceService(configuration: api, transport: wire, enabled: [.reads]).ending(scope: .topic(0), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await PlayExperienceService(configuration: api, transport: wire, enabled: [.reads]).ending(scope: .activity(41), token: "bad\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEndingHTTPAndBusiness401AndMalformedResponsesAreNotEmptyStories() async throws {
        for (status, body, unauthorized) in [
            (401, "{}", true),
            (200, #"{"code":401}"#, true),
            (200, #"{"code":200,"data":{}}"#, false),
            (200, #"{"code":200,"data":null}"#, false)] {
            let wire = PlayEndingProtocolWire(); wire.status = status; wire.body = body
            let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: wire, enabled: [.reads])
            do { _ = try await service.ending(scope: .topic(71), token: "synthetic"); XCTFail() }
            catch {
                if unauthorized { XCTAssertEqual(error as? PlayExperienceError, .unauthorized) }
                else { XCTAssertTrue(error is DecodingError) }
            }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testEndingLateSuccessAnd401CannotCrossCapturedSession() async throws {
        let base = URL(string: "https://example.test/native")!
        for unauthorized in [false, true] {
            let captured = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
                session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
            let replacement = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
                session: try .init(accountID: 8, epoch: 2, namespace: "synthetic", token: "replacement"))
            var current: RuntimeDependencyContext? = captured
            let approval = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 7, paths: ["api/play/ending"])
            let wire = PlayEndingProtocolWire(); wire.onSend = { current = replacement }
            if unauthorized { wire.body = #"{"code":401}"# }
            let factory = RuntimeDependencyFactory(api: try APIConfiguration(baseURL: base),
                configuration: .init(market: .china, endpoints: approval, play: [.reads]), transport: wire, current: { current })
            do { _ = try await factory.playService().ending(scope: .topic(71), token: "synthetic"); XCTFail() }
            catch { XCTAssertEqual(error as? PlayExperienceError, .staleSession) }
            XCTAssertEqual(current, replacement); XCTAssertEqual(wire.requests.count, 1)
        }
    }
}
@MainActor private final class PlayEndingProtocolWire: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var body = #"{"code":200,"data":{"opener":"","fragments":[]}}"#
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        onSend?()
        return (Data(body.utf8), status)
    }
}
