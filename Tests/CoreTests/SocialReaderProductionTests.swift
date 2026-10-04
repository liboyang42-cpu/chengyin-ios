import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class SocialReaderRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> (Data, Int) = { _ in (Data(), 200) }
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let result = try handler(request)
        after?()
        return result
    }
}
private actor SocialReaderPending: HTTPTransport {
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async { while pending == nil { await Task.yield() } }
    func finish(_ data: Data) { pending?.resume(returning: (data, 200)); pending = nil }
}
@MainActor final class SocialReaderProductionTests: XCTestCase {
    private let base = URL(string: "https://api.example.com")!
    private let imageURL = "https://media.example.com/image.png?signature=synthetic"
    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic", namespace: String = "cn", market: RegionalMarket = .china, role: String = "user", base: URL? = nil) throws -> RuntimeDependencyContext {
        try .init(market: market, baseURL: base ?? self.base, role: role,
            session: .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func approval(objects: Bool = true, images: Bool = true, origins: Set<String> = ["https://media.example.com"], paths: Set<String> = ["api/object-card/list", "api/im/messages"]) throws -> SocialReaderProductionApproval {
        try .init(market: .china, endpoints: .init(baseURL: base, namespace: "cn", accountID: 7, paths: paths),
            objectCards: objects, messageImages: images, imageOrigins: origins)
    }
    private func media(id: Int = 21, conversation: Int = 9, url: String? = nil, type: Int = 2) throws -> SocialMessageMedia {
        let bytes = try JSONSerialization.data(withJSONObject: ["id": id, "conversationId": conversation, "status":0,"msgType": type, "content": url ?? imageURL])
        return try .init(message: JSONDecoder().decode(MessagingMessage.self, from: bytes))
    }
    private func page(id: Int = 21, conversation: Int = 9, url: String? = nil, type: Int = 2, more: Bool = false, cursor: Int = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["list": [["id": id, "conversationId": conversation, "status":0,"msgType": type, "content": url ?? imageURL]], "hasMore": more, "nextCursor": cursor]])
    }
    private func factory(approval: SocialReaderProductionApproval?, api: any HTTPTransport, media: (any HTTPTransport)? = nil,
                         current: @escaping () -> RuntimeDependencyContext?) throws -> SocialReaderProductionFactory {
        try .init(configuration: APIConfiguration(baseURL: base), approval: approval, apiTransport: api, mediaTransport: media ?? api, current: current)
    }
    func testDefaultAndIndependentReadGrantsNeverDispatch() throws {
        let t = SocialReaderRecorder(), c = try context()
        let dormant = try factory(approval: nil, api: t, current: { c })
        XCTAssertNil(dormant.objectCards()); XCTAssertNil(dormant.messageMedia())
        let objects = try factory(approval: approval(images: false), api: t, current: { c })
        XCTAssertNotNil(objects.objectCards()); XCTAssertNil(objects.messageMedia())
        let images = try factory(approval: approval(objects: false), api: t, current: { c })
        XCTAssertNil(images.objectCards()); XCTAssertNotNil(images.messageMedia())
        for grant in [try approval(origins: []), try approval(origins: ["https://media.example.com/path"]),
                      try approval(paths: ["api/object-card/list"])] {
            XCTAssertNil(try factory(approval: grant, api: t, current: { c }).messageMedia())
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testWrongAccountMarketNamespaceAndAPIOriginHaveNoAccess() throws {
        let t = SocialReaderRecorder(), grant = try approval()
        let cases = [try context(account: 8), try context(namespace: "us"), try context(market: .unitedStates),
                     try context(base: URL(string: "https://other.example.com")!)]
        for c in cases {
            let f = try factory(approval: grant, api: t, current: { c })
            XCTAssertNil(f.objectCards()); XCTAssertNil(f.messageMedia())
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testObjectReaderResolvesCurrentGrantAfterSignedOutConstruction() async throws {
        let t = SocialReaderRecorder(), grant = try approval()
        t.handler = { _ in (Data(#"{"code":200,"data":{"list":[],"total":0}}"#.utf8), 200) }
        var current: RuntimeDependencyContext?
        let f = try factory(approval: grant, api: t, current: { current })
        let reader = ObjectCardSessionReader(serviceProvider: { f.objectCards() }, currentSession: {
            guard let current else { return nil }
            return try? ObjectCardSession(accountID: current.session.accountID, epoch: current.session.epoch, token: current.session.token)
        }, currentContext: { current })
        XCTAssertFalse(reader.isConfigured)
        current = try context()
        XCTAssertTrue(reader.isConfigured)
        _ = try await reader.list(category: .books)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/api/object-card/list"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
        XCTAssertFalse(request.httpShouldHandleCookies)
        let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
        XCTAssertTrue(body.hasPrefix("pageNum=1&pageSize=40&category=")); XCTAssertFalse(body.contains("memberId"))
        current = try context(account: 8)
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.list(category: .all); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testRetainedObjectServiceAndLateUnauthorizedCannotCrossSession() async throws {
        let t = SocialReaderRecorder(), initial = try context()
        var current: RuntimeDependencyContext? = initial
        let f = try factory(approval: approval(), api: t, current: { current })
        let service = try XCTUnwrap(f.objectCards())
        current = try context(epoch: 2)
        do { _ = try await service.list(category: .all, token: "synthetic"); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(t.requests.isEmpty)
        current = initial
        t.handler = { _ in (Data(#"{"code":401}"#.utf8), 401) }
        t.after = { current = nil }
        do { _ = try await service.list(category: .all, token: "synthetic"); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testObjectCancellationDiscardsSuccessfulResponse() async throws {
        let t = SocialReaderPending(), c = try context()
        let f = try factory(approval: approval(), api: t, current: { c })
        let service = try XCTUnwrap(f.objectCards())
        let task = Task { try await service.list(category: .all, token: "synthetic") }
        await t.waitForRequest(); task.cancel()
        await t.finish(Data(#"{"code":200,"data":{"list":[],"total":0}}"#.utf8))
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testApprovedImageUsesExactMessageReadbackBeforeAndAfterAnonymousFetch() async throws {
        let api = SocialReaderRecorder(), bytes = SocialReaderRecorder(), c = try context(), body = try page()
        api.handler = { _ in (body, 200) }; bytes.handler = { _ in (self.png, 200) }
        let f = try factory(approval: approval(), api: api, media: bytes, current: { c })
        let service = try XCTUnwrap(f.messageMedia())
        let result = try await service.image(media())
        XCTAssertEqual(result, png); XCTAssertEqual(api.requests.count, 2); XCTAssertEqual(bytes.requests.count, 1)
        for request in api.requests {
            XCTAssertEqual(request.url?.path, "/api/im/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
            let fields = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
            XCTAssertTrue(fields.contains("name=\"conversation_id\"\r\n\r\n9")); XCTAssertTrue(fields.contains("name=\"size\"\r\n\r\n50"))
        }
        let request = try XCTUnwrap(bytes.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.absoluteString, imageURL)
        XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testWrongMessageConversationTypeOrURLNeverFetchesMedia() async throws {
        let c = try context()
        for body in [try page(id: 22), try page(conversation: 10), try page(type: 1), try page(url: "https://media.example.com/other.png")] {
            let api = SocialReaderRecorder(), bytes = SocialReaderRecorder()
            api.handler = { _ in (body, 200) }
            let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
            do { _ = try await service.image(media()); XCTFail() } catch {}
            XCTAssertEqual(api.requests.count, 1); XCTAssertTrue(bytes.requests.isEmpty)
        }
    }
    func testNoConversationAccessOrClosedHangoutNeverFetchesMedia() async throws {
        let c = try context()
        for body in [#"{"code":500,"msg":"No access"}"#, #"{"code":409,"errorCode":"HANGOUT_CLOSED"}"#, #"{"code":401}"#] {
            let api = SocialReaderRecorder(), bytes = SocialReaderRecorder()
            api.handler = { _ in (Data(body.utf8), 200) }
            let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
            do { _ = try await service.image(media()); XCTFail() } catch {}
            XCTAssertTrue(bytes.requests.isEmpty)
        }
    }
    func testUnapprovedMediaOriginDoesNotEvenStartReadback() async throws {
        let t = SocialReaderRecorder(), c = try context()
        let service = try XCTUnwrap(factory(approval: approval(), api: t, current: { c }).messageMedia())
        do { _ = try await service.image(media(url: "https://other.example.com/a.png")); XCTFail() }
        catch { XCTAssertEqual(error as? SocialMediaFailure, .originNotApproved) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testPermissionRevocationOrChangedMessageAfterFetchDiscardsBytes() async throws {
        let c = try context(), before = try page()
        for after in [Data(#"{"code":500,"msg":"No access"}"#.utf8), try page(url: "https://media.example.com/replaced.png")] {
            let api = SocialReaderRecorder(), bytes = SocialReaderRecorder()
            api.handler = { _ in (api.requests.count == 1 ? before : after, 200) }
            bytes.handler = { _ in (self.png, 200) }
            let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
            do { _ = try await service.image(media()); XCTFail("Revoked bytes escaped") } catch {}
            XCTAssertEqual(api.requests.count, 2); XCTAssertEqual(bytes.requests.count, 1)
        }
    }
    func testMediaSessionRoleAndTokenChangesDiscardBytesAndStaleFailure() async throws {
        let initial = try context(), body = try page()
        for replacement in [try context(epoch: 2), try context(role: "merchant"), try context(token: "replacement"), try context(account: 8)] {
            var current: RuntimeDependencyContext? = initial
            let api = SocialReaderRecorder(), bytes = SocialReaderRecorder()
            api.handler = { _ in (body, 200) }; bytes.handler = { _ in (self.png, 200) }; bytes.after = { current = replacement }
            let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { current }).messageMedia())
            do { _ = try await service.image(media()); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(api.requests.count, 1)
        }
    }
    func testCancelledReadbackNeverRequestsImage() async throws {
        let api = SocialReaderPending(), bytes = SocialReaderRecorder(), c = try context(), target = try media()
        let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
        let task = Task { try await service.image(target) }
        await api.waitForRequest(); task.cancel(); await api.finish(try page())
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(bytes.requests.isEmpty)
    }
    func testCancelledMediaTransferDiscardsBytesWithoutSecondReadback() async throws {
        let api = SocialReaderRecorder(), bytes = SocialReaderPending(), c = try context(), body = try page(), target = try media()
        api.handler = { _ in (body, 200) }
        let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
        let task = Task { try await service.image(target) }
        await bytes.waitForRequest(); task.cancel(); await bytes.finish(png)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.requests.count, 1)
    }
    func testMediaReaderResolvesLoginAndRejectsWrongExpectedOwnerBeforeAnyRead() async throws {
        let api = SocialReaderRecorder(), bytes = SocialReaderRecorder(), body = try page()
        api.handler = { _ in (body, 200) }; bytes.handler = { _ in (self.png, 200) }
        var current: RuntimeDependencyContext?
        let f = try factory(approval: approval(), api: api, media: bytes, current: { current })
        let reader = SocialMessageMediaReader(serviceProvider: { f.messageMedia() }, currentIdentity: {
            current.map { .init(accountID: $0.session.accountID, epoch: $0.session.epoch) }
        }, currentContext: { current })
        XCTAssertFalse(reader.isConfigured)
        current = try context()
        XCTAssertTrue(reader.isConfigured)
        do { _ = try await reader.image(media(), expectedIdentity: .init(accountID: 8, epoch: 1)); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(api.requests.isEmpty); XCTAssertTrue(bytes.requests.isEmpty)
        let result = try await reader.image(media(), expectedIdentity: .init(accountID: 7, epoch: 1))
        XCTAssertEqual(result, png)
        current = nil
        XCTAssertFalse(reader.isConfigured)
    }
    func testReadbackFollowsOnlyReturnedCursorsAndRejectsLoops() async throws {
        let c = try context(), first = try page(id: 88, more: true, cursor: 777), second = try page()
        let api = SocialReaderRecorder(), bytes = SocialReaderRecorder()
        api.handler = { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return (body.contains("name=\"cursor_id\"\r\n\r\n777") ? second : first, 200)
        }
        bytes.handler = { _ in (self.png, 200) }
        let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
        _ = try await service.image(media())
        XCTAssertEqual(api.requests.count, 4)
        api.requests.removeAll(); bytes.requests.removeAll(); api.handler = { _ in (first, 200) }
        do { _ = try await service.image(media()); XCTFail() } catch { XCTAssertEqual(error as? SocialMediaFailure, .unavailable) }
        XCTAssertEqual(api.requests.count, 2); XCTAssertTrue(bytes.requests.isEmpty)
    }
    func testDeepReadbackStopsAtFixedPageBudgetWithoutMedia() async throws {
        let api = SocialReaderRecorder(), bytes = SocialReaderRecorder(), c = try context()
        api.handler = { _ in (try self.page(id: 88, more: true, cursor: api.requests.count), 200) }
        let service = try XCTUnwrap(factory(approval: approval(), api: api, media: bytes, current: { c }).messageMedia())
        do { _ = try await service.image(media()); XCTFail() } catch { XCTAssertEqual(error as? SocialMediaFailure, .unavailable) }
        XCTAssertEqual(api.requests.count, SocialMessageMediaReadback.maximumPages); XCTAssertTrue(bytes.requests.isEmpty)
    }
    func testReaderOnlyExpiresCurrentUnauthorizedIdentity() async throws {
        let initial = try context(), api = SocialReaderRecorder()
        var current: RuntimeDependencyContext? = initial
        let f = try factory(approval: approval(), api: api, current: { current })
        let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
        var expired = 0
        let reader = SocialMessageMediaReader(serviceProvider: { f.messageMedia() }, currentIdentity: {
            current.map { .init(accountID: $0.session.accountID, epoch: $0.session.epoch) }
        }, currentContext: { current }, onUnauthorized: { _ in expired += 1 })
        api.handler = { _ in (Data(#"{"code":401}"#.utf8), 401) }
        do { _ = try await reader.image(media(), expectedIdentity: identity); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, 1)
        api.after = { current = nil }
        do { _ = try await reader.image(media(), expectedIdentity: identity); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 1)
    }
    func testReadTransportsRejectWrongEndpointMethodTokenAndCredentialedMedia() async throws {
        let t = SocialReaderRecorder(), c = try context()
        let api = SocialReaderApprovedAPITransport(path: "api/object-card/list", captured: c, transport: t, current: { c })
        for (path, method, token) in [("api/object-card/rename", "POST", "synthetic"), ("api/object-card/list", "GET", "synthetic"), ("api/object-card/list", "POST", "wrong")] {
            var request = URLRequest(url: base.appendingPathComponent(path)); request.httpMethod = method
            request.setValue(token, forHTTPHeaderField: "Authorization")
            do { _ = try await api.send(request); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let media = SocialReaderApprovedMediaTransport(origins: ["https://media.example.com"], captured: c, transport: t, current: { c })
        var request = URLRequest(url: URL(string: imageURL)!); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue("synthetic", forHTTPHeaderField: "Authorization")
        do { _ = try await media.send(request); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
    }
}
