import Foundation

/// Primary navigation, in the mini-program tab bar order (components/tabBar CONSUMER_LIST):
/// 首页 · 漫游 · 发布 · 俱乐部 · 我的. Activities are browsed inside Home (主题/活动), not as a tab.
public enum RootTab: Int, CaseIterable, Hashable, Sendable {
    case home, roam, publish, club, mine

    public var titleKey: String {
        switch self {
        case .home: return "tabBar.home"
        case .roam: return "tabBar.roam"
        case .publish: return "tabBar.publish"
        case .club: return "tabBar.club"
        case .mine: return "tabBar.mine"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house"
        case .roam: return "map"
        case .publish: return "plus.square"
        case .club: return "person.3"
        case .mine: return "person.crop.circle"
        }
    }
}
