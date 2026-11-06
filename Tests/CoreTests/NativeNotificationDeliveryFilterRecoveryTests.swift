import Foundation
import XCTest
@testable import QuestifyCore

/// Authored, NOT_RUN. In-memory responses only; no notification or network transport.
@MainActor final class NativeNotificationDeliveryFilterRecoveryTests: XCTestCase {
    private final class Client: NativeChannelNotificationAccess {
        let context: RuntimeDependencyContext
        var isCurrent = true
        var queries: [NativeNotificationDeliveryLogQuery] = []
        var fail = false
        var more = false
        init() throws {
            context = .init(market: .china, baseURL: URL(string: "https://example.com/")!, role: "player",
                            session: try .init(accountID: 2, epoch: 1, namespace: "delivery-test", token: "synthetic-token", role: "player"))
        }
        func retireOperations() { isCurrent = false }
        func allows(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> Bool { isCurrent }
        func deliveryLog(query: NativeNotificationDeliveryLogQuery) async throws -> NativeNotificationDeliveryLogPage {
            queries.append(query)
            if fail { throw NativeChannelNotificationError.malformedResponse }
            var object: [String: Any] = ["source": "original-notification-results-v1", "member_id": "2", "list": [],
                                       "has_more": more, "sources": ["wx": true, "apns": false, "inapp": false], "delivery_proven": false]
            if more {
                object["next_cursor"] = "original_cursor"
                object["list"] = [["id": "wx:1", "event": query.event ?? "MESSAGE_MENTION", "channel": "wx", "ok": 1,
                                   "create_time": "2026-11-05 10:00:00.000000", "result_source": "signed-wx-sent-event", "source_conflict": false]]
            }
            return try JSONDecoder().decode(NativeNotificationDeliveryLogPage.self, from: JSONSerialization.data(withJSONObject: object))
        }
        func preferences(scope: NativeChannelNotificationScope?) async throws -> NativeChannelNotificationDirectory { throw NativeChannelNotificationError.accessClosed }
        func submit(_ command: NativeChannelNotificationCommand) async throws -> NativeChannelNotificationReceipt { XCTFail("No write allowed"); throw NativeChannelNotificationError.accessClosed }
        func receipt(_ command: NativeChannelNotificationCommand, recovery: NativeChannelNotificationRecovery?) async throws -> NativeChannelNotificationReceipt { throw NativeChannelNotificationError.accessClosed }
        func unreadSummary() async throws -> NativeChannelNotificationUnreadSummary { throw NativeChannelNotificationError.accessClosed }
    }
    func testInvalidFilterRetryNeverReadsPreviousSuccessfulFilter() async throws {
        let client = try Client(), flow = NativeNotificationDeliveryLogCoordinator(client: client)
        await flow.activate()
        await flow.refresh(event: "MESSAGE_MENTION")
        XCTAssertEqual(client.queries.count, 2)
        await flow.refresh(event: "INVALID FILTER")
        XCTAssertEqual(flow.state, .unavailable)
        XCTAssertNil(flow.page)
        XCTAssertEqual(flow.currentEvent, "INVALID FILTER")
        await flow.rereadPage()
        XCTAssertEqual(client.queries.count, 2)
        XCTAssertEqual(flow.state, .unavailable)
        XCTAssertNil(flow.page)
    }
    func testCorrectedFilterStartsItsOwnReadAndClearsRejectedSelection() async throws {
        let client = try Client(), flow = NativeNotificationDeliveryLogCoordinator(client: client)
        await flow.activate()
        await flow.refresh(event: "bad filter")
        await flow.refresh(event: "MESSAGE_MENTION")
        XCTAssertEqual(flow.state, .ready)
        XCTAssertEqual(flow.currentEvent, "MESSAGE_MENTION")
        await flow.rereadPage()
        XCTAssertEqual(client.queries.count, 3)
        XCTAssertEqual(client.queries.last?.event, "MESSAGE_MENTION")
        XCTAssertNil(client.queries.last?.cursor)
    }
    func testFailedNextPageRetriesExactOriginalCursorAndFilter() async throws {
        let client = try Client(), flow = NativeNotificationDeliveryLogCoordinator(client: client)
        await flow.activate()
        client.more = true
        await flow.refresh(event: "MESSAGE_MENTION")
        XCTAssertTrue(flow.canReadNext)
        client.fail = true
        await flow.readNext()
        let failed = try XCTUnwrap(client.queries.last)
        XCTAssertEqual(failed.cursor, "original_cursor")
        XCTAssertEqual(flow.state, .unavailable)
        client.fail = false; client.more = false
        await flow.rereadPage()
        XCTAssertEqual(client.queries.last, failed)
        XCTAssertEqual(flow.state, .ready)
    }
    func testRetirementClearsRejectedFilterAndCannotRetryOrReactivate() async throws {
        let client = try Client(), flow = NativeNotificationDeliveryLogCoordinator(client: client)
        await flow.activate()
        await flow.refresh(event: "bad filter")
        flow.deactivate()
        await flow.rereadPage()
        await flow.activate()
        XCTAssertEqual(client.queries.count, 1)
        XCTAssertNil(flow.currentEvent)
        XCTAssertNil(flow.page)
        XCTAssertEqual(flow.state, .accessClosed)
    }
}
