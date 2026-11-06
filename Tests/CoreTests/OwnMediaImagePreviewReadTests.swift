import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor private final class OwnerImageList: OwnMediaReading {
    var scope = UUID(), isSignedIn = true, isAvailable = true
    var pages = 0
    func page(before cursor: Int64?) async throws -> OwnMediaPage { pages += 1; return .init(rows: []) }
}
@MainActor private final class OwnerImageMetadata: OwnMediaImagePreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, body = OwnerImageFixture.payload()
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, cancelled = false
    func send(_ input: URLRequest, authorization: OwnMediaImagePreviewAuthorization) async throws -> (Data, Int) {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); return (Data(body.utf8), status)
    }
}
@MainActor private final class OwnerImageBytes: OwnMediaPrivateImageReading {
    var requests: [URLRequest] = [], bytes = Data([1, 2, 3]), cancelled = false
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, failure: Error?
    func image(_ input: URLRequest, authorization: OwnMediaImagePreviewAuthorization) async throws -> Data {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); if let failure { throw failure }; return bytes
    }
}
@MainActor private final class OwnerImageFixture {
    nonisolated static let url = "https://private-images.example.test/object.jpg?Expires=123&Signature=a%2Bb%3D"
    let context: RuntimeDependencyContext, approval: OwnMediaImagePreviewApproval
    let list = OwnerImageList(), metadata = OwnerImageMetadata(), image = OwnerImageBytes()
    var current: RuntimeDependencyContext?, viewer: UInt64? = 3, selected: OwnMediaImagePreviewApproval?, visible = true
    var asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Waiting", mediaType: .image)
    var row: OwnMediaAsset?
    lazy var reader = OwnMediaImagePreviewReader(approval: approval, currentContext: { [unowned self] in current },
        currentViewerRevision: { [unowned self] in viewer }, selected: { [unowned self] in selected }, listReader: list, metadata: metadata, imageReader: image)
    init() throws {
        context = try Self.context(); current = context
        approval = try .init(context: context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        selected = approval; row = asset
    }
    static func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-owner",
                        namespace: String = "owner-image", base: String = "https://owner-api.example.test/native", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    nonisolated static func payload(_ url: String = OwnerImageFixture.url) -> String { "{\"code\":200,\"data\":{\"authorPreviewUrl\":\"\(url)\"}}" }
    func load() async throws -> OwnMediaImagePreviewData {
        try await reader.load(asset: asset, currentAsset: { [unowned self] in row }, presentationIsCurrent: { [unowned self] in visible })
    }
}
@MainActor final class OwnMediaImagePreviewReadTests: XCTestCase {
    func testTwoExactReadsKeepCredentialAtFirstPartyAndSignatureAtImageOrigin() async throws {
        let f = try OwnerImageFixture(), data = try await f.load()
        let metadata = try XCTUnwrap(f.metadata.requests.first), image = try XCTUnwrap(f.image.requests.first)
        XCTAssertEqual(metadata.url?.absoluteString, "https://owner-api.example.test/native/api/media/asset/9/preview")
        XCTAssertEqual(metadata.httpMethod, "GET"); XCTAssertEqual(metadata.value(forHTTPHeaderField: "Authorization"), "synthetic-owner")
        XCTAssertNil(metadata.httpBody); XCTAssertNil(metadata.url?.query)
        XCTAssertEqual(image.url?.absoluteString, OwnerImageFixture.url); XCTAssertEqual(image.httpMethod, "GET")
        XCTAssertNil(image.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(image.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(image.httpBody)
        XCTAssertEqual(data.bytes, f.image.bytes); XCTAssertEqual(f.list.pages, 0)
    }
    func testResponseNeedsOnlyOriginalURLNotInventedIdentityOrTimeFields() async throws {
        let f = try OwnerImageFixture(); _ = try await f.load()
        XCTAssertFalse(f.metadata.body.contains("assetId")); XCTAssertFalse(f.metadata.body.contains("issuedAt")); XCTAssertFalse(f.metadata.body.contains("version"))
        XCTAssertEqual(f.image.requests.count, 1)
    }
    func testPositiveInt64OriginalRouteAndInvalidIDs() throws {
        let r = try OwnMediaImagePreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: Int64.max, token: "synthetic")
        XCTAssertEqual(r.url?.path, "/api/media/asset/9223372036854775807/preview")
        for id in [Int64(0), Int64(-1)] { XCTAssertThrowsError(try OwnMediaImagePreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: id, token: "synthetic")) }
    }
    func testNoPreviewAuthorityFromAvailableListAlone() async throws {
        let f = try OwnerImageFixture(); f.selected = nil
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testPreviewAuthorityStillRequiresLiveListSourceAndCurrentRow() async throws {
        let a = try OwnerImageFixture(); a.list.isAvailable = false
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerImageFixture(); b.row = nil
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testAudioModelOtherAndWrongAssetCannotUseImageLease() async throws {
        for type in [OwnMediaAsset.MediaType.audio, .model3D, .other] {
            let f = try OwnerImageFixture(); f.asset = .init(id: 9, reviewState: .hold, reviewReason: "", mediaType: type); f.row = f.asset
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
        }
        let f = try OwnerImageFixture(); f.asset = .init(id: 10, reviewState: .approved, reviewReason: "", mediaType: .image); f.row = f.asset
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
    }
    func testPendingRejectedUnavailableRemainOwnerPreviewWithoutApprovalVerdict() async throws {
        for state in [OwnMediaAsset.ReviewState.hold, .rejected, .unavailable, .approved] {
            let f = try OwnerImageFixture(); f.asset = .init(id: 9, reviewState: state, reviewReason: "", mediaType: .image); f.row = f.asset
            _ = try await f.load(); XCTAssertEqual(f.row?.reviewState, state)
        }
    }
    func testAllIdentityContextChangesRetireReaderPermanently() throws {
        for c in [try OwnerImageFixture.context(account: 8), try OwnerImageFixture.context(epoch: 2), try OwnerImageFixture.context(role: "club"),
                  try OwnerImageFixture.context(token: "other"), try OwnerImageFixture.context(namespace: "other"),
                  try OwnerImageFixture.context(base: "https://other.example.test"), try OwnerImageFixture.context(market: .unitedStates)] {
            let f = try OwnerImageFixture(); XCTAssertTrue(f.reader.isConfigured); f.current = c; XCTAssertFalse(f.reader.isConfigured)
            f.current = f.context; XCTAssertFalse(f.reader.isConfigured)
        }
    }
    func testViewerAndListScopeChangesInvalidateOldReader() throws {
        let f = try OwnerImageFixture(); f.viewer = 4; XCTAssertFalse(f.reader.isConfigured)
        let g = try OwnerImageFixture(); _ = g.reader; g.list.scope = UUID(); XCTAssertFalse(g.reader.isConfigured)
    }
    func testMetadataFinalForwardRechecksVisibilityAndSelectedSource() async throws {
        let a = try OwnerImageFixture(); a.metadata.before = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerImageFixture(); b.metadata.before = { b.selected = nil }
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testImageFinalForwardRechecksCurrentRowAndGrant() async throws {
        let f = try OwnerImageFixture(); f.image.before = { f.row = nil }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertEqual(f.metadata.requests.count, 1); XCTAssertTrue(f.image.requests.isEmpty)
        let g = try OwnerImageFixture(); g.image.before = { g.approval.revoke() }
        do { _ = try await g.load(); XCTFail() } catch {}; XCTAssertTrue(g.image.requests.isEmpty)
    }
    func testLateMetadataResponseCannotStartImageAfterListWithdrawal() async throws {
        let f = try OwnerImageFixture(); f.metadata.after = { f.list.isAvailable = false }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testLateImageResponseCannotPublishAfterCloseOrRowReplacement() async throws {
        let a = try OwnerImageFixture(); a.image.after = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerImageFixture(); b.image.after = { b.row = .init(id: 9, reviewState: .approved, reviewReason: "changed", mediaType: .image) }
        do { _ = try await b.load(); XCTFail() } catch {}
    }
    func testMalformedDuplicateOrMissingURLPayloadNeverLoadsImage() async throws {
        for body in ["{}", #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"url":"https://private-images.example.test/a.jpg"}}"#,
                     #"{"code":200,"code":200,"data":{"authorPreviewUrl":"https://private-images.example.test/a.jpg"}}"#, String(repeating: " ", count: 65_537)] {
            let f = try OwnerImageFixture(); f.metadata.body = body
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidURLNeverRewrittenOrGivenCredential() async throws {
        for url in ["http://private-images.example.test/a.jpg", "https://other.example.test/a.jpg", "media-asset:9", "https://user@private-images.example.test/a.jpg", "https://private-images.example.test/a b.jpg", "https://private-images.example.test/a.jpg#fragment"] {
            let f = try OwnerImageFixture(); f.metadata.body = OwnerImageFixture.payload(url)
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidOriginAndExpiredOrWrongMarketLeaseAreRejected() throws {
        for origin in ["http://private-images.example.test", "https://private-images.example.test/", "https://private-images.example.test:0", "https://private-images.example.test:65536", "https://u@private-images.example.test"] {
            XCTAssertThrowsError(try OwnMediaImagePreviewApproval(context: OwnerImageFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [origin], expiresAt: .distantFuture))
        }
        XCTAssertThrowsError(try OwnMediaImagePreviewApproval(context: OwnerImageFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [], expiresAt: .distantFuture))
        XCTAssertThrowsError(try OwnMediaImagePreviewApproval(context: OwnerImageFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantPast))
        XCTAssertThrowsError(try OwnMediaImagePreviewApproval(context: OwnerImageFixture.context(market: .unitedStates), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture))
    }
    func testCurrentMetadataDenialRevokesOnlyItsPreviewLease() async throws {
        for code in [401, 403, 2] {
            let f = try OwnerImageFixture(); f.metadata.body = "{\"code\":\(code)}"
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testCurrentHTTPDenialsRevokeOnlyTheSelectedPreviewLease() async throws {
        for status in [401, 403] {
            let f = try OwnerImageFixture(); f.metadata.status = status
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testMetadataCannotBeRetargetedOrChangedToWriterAtFinalForward() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.url = URL(string: "https://other.example.test/api/media/asset/9/preview") },
            { $0.url = URL(string: "https://owner-api.example.test/native/api/media/asset/9/retry") },
            { $0.setValue("other-token", forHTTPHeaderField: "Authorization") }, { $0.httpMethod = "POST" }, { $0.httpBody = Data([1]) }]
        for mutate in mutations {
            let f = try OwnerImageFixture(); f.metadata.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testLateDenialCannotRevokeReplacementLease() async throws {
        let f = try OwnerImageFixture(), replacement = try OwnMediaImagePreviewApproval(context: f.context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture)
        f.metadata.status = 401; f.metadata.after = { f.selected = replacement }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertFalse(replacement.revoked)
    }
    func testImageFailureDoesNotRevokeLeaseOrApproveAnything() async throws {
        let f = try OwnerImageFixture(); f.image.failure = OwnMediaImagePreviewFailure.invalidResponse
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertEqual(f.row?.reviewState, .hold)
    }
    func testResourceAuthenticationErrorIsNotMetadataDenial() async throws {
        let f = try OwnerImageFixture(); f.image.failure = OwnMediaImagePreviewFailure.unauthorized
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertTrue(f.list.isAvailable)
    }
    func testNoPhaseCanSucceedWithoutForwardOrForwardTwice() async throws {
        for phase in [0, 1, 2, 3] {
            let f = try OwnerImageFixture(); f.metadata.skip = phase == 0; f.metadata.twice = phase == 1; f.image.skip = phase == 2; f.image.twice = phase == 3
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertLessThanOrEqual(f.metadata.requests.count, 1); XCTAssertLessThanOrEqual(f.image.requests.count, 1)
        }
    }
    func testImageTransportCannotAcceptAppTokenOrDifferentSignedURL() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.setValue("synthetic-owner", forHTTPHeaderField: "Authorization") }, { $0.url = URL(string: "https://private-images.example.test/other.jpg") }, { $0.httpMethod = "POST" }]
        for mutate in mutations {
            let f = try OwnerImageFixture(); f.image.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testClientDisplayWindowIsNoLaterThanRequestStartPlus300Seconds() async throws {
        let f = try OwnerImageFixture(), clock = ContinuousClock(), start = clock.now, value = try await f.load()
        XCTAssertLessThanOrEqual(value.displayDeadline, clock.now.advanced(by: .seconds(300)))
        XCTAssertGreaterThan(value.displayDeadline, start); XCTAssertLessThanOrEqual(value.displayDeadline, f.approval.clientDeadline)
    }
    func testImageBytesAndHeadersAreBoundedAndWrongMIMEOrEndpointFailClosed() async throws {
        for bytes in [Data(), Data(repeating: 1, count: RetainedSelectedImage.maximumInputBytes + 1)] {
            let f = try OwnerImageFixture(); f.image.bytes = bytes
            do { _ = try await f.load(); XCTFail() } catch {}
        }
        let url = URL(string: OwnerImageFixture.url)!
        let good = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!
        XCTAssertTrue(OwnMediaPrivateImageReader.acceptsResponse(good, endpoint: url, image: true))
        for headers in [["Content-Type": "text/html"], ["Content-Type": "image/jpeg", "Content-Length": String(RetainedSelectedImage.maximumInputBytes + 1)], ["Content-Type": "image/jpeg", "X-Large": String(repeating: "a", count: 32_769)]] {
            let bad = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
            XCTAssertFalse(OwnMediaPrivateImageReader.acceptsResponse(bad, endpoint: url, image: true))
        }
    }
}
