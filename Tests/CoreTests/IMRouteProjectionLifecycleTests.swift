import XCTest
@testable import QuestifyCore

/// These exercise the actual state reducer used by the detail view, without claiming UI execution.
final class IMRouteProjectionLifecycleTests: XCTestCase {
    private func message(_ content: String = "[路线] Current", cover: String = "current.jpg", status: Int = 0) throws -> MessagingMessage {
        let extra = String(decoding: try JSONSerialization.data(withJSONObject: ["cardType": "route", "topicId": 42, "imgUrl": cover]), as: UTF8.self)
        return try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject:
            ["id": 101, "conversationId": 9, "senderId": 7, "status": status, "msgType": 3, "content": content, "extraJson": extra]))
    }
    func testNoProjectionBeforeSuccessfulReadOrAfterReadFailure() throws {
        var state = IMRouteProjectionReadState(); let m = try message()
        XCTAssertFalse(state.isCurrent(m, upstream: m))
        let first = try XCTUnwrap(state.begin()); XCTAssertNil(state.begin())
        XCTAssertTrue(state.complete(first, message: m, upstream: m)); XCTAssertTrue(state.isCurrent(m, upstream: m))
        let retry = try XCTUnwrap(state.begin()); XCTAssertFalse(state.isCurrent(m, upstream: m))
        state.finish(retry); XCTAssertFalse(state.isCurrent(m, upstream: m))
    }
    func testBackgroundDisappearAndIdentityInvalidationRequireNewRead() throws {
        for _ in ["background", "disappear", "identity", "reader"] {
            var state = IMRouteProjectionReadState(); let m = try message()
            let first = try XCTUnwrap(state.begin()); XCTAssertTrue(state.complete(first, message: m, upstream: m))
            state.invalidate(); XCTAssertFalse(state.isCurrent(m, upstream: m))
            let next = try XCTUnwrap(state.begin()); XCTAssertFalse(state.isCurrent(m, upstream: m))
            XCTAssertTrue(state.complete(next, message: m, upstream: m)); XCTAssertTrue(state.isCurrent(m, upstream: m))
        }
    }
    func testOldCompletionAndDeferCannotReleaseNewerRead() throws {
        var state = IMRouteProjectionReadState(); let m = try message()
        let old = try XCTUnwrap(state.begin()); state.invalidate()
        let newer = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.complete(old, message: m, upstream: m)); state.finish(old)
        XCTAssertTrue(state.isReading(newer)); XCTAssertNil(state.begin()); XCTAssertFalse(state.isCurrent(m, upstream: m))
        XCTAssertTrue(state.complete(newer, message: m, upstream: m)); state.finish(old)
        XCTAssertTrue(state.isCurrent(m, upstream: m))
    }
    func testNormalStatusUnavailableUpstreamWinsOverOldVerifiedNameAndCover() throws {
        let old = try message("[路线] Former", cover: "former.jpg"), unavailable = try message("路线已不可用", cover: "private.jpg")
        var state = IMRouteProjectionReadState(); let ticket = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.complete(ticket, message: old, upstream: old))
        let current = IMRouteProjectionReadState.resolve(verified: old, upstream: unavailable, upstreamAtRead: old)
        XCTAssertEqual(current, unavailable); XCTAssertTrue(unavailable.isPayloadVisible)
        XCTAssertFalse(state.isCurrent(unavailable, upstream: unavailable)); XCTAssertNil(IMRouteCardProjection.read(try XCTUnwrap(current)))
        XCTAssertTrue(IMCardAction.actions(for: try XCTUnwrap(current)).isEmpty)
    }
    func testNewUpstreamRenameAndRemovalCannotBorrowOldProof() throws {
        let old = try message("[路线] Former"), renamed = try message("[路线] Renamed")
        var state = IMRouteProjectionReadState(); let ticket = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.complete(ticket, message: old, upstream: old))
        XCTAssertEqual(IMRouteProjectionReadState.resolve(verified: old, upstream: renamed, upstreamAtRead: old), renamed)
        XCTAssertFalse(state.isCurrent(renamed, upstream: renamed)); XCTAssertFalse(state.isCurrent(old, upstream: nil))
        XCTAssertNil(IMRouteProjectionReadState.resolve(verified: old, upstream: nil, upstreamAtRead: old))
        for status in [1, 2, 99] {
            let withheld = try message(status: status)
            XCTAssertEqual(IMRouteProjectionReadState.resolve(verified: old, upstream: withheld, upstreamAtRead: old), withheld)
        }
    }
    func testFreshDetailRevocationWinsWhenUpstreamHasNotChanged() throws {
        let upstream = try message(), unavailable = try message("路线已不可用")
        XCTAssertEqual(IMRouteProjectionReadState.resolve(verified: unavailable, upstream: upstream, upstreamAtRead: upstream), unavailable)
        XCTAssertNil(IMRouteCardProjection.read(unavailable))
    }
    func testExplicitFreshReadAfterUnavailableUpstreamCanRecoverNewPublicProjection() throws {
        let unavailable = try message("路线已不可用", cover: "old.jpg")
        let fresh = try message("[路线] Public again", cover: "fresh.jpg")
        var state = IMRouteProjectionReadState(); let retry = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.complete(retry, message: fresh, upstream: unavailable))
        let current = try XCTUnwrap(IMRouteProjectionReadState.resolve(verified: fresh, upstream: unavailable, upstreamAtRead: unavailable))
        XCTAssertTrue(state.isCurrent(current, upstream: unavailable))
        XCTAssertEqual(IMRouteCardProjection.read(current)?.name, "Public again")
        XCTAssertEqual(IMRouteCardProjection.read(current)?.imageURL, "fresh.jpg")
        XCTAssertEqual(IMCardAction.actions(for: current).map(\.destination), [.topic(42)])
    }
    @MainActor func testOriginalHistoryReaderFeedsCurrentNameCoverAndTypedAction() async throws {
        let upstream = try message("[路线] Current reader name", cover: "https://media.example.test/current.jpg")
        let reader = try RouteProjectionHistoryReader(message: upstream)
        var state = IMRouteProjectionReadState(); let ticket = try XCTUnwrap(state.begin())
        let received = try await MessagingHistory.readExistingMessage(id: 101, conversationID: 9,
            using: reader, stillCurrent: { state.isReading(ticket) })
        XCTAssertEqual(reader.reads, [0]); XCTAssertEqual(received.cursor, 0)
        XCTAssertTrue(state.complete(ticket, message: received.message, upstream: upstream))
        let accepted = try XCTUnwrap(received.message)
        XCTAssertTrue(state.isCurrent(accepted, upstream: upstream))
        XCTAssertEqual(IMRouteCardProjection.read(accepted)?.name, "Current reader name")
        XCTAssertEqual(IMRouteCardProjection.read(accepted)?.imageURL, "https://media.example.test/current.jpg")
        XCTAssertEqual(IMCardAction.actions(for: accepted).map(\.destination), [.topic(42)])
        state.invalidate(); let next = try XCTUnwrap(state.begin())
        reader.beforeReply = { state.invalidate() }
        do {
            _ = try await MessagingHistory.readExistingMessage(id: 101, conversationID: 9,
                using: reader, stillCurrent: { state.isReading(next) })
            XCTFail("A lifecycle change during the original read cannot publish")
        } catch is CancellationError {} catch { XCTFail("Unexpected failure: \(error)") }
        state.finish(next); XCTAssertFalse(state.isCurrent(accepted, upstream: upstream))
    }
}

@MainActor private final class RouteProjectionHistoryReader: MessagingReading {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    let isConfigured = true
    var reads: [Int] = []
    var beforeReply: (() -> Void)?
    private let page: MessagingPage
    init(message: MessagingMessage) throws {
        let row: [String: Any] = ["id": message.id, "conversationId": message.conversationID,
            "senderId": 7, "status": 0, "msgType": 3, "content": message.content ?? "",
            "extraJson": message.extraJSON ?? ""]
        page = try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject:
            ["list": [row], "hasMore": false, "nextCursor": 0]))
    }
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        XCTAssertEqual(conversationID, 9); reads.append(cursor); beforeReply?(); return page
    }
}
