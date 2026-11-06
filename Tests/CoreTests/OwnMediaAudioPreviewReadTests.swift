import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor private final class OwnerAudioList: OwnMediaReading {
    var scope = UUID(), isSignedIn = true, isAvailable = true
    var pages = 0
    func page(before cursor: Int64?) async throws -> OwnMediaPage { pages += 1; return .init(rows: []) }
}
@MainActor private final class OwnerAudioMetadata: OwnMediaAudioPreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, body = OwnerAudioFixture.payload()
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, cancelled = false
    func send(_ input: URLRequest, authorization: OwnMediaAudioPreviewAuthorization) async throws -> (Data, Int) {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); return (Data(body.utf8), status)
    }
}
@MainActor private final class OwnerAudioBytes: OwnMediaPrivateAudioReading {
    var requests: [URLRequest] = [], bytes = Data([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69]), cancelled = false
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, failure: Error?
    func audio(_ input: URLRequest, authorization: OwnMediaAudioPreviewAuthorization) async throws -> Data {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); if let failure { throw failure }; return bytes
    }
}
@MainActor private final class OwnerAudioFixture {
    nonisolated static let url = "https://private-images.example.test/object.m4a?Expires=123&Signature=a%2Bb%3D"
    let context: RuntimeDependencyContext, approval: OwnMediaAudioPreviewApproval
    let list = OwnerAudioList(), metadata = OwnerAudioMetadata(), image = OwnerAudioBytes()
    var current: RuntimeDependencyContext?, viewer: UInt64? = 3, selected: OwnMediaAudioPreviewApproval?, visible = true
    var asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Waiting", mediaType: .audio)
    var row: OwnMediaAsset?
    lazy var reader = OwnMediaAudioPreviewReader(approval: approval, currentContext: { [unowned self] in current },
        currentViewerRevision: { [unowned self] in viewer }, selected: { [unowned self] in selected }, listReader: list, metadata: metadata, audioReader: image)
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
    nonisolated static func payload(_ url: String = OwnerAudioFixture.url) -> String { "{\"code\":200,\"data\":{\"authorPreviewUrl\":\"\(url)\"}}" }
    func load() async throws -> OwnMediaAudioPreviewData {
        try await reader.load(asset: asset, currentAsset: { [unowned self] in row }, presentationIsCurrent: { [unowned self] in visible })
    }
}
@MainActor final class OwnMediaAudioPreviewReadTests: XCTestCase {
    func testTwoExactReadsKeepCredentialAtFirstPartyAndSignatureAtAudioOrigin() async throws {
        let f = try OwnerAudioFixture(), data = try await f.load()
        let metadata = try XCTUnwrap(f.metadata.requests.first), image = try XCTUnwrap(f.image.requests.first)
        XCTAssertEqual(metadata.url?.absoluteString, "https://owner-api.example.test/native/api/media/asset/9/preview")
        XCTAssertEqual(metadata.httpMethod, "GET"); XCTAssertEqual(metadata.value(forHTTPHeaderField: "Authorization"), "synthetic-owner")
        XCTAssertNil(metadata.httpBody); XCTAssertNil(metadata.url?.query)
        XCTAssertEqual(image.url?.absoluteString, OwnerAudioFixture.url); XCTAssertEqual(image.httpMethod, "GET")
        XCTAssertNil(image.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(image.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(image.httpBody)
        XCTAssertEqual(data.bytes, f.image.bytes); XCTAssertEqual(f.list.pages, 0)
    }
    func testResponseNeedsOnlyOriginalURLNotInventedIdentityOrTimeFields() async throws {
        let f = try OwnerAudioFixture(); _ = try await f.load()
        XCTAssertFalse(f.metadata.body.contains("assetId")); XCTAssertFalse(f.metadata.body.contains("issuedAt")); XCTAssertFalse(f.metadata.body.contains("version"))
        XCTAssertEqual(f.image.requests.count, 1)
    }
    func testPositiveInt64OriginalRouteAndInvalidIDs() throws {
        let r = try OwnMediaAudioPreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: Int64.max, token: "synthetic")
        XCTAssertEqual(r.url?.path, "/api/media/asset/9223372036854775807/preview")
        for id in [Int64(0), Int64(-1)] { XCTAssertThrowsError(try OwnMediaAudioPreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: id, token: "synthetic")) }
    }
    func testNoPreviewAuthorityFromAvailableListAlone() async throws {
        let f = try OwnerAudioFixture(); f.selected = nil
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testPreviewAuthorityStillRequiresLiveListSourceAndCurrentRow() async throws {
        let a = try OwnerAudioFixture(); a.list.isAvailable = false
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerAudioFixture(); b.row = nil
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testImageModelOtherAndWrongAssetCannotUseAudioLease() async throws {
        for type in [OwnMediaAsset.MediaType.image, .model3D, .other] {
            let f = try OwnerAudioFixture(); f.asset = .init(id: 9, reviewState: .hold, reviewReason: "", mediaType: type); f.row = f.asset
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
        }
        let f = try OwnerAudioFixture(); f.asset = .init(id: 10, reviewState: .approved, reviewReason: "", mediaType: .audio); f.row = f.asset
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
    }
    func testPendingRejectedUnavailableRemainOwnerPreviewWithoutApprovalVerdict() async throws {
        for state in [OwnMediaAsset.ReviewState.hold, .rejected, .unavailable, .approved] {
            let f = try OwnerAudioFixture(); f.asset = .init(id: 9, reviewState: state, reviewReason: "", mediaType: .audio); f.row = f.asset
            _ = try await f.load(); XCTAssertEqual(f.row?.reviewState, state)
        }
    }
    func testAllIdentityContextChangesRetireReaderPermanently() throws {
        for c in [try OwnerAudioFixture.context(account: 8), try OwnerAudioFixture.context(epoch: 2), try OwnerAudioFixture.context(role: "club"),
                  try OwnerAudioFixture.context(token: "other"), try OwnerAudioFixture.context(namespace: "other"),
                  try OwnerAudioFixture.context(base: "https://other.example.test"), try OwnerAudioFixture.context(market: .unitedStates)] {
            let f = try OwnerAudioFixture(); XCTAssertTrue(f.reader.isConfigured); f.current = c; XCTAssertFalse(f.reader.isConfigured)
            f.current = f.context; XCTAssertFalse(f.reader.isConfigured)
        }
    }
    func testViewerAndListScopeChangesInvalidateOldReader() throws {
        let f = try OwnerAudioFixture(); f.viewer = 4; XCTAssertFalse(f.reader.isConfigured)
        let g = try OwnerAudioFixture(); _ = g.reader; g.list.scope = UUID(); XCTAssertFalse(g.reader.isConfigured)
    }
    func testMetadataFinalForwardRechecksVisibilityAndSelectedSource() async throws {
        let a = try OwnerAudioFixture(); a.metadata.before = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerAudioFixture(); b.metadata.before = { b.selected = nil }
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testAudioFinalForwardRechecksCurrentRowAndGrant() async throws {
        let f = try OwnerAudioFixture(); f.image.before = { f.row = nil }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertEqual(f.metadata.requests.count, 1); XCTAssertTrue(f.image.requests.isEmpty)
        let g = try OwnerAudioFixture(); g.image.before = { g.approval.revoke() }
        do { _ = try await g.load(); XCTFail() } catch {}; XCTAssertTrue(g.image.requests.isEmpty)
    }
    func testLateMetadataResponseCannotStartAudioAfterListWithdrawal() async throws {
        let f = try OwnerAudioFixture(); f.metadata.after = { f.list.isAvailable = false }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testLateAudioResponseCannotPublishAfterCloseOrRowReplacement() async throws {
        let a = try OwnerAudioFixture(); a.image.after = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerAudioFixture(); b.image.after = { b.row = .init(id: 9, reviewState: .approved, reviewReason: "changed", mediaType: .audio) }
        do { _ = try await b.load(); XCTFail() } catch {}
    }
    func testMalformedDuplicateOrMissingURLPayloadNeverLoadsAudio() async throws {
        for body in ["{}", #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"url":"https://private-images.example.test/a.m4a"}}"#,
                     #"{"code":200,"code":200,"data":{"authorPreviewUrl":"https://private-images.example.test/a.m4a"}}"#, String(repeating: " ", count: 65_537)] {
            let f = try OwnerAudioFixture(); f.metadata.body = body
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidURLNeverRewrittenOrGivenCredential() async throws {
        for url in ["http://private-images.example.test/a.m4a", "https://other.example.test/a.m4a", "media-asset:9", "https://user@private-images.example.test/a.m4a", "https://private-images.example.test/a b.m4a", "https://private-images.example.test/a.m4a#fragment"] {
            let f = try OwnerAudioFixture(); f.metadata.body = OwnerAudioFixture.payload(url)
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidOriginAndExpiredOrWrongMarketLeaseAreRejected() throws {
        for origin in ["http://private-images.example.test", "https://private-images.example.test/", "https://private-images.example.test:0", "https://private-images.example.test:65536", "https://u@private-images.example.test"] {
            XCTAssertThrowsError(try OwnMediaAudioPreviewApproval(context: OwnerAudioFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [origin], expiresAt: .distantFuture))
        }
        XCTAssertThrowsError(try OwnMediaAudioPreviewApproval(context: OwnerAudioFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [], expiresAt: .distantFuture))
        XCTAssertThrowsError(try OwnMediaAudioPreviewApproval(context: OwnerAudioFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantPast))
        XCTAssertThrowsError(try OwnMediaAudioPreviewApproval(context: OwnerAudioFixture.context(market: .unitedStates), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture))
    }
    func testCurrentMetadataDenialRevokesOnlyItsPreviewLease() async throws {
        for code in [401, 403, 2] {
            let f = try OwnerAudioFixture(); f.metadata.body = "{\"code\":\(code)}"
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testCurrentHTTPDenialsRevokeOnlyTheSelectedPreviewLease() async throws {
        for status in [401, 403] {
            let f = try OwnerAudioFixture(); f.metadata.status = status
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testMetadataCannotBeRetargetedOrChangedToWriterAtFinalForward() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.url = URL(string: "https://other.example.test/api/media/asset/9/preview") },
            { $0.url = URL(string: "https://owner-api.example.test/native/api/media/asset/9/retry") },
            { $0.setValue("other-token", forHTTPHeaderField: "Authorization") }, { $0.httpMethod = "POST" }, { $0.httpBody = Data([1]) }]
        for mutate in mutations {
            let f = try OwnerAudioFixture(); f.metadata.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testLateDenialCannotRevokeReplacementLease() async throws {
        let f = try OwnerAudioFixture(), replacement = try OwnMediaAudioPreviewApproval(context: f.context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture)
        f.metadata.status = 401; f.metadata.after = { f.selected = replacement }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertFalse(replacement.revoked)
    }
    func testAudioFailureDoesNotRevokeLeaseOrApproveAnything() async throws {
        let f = try OwnerAudioFixture(); f.image.failure = OwnMediaAudioPreviewFailure.invalidResponse
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertEqual(f.row?.reviewState, .hold)
    }
    func testResourceAuthenticationErrorIsNotMetadataDenial() async throws {
        let f = try OwnerAudioFixture(); f.image.failure = OwnMediaAudioPreviewFailure.unauthorized
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertTrue(f.list.isAvailable)
    }
    func testNoPhaseCanSucceedWithoutForwardOrForwardTwice() async throws {
        for phase in [0, 1, 2, 3] {
            let f = try OwnerAudioFixture(); f.metadata.skip = phase == 0; f.metadata.twice = phase == 1; f.image.skip = phase == 2; f.image.twice = phase == 3
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertLessThanOrEqual(f.metadata.requests.count, 1); XCTAssertLessThanOrEqual(f.image.requests.count, 1)
        }
    }
    func testAudioTransportCannotAcceptAppTokenOrDifferentSignedURL() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.setValue("synthetic-owner", forHTTPHeaderField: "Authorization") }, { $0.url = URL(string: "https://private-images.example.test/other.m4a") }, { $0.httpMethod = "POST" }]
        for mutate in mutations {
            let f = try OwnerAudioFixture(); f.image.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testClientDisplayWindowIsNoLaterThanRequestStartPlus300Seconds() async throws {
        let f = try OwnerAudioFixture(), clock = ContinuousClock(), start = clock.now, value = try await f.load()
        XCTAssertLessThanOrEqual(value.displayDeadline, clock.now.advanced(by: .seconds(300)))
        XCTAssertGreaterThan(value.displayDeadline, start); XCTAssertLessThanOrEqual(value.displayDeadline, f.approval.clientDeadline)
    }
    func testAudioBytesAndHeadersAreBoundedAndWrongMIMEOrEndpointFailClosed() async throws {
        for bytes in [Data(), Data(repeating: 1, count: OwnMediaAudioBytes.maximumInputBytes + 1)] {
            let f = try OwnerAudioFixture(); f.image.bytes = bytes
            do { _ = try await f.load(); XCTFail() } catch {}
        }
        let url = URL(string: OwnerAudioFixture.url)!
        let good = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/wav"])!
        XCTAssertTrue(OwnMediaPrivateAudioReader.acceptsResponse(good, endpoint: url, audio: true))
        for headers in [["Content-Type": "text/html"], ["Content-Type": "audio/wav", "Content-Length": String(OwnMediaAudioBytes.maximumInputBytes + 1)], ["Content-Type": "audio/wav", "X-Large": String(repeating: "a", count: 32_769)]] {
            let bad = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
            XCTAssertFalse(OwnMediaPrivateAudioReader.acceptsResponse(bad, endpoint: url, audio: true))
        }
    }
    func testHeaderGateAcceptsOnlyBoundedOriginalContainersAndDoesNotProveDecode() {
        let headers: [[UInt8]] = [
            [82,73,70,70,4,0,0,0,87,65,86,69],
            [0,0,0,12,102,116,121,112,77,52,65,32],
            [73,68,51,4,0,0,0,0,0,0], [255,241,80,128,0,255,252], [255,251,144,0,0,0,0]]
        for header in headers { XCTAssertTrue(OwnMediaAudioBytes.accepts(Data(header))) }
        for data in [Data(), Data("<html>".utf8), Data([255,216,255,224,0,0,0,0,0,0,0,0])] { XCTAssertFalse(OwnMediaAudioBytes.accepts(data)) }
    }
    func testRetirementSynchronouslyCallsOnlyItsOwnerOnce() throws {
        let f = try OwnerAudioFixture(); var stops = 0; f.reader.onRetired = { stops += 1 }
        f.reader.retire(); XCTAssertEqual(stops, 1); f.reader.retire(); XCTAssertEqual(stops, 1); XCTAssertFalse(f.reader.isConfigured)
    }

}
