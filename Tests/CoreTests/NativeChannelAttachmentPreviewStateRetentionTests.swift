import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// No URLSession, real clock delay, credentials or external media are used here.
@MainActor final class NativeChannelAttachmentPreviewStateRetentionTests: XCTestCase {
    private typealias Flow = NativeChannelAttachmentPreviewFlow
    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10]) // Signature-only synthetic bytes; not UI decoding.

    func testEveryNewDescriptorStateSurvivesTheRetiredDisplayDeadline() async throws {
        let cases: [(String, Flow.State)] = [("PENDING", .pending), ("REJECTED", .rejected),
            ("UNAVAILABLE", .unavailable), ("UNSUPPORTED", .unsupported),
            ("SOURCE_UNCONFIRMED", .sourceUnconfirmed), ("UNKNOWN", .unknown), ("READY", .unknown)]
        for (raw, expected) in cases {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            api.result = (try descriptor(), 200);media.result = (png, 200)
            let flow = try make(api: api, media: media, clock: clock)
            await flow.load();XCTAssertEqual(flow.visibleState, .displayed)
            await settle { clock.sleepers.count == 2 }
            api.result = (try descriptor(state: raw, version: raw == "READY" ? 2 : 1), 200)
            clock.advance(seconds: 5)
            await settle { flow.visibleState == expected }
            XCTAssertNil(flow.bytes, raw)
            let readCount = api.requests.count
            clock.advance(seconds: 5) // Delivers the old, cancelled expiry sleeper anyway.
            await settle { clock.sleepers.isEmpty }
            XCTAssertEqual(flow.visibleState, expected, raw)
            XCTAssertEqual(api.requests.count, readCount, "Retired previews do not silently reauthorize")
            XCTAssertEqual(media.requests.count, 1)
            flow.clear();clock.finishAll()
        }
    }

    func testIndependentExpiryClearsBytesDuringAStalledMonitorRead() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (png, 200)
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        await flow.load();await settle { clock.sleepers.count == 2 }
        let pending = AttachmentPreviewPendingResponse()
        api.operation = { _ in try await pending.wait() }
        clock.advance(seconds: 5);await settle { pending.isWaiting }
        XCTAssertEqual(flow.visibleState, .displayed)
        clock.advance(seconds: 5);await settle { flow.visibleState == .expired }
        XCTAssertNil(flow.bytes)
        pending.resume((try descriptor(state: "REJECTED"), 200))
        await settle { !pending.isWaiting }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(flow.visibleState, .expired, "A retired monitor cannot overwrite the terminal state")
        XCTAssertEqual(media.requests.count, 1)
    }

    func testExplicitReloadIsNotExpiredByTheOldLeaseAndDoesNotAutoRenew() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (png, 200)
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        await flow.load();await settle { clock.sleepers.count == 2 }
        api.result = (try descriptor(state: "REJECTED"), 200)
        clock.advance(seconds: 5);await settle { flow.visibleState == .rejected }
        api.result = (try descriptor(expires: 100), 200)
        await flow.load();await settle { clock.sleepers.count == 3 }
        XCTAssertEqual(media.requests.count, 2)
        clock.advance(seconds: 5)
        await settle { api.requests.count == 6 }
        XCTAssertEqual(flow.visibleState, .displayed)
        XCTAssertNotNil(flow.bytes)
        XCTAssertEqual(media.requests.count, 2, "Monitor only rereads descriptor, never refetches the image")
        clock.advance(seconds: 95);await settle { flow.visibleState == .expired }
        XCTAssertNil(flow.bytes, "A later READY descriptor cannot extend the original deadline")
    }

    func testClearAndNewLoadDiscardAnOldInflightMediaCompletion() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200)
        let pending = AttachmentPreviewPendingResponse()
        media.operation = { _ in try await pending.wait() }
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        let oldLoad = Task { await flow.load() }
        await settle { pending.isWaiting }
        XCTAssertEqual(flow.visibleState, .loading)
        await flow.load();XCTAssertEqual(media.requests.count, 1, "Repeated load while loading cannot dispatch twice")
        flow.clear()
        api.result = (try descriptor(state: "REJECTED"), 200)
        await flow.load();XCTAssertEqual(flow.visibleState, .rejected)
        pending.resume((png, 200));await oldLoad.value
        XCTAssertEqual(flow.visibleState, .rejected)
        XCTAssertNil(flow.bytes)
        XCTAssertTrue(clock.sleepers.isEmpty)
        XCTAssertEqual(api.requests.count, 2, "Retired media must not start another original descriptor request")
    }

    func testCurrentSession401ExpiresOnlyTheCapturedSessionAndLate401DoesNot() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        var current = true, expirations = 0
        let flow = try make(api: api, media: media, clock: clock, current: { current }, unauthorized: { expirations += 1 })
        defer { flow.clear();clock.finishAll() }
        api.result = (Data(), 401)
        await flow.load();XCTAssertEqual(expirations, 1);XCTAssertTrue(media.requests.isEmpty)
        let pending = AttachmentPreviewPendingResponse()
        api.operation = { _ in try await pending.wait() }
        let oldLoad = Task { await flow.load() };await settle { pending.isWaiting }
        current = false
        pending.resume((Data(), 401));await oldLoad.value
        XCTAssertEqual(expirations, 1);XCTAssertEqual(flow.visibleState, .unavailable);XCTAssertNil(flow.bytes)
    }

    func testTokenReplacementRejectsLate401WithoutExpiringNewCredential() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        var credential = "original-token", expirations = 0
        let pending = AttachmentPreviewPendingResponse();api.operation = { _ in try await pending.wait() }
        let flow = try make(api: api, media: media, clock: clock, token: { credential }, unauthorized: { expirations += 1 })
        defer { flow.clear();clock.finishAll() }
        let load = Task { await flow.load() };await settle { pending.isWaiting }
        credential = "new-token";pending.resume((Data(), 401));await load.value
        XCTAssertEqual(expirations, 0);XCTAssertNil(flow.bytes);XCTAssertTrue(media.requests.isEmpty)
    }

    func testStorage401RereadsOriginalDescriptorWithoutExpiringSession() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (Data(), 401)
        var expirations = 0
        let flow = try make(api: api, media: media, clock: clock, unauthorized: { expirations += 1 })
        defer { flow.clear();clock.finishAll() }
        await flow.load()
        XCTAssertEqual(flow.visibleState, .expired);XCTAssertNil(flow.bytes)
        XCTAssertEqual(expirations, 0);XCTAssertEqual(api.requests.count, 2);XCTAssertEqual(media.requests.count, 1)
    }

    func testMonitorDenialUnknownAndUnsupportedBytesDoNotRetainImage() async throws {
        for status in [403, 404, 500] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            api.result = (try descriptor(), 200);media.result = (png, 200)
            let flow = try make(api: api, media: media, clock: clock)
            await flow.load();await settle { clock.sleepers.count == 2 }
            api.result = (Data(), status)
            clock.advance(seconds: 5)
            let expected: Flow.State = status == 500 ? .unknown : .unavailable
            await settle { flow.visibleState == expected }
            clock.advance(seconds: 5);await settle { clock.sleepers.isEmpty }
            XCTAssertEqual(flow.visibleState, expected);XCTAssertNil(flow.bytes)
            flow.clear();clock.finishAll()
        }
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (png, 200)
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        await flow.load();await settle { clock.sleepers.count == 2 }
        flow.unsupportedBytes();clock.advance(seconds: 10)
        await settle { clock.sleepers.isEmpty }
        XCTAssertEqual(flow.visibleState, .unsupported);XCTAssertNil(flow.bytes)
    }

    func testLeaseWithdrawalDuringMonitorClearsWithoutPublishingAndNoRenewal() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (png, 200)
        var current = true
        let flow = try make(api: api, media: media, clock: clock, current: { current })
        defer { flow.clear();clock.finishAll() }
        await flow.load();await settle { clock.sleepers.count == 2 }
        let pending = AttachmentPreviewPendingResponse();api.operation = { _ in try await pending.wait() }
        clock.advance(seconds: 5);await settle { pending.isWaiting }
        current = false;pending.resume((try descriptor(), 200))
        await settle { flow.bytes == nil }
        XCTAssertEqual(flow.visibleState, .unavailable)
        clock.advance(seconds: 5);await settle { clock.sleepers.isEmpty }
        XCTAssertEqual(media.requests.count, 1)
    }

    func testAbsentGrantAndFirstNonReadyStatesNeverFetchMedia() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        let disabled = try make(api: api, media: media, clock: clock, enabled: false)
        await disabled.load();XCTAssertEqual(disabled.visibleState, .idle);XCTAssertTrue(api.requests.isEmpty)
        for state in ["PENDING", "REJECTED", "UNAVAILABLE", "UNSUPPORTED", "SOURCE_UNCONFIRMED", "UNKNOWN"] {
            api.result = (try descriptor(state: state), 200)
            let flow = try make(api: api, media: media, clock: clock)
            await flow.load();XCTAssertNil(flow.bytes);XCTAssertTrue(media.requests.isEmpty);XCTAssertTrue(clock.sleepers.isEmpty)
            flow.clear()
        }
    }

    func testPreviewMediaKeepsSignedURLAndSendsNoCredentialsCookiesOrBody() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200);media.result = (png, 200)
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        await flow.load()
        XCTAssertEqual(flow.visibleState, .displayed)
        let request = try XCTUnwrap(media.requests.first)
        XCTAssertEqual(media.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://media.example.test/original?signature=synthetic")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody);XCTAssertNil(request.httpBodyStream)
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Cookie2"] {
            XCTAssertNil(request.value(forHTTPHeaderField: header), header)
        }
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
        XCTAssertEqual(api.requests.count, 2)
        XCTAssertEqual(api.requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }

    func testEveryStorageDenialRechecksOriginalDescriptorWithoutExpiringLogin() async throws {
        for status in [401, 403, 404] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            let original = try descriptor(), rejected = try descriptor(state: "REJECTED")
            var descriptorReads = 0
            api.operation = { _ in descriptorReads += 1;return (descriptorReads == 1 ? original : rejected, 200) }
            media.result = (Data(), status)
            var expirations = 0
            let flow = try make(api: api, media: media, clock: clock, unauthorized: { expirations += 1 })
            await flow.load()
            XCTAssertEqual(flow.visibleState, .rejected, "Storage \(status) cannot replace the original descriptor authority")
            XCTAssertNil(flow.bytes);XCTAssertEqual(expirations, 0)
            XCTAssertEqual(api.requests.count, 2);XCTAssertEqual(media.requests.count, 1)
            flow.clear();clock.finishAll()
        }
    }

    func testEveryStorageDenialWithStillReadyDescriptorExpiresOnlyThePreview() async throws {
        for status in [401, 403, 404] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            api.result = (try descriptor(), 200);media.result = (Data(), status)
            var expirations = 0
            let flow = try make(api: api, media: media, clock: clock, unauthorized: { expirations += 1 })
            await flow.load()
            XCTAssertEqual(flow.visibleState, .expired);XCTAssertNil(flow.bytes)
            XCTAssertEqual(expirations, 0);XCTAssertEqual(api.requests.count, 2);XCTAssertEqual(media.requests.count, 1)
            flow.clear();clock.finishAll()
        }
    }

    func testStorageRedirectAndServerErrorsNeverPublishOrReauthorize() async throws {
        for status in [300, 301, 302, 307, 308, 500, 503] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            api.result = (try descriptor(), 200);media.result = (png, status)
            var expirations = 0
            let flow = try make(api: api, media: media, clock: clock, unauthorized: { expirations += 1 })
            await flow.load()
            XCTAssertEqual(flow.visibleState, .unknown, "HTTP \(status) is not a successful image")
            XCTAssertNil(flow.bytes);XCTAssertEqual(expirations, 0)
            XCTAssertEqual(api.requests.count, 1);XCTAssertEqual(media.requests.count, 1)
            XCTAssertTrue(clock.sleepers.isEmpty)
            flow.clear();clock.finishAll()
        }
    }

    func testPreviewDescriptorUnsafeURLsNeverReachMediaEvenWithAnOriginEntry() async throws {
        for raw in ["http://media.example.test/a.png", "https://user:secret@media.example.test/a.png",
                    "https://media.example.test/a.png#fragment", "https://localhost/a.png",
                    "https://127.0.0.1/a.png", "https://[::1]/a.png", "https://host.local/a.png"] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: descriptor()) as? [String: Any])
            var value = try XCTUnwrap(envelope["data"] as? [String: Any]);value["url"] = raw;envelope["data"] = value
            api.result = (try JSONSerialization.data(withJSONObject: envelope), 200);media.result = (png, 200)
            let origin = URL(string: raw).flatMap(SocialMessageMediaService.origin) ?? "https://media.example.test"
            let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 9)
            let flow = Flow(messageID: 1, scope: scope,
                configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!),
                api: api, media: media, origins: [origin], enabled: true,
                token: { "synthetic-token" }, current: { true }, unauthorized: {},
                timing: .init(now: { clock.now }, sleepUntil: { try await clock.sleep(until: $0) }))
            await flow.load()
            XCTAssertEqual(flow.visibleState, .unknown, raw);XCTAssertNil(flow.bytes)
            XCTAssertTrue(media.requests.isEmpty, raw);XCTAssertEqual(api.requests.count, 1)
            flow.clear();clock.finishAll()
        }
    }

    func testPreviewRetainsImageSignatureAndMaximumByteGates() async throws {
        for (data, expected) in [(Data("not an image".utf8), Flow.State.unsupported),
                                 (Data(repeating: 0, count: SocialMessageMediaService.maximumBytes + 1), Flow.State.unknown)] {
            let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
            api.result = (try descriptor(), 200);media.result = (data, 200)
            let flow = try make(api: api, media: media, clock: clock)
            await flow.load()
            XCTAssertEqual(flow.visibleState, expected);XCTAssertNil(flow.bytes)
            XCTAssertEqual(api.requests.count, 1);XCTAssertEqual(media.requests.count, 1)
            flow.clear();clock.finishAll()
        }
    }

    func testGeneric302KeepsUnavailableWhilePreview302StaysUnknown() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        let messageData = try JSONSerialization.data(withJSONObject: ["id": 1, "conversationId": 9,
            "status": 0, "msgType": 2, "content": "https://media.example.test/original?signature=synthetic"])
        let message = try JSONDecoder().decode(MessagingMessage.self, from: messageData)
        let service = SocialMessageMediaService(approvedOrigins: ["https://media.example.test"], transport: media)
        media.result = (png, 302)
        do { _ = try await service.image(.init(message: message));XCTFail("Generic redirect must fail") }
        catch { XCTAssertEqual(error as? SocialMediaFailure, .unavailable) }
        api.result = (try descriptor(), 200)
        let flow = try make(api: api, media: media, clock: clock)
        defer { flow.clear();clock.finishAll() }
        await flow.load()
        XCTAssertEqual(flow.visibleState, .unknown);XCTAssertNil(flow.bytes)
        XCTAssertEqual(api.requests.count, 1);XCTAssertEqual(media.requests.count, 2)
    }

    func testLateStorageDenialAfterClearCannotStartAnotherDescriptorRead() async throws {
        let clock = AttachmentPreviewTestClock(), api = AttachmentPreviewTestTransport(), media = AttachmentPreviewTestTransport()
        api.result = (try descriptor(), 200)
        let pending = AttachmentPreviewPendingResponse();media.operation = { _ in try await pending.wait() }
        var expirations = 0
        let flow = try make(api: api, media: media, clock: clock, unauthorized: { expirations += 1 })
        defer { flow.clear();clock.finishAll() }
        let load = Task { await flow.load() };await settle { pending.isWaiting }
        flow.clear();pending.resume((Data(), 403));await load.value
        XCTAssertEqual(flow.visibleState, .idle);XCTAssertNil(flow.bytes)
        XCTAssertEqual(api.requests.count, 1);XCTAssertEqual(media.requests.count, 1)
        XCTAssertEqual(expirations, 0);XCTAssertTrue(clock.sleepers.isEmpty)
    }

    private func make(api: AttachmentPreviewTestTransport, media: AttachmentPreviewTestTransport,
                      clock: AttachmentPreviewTestClock, enabled: Bool = true,
                      token: @escaping () -> String? = { "synthetic-token" }, current: @escaping () -> Bool = { true },
                      unauthorized: @escaping () -> Void = {}) throws -> Flow {
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 9)
        return Flow(messageID: 1, scope: scope,
            configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!),
            api: api, media: media, origins: ["https://media.example.test"], enabled: enabled,
            token: token, current: current, unauthorized: unauthorized,
            timing: .init(now: { clock.now }, sleepUntil: { try await clock.sleep(until: $0) }))
    }
    private func descriptor(state: String = "READY", version: Int = 1, expires: Int = 10) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["message_id": "1", "conversation_id": "9",
            "kind": "IMAGE", "source": "LEGACY_SINGLE_IMAGE", "state": state, "asset_id": "5", "asset_version": 0,
            "message_version": version, "url": "https://media.example.test/original?signature=synthetic", "expires_in_seconds": expires]])
    }
    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() {
                // A fake sleeper is removed before its continuation runs. Drain the
                // ready actor jobs before asserting that no stale callback overwrote UI.
                for _ in 0..<3 { await Task.yield() }
                return
            }
            await Task.yield()
        }
        XCTFail("Deterministic task did not reach expected state", file: file, line: line)
    }
}

@MainActor private final class AttachmentPreviewTestClock {
    var now = ContinuousClock.now
    struct Sleeper { let deadline: ContinuousClock.Instant;let continuation: CheckedContinuation<Void, Error> }
    var sleepers: [Sleeper] = []
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        if now >= deadline { return }
        // Deliberately ignores cancellation: tests verify retirement, not just cancel().
        try await withCheckedThrowingContinuation { sleepers.append(.init(deadline: deadline, continuation: $0)) }
    }
    func advance(seconds: Int) {
        now = now.advanced(by: .seconds(seconds))
        let due = sleepers.filter { $0.deadline <= now };sleepers.removeAll { $0.deadline <= now }
        for item in due { item.continuation.resume() }
    }
    func finishAll() {
        let pending = sleepers;sleepers = []
        for item in pending { item.continuation.resume(throwing: CancellationError()) }
    }
}
@MainActor private final class AttachmentPreviewTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var result = (Data(), 200)
    var operation: ((URLRequest) async throws -> (Data, Int))?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await operation?(request) ?? result
    }
}
@MainActor private final class AttachmentPreviewPendingResponse {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    var isWaiting: Bool { continuation != nil }
    func wait() async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func resume(_ result: (Data, Int)) { let saved = continuation;continuation = nil;saved?.resume(returning: result) }
}
