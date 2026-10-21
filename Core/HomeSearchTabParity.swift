import Foundation

// MARK: - Home Index Parity (`pages/index/index`)

/// Presentation rules for the mini-program Home screen (`pages/index/index`).
public enum HomeIndexParityPresentation {
    /// Shelf identifiers matching the mini-program home page sections.
    public enum ShelfKind: String, CaseIterable, Hashable, Sendable {
        case featuredRoutes
        case upcomingActivities
        case popularTopics
        case readyMadeTemplates

        /// Mini-program section header title.
        public var title: String {
            switch self {
            case .featuredRoutes: return "精选路线"
            case .upcomingActivities: return "近期活动"
            case .popularTopics: return "热门主题"
            case .readyMadeTemplates: return "现成玩法"
            }
        }

        /// Optional subtitle or action hint shown alongside the shelf header.
        public var actionHint: String {
            switch self {
            case .featuredRoutes: return "查看全部"
            case .upcomingActivities: return "更多活动"
            case .popularTopics: return "全部主题"
            case .readyMadeTemplates: return "去挑选"
            }
        }
    }

    /// Fixed action banners shown in the mini-program hero carousel.
    public struct ActionBanner: Equatable, Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let routePath: String

        public init(id: String, title: String, routePath: String) {
            self.id = id
            self.title = title
            self.routePath = routePath
        }
    }

    public static let defaultCityFallback = "选择城市"
    public static let nationwideCityLabel = "全国"
    public static let defaultTravelerNickname = "旅人"

    public static let emptyStateTitle = "暂无内容"
    public static let emptyStateHint = "切换城市或稍后再来看看"
    public static let loadingCopy = "加载中..."
    public static let errorCopy = "加载失败，请点击重试"
    public static let retryButtonTitle = "重试"
    public static let noMoreFooterCopy = "· 没有更多了 ·"

    public static let fixedActionBanners: [ActionBanner] = [
        ActionBanner(id: "club_apply", title: "成为俱乐部", routePath: "pages/club/apply"),
        ActionBanner(id: "merchant_apply", title: "成为商家", routePath: "pages/merchant/apply"),
        ActionBanner(id: "activity_list", title: "和朋友报名活动", routePath: "pages/activity/list")
    ]

    /// Resolves the city selector label: returns trimmed city name, `"全国"` when nationwide is selected,
    /// or `"选择城市"` when no city is resolved.
    public static func citySelectorLabel(selectedCity: String?, isNationwide: Bool = false) -> String {
        if isNationwide {
            return nationwideCityLabel
        }
        let trimmed = selectedCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultCityFallback : trimmed
    }

    /// Formats the mini-program hero greeting (`"Hi, {昵称‖旅人}!"`).
    public static func greetingText(nickname: String?) -> String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? defaultTravelerNickname : trimmed
        return "Hi, \(resolved)!"
    }

    /// Returns all shelf headers in display order.
    public static var shelfHeaders: [String] {
        ShelfKind.allCases.map(\.title)
    }
}

// MARK: - Global Search Parity (`pages/search2`)

/// Presentation rules for the mini-program global search page (`pages/search2`).
public enum GlobalSearchParityPresentation {
    public static let maxHistoryCount = 10
    public static let placeholderCopy = "搜索主题、活动、俱乐部、商家"
    public static let emptyQueryHint = "输入关键词搜索路线、活动、商家或俱乐部"
    public static let noResultsTitle = "未找到相关内容"
    public static let noResultsHint = "换个关键词或调整筛选条件试试"

    /// Result tab kinds matching `pages/search2` tabs.
    public enum ResultTabKind: String, CaseIterable, Hashable, Sendable {
        case all
        case routes
        case activities
        case merchants
        case clubs
        case moments

        public var title: String {
            switch self {
            case .all: return "全部"
            case .routes: return "路线"
            case .activities: return "活动"
            case .merchants: return "商家"
            case .clubs: return "俱乐部"
            case .moments: return "动态"
            }
        }
    }

    /// Descriptor for a single search result tab with its count badge.
    public struct ResultTabDescriptor: Equatable, Hashable, Sendable, Identifiable {
        public let kind: ResultTabKind
        public let title: String
        public let count: Int

        public var id: String { kind.rawValue }

        public init(kind: ResultTabKind, count: Int) {
            self.kind = kind
            self.title = kind.title
            self.count = max(0, count)
        }

        /// Formatted badge text (nil when 0 for cleaner display, or string value when > 0).
        public var badgeText: String? {
            count > 0 ? "\(count)" : nil
        }

        /// Combined display label e.g. `"路线 3"` or `"路线"`.
        public var displayLabel: String {
            if let badge = badgeText {
                return "\(title) \(badge)"
            }
            return title
        }
    }

    /// Trims leading and trailing whitespace and newlines from a raw search input.
    public static func trimmedKeyword(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deduplicates search history preserving most-recent-first order, trimming whitespace,
    /// discarding empty entries, and capping at `maxHistoryCount` (10).
    public static func recordHistory(keyword: String, into existing: [String]) -> [String] {
        let cleaned = trimmedKeyword(keyword)
        var combined = existing
        if !cleaned.isEmpty {
            combined.insert(cleaned, at: 0)
        }
        return deduplicateHistory(combined)
    }

    /// Normalizes an array of history strings into at most 10 unique non-empty trimmed keywords.
    public static func deduplicateHistory(_ entries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let cleaned = trimmedKeyword(entry)
            guard !cleaned.isEmpty else { continue }
            if seen.insert(cleaned).inserted {
                result.append(cleaned)
                if result.count >= maxHistoryCount {
                    break
                }
            }
        }
        return result
    }

    /// Builds the 6 result tab descriptors (`全部`, `路线`, `活动`, `商家`, `俱乐部`, `动态`) with count badges.
    public static func resultTabs(
        routesCount: Int = 0,
        activitiesCount: Int = 0,
        merchantsCount: Int = 0,
        clubsCount: Int = 0,
        momentsCount: Int = 0
    ) -> [ResultTabDescriptor] {
        let r = max(0, routesCount)
        let a = max(0, activitiesCount)
        let m = max(0, merchantsCount)
        let c = max(0, clubsCount)
        let d = max(0, momentsCount)
        let total = r + a + m + c + d
        return [
            ResultTabDescriptor(kind: .all, count: total),
            ResultTabDescriptor(kind: .routes, count: r),
            ResultTabDescriptor(kind: .activities, count: a),
            ResultTabDescriptor(kind: .merchants, count: m),
            ResultTabDescriptor(kind: .clubs, count: c),
            ResultTabDescriptor(kind: .moments, count: d)
        ]
    }

    /// Builds result tab descriptors from an existing `GlobalSearchResults` value.
    public static func resultTabs(from results: GlobalSearchResults, momentsCount: Int = 0) -> [ResultTabDescriptor] {
        resultTabs(
            routesCount: results.count(.topic),
            activitiesCount: results.count(.activity),
            merchantsCount: results.count(.merchant),
            clubsCount: results.count(.club),
            momentsCount: momentsCount
        )
    }
}

// MARK: - Root Tab Bar Parity (`components/tabBar`)

/// Role-aware 5-tab bar specification matching mini-program `components/tabBar`.
public enum RootTabBarParity {
    public enum RoleMode: String, CaseIterable, Hashable, Sendable {
        case consumer
        case merchant
    }

    public struct TabDescriptor: Equatable, Hashable, Sendable, Identifiable {
        public let index: Int
        public let rootTab: RootTab
        public let primaryTitle: String
        public let alternateTitle: String?
        public let titleKey: String
        public let systemImage: String

        public var id: Int { index }

        public init(
            index: Int,
            rootTab: RootTab,
            primaryTitle: String,
            alternateTitle: String? = nil,
            titleKey: String,
            systemImage: String
        ) {
            self.index = index
            self.rootTab = rootTab
            self.primaryTitle = primaryTitle
            self.alternateTitle = alternateTitle
            self.titleKey = titleKey
            self.systemImage = systemImage
        }

        /// Returns whether a candidate label matches either the primary or alternate title.
        public func matchesLabel(_ label: String) -> Bool {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == primaryTitle || (alternateTitle != nil && trimmed == alternateTitle)
        }
    }

    public struct TabBarState: Equatable, Hashable, Sendable {
        public let mode: RoleMode
        public let selectedTab: RootTab
        public let isAuthenticated: Bool
        public let tabs: [TabDescriptor]

        public init(mode: RoleMode = .consumer, selectedTab: RootTab = .home, isAuthenticated: Bool = false) {
            self.mode = mode
            self.selectedTab = selectedTab
            self.isAuthenticated = isAuthenticated
            self.tabs = RootTabBarParity.tabs(for: mode)
        }

        public func requiresAuthenticationPrompt(for tab: RootTab) -> Bool {
            false
        }
    }

    /// Standard 5 consumer tabs: `发现`/`首页`, `漫游`, `模板`/`玩法`, `俱乐部`, `我的`.
    public static let consumerTabs: [TabDescriptor] = [
        TabDescriptor(
            index: 0,
            rootTab: .home,
            primaryTitle: "首页",
            alternateTitle: "发现",
            titleKey: RootTab.home.titleKey,
            systemImage: RootTab.home.systemImage
        ),
        TabDescriptor(
            index: 1,
            rootTab: .roam,
            primaryTitle: "漫游",
            alternateTitle: nil,
            titleKey: RootTab.roam.titleKey,
            systemImage: RootTab.roam.systemImage
        ),
        TabDescriptor(
            index: 2,
            rootTab: .publish,
            primaryTitle: "模板",
            alternateTitle: "玩法",
            titleKey: RootTab.publish.titleKey,
            systemImage: RootTab.publish.systemImage
        ),
        TabDescriptor(
            index: 3,
            rootTab: .club,
            primaryTitle: "俱乐部",
            alternateTitle: nil,
            titleKey: RootTab.club.titleKey,
            systemImage: RootTab.club.systemImage
        ),
        TabDescriptor(
            index: 4,
            rootTab: .mine,
            primaryTitle: "我的",
            alternateTitle: nil,
            titleKey: RootTab.mine.titleKey,
            systemImage: RootTab.mine.systemImage
        )
    ]

    /// Merchant role 5-tab bar specification (`工作台`, `营销`, `模板`, `合作`, `我的`).
    public static let merchantTabs: [TabDescriptor] = [
        TabDescriptor(
            index: 0,
            rootTab: .home,
            primaryTitle: "工作台",
            alternateTitle: "首页",
            titleKey: "tabBar.merchant.workbench",
            systemImage: "square.grid.2x2"
        ),
        TabDescriptor(
            index: 1,
            rootTab: .roam,
            primaryTitle: "营销",
            alternateTitle: nil,
            titleKey: "tabBar.merchant.marketing",
            systemImage: "megaphone"
        ),
        TabDescriptor(
            index: 2,
            rootTab: .publish,
            primaryTitle: "模板",
            alternateTitle: "玩法",
            titleKey: "tabBar.merchant.templates",
            systemImage: "plus.square"
        ),
        TabDescriptor(
            index: 3,
            rootTab: .club,
            primaryTitle: "合作",
            alternateTitle: nil,
            titleKey: "tabBar.merchant.cooperation",
            systemImage: "person.2"
        ),
        TabDescriptor(
            index: 4,
            rootTab: .mine,
            primaryTitle: "我的",
            alternateTitle: nil,
            titleKey: RootTab.mine.titleKey,
            systemImage: RootTab.mine.systemImage
        )
    ]

    public static func tabs(for mode: RoleMode) -> [TabDescriptor] {
        switch mode {
        case .consumer: return consumerTabs
        case .merchant: return merchantTabs
        }
    }
}
