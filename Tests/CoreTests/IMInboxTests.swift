import XCTest
@testable import QuestifyCore

/// w2-20: mini-program im/list `tabOf`, badge counts, `fmtTime` and chat `fmtAbs`.
final class IMInboxTests: XCTestCase {
    private func rows(_ values: [[String: Any]]) throws -> [MessagingConversation] {
        try JSONDecoder().decode([MessagingConversation].self, from: JSONSerialization.data(withJSONObject: values))
    }
    private func china(_ text: String) throws -> Date { try XCTUnwrap(IMInboxTime.parse(text)) }

    func testTabsFollowSourceTypeMappingAndKeepGroupsNativeOnly() throws {
        let list = try rows([
            ["conversationId": 1, "type": 1], ["conversationId": 2, "type": 2], ["conversationId": 3, "type": 3],
            ["conversationId": 4, "type": 4], ["conversationId": 5], ["conversationId": 6, "type": 9]
        ])
        let summary = IMInboxSummary(conversations: list)
        XCTAssertEqual(summary.rows(for: .direct).map(\.id), [1, 3, 5, 6])
        XCTAssertEqual(summary.rows(for: .system).map(\.id), [2])
        XCTAssertEqual(summary.rows(for: .group).map(\.id), [4])
        XCTAssertEqual(summary.visibleTabs, [.direct, .system, .group])
        XCTAssertEqual(summary.initialTab, .direct)
    }
    func testGroupTabOnlyAppearsWithGroupRows() throws {
        XCTAssertEqual(IMInboxSummary(conversations: []).visibleTabs, [.direct, .system])
        XCTAssertEqual(IMInboxSummary(conversations: []).initialTab, .direct)
        let groups = IMInboxSummary(conversations: try rows([["conversationId": 4, "type": 4]]))
        XCTAssertEqual(groups.initialTab, .group)
    }
    func testBadgesExcludeMutedRowsLikeTheGlobalRedDot() throws {
        let summary = IMInboxSummary(conversations: try rows([
            ["conversationId": 1, "type": 1, "unread": 3, "muted": 0],
            ["conversationId": 2, "type": 1, "unread": 5, "muted": 1],
            ["conversationId": 3, "type": 3, "unread": 2],
            ["conversationId": 4, "type": 2, "unread": 7, "muted": "1"],
            ["conversationId": 5, "type": 2, "unread": 1, "muted": "maybe"]
        ]))
        XCTAssertEqual(summary.badge(for: .direct), 5)
        XCTAssertEqual(summary.badge(for: .system), 1, "unknown muted is not treated as muted")
        XCTAssertTrue(summary.hasUnread)
        XCTAssertFalse(IMInboxSummary(conversations: try rows([["conversationId": 1, "unread": 0]])).hasUnread)
    }
    func testBadgeTextCapsAtNinetyNinePlus() {
        XCTAssertNil(IMInboxSummary.badgeText(nil)); XCTAssertNil(IMInboxSummary.badgeText(0))
        XCTAssertEqual(IMInboxSummary.badgeText(7), "7"); XCTAssertEqual(IMInboxSummary.badgeText(99), "99")
        XCTAssertEqual(IMInboxSummary.badgeText(100), "99+")
    }
    func testWallClockStringsAreAnchoredToChinaTime() throws {
        let date = try china("2026-10-19 08:30:00")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_792_369_800))
        XCTAssertEqual(try china("2026-10-19T08:30:00.123"), date.addingTimeInterval(0))
        XCTAssertEqual(IMInboxTime.parse("2026-10-19T00:30:00Z"), date)
        XCTAssertEqual(IMInboxTime.parse("1792369800"), date)
        XCTAssertNil(IMInboxTime.parse("2026-02-30 10:00:00"))
        XCTAssertNil(IMInboxTime.parse("yesterday"))
        XCTAssertNil(IMInboxTime.parse(nil))
    }
    func testListTimeTextMatchesSourceBuckets() throws {
        let now = try china("2026-10-19 12:00:00") // Monday
        XCTAssertEqual(IMInboxTime.listText("2026-10-19 11:59:30", now: now), .justNow)
        XCTAssertEqual(IMInboxTime.listText("2026-10-19 11:15:00", now: now), .minutesAgo(45))
        XCTAssertEqual(IMInboxTime.listText("2026-10-19 08:05:00", now: now), .clock("08:05"))
        XCTAssertEqual(IMInboxTime.listText("2026-10-18 23:00:00", now: now), .yesterday)
        XCTAssertEqual(IMInboxTime.listText("2026-10-15 09:00:00", now: now), .weekday(4))
        XCTAssertEqual(IMInboxTime.listText("2026-09-01 09:00:00", now: now), .monthDay(month: 9, day: 1))
        XCTAssertNil(IMInboxTime.listText("", now: now))
    }
    func testChatDividersFollowFiveMinuteGaps() throws {
        let now = try china("2026-10-19 12:00:00")
        let page = try JSONDecoder().decode(MessagingPage.self, from: Data(#"""
        {"list":[
          {"id":1,"conversationId":9,"status":0,"createTime":"2026-10-18 21:00:00"},
          {"id":2,"conversationId":9,"status":0,"createTime":"2026-10-18 21:04:00"},
          {"id":3,"conversationId":9,"status":0},
          {"id":4,"conversationId":9,"status":0,"createTime":"2026-10-18 21:10:00"},
          {"id":5,"conversationId":9,"status":0,"createTime":"2026-10-19 09:01:00"},
          {"id":6,"conversationId":9,"status":0,"createTime":"2026-10-01 09:01:00"}
        ],"hasMore":false}
        """#.utf8))
        let dividers = IMInboxTime.dividers(for: page.messages, now: now)
        XCTAssertEqual(dividers[1], .yesterday(clock: "21:00"))
        XCTAssertNil(dividers[2]); XCTAssertNil(dividers[3])
        XCTAssertEqual(dividers[4], .yesterday(clock: "21:10"))
        XCTAssertEqual(dividers[5], .today(clock: "09:01"))
        XCTAssertNil(dividers[6], "an older out-of-order stamp is not more than five minutes after its predecessor")
    }
    func testMessagesPageDecodesOnlyLiteralBlockFlags() throws {
        func page(_ extra: String) throws -> MessagingPage {
            try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false\#(extra)}"#.utf8))
        }
        let blocked = try page(#","blocked":true,"blockedByMe":false"#)
        XCTAssertEqual(blocked.blocked, true); XCTAssertEqual(blocked.blockedByMe, false)
        let absent = try page("")
        XCTAssertNil(absent.blocked); XCTAssertNil(absent.blockedByMe)
        XCTAssertNil(try page(#","blocked":"yes""#).blocked)
    }
    func testPreviewPolicySilentRefreshAndReadReceiptTriggerPolicy() throws {
        let conversation = try XCTUnwrap(rows([
            ["conversationId": 11, "type": 1, "lastMsgText": "  周末集合点确认  "]
        ]).first)
        XCTAssertEqual(IMConversationPreviewPolicy.defaultPolicy, .redactedPlaceholder)
        XCTAssertEqual(IMConversationPreviewPolicy.resolve(for: conversation), "打开会话查看消息")
        XCTAssertEqual(
            IMConversationPreviewPolicy.resolve(for: conversation, policy: .serverPreviewWhenUnrecalled),
            "周末集合点确认"
        )
        XCTAssertEqual(
            IMConversationPreviewPolicy.resolve(for: conversation, policy: .serverPreviewWhenUnrecalled, isRecalled: true),
            "打开会话查看消息"
        )
        XCTAssertEqual(
            IMConversationPreviewPolicy.serverPreviewWhenUnrecalled.previewText(serverPreview: "   "),
            "打开会话查看消息"
        )

        let refreshing = IMSilentRefreshPresentation(isRefreshingWithSnapshot: true)
        XCTAssertEqual(refreshing.statusText, "正在刷新消息")
        let idle = IMSilentRefreshPresentation(isLoading: false, hasSnapshot: true)
        XCTAssertFalse(idle.isRefreshingWithSnapshot)
        XCTAssertNil(idle.statusText)

        XCTAssertEqual(IMReadReceiptTriggerPolicy.defaultPolicy, .explicitUserActionOnly)
        XCTAssertFalse(IMReadReceiptTriggerPolicy.explicitUserActionOnly.shouldAutoMarkRead)
        XCTAssertFalse(IMReadReceiptTriggerPolicy.autoOnLoadWhenGranted(imReadGranted: false).shouldAutoMarkRead)
        XCTAssertTrue(IMReadReceiptTriggerPolicy.autoOnLoadWhenGranted(imReadGranted: true).shouldAutoMarkRead)
        XCTAssertTrue(IMReadReceiptTriggerPolicy.autoOnLoadWhenGranted(imReadGranted: true).shouldAutoMarkRead(unreadCount: 2))
        XCTAssertFalse(IMReadReceiptTriggerPolicy.autoOnLoadWhenGranted(imReadGranted: true).shouldAutoMarkRead(unreadCount: 0))
    }
}
