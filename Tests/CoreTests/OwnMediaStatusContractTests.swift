import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OwnMediaStatusContractTests: XCTestCase {
    func testNumericAndDecimalStringIdentifiersMatchOnlyOriginalAsset() throws {
        for id in ["42", "\"42\""] {
            let data = Data("{\"code\":200,\"data\":{\"assetId\":\(id),\"reviewState\":\"HOLD\",\"mediaType\":\"IMAGE\"}}".utf8)
            XCTAssertEqual(try OwnMediaStatus.decode(data, requestedID: 42).asset.id, 42)
            XCTAssertThrowsError(try OwnMediaStatus.decode(data, requestedID: 43))
        }
    }
    func testApprovedURLIsNotRequiredOrConsumed() throws {
        let data = Data(#"{"code":200,"data":{"assetId":42,"reviewState":"APPROVED","url":{"untrusted":"not an image URL"}}}"#.utf8)
        XCTAssertEqual(try OwnMediaStatus.decode(data, requestedID: 42).asset.reviewState, .approved)
    }
    func testUnknownStateAndUnrelatedIdentityFailClosed() {
        for body in [#"{"assetId":42,"reviewState":"FUTURE"}"#, #"{"assetId":-1,"reviewState":"HOLD"}"#, #"{"reviewState":"HOLD"}"#] {
            XCTAssertThrowsError(try OwnMediaStatus.decode(Data("{\"code\":200,\"data\":\(body)}".utf8), requestedID: 42))
        }
    }
    func testUnauthorizedWithoutDataIsNotAValidStatus() {
        XCTAssertThrowsError(try OwnMediaStatus.decode(Data(#"{"code":401}"#.utf8), requestedID: 42)) {
            XCTAssertEqual($0 as? APIError, .unauthorized)
        }
    }
    func testRouteOnlyAllowsExactStatusGetAndNeverPreviewRetryOrURLFetch() throws {
        let base = URL(string: "https://example.com/")!
        let request = try OwnMediaStatusRoute.request(baseURL: base, id: 42, token: "synthetic")
        XCTAssertEqual(OwnMediaStatusRoute.assetID(request, baseURL: base), 42)
        XCTAssertFalse(OwnMediaReadRoute.accepts(request, baseURL: base))
        for path in ["api/media/asset/42/preview", "api/media/asset/42/retry", "api/media/asset/list", "api/media/asset/042", "api/media/asset/42?x=1"] {
            var altered = request; altered.url = URL(string: path, relativeTo: base)!.absoluteURL
            XCTAssertNil(OwnMediaStatusRoute.assetID(altered, baseURL: base))
        }
        var post = request; post.httpMethod = "POST"
        XCTAssertNil(OwnMediaStatusRoute.assetID(post, baseURL: base))
        var body = request; body.httpBody = Data()
        XCTAssertNil(OwnMediaStatusRoute.assetID(body, baseURL: base))
    }
    @MainActor func testStatusRequiresExplicitScopeBeforeAnyTransportCall() async throws {
        let wire = StatusAdmissionWire()
        let service = OwnMediaService(configuration: try APIConfiguration(baseURL: URL(string: "https://media.example/native")!), transport: wire)
        var session = try OwnMediaSession(accountID: 1, epoch: 1, token: "synthetic", approval: UUID())
        let reader = OwnMediaSessionReader(service: service, currentSession: { session })
        do { _ = try await reader.status(id: 42); XCTFail("List approval cannot read individual status") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let rejectedCount = await wire.calls
        XCTAssertEqual(rejectedCount, 0)
        let oldScope = reader.scope
        session = try OwnMediaSession(accountID: 1, epoch: 1, token: "synthetic", approval: session.approval, statusApproved: true)
        XCTAssertNotEqual(reader.scope, oldScope)
        let result = try await reader.status(id: 42)
        XCTAssertEqual(result.asset.id, 42)
        let acceptedCount = await wire.calls
        XCTAssertEqual(acceptedCount, 1)
    }
    func testExistingSessionsStayListOnlyAndStatusAffectsIdentity() throws {
        let approval = UUID()
        let original = try OwnMediaSession(accountID: 1, epoch: 2, token: "synthetic", approval: approval)
        XCTAssertFalse(original.statusApproved)
        let status = try OwnMediaSession(accountID: 1, epoch: 2, token: "synthetic", approval: approval, statusApproved: true)
        XCTAssertNotEqual(original, status)
        XCTAssertFalse(try OwnMediaSession(accountID: 1, epoch: 2, token: "synthetic", approval: nil, statusApproved: true).statusApproved)
    }
}

private actor StatusAdmissionWire: HTTPTransport {
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        return (Data(#"{"code":200,"data":{"assetId":42,"reviewState":"HOLD"}}"#.utf8), 200)
    }
}
