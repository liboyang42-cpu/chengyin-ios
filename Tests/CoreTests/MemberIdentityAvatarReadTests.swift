import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class CardAvatarMember: MemberHomeReading {
    var scope = UUID(), isSignedIn = true, isConfigured = true, roleInfoAvailable = false
    func identity() async throws -> MemberIdentitySnapshot { throw APIError.notConfigured }
    func roleInfo() async throws -> MemberRoleInfo { throw APIError.notConfigured }
}
@MainActor private final class CardAvatarBytes: MemberIdentityAvatarDispatching {
    var requests: [URLRequest] = [], bytes = Data([1, 2, 3]), cancelled = false, skip = false
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    func send(_ input: URLRequest, authorization: MemberIdentityAvatarAuthorization) async throws -> Data {
        before?(); var request = input; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        after?(); return bytes
    }
}
@MainActor private final class CardAvatarFixture {
    nonisolated static let raw = "https://card-images.example.test/avatar.png?Signature=A%2BB%3D&Expires=123"
    let member = CardAvatarMember(), bytes = CardAvatarBytes(), context: RuntimeDependencyContext
    let approval: MemberIdentityAvatarApproval
    var current: RuntimeDependencyContext?, viewer: UInt64? = 3, selected: MemberIdentityAvatarApproval?
    var observation: MemberIdentityAvatarObservation?
    lazy var reader = MemberIdentityAvatarReader(approval: approval, currentContext: { [unowned self] in current },
        currentViewer: { [unowned self] in viewer }, selected: { [unowned self] in selected }, member: member, transport: bytes)
    init() throws {
        context = try Self.context(); current = context
        approval = try .init(context: context, viewerRevision: 3, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(600)); selected = approval
        observation = .init(snapshot: try Self.snapshot(), scope: member.scope, readRevision: UUID(), requestStarted: ContinuousClock().now)
    }
    static func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-card", namespace: String = "card", base: String = "https://card-api.example.test/native", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    static func snapshot(id: Any = 7, raw: Any = CardAvatarFixture.raw) throws -> MemberIdentitySnapshot {
        try JSONDecoder().decode(MemberIdentitySnapshot.self, from: JSONSerialization.data(withJSONObject: ["id": id, "avatar": raw, "nickname": "Synthetic"]))
    }
    func load(_ value: MemberIdentityAvatarObservation? = nil) async throws -> Data {
        try await reader.image(try XCTUnwrap(value ?? observation), currentObservation: { [unowned self] in observation })
    }
}
@MainActor final class MemberIdentityAvatarReadTests: XCTestCase {
    func testDisplayTrimIsPreservedButSourceBytesAreNotTrimmed() throws {
        let raw = " \n" + CardAvatarFixture.raw + "\t", value = try CardAvatarFixture.snapshot(raw: raw)
        XCTAssertEqual(value.avatar, CardAvatarFixture.raw); XCTAssertEqual(Data(try XCTUnwrap(value.avatarSource).utf8), Data(raw.utf8))
    }
    func testInvalidAvatarTypeDoesNotInventSource() throws {
        for raw in [NSNull(), 7, ["url": "synthetic"]] as [Any] {
            let value = try CardAvatarFixture.snapshot(raw: raw); XCTAssertEqual(value.avatar, ""); XCTAssertNil(value.avatarSource)
            XCTAssertNil(MemberIdentityAvatarObservation(snapshot: value, scope: UUID(), readRevision: UUID(), requestStarted: ContinuousClock().now))
        }
    }
    func testMissingForeignAndNonpositiveSubjectCannotBecomeSelf() async throws {
        for id in [NSNull(), 0, -1, 8] as [Any] {
            let f = try CardAvatarFixture()
            f.observation = .init(snapshot: try CardAvatarFixture.snapshot(id: id), scope: f.member.scope, readRevision: UUID(), requestStarted: ContinuousClock().now)
            if let observation = f.observation { XCTAssertFalse(f.reader.accepts(observation)); do { _ = try await f.load(); XCTFail() } catch {} }
            XCTAssertTrue(f.bytes.requests.isEmpty)
        }
    }
    func testOriginalStringNumericIDIsSupportedWithoutFallbackIdentity() throws {
        let f = try CardAvatarFixture(), observation = try XCTUnwrap(MemberIdentityAvatarObservation(snapshot: CardAvatarFixture.snapshot(id: "7"), scope: f.member.scope, readRevision: UUID(), requestStarted: ContinuousClock().now))
        XCTAssertTrue(f.reader.accepts(observation))
    }
    func testExactSignedURLIsAnonymousGETAndNeverReissued() async throws {
        let f = try CardAvatarFixture(), data = try await f.load(); XCTAssertEqual(data, Data([1, 2, 3]))
        let request = try XCTUnwrap(f.bytes.requests.first)
        XCTAssertEqual(Data(try XCTUnwrap(request.url?.absoluteString).utf8), Data(CardAvatarFixture.raw.utf8))
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertNil(request.httpBodyStream)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testOriginsMustBeExplicitCanonicalHTTPS() throws {
        for origin in ["", "http://card-images.example.test", "https://CARD-images.example.test", "https://card-images.example.test/", "https://u:p@card-images.example.test", "https://card-images.example.test?q=1", "https://card-images.example.test#f", "https://card-images.example.test:0"] {
            XCTAssertThrowsError(try MemberIdentityAvatarApproval(context: CardAvatarFixture.context(), viewerRevision: 3, approvedOrigins: [origin], expiresAt: Date().addingTimeInterval(60)))
        }
        XCTAssertThrowsError(try MemberIdentityAvatarApproval(context: CardAvatarFixture.context(), viewerRevision: 3, approvedOrigins: [], expiresAt: Date().addingTimeInterval(60)))
    }
    func testExpiredNonfiniteAndWrongMarketLeasesFailClosed() throws {
        for date in [Date.distantPast, Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertThrowsError(try MemberIdentityAvatarApproval(context: CardAvatarFixture.context(), viewerRevision: 3, approvedOrigins: ["https://card-images.example.test"], expiresAt: date))
        }
        XCTAssertThrowsError(try MemberIdentityAvatarApproval(context: CardAvatarFixture.context(market: .unitedStates), viewerRevision: 3, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(60)))
    }
    func testWhitespaceRelativeCredentialFragmentAndForeignURLCannotDispatch() async throws {
        for raw in [" " + CardAvatarFixture.raw, CardAvatarFixture.raw + "\n", "/profile/avatar.png", "http://card-images.example.test/a", "https://foreign.example.test/a", "https://u:p@card-images.example.test/a", "https://card-images.example.test/a#fragment", "https://card-images.example.test/", "media-asset:7"] {
            let f = try CardAvatarFixture(); f.observation = .init(snapshot: try CardAvatarFixture.snapshot(raw: raw), scope: f.member.scope, readRevision: UUID(), requestStarted: ContinuousClock().now)
            do { _ = try await f.load(); XCTFail(raw) } catch {}; XCTAssertTrue(f.bytes.requests.isEmpty)
        }
    }
    func testOversizedSourceCannotCreateObservation() throws {
        XCTAssertNil(MemberIdentityAvatarObservation(snapshot: try CardAvatarFixture.snapshot(raw: String(repeating: "a", count: 8193)), scope: UUID(), readRevision: UUID(), requestStarted: ContinuousClock().now))
    }
    func testScopeAndGenerationBindOneMetadataObservation() async throws {
        let f = try CardAvatarFixture(), original = try XCTUnwrap(f.observation)
        f.observation = .init(snapshot: try CardAvatarFixture.snapshot(), scope: f.member.scope, readRevision: UUID(), requestStarted: original.requestStarted)
        do { _ = try await f.load(original); XCTFail() } catch {}; XCTAssertTrue(f.bytes.requests.isEmpty)
        f.member.scope = UUID(); XCTAssertFalse(f.reader.accepts(try XCTUnwrap(f.observation)))
    }
    func testObservationEqualityUsesOriginalUTF8NotUnicodeCanonicalEquality() throws {
        let f = try CardAvatarFixture(), revision = UUID(), start = ContinuousClock().now
        let a = MemberIdentityAvatarObservation(snapshot: try CardAvatarFixture.snapshot(raw: "https://card-images.example.test/é"), scope: f.member.scope, readRevision: revision, requestStarted: start)
        let b = MemberIdentityAvatarObservation(snapshot: try CardAvatarFixture.snapshot(raw: "https://card-images.example.test/e\u{301}"), scope: f.member.scope, readRevision: revision, requestStarted: start)
        XCTAssertNotEqual(a, b)
    }
    func testThreeHundredSecondLimitStartsBeforeMetadataNotAtImageFetch() throws {
        let f = try CardAvatarFixture(), old = ContinuousClock().now.advanced(by: .seconds(-301))
        let observation = try XCTUnwrap(MemberIdentityAvatarObservation(snapshot: CardAvatarFixture.snapshot(), scope: f.member.scope, readRevision: UUID(), requestStarted: old))
        XCTAssertFalse(f.reader.accepts(observation)); XCTAssertEqual(f.reader.deadline(for: observation), old.advanced(by: .seconds(300)))
    }
    func testFutureObservationIsNotAProducerTimestamp() throws {
        let f = try CardAvatarFixture(), future = ContinuousClock().now.advanced(by: .seconds(100))
        let observation = try XCTUnwrap(MemberIdentityAvatarObservation(snapshot: CardAvatarFixture.snapshot(), scope: f.member.scope, readRevision: UUID(), requestStarted: future))
        XCTAssertFalse(f.reader.accepts(observation))
    }
    func testFullContextChangesPermanentlyRetireOldReader() throws {
        for next in [try CardAvatarFixture.context(account: 8), try CardAvatarFixture.context(epoch: 2), try CardAvatarFixture.context(role: "merchant"), try CardAvatarFixture.context(token: "other"), try CardAvatarFixture.context(namespace: "other"), try CardAvatarFixture.context(base: "https://other.example.test"), try CardAvatarFixture.context(market: .unitedStates)] {
            let f = try CardAvatarFixture(); XCTAssertTrue(f.reader.isConfigured); f.current = next; XCTAssertFalse(f.reader.isConfigured)
            f.current = f.context; XCTAssertFalse(f.reader.isConfigured)
        }
    }
    func testViewerAndMissingSourceCannotAdoptOldReader() throws {
        let f = try CardAvatarFixture(); f.viewer = 4; XCTAssertFalse(f.reader.isConfigured); f.viewer = 3; XCTAssertFalse(f.reader.isConfigured)
        let g = try CardAvatarFixture(); g.selected = nil; XCTAssertFalse(g.reader.isConfigured); g.selected = g.approval; XCTAssertFalse(g.reader.isConfigured)
    }
    func testDirectRevokeRetiresSynchronouslyAndOnlyOnce() throws {
        let f = try CardAvatarFixture(); var clears = 0; f.reader.onRetire = { clears += 1 }
        f.approval.revoke(); XCTAssertEqual(clears, 1); f.approval.revoke(); XCTAssertEqual(clears, 1); XCTAssertFalse(f.reader.isConfigured)
    }
    func testRetireBeforeForwardDoesNotDispatch() async throws {
        let f = try CardAvatarFixture(); f.bytes.before = { f.reader.retire() }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.bytes.requests.isEmpty)
    }
    func testLateSuccessAfterSnapshotWithdrawalCannotReturnBytes() async throws {
        let f = try CardAvatarFixture(); f.bytes.after = { f.observation = nil }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertEqual(f.bytes.requests.count, 1)
    }
    func testDirectRevokeCancelsAlreadyForwardedWork() async throws {
        let f = try CardAvatarFixture(); f.bytes.after = { f.approval.revoke() }
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.bytes.cancelled)
    }
    func testTransportCannotFabricateSuccessfulDispatch() async throws {
        let f = try CardAvatarFixture(); f.bytes.skip = true
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.bytes.requests.isEmpty)
    }
    func testAuthorizationRejectsMethodURLTokenCookieBodyAndCacheMutation() async throws {
        let mutations: [(inout URLRequest) -> Void] = [
            { $0.httpMethod = "POST" }, { $0.url = URL(string: "https://card-images.example.test/other")! },
            { $0.setValue("synthetic", forHTTPHeaderField: "Authorization") }, { $0.setValue("synthetic", forHTTPHeaderField: "Cookie") },
            { $0.httpBody = Data([1]) }, { $0.httpShouldHandleCookies = true }, { $0.cachePolicy = .returnCacheDataElseLoad },
            { $0.setValue("*/*", forHTTPHeaderField: "Accept") }
        ]
        for mutation in mutations {
            let f = try CardAvatarFixture(); f.bytes.mutate = mutation
            do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertTrue(f.bytes.requests.isEmpty)
        }
    }
    func testOneAuthorizationCannotForwardTwice() throws {
        let request = try MemberIdentityAvatarReader.request(originalURL: CardAvatarFixture.raw, origins: ["https://card-images.example.test"])
        let auth = MemberIdentityAvatarAuthorization(expected: request, current: { true }); var sends = 0
        try auth.forward(request, cancel: {}) { sends += 1 }; XCTAssertThrowsError(try auth.forward(request, cancel: {}) { sends += 1 }); XCTAssertEqual(sends, 1)
    }
    func testOneReaderCannotRepeatResourceDispatch() async throws {
        let f = try CardAvatarFixture(); _ = try await f.load()
        do { _ = try await f.load(); XCTFail() } catch {}; XCTAssertEqual(f.bytes.requests.count, 1)
    }
    func testEmptyAndOverBudgetBytesFailClosed() async throws {
        for data in [Data(), Data(repeating: 0, count: RetainedSelectedImage.maximumInputBytes + 1)] {
            let f = try CardAvatarFixture(); f.bytes.bytes = data; do { _ = try await f.load(); XCTFail() } catch {}
        }
    }
    func testResponseStatusMIMEExactEndpointAndAdvertisedSizeAreBounded() throws {
        let url = URL(string: CardAvatarFixture.raw)!
        func response(_ status: Int = 200, _ headers: [String: String] = ["Content-Type": "image/png"], _ endpoint: URL? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: endpoint ?? url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        XCTAssertTrue(MemberIdentityAvatarTransport.acceptsResponse(response(), endpoint: url))
        for status in [201, 204, 206, 301, 401, 403, 500] { XCTAssertFalse(MemberIdentityAvatarTransport.acceptsResponse(response(status), endpoint: url)) }
        XCTAssertFalse(MemberIdentityAvatarTransport.acceptsResponse(response(200, ["Content-Type": "text/html"]), endpoint: url))
        XCTAssertFalse(MemberIdentityAvatarTransport.acceptsResponse(response(200, ["Content-Type": "image/png", "Content-Length": "20971521"]), endpoint: url))
        XCTAssertFalse(MemberIdentityAvatarTransport.acceptsResponse(response(200, ["Content-Type": "image/png"], URL(string: "https://foreign.example.test/a")!), endpoint: url))
    }
    func testUnauthenticatedOrDormantMetadataReaderCannotFetchAvatar() throws {
        let f = try CardAvatarFixture(); f.member.isSignedIn = false; XCTAssertFalse(f.reader.isConfigured)
        let g = try CardAvatarFixture(); g.member.isConfigured = false; XCTAssertFalse(g.reader.isConfigured)
    }
}
