import XCTest
@testable import QuestifyCore

final class HomeSearchTabParityTests: XCTestCase {
    // MARK: - HomeIndexParityPresentation

    func testCitySelectorFallbackAndNationwide() {
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: nil), "选择城市")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: "   \n "), "选择城市")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: "上海"), "上海")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: " 上海 "), "上海")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: "上海", isNationwide: true), "全国")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: nil, isNationwide: true), "全国")
    }

    func testHomeShelfHeadersAndGreetingCopy() {
        XCTAssertEqual(
            HomeIndexParityPresentation.shelfHeaders,
            ["精选路线", "近期活动", "热门主题", "现成玩法"]
        )
        XCTAssertEqual(HomeIndexParityPresentation.greetingText(nickname: nil), "Hi, 旅人!")
        XCTAssertEqual(HomeIndexParityPresentation.greetingText(nickname: "  "), "Hi, 旅人!")
        XCTAssertEqual(HomeIndexParityPresentation.greetingText(nickname: "阿明"), "Hi, 阿明!")
        XCTAssertEqual(HomeIndexParityPresentation.fixedActionBanners.count, 3)
        XCTAssertEqual(
            HomeIndexParityPresentation.fixedActionBanners.map(\.routePath),
            ["pages/club/apply", "pages/merchant/apply", "pages/activity/list"]
        )
        XCTAssertEqual(HomeIndexParityPresentation.recommendedTopicsTitle, "推荐主题")
        XCTAssertEqual(HomeIndexParityPresentation.nearbyActivitiesTitle, "附近活动")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingActivitiesTitle, "即将上线")
        XCTAssertEqual(HomeIndexParityPresentation.noMoreFooterCopy, "· 没有更多了 ·")
        XCTAssertEqual(HomeIndexParityPresentation.emptyStateTitle, "暂无内容")
        XCTAssertEqual(HomeIndexParityPresentation.loadingCopy, "加载中...")
        XCTAssertEqual(HomeIndexParityPresentation.errorCopy, "加载失败，请点击重试")

        let runs = [
            PlayContinueRun(scope: .activity(12), elapsedSeconds: 300, title: "外滩迷雾"),
            PlayContinueRun(scope: .topic(55), elapsedSeconds: 0, title: "   ")
        ]
        let duplicateActivity = try! JSONDecoder().decode(
            ParticipationRecord.self,
            from: Data(#"{"id":70,"ownerType":0,"cmsActivity":{"id":12,"name":"外滩迷雾重复","address":"外滩18号"}}"#.utf8)
        )
        let joinedTopic = try! JSONDecoder().decode(
            ParticipationRecord.self,
            from: Data(#"{"id":71,"ownerType":1,"activityTitle":" 愚园路漫步 ","cmsTopic":{"id":91,"address":" 静安寺 "}}"#.utf8)
        )
        let cards = HomeIndexParityPresentation.continuationCards(
            pausedRuns: runs,
            participations: [duplicateActivity, joinedTopic]
        )
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards[0].kind, .continueGame)
        XCTAssertEqual(cards[0].kind.badgeTitle, "继续游戏")
        XCTAssertEqual(cards[0].destination, .activity(12))
        XCTAssertEqual(cards[0].title, "外滩迷雾")
        XCTAssertEqual(cards[0].subtitle, "已进行 5 分钟")
        XCTAssertEqual(cards[1].kind, .continueGame)
        XCTAssertEqual(cards[1].destination, .topic(55))
        XCTAssertEqual(cards[1].title, "进行中的路线 #55")
        XCTAssertNil(cards[1].subtitle)
        XCTAssertEqual(cards[2].kind, .continueExploration)
        XCTAssertEqual(cards[2].kind.badgeTitle, "继续探索")
        XCTAssertEqual(cards[2].destination, .topic(91))
        XCTAssertEqual(cards[2].title, "愚园路漫步")
        XCTAssertEqual(cards[2].subtitle, "静安寺")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let futureDays = now.addingTimeInterval(2 * 86_400 + 3 * 3_600)
        let futureHours = now.addingTimeInterval(3 * 3_600 + 15 * 60)
        let futureMinutes = now.addingTimeInterval(25 * 60)
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureDays, now: now), "距上线 2天3小时")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureHours, now: now), "距上线 3小时15分")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureMinutes, now: now), "距上线 25分钟")
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: now, now: now))
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: now.addingTimeInterval(-60), now: now))
    }

    // MARK: - GlobalSearchParityPresentation

    func testKeywordTrimmingAndHistoryDeduplicationMaxTen() {
        XCTAssertEqual(GlobalSearchParityPresentation.trimmedKeyword("  外滩 \n"), "外滩")
        XCTAssertEqual(GlobalSearchParityPresentation.trimmedKeyword(nil), "")

        let initial = ["骑行", "外滩", "书店", "骑行", "  ", "美术馆"]
        let deduped = GlobalSearchParityPresentation.deduplicateHistory(initial)
        XCTAssertEqual(deduped, ["骑行", "外滩", "书店", "美术馆"])

        let updated = GlobalSearchParityPresentation.recordHistory(keyword: " 书店 ", into: deduped)
        XCTAssertEqual(updated, ["书店", "骑行", "外滩", "美术馆"])

        let twelve = (1...12).map { "关键词\($0)" }
        let capped = GlobalSearchParityPresentation.deduplicateHistory(twelve)
        XCTAssertEqual(capped.count, 10)
        XCTAssertEqual(capped.first, "关键词1")
        XCTAssertEqual(capped.last, "关键词10")
    }

    func testResultTabDescriptorsAndCountBadges() {
        let tabs = GlobalSearchParityPresentation.resultTabs(
            routesCount: 3,
            activitiesCount: 0,
            merchantsCount: 2,
            clubsCount: 1,
            momentsCount: 4
        )
        XCTAssertEqual(tabs.map(\.title), ["全部", "路线", "活动", "商家", "俱乐部", "动态"])
        XCTAssertEqual(tabs.map(\.count), [10, 3, 0, 2, 1, 4])
        XCTAssertEqual(tabs[0].badgeText, "10")
        XCTAssertEqual(tabs[1].displayLabel, "路线 3")
        XCTAssertNil(tabs[2].badgeText)
        XCTAssertEqual(tabs[2].displayLabel, "活动")
    }

    // MARK: - RootTabBarParity

    func testConsumerAndMerchantRootTabBarSpecifications() {
        let consumerState = RootTabBarParity.TabBarState(mode: .consumer, selectedTab: .home, isAuthenticated: false)
        XCTAssertEqual(consumerState.tabs.count, 5)
        XCTAssertEqual(consumerState.tabs.map(\.rootTab), [.home, .roam, .publish, .club, .mine])
        XCTAssertTrue(consumerState.tabs[0].matchesLabel("首页"))
        XCTAssertTrue(consumerState.tabs[0].matchesLabel("发现"))
        XCTAssertTrue(consumerState.tabs[1].matchesLabel("漫游"))
        XCTAssertTrue(consumerState.tabs[2].matchesLabel("模板"))
        XCTAssertTrue(consumerState.tabs[2].matchesLabel("玩法"))
        XCTAssertTrue(consumerState.tabs[3].matchesLabel("俱乐部"))
        XCTAssertTrue(consumerState.tabs[4].matchesLabel("我的"))

        let merchantState = RootTabBarParity.TabBarState(mode: .merchant, selectedTab: .roam, isAuthenticated: true)
        XCTAssertEqual(merchantState.tabs.count, 5)
        XCTAssertEqual(merchantState.tabs.map(\.primaryTitle), ["工作台", "营销", "模板", "合作", "我的"])
    }
}
