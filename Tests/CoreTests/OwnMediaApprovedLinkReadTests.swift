import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor private final class ApprovedLinkList: OwnMediaReading {
    var scope = UUID(), isSignedIn = true, isAvailable = true, pages = 0
    func page(before cursor: Int64?) async throws -> OwnMediaPage { pages += 1; return .init(rows: []) }
}
@MainActor private final class ApprovedLinkTransport: OwnMediaApprovedLinkDispatching {
    var requests: [URLRequest] = [], body = ApprovedLinkFixture.payload(), status = 200
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, cancelled = false
    func send(_ input: URLRequest, authorization: OwnMediaApprovedLinkAuthorization) async throws -> (Data, Int) {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); return (Data(body.utf8), status)
    }
}
@MainActor private final class ApprovedLinkFixture {
    nonisolated static let url = "https://approved.example.test/object.jpg?Expires=9999999999&Signature=a%2Bb%3D"
    let context: RuntimeDependencyContext, approval: OwnMediaApprovedLinkApproval
    let list = ApprovedLinkList(), transport = ApprovedLinkTransport()
    var current: RuntimeDependencyContext?, viewer: UInt64? = 3, selected: OwnMediaApprovedLinkApproval?, visible = true
    var asset = OwnMediaAsset(id: 9, reviewState: .approved, reviewReason: "", mediaType: .image)
    var row: OwnMediaAsset?, copied: [String] = []
    lazy var reader = OwnMediaApprovedLinkReader(approval: approval, currentContext: { [unowned self] in current },
        currentViewerRevision: { [unowned self] in viewer }, selected: { [unowned self] in selected }, listReader: list, transport: transport)
    init() throws {
        context = try Self.context(); current = context
        approval = try .init(context: context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://approved.example.test"], expiresAt: Date().addingTimeInterval(600))
        selected = approval; row = asset
    }
    static func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-link",
                        namespace: String = "approved-link", base: String = "https://link-api.example.test/native", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    nonisolated static func payload(id: String = "9", state: String = "APPROVED", type: String = "IMAGE", url: String = ApprovedLinkFixture.url) -> String {
        "{\"code\":200,\"data\":{\"assetId\":\(id),\"reviewState\":\"\(state)\",\"mediaType\":\"\(type)\",\"url\":\"\(url)\"}}"
    }
    func read() async throws -> OwnMediaApprovedLinkDelivery {
        try await reader.readForCopy(asset: asset, currentAsset: { [unowned self] in row }, actionIsCurrent: { [unowned self] in visible })
    }
}
@MainActor final class OwnMediaApprovedLinkReadTests: XCTestCase {
    func testExplicitReadPreservesLongSignatureAndDeliversOnlyOnce() async throws {
        let f = try ApprovedLinkFixture(), value = try await f.read()
        XCTAssertTrue(f.copied.isEmpty); try value.deliver { f.copied.append($0) }
        XCTAssertEqual(f.copied, [ApprovedLinkFixture.url]); XCTAssertThrowsError(try value.deliver { f.copied.append($0) })
        XCTAssertEqual(f.transport.requests.count, 1); XCTAssertEqual(f.list.pages, 0)
        let request = try XCTUnwrap(f.transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://link-api.example.test/native/api/media/asset/9")
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-link")
        XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
    }
    func testOriginalResponseNeedsNoInventedVersionOrExpiry() async throws {
        let f = try ApprovedLinkFixture(); XCTAssertFalse(f.transport.body.contains("issuedAt")); XCTAssertFalse(f.transport.body.contains("expiresAt"))
        let delivery = try await f.read(); try delivery.deliver { f.copied.append($0) }; XCTAssertEqual(f.copied.first, ApprovedLinkFixture.url)
    }
    func testExactNumericAndStringInt64IDs() async throws {
        for id in [Int64(9), Int64.max] { for string in [false, true] {
            let f = try ApprovedLinkFixture(); let approval = try OwnMediaApprovedLinkApproval(context: f.context, viewerRevision: 3, assetID: id, approvedOrigins: ["https://approved.example.test"], expiresAt: .distantFuture)
            f.asset = .init(id: id, reviewState: .approved, reviewReason: "", mediaType: .image); f.row = f.asset; f.transport.body = ApprovedLinkFixture.payload(id: string ? "\"\(id)\"" : "\(id)")
            let reader = OwnMediaApprovedLinkReader(approval: approval, currentContext: { f.context }, currentViewerRevision: { 3 }, selected: { approval }, listReader: f.list, transport: f.transport)
            let delivery = try await reader.readForCopy(asset: f.asset, currentAsset: { f.row }, actionIsCurrent: { true }); try delivery.deliver { f.copied.append($0) }
            XCTAssertEqual(f.copied.count, 1)
        } }
    }
    func testMalformedOrWrongIDCannotCopy() async throws {
        for id in ["0", "-1", "10", "9.5", "true", "null", "\"09\"", "\"+9\"", "\"9223372036854775808\""] {
            let f = try ApprovedLinkFixture(); f.transport.body = ApprovedLinkFixture.payload(id: id)
            do { _ = try await f.read(); XCTFail(id) } catch {}; XCTAssertTrue(f.copied.isEmpty)
        }
    }
    func testCurrentRowMustBeApprovedKnownTypeAndExactAsset() async throws {
        let rows: [OwnMediaAsset] = [.init(id: 9, reviewState: .hold, reviewReason: "", mediaType: .image),
            .init(id: 9, reviewState: .rejected, reviewReason: "", mediaType: .image), .init(id: 9, reviewState: .unavailable, reviewReason: "", mediaType: .image),
            .init(id: 9, reviewState: .approved, reviewReason: "", mediaType: .other), .init(id: 10, reviewState: .approved, reviewReason: "", mediaType: .image)]
        for row in rows { let f = try ApprovedLinkFixture(); f.asset = row; f.row = row; do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.transport.requests.isEmpty) }
    }
    func testOriginalAudioAndModelTypesCopyWithoutResourceLoading() async throws {
        for (type, raw) in [(OwnMediaAsset.MediaType.audio, "AUDIO"), (.model3D, "MODEL3D")] {
            let f = try ApprovedLinkFixture(); f.asset = .init(id: 9, reviewState: .approved, reviewReason: "", mediaType: type); f.row = f.asset; f.transport.body = ApprovedLinkFixture.payload(type: raw)
            let value = try await f.read(); try value.deliver { f.copied.append($0) }; XCTAssertEqual(f.transport.requests.count, 1); XCTAssertEqual(f.copied.count, 1)
        }
    }
    func testResponseTypeStateAndMalformedEnvelopeFailClosedWithoutRevokingLease() async throws {
        let inputs = [ApprovedLinkFixture.payload(type: "AUDIO"), ApprovedLinkFixture.payload(state: "HOLD"), ApprovedLinkFixture.payload(state: "approved"),
            "{\"code\":200,\"data\":{}}", "{\"code\":200,\"code\":200,\"data\":{}}", "{\"code\":500}"]
        for body in inputs { let f = try ApprovedLinkFixture(); f.transport.body = body; do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertFalse(f.approval.revoked) }
    }
    func testUnapprovedOriginsAndMalformedURLsCannotBeDelivered() async throws {
        for url in ["http://approved.example.test/a", "https://evil.example.test/a", "https://u:p@approved.example.test/a", "https://approved.example.test/a#x", "https://approved.example.test", "https://approved.example.test/a b"] {
            let f = try ApprovedLinkFixture(); f.transport.body = ApprovedLinkFixture.payload(url: url); do { _ = try await f.read(); XCTFail(url) } catch {}; XCTAssertTrue(f.copied.isEmpty)
        }
    }
    func testApprovedLocalHTTPSLinkRemainsUnmodifiedWithoutAssumedExpiry() async throws {
        let f = try ApprovedLinkFixture(), raw = "https://approved.example.test/prod-api/profile/upload/2026/11/06/0123456789abcdef0123456789abcdef.png"
        f.transport.body = ApprovedLinkFixture.payload(url: raw); let value = try await f.read(); try value.deliver { f.copied.append($0) }; XCTAssertEqual(f.copied, [raw])
    }
    func testNilSelectedSourceOrListLossCannotRead() async throws {
        for mode in 0..<4 { let f = try ApprovedLinkFixture(); if mode == 0 { f.selected = nil }; if mode == 1 { f.list.isAvailable = false }; if mode == 2 { f.list.isSignedIn = false }; if mode == 3 { f.row = nil }
            do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.transport.requests.isEmpty)
        }
    }
    func testEveryContextChangeRetiresOldReaderPermanently() throws {
        let changes = [try ApprovedLinkFixture.context(account: 8), try ApprovedLinkFixture.context(epoch: 2), try ApprovedLinkFixture.context(role: "merchant"),
            try ApprovedLinkFixture.context(token: "other"), try ApprovedLinkFixture.context(namespace: "other"), try ApprovedLinkFixture.context(base: "https://other.example.test"), try ApprovedLinkFixture.context(market: .unitedStates)]
        for changed in changes { let f = try ApprovedLinkFixture(); XCTAssertTrue(f.reader.isConfigured); f.current = changed; XCTAssertFalse(f.reader.isConfigured); f.current = f.context; XCTAssertFalse(f.reader.isConfigured) }
    }
    func testViewerAndListScopeChangesRetireReader() throws {
        for change in 0..<2 { let f = try ApprovedLinkFixture(); XCTAssertTrue(f.reader.isConfigured); if change == 0 { f.viewer = 4 } else { f.list.scope = UUID() }; XCTAssertFalse(f.reader.isConfigured) }
    }
    func testFinalDispatchRejectsCloseSourceAndRowChanges() async throws {
        for mode in 0..<3 { let f = try ApprovedLinkFixture(); f.transport.before = { if mode == 0 { f.visible = false }; if mode == 1 { f.selected = nil }; if mode == 2 { f.row = nil } }
            do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.transport.requests.isEmpty)
        }
    }
    func testFinalDispatchRejectsMutationAndDoubleDispatch() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.url = URL(string: "https://evil.example.test/api/media/asset/9") }, { $0.httpMethod = "POST" },
            { $0.httpBody = Data([1]) }, { $0.setValue("other", forHTTPHeaderField: "Authorization") }, { $0.setValue("cookie", forHTTPHeaderField: "Cookie") }]
        for mutation in mutations { let f = try ApprovedLinkFixture(); f.transport.mutate = mutation; do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.transport.requests.isEmpty) }
        for skip in [false, true] { let f = try ApprovedLinkFixture(); f.transport.skip = skip; f.transport.twice = !skip; do { _ = try await f.read(); XCTFail() } catch {} }
    }
    func testLateResponseCannotProduceDeliveryAfterWithdrawal() async throws {
        let f = try ApprovedLinkFixture(); f.transport.after = { f.list.isAvailable = false }
        do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.copied.isEmpty)
    }
    func testDeliveryRechecksCurrentApprovedRowAndActionAtLastMoment() async throws {
        for mode in 0..<4 { let f = try ApprovedLinkFixture(), value = try await f.read()
            if mode == 0 { f.row = nil }; if mode == 1 { f.row = .init(id: 9, reviewState: .hold, reviewReason: "", mediaType: .image) }; if mode == 2 { f.visible = false }; if mode == 3 { f.selected = nil }
            XCTAssertThrowsError(try value.deliver { f.copied.append($0) }); XCTAssertTrue(f.copied.isEmpty)
            f.row = f.asset; f.visible = true; f.selected = f.approval; XCTAssertThrowsError(try value.deliver { f.copied.append($0) })
        }
    }
    func testSinkFailureConsumesDeliveryAndDoesNotRecallEarlierCopy() async throws {
        let f = try ApprovedLinkFixture(), value = try await f.read(); enum Failure: Error { case denied }
        XCTAssertThrowsError(try value.deliver { _ in throw Failure.denied }); XCTAssertThrowsError(try value.deliver { f.copied.append($0) }); XCTAssertTrue(f.copied.isEmpty)
    }
    func testCurrentUnauthorizedOnlyRevokesItsCopyLease() async throws {
        for (status, body) in [(401, "{}"), (403, "{}"), (200, "{\"code\":2}"), (200, "{\"code\":403}")] {
            let f = try ApprovedLinkFixture(); f.transport.status = status; f.transport.body = body
            do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable)
        }
    }
    func testLateUnauthorizedCannotRevokeNewSource() async throws {
        let f = try ApprovedLinkFixture(), new = try OwnMediaApprovedLinkApproval(context: f.context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://approved.example.test"], expiresAt: .distantFuture)
        f.transport.status = 403; f.transport.after = { f.selected = new }; do { _ = try await f.read(); XCTFail() } catch {}; XCTAssertFalse(new.revoked)
    }
    func testRetirementCancelsOwnedExchangeAndRejectsPreparedDelivery() async throws {
        let f = try ApprovedLinkFixture(), value = try await f.read(); f.reader.retire(); XCTAssertTrue(f.transport.cancelled)
        XCTAssertThrowsError(try value.deliver { f.copied.append($0) })
    }
    func testInvalidOriginIDAndExpiryCannotMintAuthority() throws {
        let context = try ApprovedLinkFixture.context()
        let cases: [Set<String>] = [[], ["http://approved.example.test"], ["https://approved.example.test/"], ["https://approved.example.test:0"], ["https://APPROVED.example.test"]]
        for origins in cases {
            XCTAssertThrowsError(try OwnMediaApprovedLinkApproval(context: context, viewerRevision: 3, assetID: 9, approvedOrigins: origins, expiresAt: .distantFuture))
        }
        for id in [Int64(0), Int64(-1)] { XCTAssertThrowsError(try OwnMediaApprovedLinkApproval(context: context, viewerRevision: 3, assetID: id, approvedOrigins: ["https://approved.example.test"], expiresAt: .distantFuture)) }
        XCTAssertThrowsError(try OwnMediaApprovedLinkApproval(context: context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://approved.example.test"], expiresAt: .distantPast))
    }
    func testTransportResponseEndpointAndMetadataBounds() throws {
        let url = URL(string: "https://link-api.example.test/native/api/media/asset/9")!
        for (endpoint, length, allowed) in [(url, "65536", true), (url, "65537", false), (URL(string: "https://evil.example.test")!, "1", false)] {
            let response = try XCTUnwrap(HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": length]))
            XCTAssertEqual(OwnMediaApprovedLinkTransport.acceptsResponse(response, endpoint: url), allowed)
        }
    }
}
