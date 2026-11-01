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
        let exactOneHour = now.addingTimeInterval(3_600)
        let futureMinutes = now.addingTimeInterval(25 * 60)
        let subSecond = now.addingTimeInterval(0.2)
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureDays, now: now), "距上线 2天3小时")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureHours, now: now), "距上线 3小时15分")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: exactOneHour, now: now), "距上线 1小时0分")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureMinutes, now: now), "距上线 25分钟")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: subSecond, now: now), "距上线 1分钟")
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: now, now: now))
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: now.addingTimeInterval(-60), now: now))

        let enLocale = Locale(identifier: "en_US")
        XCTAssertEqual(HomeIndexParityPresentation.greetingText(nickname: nil, locale: enLocale), "Hi, Traveler!")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: nil, locale: enLocale), "Select City")
        XCTAssertEqual(HomeIndexParityPresentation.citySelectorLabel(selectedCity: "上海", isNationwide: true, locale: enLocale), "Nationwide")
        XCTAssertEqual(
            HomeIndexParityPresentation.fixedActionBanners.map { $0.title(locale: enLocale) },
            ["Become a Club", "Become a Merchant", "Join Activities with Friends"]
        )
        XCTAssertEqual(HomeIndexParityPresentation.noMoreFooterCopy(locale: enLocale), "· No more items ·")
        XCTAssertEqual(HomeIndexParityPresentation.continuationSectionTitle(locale: enLocale), "Continue Game / Continue Exploration")
        XCTAssertEqual(cards[0].kind.badgeTitle(locale: enLocale), "Continue Game")
        XCTAssertEqual(cards[0].localizedSubtitle(locale: enLocale), "5 min elapsed")
        XCTAssertEqual(cards[1].localizedTitle(locale: enLocale), "Route in progress #55")
        XCTAssertEqual(cards[2].kind.badgeTitle(locale: enLocale), "Continue Exploration")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: futureDays, now: now, locale: enLocale), "Starts in 2d 3h")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: exactOneHour, now: now, locale: enLocale), "Starts in 1h 0m")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: subSecond, now: now, locale: enLocale), "Starts in 1m")

        let scheduleStart = now.addingTimeInterval(185)
        let ticks = HomeIndexParityPresentation.countdownScheduleDates(from: now, start: scheduleStart, base: [now, scheduleStart])
        XCTAssertEqual(
            ticks,
            [
                now,
                scheduleStart.addingTimeInterval(-180),
                scheduleStart.addingTimeInterval(-120),
                scheduleStart.addingTimeInterval(-60),
                scheduleStart
            ]
        )
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: scheduleStart, now: ticks[0]), "距上线 3分钟")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: scheduleStart, now: ticks[1]), "距上线 3分钟")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: scheduleStart, now: ticks[2]), "距上线 2分钟")
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: scheduleStart, now: ticks[3]), "距上线 1分钟")
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: scheduleStart, now: ticks[4]))
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
        XCTAssertEqual(consumerState.activeContainerRoute, .consumerHome)

        let merchantState = consumerState.switchingMode(to: .merchant, resettingTabTo: .roam)
        XCTAssertEqual(merchantState.tabs.count, 5)
        XCTAssertEqual(merchantState.tabs.map(\.primaryTitle), ["工作台", "营销", "模板", "合作", "我的"])
        XCTAssertEqual(merchantState.activeContainerRoute, .merchantMarketing)
        XCTAssertEqual(RootTabBarParity.containerRoute(for: .publish, mode: .merchant), .merchantTemplates)
        XCTAssertEqual(RootTabBarParity.containerRoute(for: .club, mode: .merchant), .merchantCooperation)
        XCTAssertEqual(RootTabBarParity.containerRoute(for: .mine, mode: .merchant), .mine)

        XCTAssertEqual(RootTabBarParity.resolvedMode(accountRole: "merchant", prefersMerchantContainer: false), .consumer)
        XCTAssertEqual(RootTabBarParity.resolvedMode(accountRole: "player", prefersMerchantContainer: true), .consumer)
        XCTAssertEqual(RootTabBarParity.resolvedMode(accountRole: " Merchant ", prefersMerchantContainer: true), .merchant)
    }

    // MARK: - PublishTabFloatingSheetParity

    func testPublishTabFloatingSheetCapabilityPresentation() {
        let signedOut = PublishTabFloatingSheetParity.presentation(capability: nil)
        XCTAssertNil(signedOut.quotaBadgeText)
        XCTAssertEqual(signedOut.actions.count, 3)
        XCTAssertTrue(signedOut.actions.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(signedOut.actions.first?.disabledReason, "请先登录并获取发布权限")

        let clubCap = PublishingCapability([
            "role": .string("club"),
            "quota": .object(["themesRemaining": .number(3)]),
            "permission": .object(["canSimplePublish": .bool(true), "canProPublish": .bool(true)])
        ])
        let clubSheet = PublishTabFloatingSheetParity.presentation(capability: clubCap)
        XCTAssertEqual(clubSheet.quotaBadgeText, "剩余可发布 3 个主题")
        XCTAssertEqual(clubSheet.actions.map(\.isEnabled), [true, true, true])

        let exhaustedPlayerCap = PublishingCapability([
            "role": .string("player"),
            "quota": .object(["themesRemaining": .number(0)]),
            "permission": .object(["canSimplePublish": .bool(true), "canProPublish": .bool(false)])
        ])
        let exhaustedSheet = PublishTabFloatingSheetParity.presentation(capability: exhaustedPlayerCap)
        XCTAssertEqual(exhaustedSheet.quotaBadgeText, "今日发布额度已用完")
        XCTAssertEqual(exhaustedSheet.actions.map(\.isEnabled), [false, false, false])
        XCTAssertEqual(exhaustedSheet.actions[0].disabledReason, "主题发布额度已用完")
        XCTAssertEqual(exhaustedSheet.actions[2].disabledReason, "仅认证俱乐部主理人可发布单场活动")
    }

    func testCountdownScheduleDatesContinuesPast256EntriesUntilStart() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 26 hours ahead => 2 hourly boundaries (>24h) + 1440 minute boundaries (<=24h) + start (> 1440 ticks, well above 256).
        let start = now.addingTimeInterval(26 * 3_600 + 30)
        let ticks = HomeIndexParityPresentation.countdownScheduleDates(from: now, start: start)
        XCTAssertGreaterThan(ticks.count, 1_400)
        XCTAssertEqual(ticks.first, now)
        XCTAssertEqual(ticks.last, start)
        // Penultimate tick is exactly 1 minute before start:
        XCTAssertEqual(ticks[ticks.count - 2], start.addingTimeInterval(-60))
        XCTAssertEqual(HomeIndexParityPresentation.upcomingCountdownText(start: start, now: ticks[ticks.count - 2]), "距上线 1分钟")
        XCTAssertNil(HomeIndexParityPresentation.upcomingCountdownText(start: start, now: ticks[ticks.count - 1]))

        // Arbitrary far-future start (e.g., 365 days ahead) stays bounded by maxScheduleHorizon (default 7 days = <= 1_586 ticks):
        let farFuture = now.addingTimeInterval(365 * 86_400)
        let boundedTicks = HomeIndexParityPresentation.countdownScheduleDates(from: now, start: farFuture)
        XCTAssertLessThanOrEqual(boundedTicks.count, 1_600)
        XCTAssertEqual(boundedTicks.first, now)
        XCTAssertEqual(boundedTicks.last, now.addingTimeInterval(7 * 86_400))

        // Counter-examples for extreme/non-finite maxScheduleHorizon inputs (.infinity, .nan, negative, 0, 365 days):
        // All must be clamped to maxAllowedScheduleHorizon (7 days) without unbounded allocation:
        let invalidHorizons: [TimeInterval] = [.infinity, -.infinity, .nan, -100, 0, 365 * 86_400]
        for invalidHorizon in invalidHorizons {
            let clampedTicks = HomeIndexParityPresentation.countdownScheduleDates(
                from: now,
                start: farFuture,
                maxScheduleHorizon: invalidHorizon
            )
            XCTAssertLessThanOrEqual(clampedTicks.count, 1_600)
            XCTAssertEqual(clampedTicks.first, now)
            XCTAssertEqual(clampedTicks.last, now.addingTimeInterval(HomeIndexParityPresentation.maxAllowedScheduleHorizon))
        }
        // Small positive finite value < 60 is clamped to minimum 60s:
        let minClampedTicks = HomeIndexParityPresentation.countdownScheduleDates(
            from: now,
            start: farFuture,
            maxScheduleHorizon: 10
        )
        XCTAssertEqual(minClampedTicks, [now, now.addingTimeInterval(60)])
    }

    @MainActor
    func testHomeContinuationCoordinatorScopeBindingGenerationIsolationAndPreTapVerification() async throws {
        let coordinator = HomeContinuationCoordinator()
        let scopeA = HomeContinuationOwnerScope(accountID: 701, sessionRevision: 1, journeyScope: UUID())
        var liveOwner: HomeContinuationOwnerScope? = scopeA

        // 1. Default PlayerJourneyService readsEnabled == false (isJourneyReadConfigured == false):
        // Remote participation reads are never called, readAvailability reports .journeyReadNotApproved,
        // and local durable paused runs still recover across restarts.
        var remoteCallCount = 0
        let durableCards = await coordinator.reload(
            ownerScope: scopeA,
            isAuthenticated: true,
            isJourneyReadConfigured: false,
            currentOwnerScope: { liveOwner },
            loadParticipations: {
                remoteCallCount += 1
                return []
            },
            loadPausedRuns: { _ in
                [PlayContinueRun(scope: .activity(12), elapsedSeconds: 360, title: "外滩迷雾")]
            }
        )
        XCTAssertEqual(remoteCallCount, 0)
        XCTAssertEqual(coordinator.readAvailability, .journeyReadNotApproved)
        XCTAssertEqual(durableCards.count, 1)
        XCTAssertEqual(durableCards.first?.playScope, .activity(12))
        XCTAssertEqual(durableCards.first?.subtitle, "已进行 6 分钟")

        // 2. Monotonic generation isolation: an older reload's completion or cancellation cannot overwrite a newer reload.
        var releaseStaleReload: CheckedContinuation<[ParticipationRecord], Error>?
        let staleTask = Task { @MainActor in
            await coordinator.reload(
                ownerScope: scopeA,
                isAuthenticated: true,
                isJourneyReadConfigured: true,
                currentOwnerScope: { liveOwner },
                loadParticipations: {
                    try await withCheckedThrowingContinuation { cont in
                        releaseStaleReload = cont
                    }
                },
                loadPausedRuns: { _ in
                    [PlayContinueRun(scope: .activity(99), elapsedSeconds: 60, title: "旧数据")]
                }
            )
        }
        await Task.yield()

        let joinedRecord = try JSONDecoder().decode(
            ParticipationRecord.self,
            from: Data(#"{"id":88,"ownerType":1,"activityTitle":"愚园路漫步","cmsTopic":{"id":91,"address":"静安寺"}}"#.utf8)
        )
        let freshCards = await coordinator.reload(
            ownerScope: scopeA,
            isAuthenticated: true,
            isJourneyReadConfigured: true,
            currentOwnerScope: { liveOwner },
            loadParticipations: { [joinedRecord] },
            loadPausedRuns: { _ in
                [PlayContinueRun(scope: .activity(12), elapsedSeconds: 480, title: "外滩迷雾")]
            }
        )
        XCTAssertEqual(coordinator.readAvailability, .available)
        XCTAssertEqual(freshCards.map(\.playScope), [.activity(12), .topic(91)])
        XCTAssertEqual(freshCards.first?.subtitle, "已进行 8 分钟")

        // Let the older reload complete now; it must be ignored because its generation was superseded:
        releaseStaleReload?.resume(returning: [])
        _ = await staleTask.value
        XCTAssertEqual(coordinator.cards.map(\.playScope), [.activity(12), .topic(91)])
        XCTAssertEqual(coordinator.cards.first?.subtitle, "已进行 8 分钟")

        // 3. Pre-tap re-verification succeeds when pause & runtime are valid, then rejects when pause is cleared on return:
        let card12 = try XCTUnwrap(coordinator.cards.first)
        let decision1 = await coordinator.verifyNavigation(
            for: card12,
            currentOwnerScope: { liveOwner },
            canEnterRuntime: { $0 == .activity(12) },
            hasDurableOrLivePause: { $0 == .activity(12) }
        )
        XCTAssertEqual(decision1, .enterRuntime(.activity(12)))

        // 4. Counter-example: verifyNavigation in-flight while a new reload occurs must reject the old navigation lease
        // even if scopeGeneration would otherwise have collided with g+1:
        var releasePauseCheck: CheckedContinuation<Bool, Never>?
        let racingVerifyTask = Task { @MainActor in
            await coordinator.verifyNavigation(
                for: card12,
                currentOwnerScope: { liveOwner },
                canEnterRuntime: { $0 == .activity(12) },
                hasDurableOrLivePause: { _ in
                    await withCheckedContinuation { cont in
                        releasePauseCheck = cont
                    }
                }
            )
        }
        await Task.yield()
        _ = await coordinator.reload(
            ownerScope: scopeA,
            isAuthenticated: true,
            isJourneyReadConfigured: true,
            currentOwnerScope: { liveOwner },
            loadParticipations: { [joinedRecord] },
            loadPausedRuns: { _ in
                [PlayContinueRun(scope: .activity(12), elapsedSeconds: 540, title: "外滩迷雾")]
            }
        )
        releasePauseCheck?.resume(returning: true)
        let racingDecision = await racingVerifyTask.value
        XCTAssertEqual(racingDecision, .staleRejected)

        // 5. Counter-example: duplicate taps on the same card invalidate the earlier tap's navigation lease:
        var releaseFirstTap: CheckedContinuation<Bool, Never>?
        let refreshedCard12 = try XCTUnwrap(coordinator.cards.first)
        let firstTapTask = Task { @MainActor in
            await coordinator.verifyNavigation(
                for: refreshedCard12,
                currentOwnerScope: { liveOwner },
                canEnterRuntime: { $0 == .activity(12) },
                hasDurableOrLivePause: { _ in
                    await withCheckedContinuation { cont in
                        releaseFirstTap = cont
                    }
                }
            )
        }
        await Task.yield()
        let secondTapDecision = await coordinator.verifyNavigation(
            for: refreshedCard12,
            currentOwnerScope: { liveOwner },
            canEnterRuntime: { $0 == .activity(12) },
            hasDurableOrLivePause: { _ in true }
        )
        XCTAssertEqual(secondTapDecision, .enterRuntime(.activity(12)))
        releaseFirstTap?.resume(returning: true)
        let firstTapDecision = await firstTapTask.value
        XCTAssertEqual(firstTapDecision, .staleRejected)

        // If the paused run was ended/cleared before tap, pre-tap re-verification rejects and removes the stale card:
        let decision2 = await coordinator.verifyNavigation(
            for: refreshedCard12,
            currentOwnerScope: { liveOwner },
            canEnterRuntime: { $0 == .activity(12) },
            hasDurableOrLivePause: { _ in false }
        )
        XCTAssertEqual(decision2, .staleRejected)
        XCTAssertEqual(coordinator.cards.map(\.playScope), [.topic(91)])

        // 6. Account / revision switch invalidates continuation state on pre-tap verification:
        let card91 = try XCTUnwrap(coordinator.cards.first)
        liveOwner = HomeContinuationOwnerScope(accountID: 702, sessionRevision: 2, journeyScope: UUID())
        let decision3 = await coordinator.verifyNavigation(
            for: card91,
            currentOwnerScope: { liveOwner },
            canEnterRuntime: { _ in true },
            hasDurableOrLivePause: { _ in true }
        )
        XCTAssertEqual(decision3, .staleRejected)
        XCTAssertTrue(coordinator.cards.isEmpty)
        XCTAssertNil(coordinator.ownerScope)
    }
}
