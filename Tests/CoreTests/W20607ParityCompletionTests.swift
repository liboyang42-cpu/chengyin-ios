import XCTest
@testable import QuestifyCore

final class W20607ParityCompletionTests: XCTestCase {
    func testOfficialMineCategorySuffixAndBroadcastSummaryLine() throws {
        XCTAssertEqual(OfficialPublishedPresentation.categorySuffix("剧本杀"), " · 剧本杀")
        XCTAssertEqual(OfficialPublishedPresentation.categorySuffix("  城市漫游  "), " · 城市漫游")
        XCTAssertNil(OfficialPublishedPresentation.categorySuffix(nil))
        XCTAssertNil(OfficialPublishedPresentation.categorySuffix("   "))
        XCTAssertEqual(
            OfficialPublishedPresentation.cityAndCategoryLine(city: "杭州", category: "城市漫游"),
            "杭州 · 城市漫游"
        )
        XCTAssertEqual(
            OfficialPublishedPresentation.cityAndCategoryLine(city: nil, category: "桌游"),
            "城市待确认 · 桌游"
        )

        let known = try JSONDecoder().decode(
            OfficialPublishedBroadcastFacts.self,
            from: Data(#"{"id":9,"copyMode":1,"audience":"PLAYER,MERCHANT","status":2,"city":"杭州"}"#.utf8)
        )
        XCTAssertEqual(
            OfficialPublishedPresentation.broadcastSummaryLine(known),
            "一起发 · 发给 玩家 / 商家 · 杭州"
        )
        XCTAssertEqual(known.sourceStatusText, "已发")

        let fallback = try JSONDecoder().decode(
            OfficialPublishedBroadcastFacts.self,
            from: Data(#"{"id":10,"copyMode":99,"audience":"UNKNOWN","status":99,"city":"   "}"#.utf8)
        )
        XCTAssertEqual(
            OfficialPublishedPresentation.broadcastSummaryLine(fallback),
            "发送方式待确认 · 发给 对象待确认 · 范围待确认"
        )
        XCTAssertEqual(fallback.sourceStatusText, "状态待确认")
    }

    func testOfficialInboxBeijingTimeServiceWindowAndLoadFailureCopy() {
        XCTAssertEqual(OfficialInboxPresentation.loadFailureTitle, "邀约没有加载出来")
        XCTAssertEqual(OfficialInboxPresentation.loadFailureDetail, "邀约加载失败")
        XCTAssertEqual(OfficialInboxPresentation.loadFailureTitleKey, "official.w206.inbox.failed.title")
        XCTAssertEqual(OfficialInboxPresentation.loadFailureDetailKey, "official.w206.inbox.failed.detail")

        // 2026-09-22 09:00:00 Asia/Shanghai = 1790038800000 ms
        let startMs = OfficialEventTime.milliseconds(1_790_038_800_000)
        XCTAssertEqual(
            OfficialInboxPresentation.serviceWindowText(start: startMs, end: nil),
            "9月22日 09:00 — 不限"
        )
        XCTAssertEqual(
            OfficialInboxPresentation.serviceWindowText(start: nil, end: nil),
            "未限定服务时段"
        )
        XCTAssertEqual(
            OfficialInboxPresentation.serviceWindowText(start: .text("1790038800000"), end: .text("2026-09-22 18:00")),
            "9月22日 09:00 — 2026-09-22 18:00"
        )
    }

    func testMerchantApplyDirtyExitConfirmationAndSuccessSummary() {
        XCTAssertNil(MerchantApplyXcx.dirtyExitConfirmation(isDirty: false))
        let modal = MerchantApplyXcx.dirtyExitConfirmation(isDirty: true)
        XCTAssertEqual(
            modal,
            MerchantApplyXcx.DirtyExitConfirmation(
                title: "放弃当前编辑内容？",
                keepEditingTitle: "继续编辑",
                discardAndExitTitle: "放弃并退出"
            )
        )

        let createSummary = MerchantApplyXcx.submissionSuccessSummary(
            isEdit: false,
            chapterTitle: "第一章 · 运河码头",
            placeName: "桥西茶馆",
            placeAddress: "拱墅区桥西直街 18 号",
            startDate: "2026-05-01 00:00:00",
            endDate: "2026-05-31 23:59:59"
        )
        XCTAssertFalse(createSummary.isEdit)
        XCTAssertEqual(createSummary.title, "报名已提交")
        XCTAssertEqual(createSummary.notice, "报名成功不等于中标，需创作者审核选用后才进入正式路线")
        XCTAssertEqual(createSummary.chapterTitle, "第一章 · 运河码头")
        XCTAssertEqual(createSummary.placeSummary, "桥西茶馆 · 拱墅区桥西直街 18 号")
        XCTAssertEqual(createSummary.dateRangeText, "2026-05-01 至 2026-05-31")

        let editSummary = MerchantApplyXcx.submissionSuccessSummary(isEdit: true)
        XCTAssertTrue(editSummary.isEdit)
        XCTAssertEqual(editSummary.title, "报名信息已更新")
        XCTAssertNil(editSummary.chapterTitle)
        XCTAssertNil(editSummary.placeSummary)
        XCTAssertNil(editSummary.dateRangeText)
    }

    func testTopicPricingChapterSupplyRowTargetAndLockedNotes() throws {
        XCTAssertEqual(TopicPricingXcx.lockedNote(forPartnerDetail: false), "阵容已锁定，点开可查该合作方在本主题中的结算条款。")
        XCTAssertEqual(TopicPricingXcx.lockedNote(forPartnerDetail: true), "阵容已锁定，以下为该合作方在本主题中的结算条款。")

        let chapterRow = try XCTUnwrap(PublisherLineup(.object([
            "toType": .string("MERCHANT"),
            "toId": .number(42),
            "shareMode": .number(2),
            "fixedFee": .string("15.00"),
            "chapterId": .number(7),
            "termsMode": .string("REVSHARE")
        ])))
        XCTAssertTrue(TopicPricingXcx.opensChapterProject(chapterRow))
        XCTAssertEqual(
            TopicPricingXcx.rowTarget(topicID: 100, row: chapterRow),
            .chapterProject(topicID: 100, chapterID: 7, partnerID: 42)
        )

        let partnerRow = try XCTUnwrap(PublisherLineup(.object([
            "toType": .string("CLUB"),
            "toId": .number(88),
            "shareMode": .number(1),
            "shareRate": .string("25")
        ])))
        XCTAssertFalse(TopicPricingXcx.opensChapterProject(partnerRow))
        XCTAssertEqual(
            TopicPricingXcx.rowTarget(topicID: 100, row: partnerRow),
            .partnerTerms(topicID: 100, partnerType: "CLUB", partnerID: 88)
        )
        XCTAssertNil(TopicPricingXcx.rowTarget(topicID: 0, row: partnerRow))
    }

    func testProfileComplaintNetworkVsGenericFailureSubtitles() {
        let networkError = URLError(.notConnectedToInternet)
        XCTAssertTrue(ProfileComplaintTopicLoadFailureCopy.isNetworkError(networkError))
        XCTAssertEqual(
            ProfileComplaintTopicLoadFailureCopy.sourceSubtitle(for: networkError),
            "网络异常，请重试"
        )
        XCTAssertEqual(
            ProfileComplaintReadIssue.failed.sourceSubtitle(isNetworkError: true),
            "网络异常，请重试"
        )

        let serverError = CoopFlowFailure.server(503, "busy")
        XCTAssertFalse(ProfileComplaintTopicLoadFailureCopy.isNetworkError(serverError))
        XCTAssertEqual(
            ProfileComplaintTopicLoadFailureCopy.sourceSubtitle(for: serverError),
            "可投诉活动加载失败，请重试"
        )
        XCTAssertEqual(
            ProfileComplaintReadIssue.failed.sourceSubtitle(isNetworkError: false),
            "可投诉活动加载失败，请重试"
        )
        XCTAssertEqual(
            ProfileComplaintTopicLoadFailureCopy.sourceSubtitle(for: APIError.unauthorized),
            "登录状态已失效，请重新进入"
        )
    }
}
