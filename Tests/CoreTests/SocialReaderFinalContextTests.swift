import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct FinalContextReply: HTTPTransport {
    let data: Data
    let status: Int
    func send(_ request: URLRequest) async throws -> (Data, Int) { (data, status) }
}
/// Suspends *after* the wrapped approved transport has passed its final context
/// check. Returning these bytes resumes the nonisolated service's decode/error path.
private actor FinalContextPostTransport: HTTPTransport {
    private let upstream: any HTTPTransport
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ upstream: any HTTPTransport) { self.upstream = upstream }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let result = try await upstream.send(request)
        await withCheckedContinuation { continuation = $0 }
        return result
    }
    func waitUntilTransportCompleted() async { while continuation == nil { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}
/// Equivalent return boundary after the last successful MainActor authorization
/// callback. The media signature has already been decoded before this checkpoint.
private actor FinalContextReadbackReturn {
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func waitUntilAuthorized() async { while continuation == nil { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class SocialReaderFinalContextTests: XCTestCase {
    private let base = URL(string: "https://api.example.com")!
    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private func context(role: String = "user", namespace: String = "cn", base: URL? = nil,
                         market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        try .init(market: market, baseURL: base ?? self.base, role: role,
            session: .init(accountID: 7, epoch: 1, namespace: namespace, token: "synthetic"))
    }
    private func changedContexts() throws -> [RuntimeDependencyContext?] {
        [try context(role: "merchant"), try context(namespace: "new-realm"),
         try context(base: URL(string: "https://new.example.com")!), try context(market: .unitedStates), nil]
    }
    private func media() throws -> SocialMessageMedia {
        try .init(message: JSONDecoder().decode(MessagingMessage.self, from:
            Data(#"{"id":21,"conversationId":9,"status":0,"msgType":2,"content":"https://media.example.com/a.png"}"#.utf8)))
    }
    func testObjectSuccessAfterApprovedTransportAndNonisolatedDecodeCannotCrossFullContext() async throws {
        let initial = try context(), session = try ObjectCardSession(accountID: 7, epoch: 1, token: "synthetic")
        for replacement in try changedContexts() {
            var current: RuntimeDependencyContext? = initial
            let approved = SocialReaderApprovedAPITransport(path: "api/object-card/list", captured: initial,
                transport: FinalContextReply(data: Data(#"{"code":200,"data":{"list":[],"total":0}}"#.utf8), status: 200), current: { current })
            let delayed = FinalContextPostTransport(approved)
            let service = try ObjectCardService(configuration: .init(baseURL: base), transport: delayed)
            let reader = ObjectCardSessionReader(serviceProvider: { service }, currentSession: { session }, currentContext: { current })
            let originalScope = reader.scope
            let task = Task { try await reader.list(category: .all) }
            await delayed.waitUntilTransportCompleted()
            current = replacement
            XCTAssertNotEqual(reader.scope, originalScope)
            await delayed.release()
            do { _ = try await task.value; XCTFail("Old decoded collection escaped") } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testObject401AfterApprovedTransportDoesNotExpireUnchangedAccountEpoch() async throws {
        let initial = try context(), session = try ObjectCardSession(accountID: 7, epoch: 1, token: "synthetic")
        for replacement in try changedContexts() {
            var current: RuntimeDependencyContext? = initial
            var expired = 0
            let approved = SocialReaderApprovedAPITransport(path: "api/object-card/list", captured: initial,
                transport: FinalContextReply(data: Data(#"{"code":401}"#.utf8), status: 200), current: { current })
            let delayed = FinalContextPostTransport(approved)
            let service = try ObjectCardService(configuration: .init(baseURL: base), transport: delayed)
            let reader = ObjectCardSessionReader(serviceProvider: { service }, currentSession: { session },
                currentContext: { current }, onUnauthorized: { _ in expired += 1 })
            let task = Task { try await reader.list(category: .all) }
            await delayed.waitUntilTransportCompleted(); current = replacement; await delayed.release()
            do { _ = try await task.value; XCTFail("Old 401 escaped") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0)
        }
    }
    func testDecodedImageAfterFinalSuccessfulReadbackCannotCrossFullContext() async throws {
        let initial = try context(), identity = MessagingReadIdentity(accountID: 7, epoch: 1), target = try media()
        for replacement in try changedContexts() {
            var current: RuntimeDependencyContext? = initial
            var authorizations = 0
            let delayed = FinalContextReadbackReturn()
            let transport = SocialReaderApprovedMediaTransport(origins: ["https://media.example.com"], captured: initial,
                transport: FinalContextReply(data: png, status: 200), current: { current })
            let service = SocialMessageMediaService(approvedOrigins: ["https://media.example.com"], transport: transport,
                authorize: { _ in
                    guard current == initial else { throw CancellationError() }
                    authorizations += 1
                    if authorizations == 2 { await delayed.pause() }
                })
            let reader = SocialMessageMediaReader(serviceProvider: { service }, currentIdentity: { identity }, currentContext: { current })
            let task = Task { try await reader.image(target, expectedIdentity: identity) }
            await delayed.waitUntilAuthorized()
            XCTAssertEqual(authorizations, 2)
            current = replacement; await delayed.release()
            do { _ = try await task.value; XCTFail("Old decoded image escaped") } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testMedia401DecodedAfterApprovedReadbackTransportCannotExpireUnchangedIdentity() async throws {
        let initial = try context(), identity = MessagingReadIdentity(accountID: 7, epoch: 1), target = try media()
        for replacement in try changedContexts() {
            var current: RuntimeDependencyContext? = initial
            var expired = 0
            let approved = SocialReaderApprovedAPITransport(path: "api/im/messages", captured: initial,
                transport: FinalContextReply(data: Data(#"{"code":401}"#.utf8), status: 200), current: { current })
            let delayed = FinalContextPostTransport(approved)
            let readback = try MessagingService(configuration: .init(baseURL: base), transport: delayed)
            let service = SocialMessageMediaService(approvedOrigins: ["https://media.example.com"],
                transport: FinalContextReply(data: png, status: 200), authorize: { _ in
                    _ = try await readback.messages(conversationID: 9, token: "synthetic")
                })
            let reader = SocialMessageMediaReader(serviceProvider: { service }, currentIdentity: { identity },
                currentContext: { current }, onUnauthorized: { _ in expired += 1 })
            let task = Task { try await reader.image(target, expectedIdentity: identity) }
            await delayed.waitUntilTransportCompleted(); current = replacement; await delayed.release()
            do { _ = try await task.value; XCTFail("Old media 401 escaped") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0)
        }
    }
    func testDynamicReadersRequireContextAndRecoverWhenItAppears() async throws {
        let session = try ObjectCardSession(accountID: 7, epoch: 1, token: "synthetic")
        let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
        var current: RuntimeDependencyContext?
        let cards = try ObjectCardService(configuration: .init(baseURL: base),
            transport: FinalContextReply(data: Data(#"{"code":200,"data":{"list":[],"total":0}}"#.utf8), status: 200))
        let images = SocialMessageMediaService(approvedOrigins: ["https://media.example.com"], transport: FinalContextReply(data: png, status: 200))
        let objects = ObjectCardSessionReader(serviceProvider: { cards }, currentSession: { session }, currentContext: { current })
        let mediaReader = SocialMessageMediaReader(serviceProvider: { images }, currentIdentity: { identity }, currentContext: { current })
        XCTAssertFalse(objects.isConfigured); XCTAssertFalse(mediaReader.isConfigured)
        do { _ = try await objects.list(category: .all); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await mediaReader.image(media(), expectedIdentity: identity); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        current = try context()
        XCTAssertTrue(objects.isConfigured); XCTAssertTrue(mediaReader.isConfigured)
        let collection = try await objects.list(category: .all)
        let image = try await mediaReader.image(media(), expectedIdentity: identity)
        XCTAssertEqual(collection.total, 0); XCTAssertEqual(image, png)
    }
}
