import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private enum OwnerModelSynthetic {
    static func triangle(changes: [String: Any] = [:]) -> Data {
        var root: [String: Any] = ["asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]], "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "buffers": [["byteLength": 36]], "bufferViews": [["buffer": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]]]]
        for (key, value) in changes { root[key] = value }
        var json = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        while json.count % 4 != 0 { json.append(0x20) }
        var data = Data()
        func append(_ value: UInt32) { for shift in [0,8,16,24] { data.append(UInt8((value >> shift) & 255)) } }
        append(0x46546C67); append(2); append(UInt32(28 + json.count + 36)); append(UInt32(json.count)); append(0x4E4F534A)
        data.append(json); append(36); append(0x004E4942)
        for value: Float in [0,0,0, 1,0,0, 0,1,0] { append(value.bitPattern) }; return data
    }
}

@MainActor private final class OwnerModelList: OwnMediaReading {
    var scope = UUID(), isSignedIn = true, isAvailable = true
    var pages = 0
    func page(before cursor: Int64?) async throws -> OwnMediaPage { pages += 1; return .init(rows: []) }
}
@MainActor private final class OwnerModelMetadata: OwnMediaModelPreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, body = OwnerModelFixture.payload()
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, cancelled = false
    func send(_ input: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> (Data, Int) {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); return (Data(body.utf8), status)
    }
}
@MainActor private final class OwnerModelBytes: OwnMediaPrivateModelReading {
    var requests: [URLRequest] = [], bytes = OwnerModelSynthetic.triangle(), cancelled = false
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, twice = false, failure: Error?
    func model(_ input: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> Data {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if twice { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); if let failure { throw failure }; return bytes
    }
}
@MainActor private final class OwnerModelFixture {
    nonisolated static let url = "https://private-images.example.test/object.glb?Expires=123&Signature=a%2Bb%3D"
    let context: RuntimeDependencyContext, approval: OwnMediaModelPreviewApproval
    let list = OwnerModelList(), metadata = OwnerModelMetadata(), image = OwnerModelBytes()
    var current: RuntimeDependencyContext?, viewer: UInt64? = 3, selected: OwnMediaModelPreviewApproval?, visible = true
    var asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Waiting", mediaType: .model3D)
    var row: OwnMediaAsset?
    lazy var reader = OwnMediaModelPreviewReader(approval: approval, currentContext: { [unowned self] in current },
        currentViewerRevision: { [unowned self] in viewer }, selected: { [unowned self] in selected }, listReader: list, metadata: metadata, modelReader: image)
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
    nonisolated static func payload(_ url: String = OwnerModelFixture.url) -> String { "{\"code\":200,\"data\":{\"authorPreviewUrl\":\"\(url)\"}}" }
    func load() async throws -> OwnMediaModelPreviewData {
        try await reader.load(asset: asset, currentAsset: { [unowned self] in row }, presentationIsCurrent: { [unowned self] in visible })
    }
}
@MainActor final class OwnMediaModelPreviewReadTests: XCTestCase {
    func testTwoExactReadsKeepCredentialAtFirstPartyAndSignatureAtModelOrigin() async throws {
        let f = try OwnerModelFixture(), data = try await f.load()
        let metadata = try XCTUnwrap(f.metadata.requests.first), image = try XCTUnwrap(f.image.requests.first)
        XCTAssertEqual(metadata.url?.absoluteString, "https://owner-api.example.test/native/api/media/asset/9/preview")
        XCTAssertEqual(metadata.httpMethod, "GET"); XCTAssertEqual(metadata.value(forHTTPHeaderField: "Authorization"), "synthetic-owner")
        XCTAssertNil(metadata.httpBody); XCTAssertNil(metadata.url?.query)
        XCTAssertEqual(image.url?.absoluteString, OwnerModelFixture.url); XCTAssertEqual(image.httpMethod, "GET")
        XCTAssertNil(image.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(image.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(image.httpBody)
        XCTAssertEqual(data.bytes, f.image.bytes); XCTAssertEqual(f.list.pages, 0)
    }
    func testResponseNeedsOnlyOriginalURLNotInventedIdentityOrTimeFields() async throws {
        let f = try OwnerModelFixture(); _ = try await f.load()
        XCTAssertFalse(f.metadata.body.contains("assetId")); XCTAssertFalse(f.metadata.body.contains("issuedAt")); XCTAssertFalse(f.metadata.body.contains("version"))
        XCTAssertEqual(f.image.requests.count, 1)
    }
    func testPositiveInt64OriginalRouteAndInvalidIDs() throws {
        let r = try OwnMediaModelPreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: Int64.max, token: "synthetic")
        XCTAssertEqual(r.url?.path, "/api/media/asset/9223372036854775807/preview")
        for id in [Int64(0), Int64(-1)] { XCTAssertThrowsError(try OwnMediaModelPreviewRoute.request(baseURL: URL(string: "https://owner-api.example.test")!, assetID: id, token: "synthetic")) }
    }
    func testNoPreviewAuthorityFromAvailableListAlone() async throws {
        let f = try OwnerModelFixture(); f.selected = nil
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testPreviewAuthorityStillRequiresLiveListSourceAndCurrentRow() async throws {
        let a = try OwnerModelFixture(); a.list.isAvailable = false
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerModelFixture(); b.row = nil
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testImageAudioOtherAndWrongAssetCannotUseModelLease() async throws {
        for type in [OwnMediaAsset.MediaType.image, .audio, .other] {
            let f = try OwnerModelFixture(); f.asset = .init(id: 9, reviewState: .hold, reviewReason: "", mediaType: type); f.row = f.asset
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
        }
        let f = try OwnerModelFixture(); f.asset = .init(id: 10, reviewState: .approved, reviewReason: "", mediaType: .model3D); f.row = f.asset
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty)
    }
    func testPendingRejectedUnavailableRemainOwnerPreviewWithoutApprovalVerdict() async throws {
        for state in [OwnMediaAsset.ReviewState.hold, .rejected, .unavailable, .approved] {
            let f = try OwnerModelFixture(); f.asset = .init(id: 9, reviewState: state, reviewReason: "", mediaType: .model3D); f.row = f.asset
            _ = try await f.load(); XCTAssertEqual(f.row?.reviewState, state)
        }
    }
    func testAllIdentityContextChangesRetireReaderPermanently() throws {
        for c in [try OwnerModelFixture.context(account: 8), try OwnerModelFixture.context(epoch: 2), try OwnerModelFixture.context(role: "club"),
                  try OwnerModelFixture.context(token: "other"), try OwnerModelFixture.context(namespace: "other"),
                  try OwnerModelFixture.context(base: "https://other.example.test"), try OwnerModelFixture.context(market: .unitedStates)] {
            let f = try OwnerModelFixture(); XCTAssertTrue(f.reader.isConfigured); f.current = c; XCTAssertFalse(f.reader.isConfigured)
            f.current = f.context; XCTAssertFalse(f.reader.isConfigured)
        }
    }
    func testViewerAndListScopeChangesInvalidateOldReader() throws {
        let f = try OwnerModelFixture(); f.viewer = 4; XCTAssertFalse(f.reader.isConfigured)
        let g = try OwnerModelFixture(); _ = g.reader; g.list.scope = UUID(); XCTAssertFalse(g.reader.isConfigured)
    }
    func testMetadataFinalForwardRechecksVisibilityAndSelectedSource() async throws {
        let a = try OwnerModelFixture(); a.metadata.before = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerModelFixture(); b.metadata.before = { b.selected = nil }
        do { _ = try await b.load(); XCTFail() } catch {}
        XCTAssertTrue(a.metadata.requests.isEmpty); XCTAssertTrue(b.metadata.requests.isEmpty)
    }
    func testModelFinalForwardRechecksCurrentRowAndGrant() async throws {
        let f = try OwnerModelFixture(); f.image.before = { f.row = nil }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertEqual(f.metadata.requests.count, 1); XCTAssertTrue(f.image.requests.isEmpty)
        let g = try OwnerModelFixture(); g.image.before = { g.approval.revoke() }
        do { _ = try await g.load(); XCTFail() } catch {}; XCTAssertTrue(g.image.requests.isEmpty)
    }
    func testLateMetadataResponseCannotStartModelAfterListWithdrawal() async throws {
        let f = try OwnerModelFixture(); f.metadata.after = { f.list.isAvailable = false }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
    }
    func testLateModelResponseCannotPublishAfterCloseOrRowReplacement() async throws {
        let a = try OwnerModelFixture(); a.image.after = { a.visible = false }
        do { _ = try await a.load(); XCTFail() } catch {}
        let b = try OwnerModelFixture(); b.image.after = { b.row = .init(id: 9, reviewState: .approved, reviewReason: "changed", mediaType: .model3D) }
        do { _ = try await b.load(); XCTFail() } catch {}
    }
    func testMalformedDuplicateOrMissingURLPayloadNeverLoadsModel() async throws {
        for body in ["{}", #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"url":"https://private-images.example.test/a.m4a"}}"#,
                     #"{"code":200,"code":200,"data":{"authorPreviewUrl":"https://private-images.example.test/a.m4a"}}"#, String(repeating: " ", count: 65_537)] {
            let f = try OwnerModelFixture(); f.metadata.body = body
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidURLNeverRewrittenOrGivenCredential() async throws {
        for url in ["http://private-images.example.test/a.m4a", "https://other.example.test/a.m4a", "media-asset:9", "https://user@private-images.example.test/a.m4a", "https://private-images.example.test/a b.m4a", "https://private-images.example.test/a.m4a#fragment"] {
            let f = try OwnerModelFixture(); f.metadata.body = OwnerModelFixture.payload(url)
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testInvalidOriginAndExpiredOrWrongMarketLeaseAreRejected() throws {
        for origin in ["http://private-images.example.test", "https://private-images.example.test/", "https://private-images.example.test:0", "https://private-images.example.test:65536", "https://u@private-images.example.test"] {
            XCTAssertThrowsError(try OwnMediaModelPreviewApproval(context: OwnerModelFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [origin], expiresAt: .distantFuture))
        }
        XCTAssertThrowsError(try OwnMediaModelPreviewApproval(context: OwnerModelFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: [], expiresAt: .distantFuture))
        XCTAssertThrowsError(try OwnMediaModelPreviewApproval(context: OwnerModelFixture.context(), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantPast))
        XCTAssertThrowsError(try OwnMediaModelPreviewApproval(context: OwnerModelFixture.context(market: .unitedStates), viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture))
    }
    func testCurrentMetadataDenialRevokesOnlyItsPreviewLease() async throws {
        for code in [401, 403, 2] {
            let f = try OwnerModelFixture(); f.metadata.body = "{\"code\":\(code)}"
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testCurrentHTTPDenialsRevokeOnlyTheSelectedPreviewLease() async throws {
        for status in [401, 403] {
            let f = try OwnerModelFixture(); f.metadata.status = status
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.approval.revoked); XCTAssertTrue(f.list.isAvailable); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testMetadataCannotBeRetargetedOrChangedToWriterAtFinalForward() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.url = URL(string: "https://other.example.test/api/media/asset/9/preview") },
            { $0.url = URL(string: "https://owner-api.example.test/native/api/media/asset/9/retry") },
            { $0.setValue("other-token", forHTTPHeaderField: "Authorization") }, { $0.httpMethod = "POST" }, { $0.httpBody = Data([1]) }]
        for mutate in mutations {
            let f = try OwnerModelFixture(); f.metadata.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testLateDenialCannotRevokeReplacementLease() async throws {
        let f = try OwnerModelFixture(), replacement = try OwnMediaModelPreviewApproval(context: f.context, viewerRevision: 3, assetID: 9, approvedOrigins: ["https://private-images.example.test"], expiresAt: .distantFuture)
        f.metadata.status = 401; f.metadata.after = { f.selected = replacement }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertFalse(replacement.revoked)
    }
    func testModelFailureDoesNotRevokeLeaseOrApproveAnything() async throws {
        let f = try OwnerModelFixture(); f.image.failure = OwnMediaModelPreviewFailure.invalidResponse
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertEqual(f.row?.reviewState, .hold)
    }
    func testResourceAuthenticationErrorIsNotMetadataDenial() async throws {
        let f = try OwnerModelFixture(); f.image.failure = OwnMediaModelPreviewFailure.unauthorized
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertFalse(f.approval.revoked); XCTAssertTrue(f.list.isAvailable)
    }
    func testNoPhaseCanSucceedWithoutForwardOrForwardTwice() async throws {
        for phase in [0, 1, 2, 3] {
            let f = try OwnerModelFixture(); f.metadata.skip = phase == 0; f.metadata.twice = phase == 1; f.image.skip = phase == 2; f.image.twice = phase == 3
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertLessThanOrEqual(f.metadata.requests.count, 1); XCTAssertLessThanOrEqual(f.image.requests.count, 1)
        }
    }
    func testModelTransportCannotAcceptAppTokenOrDifferentSignedURL() async throws {
        let mutations: [(inout URLRequest) -> Void] = [{ $0.setValue("synthetic-owner", forHTTPHeaderField: "Authorization") }, { $0.url = URL(string: "https://private-images.example.test/other.m4a") }, { $0.httpMethod = "POST" }]
        for mutate in mutations {
            let f = try OwnerModelFixture(); f.image.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.image.requests.isEmpty)
        }
    }
    func testClientDisplayWindowIsNoLaterThanRequestStartPlus300Seconds() async throws {
        let f = try OwnerModelFixture(), clock = ContinuousClock(), start = clock.now, value = try await f.load()
        XCTAssertLessThanOrEqual(value.displayDeadline, clock.now.advanced(by: .seconds(300)))
        XCTAssertGreaterThan(value.displayDeadline, start); XCTAssertLessThanOrEqual(value.displayDeadline, f.approval.clientDeadline)
    }
    func testModelBytesAndHeadersAreBoundedAndWrongMIMEOrEndpointFailClosed() async throws {
        for bytes in [Data(), Data(repeating: 1, count: OwnMediaModelBytes.maximumInputBytes + 1)] {
            let f = try OwnerModelFixture(); f.image.bytes = bytes
            do { _ = try await f.load(); XCTFail() } catch {}
        }
        let url = URL(string: OwnerModelFixture.url)!
        let good = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "model/gltf-binary"])!
        XCTAssertTrue(OwnMediaPrivateModelReader.acceptsResponse(good, endpoint: url, model: true))
        for headers in [["Content-Type": "text/html"], ["Content-Type": "model/gltf-binary", "Content-Length": String(OwnMediaModelBytes.maximumInputBytes + 1)], ["Content-Type": "model/gltf-binary", "X-Large": String(repeating: "a", count: 32_769)]] {
            let bad = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
            XCTAssertFalse(OwnMediaPrivateModelReader.acceptsResponse(bad, endpoint: url, model: true))
        }
    }
    func testStaticGLBProfileRequiresCompleteBoundedBinaryNotAHeader() {
        XCTAssertTrue(OwnMediaModelBytes.accepts(OwnerModelSynthetic.triangle()))
        for data in [Data(), Data("glTF".utf8), Data("<html>".utf8), Data([82,73,70,70,4,0,0,0,87,65,86,69])] { XCTAssertFalse(OwnMediaModelBytes.accepts(data)) }
    }
    func testAnimatedSkinnedExtendedAndExternalModelsRemainUnsupported() {
        for changes: [String: Any] in [["animations": [[:]]], ["skins": [[:]]], ["extensionsUsed": ["KHR_materials_unlit"]],
                                      ["buffers": [["byteLength": 36, "uri": "https://not-authorized.invalid/data.bin"]]]] {
            XCTAssertFalse(OwnMediaModelBytes.accepts(OwnerModelSynthetic.triangle(changes: changes)))
        }
    }
    func testRetirementSynchronouslyCallsOnlyItsOwnerOnce() throws {
        let f = try OwnerModelFixture(); var stops = 0; f.reader.onRetired = { stops += 1 }
        f.reader.retire(); XCTAssertEqual(stops, 1); f.reader.retire(); XCTAssertEqual(stops, 1); XCTAssertFalse(f.reader.isConfigured)
    }

}
