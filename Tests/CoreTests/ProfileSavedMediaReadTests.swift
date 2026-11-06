import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor private final class SavedMediaWire: ProfileSavedMediaDispatching {
    var requests: [URLRequest] = [], bytes = Data([1, 2, 3])
    var before: (() -> Void)?, after: (() -> Void)?, mutate: ((inout URLRequest) -> Void)?
    var skip = false, duplicate = false, cancelled = false
    func send(_ value: URLRequest, authorization: ProfileSavedMediaReadAuthorization) async throws -> Data {
        before?(); var request = value; mutate?(&request)
        if !skip { try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) } }
        if duplicate { try authorization.forward(request, cancel: {}) { requests.append(request) } }
        after?(); return bytes
    }
}
@MainActor private final class SavedMediaFixture {
    let context: RuntimeDependencyContext, approval: ProfileSavedMediaReadApproval, wire = SavedMediaWire()
    var current: RuntimeDependencyContext?, session: ProfileEditSession?, selected: ProfileSavedMediaReadApproval?
    var snapshot: ProfileEditSnapshot
    lazy var reader = ProfileCurrentMediaReader(approval: approval, currentContext: { [unowned self] in current },
        currentSession: { [unowned self] in session }, selected: { [unowned self] in selected }, transport: wire)
    init(kind: ProfileCurrentMediaKind = .caseImage) throws {
        context = try Self.context(); current = context
        session = try .init(accountID: 7, epoch: 1, token: "synthetic-media", viewerRevision: 3)
        approval = try .init(context: context, viewerRevision: 3, kind: kind,
            approvedOrigins: ["https://media.example.test"], expiresAt: Date().addingTimeInterval(600))
        selected = approval; snapshot = try Self.snapshot()
    }
    static func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-media", role: String = "player",
                        namespace: String = "saved-test", base: String = "https://api.example.test/native", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    nonisolated static let url = "https://media.example.test/photo.jpg?Expires=123&Signature=a%2Bb%3D&x=1"
    static func snapshot(id: Int = 7, avatar: String = url, work: String = url, qr: String = url,
                         name: String = "Saved", phone: String = "13812345678") throws -> ProfileEditSnapshot {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "nickname": name, "introduction": "", "avatar": avatar,
            "casePics": work, "wechat": qr, "tagIds": "", "phone": phone])
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: data)
    }
    func key(_ kind: ProfileCurrentMediaKind? = nil, index: Int = 0) -> ProfileCurrentMediaReadKey? {
        reader.key(snapshot: snapshot, kind: kind ?? approval.kind, originalIndex: index, identity: session?.identity, viewerRevision: session?.viewerRevision)
    }
    func load() async throws -> Data {
        let key = try XCTUnwrap(key()); return try await reader.image(snapshot: snapshot, key: key, currentSnapshot: { [unowned self] in snapshot })
    }
}
@MainActor final class ProfileSavedMediaReadTests: XCTestCase {
    func testExactSignedURLIsAnonymousGETAndNoBody() async throws {
        let f = try SavedMediaFixture(); _ = try await f.load(); let r = try XCTUnwrap(f.wire.requests.first)
        XCTAssertEqual(r.url?.absoluteString, SavedMediaFixture.url); XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(r.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(r.httpBody)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Accept"), "image/*"); XCTAssertFalse(r.httpShouldHandleCookies)
    }
    func testPurposesCannotBorrowEachOthersAuthority() throws {
        for kind in ProfileCurrentMediaKind.allCases {
            let f = try SavedMediaFixture(kind: kind)
            for other in ProfileCurrentMediaKind.allCases where other != kind { XCTAssertNil(f.key(other)) }
        }
    }
    func testAvatarFacadeRejectsNonAvatarReader() throws {
        XCTAssertNil(ProfileCurrentAvatarReader(reader: try SavedMediaFixture().reader))
        XCTAssertNotNil(ProfileCurrentAvatarReader(reader: try SavedMediaFixture(kind: .avatar).reader))
    }
    func testInvalidOriginsAndExpiredApprovalFailClosed() throws {
        for origin in ["http://media.example.test", "https://media.example.test/", "https://user@media.example.test", "https://media.example.test:0", "https://media.example.test:65536", "https://media.example.test?q=1", "https://media.example.test#x", "https://MEDIA.example.test"] {
            XCTAssertThrowsError(try ProfileSavedMediaReadApproval(context: SavedMediaFixture.context(), viewerRevision: 3,
                kind: .caseImage, approvedOrigins: [origin], expiresAt: Date().addingTimeInterval(600)))
        }
        XCTAssertThrowsError(try ProfileSavedMediaReadApproval(context: SavedMediaFixture.context(), viewerRevision: 3,
            kind: .caseImage, approvedOrigins: ["https://media.example.test"], expiresAt: .distantPast))
    }
    func testUSApprovalAndEmptyOriginSetCannotEnableRead() throws {
        XCTAssertThrowsError(try ProfileSavedMediaReadApproval(context: SavedMediaFixture.context(market: .unitedStates), viewerRevision: 3,
            kind: .caseImage, approvedOrigins: ["https://media.example.test"], expiresAt: .distantFuture))
        XCTAssertThrowsError(try ProfileSavedMediaReadApproval(context: SavedMediaFixture.context(), viewerRevision: 3,
            kind: .caseImage, approvedOrigins: [], expiresAt: .distantFuture))
    }
    func testOriginalSourcesRetainDuplicatesAndCapPositionsWithoutReserialization() throws {
        let raw = Array(repeating: SavedMediaFixture.url, count: 101).joined(separator: ";")
        let s = try SavedMediaFixture.snapshot(work: raw)
        XCTAssertEqual(ProfileCurrentMediaReader.sources(snapshot: s, kind: .caseImage).count, 100)
        XCTAssertEqual(s.casePics, raw); XCTAssertEqual(ProfileCasePortfolio(casePics: s.casePics).omittedImageCount, 1)
        let f = try SavedMediaFixture(); f.snapshot = s
        XCTAssertNotEqual(f.key(index: 0), f.key(index: 1)); XCTAssertNil(f.key(index: 100)); XCTAssertNil(f.key(index: -1))
    }
    func testInvalidRawSourcesAreNotRewrittenOrResolved() throws {
        for raw in ["", "media-asset:5", "/profile/upload/a.jpg", "http://media.example.test/a.jpg", "https://other.example.test/a.jpg", "https://user@media.example.test/a.jpg", "https://media.example.test/a.jpg#fragment", "https://media.example.test/a b.jpg", "https://media.example.test/"] {
            let f = try SavedMediaFixture(); f.snapshot = try SavedMediaFixture.snapshot(work: raw); XCTAssertNil(f.key())
        }
    }
    func testOtherSnapshotOwnerOrViewerCannotRead() throws {
        let f = try SavedMediaFixture(); f.snapshot = try SavedMediaFixture.snapshot(id: 8); XCTAssertNil(f.key())
        f.snapshot = try SavedMediaFixture.snapshot(); f.session = try .init(accountID: 7, epoch: 1, token: "synthetic-media", viewerRevision: 4); XCTAssertNil(f.key())
    }
    func testAllContextChangesRetireOldSource() throws {
        for context in [try SavedMediaFixture.context(account: 8), try SavedMediaFixture.context(epoch: 2), try SavedMediaFixture.context(token: "replacement"),
                        try SavedMediaFixture.context(role: "club"), try SavedMediaFixture.context(namespace: "other"),
                        try SavedMediaFixture.context(base: "https://other.example.test/native"), try SavedMediaFixture.context(market: .unitedStates)] {
            let f = try SavedMediaFixture(); XCTAssertNotNil(f.key()); f.current = context; XCTAssertNil(f.key())
            f.current = f.context; XCTAssertNil(f.key())
        }
    }
    func testTokenByteChangesAndMissingSessionFailClosed() throws {
        let f = try SavedMediaFixture(); f.session = try .init(accountID: 7, epoch: 1, token: "other", viewerRevision: 3); XCTAssertNil(f.key())
        let g = try SavedMediaFixture(); g.session = nil; XCTAssertNil(g.key())
    }
    func testSelectedSourceRemovalBeforeFinalForwardSendsNothing() async throws {
        let f = try SavedMediaFixture(); f.wire.before = { f.selected = nil }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testSnapshotChangeBeforeFinalForwardSendsNothing() async throws {
        let f = try SavedMediaFixture(); f.wire.before = { f.snapshot = try! SavedMediaFixture.snapshot(name: "New") }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testResponseAfterRevocationCannotReturnBytes() async throws {
        let f = try SavedMediaFixture(); f.wire.after = { f.approval.revoke() }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(f.wire.cancelled)
    }
    func testResponseAfterSnapshotChangeCannotReturnBytes() async throws {
        let f = try SavedMediaFixture(); f.wire.after = { f.snapshot = try! SavedMediaFixture.snapshot(qr: "different") }
        do { _ = try await f.load(); XCTFail() } catch {}
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testUnforwardedOrRepeatedDispatchCannotSucceed() async throws {
        let f = try SavedMediaFixture(); f.wire.skip = true
        do { _ = try await f.load(); XCTFail() } catch {}
        let g = try SavedMediaFixture(); g.wire.duplicate = true
        do { _ = try await g.load(); XCTFail() } catch {}
        XCTAssertEqual(g.wire.requests.count, 1)
    }
    func testMutationOfDestinationOrCredentialsIsRejectedAtForward() async throws {
        let mutations: [(inout URLRequest) -> Void] = [ { $0.setValue("token", forHTTPHeaderField: "Authorization") },
            { $0.url = URL(string: "https://other.example.test/a.jpg") }, { $0.httpMethod = "POST" }, { $0.httpBody = Data([1]) },
            { $0.httpShouldHandleCookies = true }, { $0.setValue("x=y", forHTTPHeaderField: "Cookie") } ]
        for mutate in mutations {
            let f = try SavedMediaFixture(); f.wire.mutate = mutate
            do { _ = try await f.load(); XCTFail() } catch {}
            XCTAssertTrue(f.wire.requests.isEmpty)
        }
    }
    func testEmptyOrOversizedDecodedTransportResultFails() async throws {
        for bytes in [Data(), Data(repeating: 1, count: RetainedSelectedImage.maximumInputBytes + 1)] {
            let f = try SavedMediaFixture(); f.wire.bytes = bytes
            do { _ = try await f.load(); XCTFail() } catch {}
        }
    }
    func testReplacementReaderHasDifferentKeyEvenUnderSameLiveLease() throws {
        let f = try SavedMediaFixture(), old = try XCTUnwrap(f.key())
        let fresh = ProfileCurrentMediaReader(approval: f.approval, currentContext: { f.current }, currentSession: { f.session }, selected: { f.selected }, transport: f.wire)
        XCTAssertNotEqual(old, fresh.key(snapshot: f.snapshot, kind: .caseImage, originalIndex: 0, identity: f.session?.identity, viewerRevision: 3))
        f.reader.retire(); XCTAssertTrue(fresh.isConfigured)
    }
    func testSnapshotDigestIncludesDisplayMetadataAndExactUnicode() throws {
        XCTAssertNotEqual(ProfileSavedMediaExact.snapshot(try SavedMediaFixture.snapshot(name: "é")), ProfileSavedMediaExact.snapshot(try SavedMediaFixture.snapshot(name: "e\u{301}")))
        XCTAssertNotEqual(ProfileSavedMediaExact.snapshot(try SavedMediaFixture.snapshot(phone: "")), ProfileSavedMediaExact.snapshot(try SavedMediaFixture.snapshot()))
    }
    func testExpiredLiveLeaseCannotStartARead() async throws {
        let f = try SavedMediaFixture()
        let short = try ProfileSavedMediaReadApproval(context: f.context, viewerRevision: 3, kind: .caseImage,
            approvedOrigins: ["https://media.example.test"], expiresAt: Date().addingTimeInterval(0.5))
        f.selected = short
        let reader = ProfileCurrentMediaReader(approval: short, currentContext: { f.current }, currentSession: { f.session }, selected: { f.selected }, transport: f.wire)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(reader.key(snapshot: f.snapshot, kind: .caseImage, originalIndex: 0, identity: f.session?.identity, viewerRevision: 3))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRetiredReaderCannotCancelReplacementReadersRequest() async throws {
        let old = try SavedMediaFixture(), fresh = try SavedMediaFixture()
        old.reader.retire(); _ = try await fresh.load()
        XCTAssertEqual(fresh.wire.requests.count, 1); XCTAssertTrue(fresh.reader.isConfigured)
        XCTAssertNil(old.key())
    }
    func testResponseEnvelopeRequiresImageExactDestinationAndBoundedHeaders() throws {
        let endpoint = URL(string: SavedMediaFixture.url)!
        func response(_ status: Int = 200, _ mime: String = "image/jpeg", _ url: URL? = nil, _ extra: [String: String] = [:]) -> HTTPURLResponse {
            var fields = extra; fields["Content-Type"] = mime
            return HTTPURLResponse(url: url ?? endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
        }
        XCTAssertTrue(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(), endpoint: endpoint))
        XCTAssertFalse(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(403), endpoint: endpoint))
        XCTAssertFalse(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(200, "text/html"), endpoint: endpoint))
        XCTAssertFalse(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(200, "image/jpeg", URL(string: "https://other.example.test/a.jpg")), endpoint: endpoint))
        XCTAssertFalse(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(200, "image/jpeg", nil, ["X-Large": String(repeating: "a", count: 32769)]), endpoint: endpoint))
        XCTAssertFalse(ProfileSavedMediaURLSessionTransport.acceptsResponse(response(200, "image/jpeg", nil, ["Content-Length": String(RetainedSelectedImage.maximumInputBytes + 1)]), endpoint: endpoint))
    }
}
