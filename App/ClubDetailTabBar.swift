import SwiftUI

/// Mini-program `cy-tabs.club-view-tabs`: 帖子 / 活动 / 概览 (+ 管理 when allowed).
struct ClubDetailTabBar: View {
    let tabs: [ClubDetailTab]
    let selection: ClubDetailTab
    let select: (ClubDetailTab) -> Void
    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    Button { select(tab) } label: {
                        Text(tab.titleKey)
                            .font(.subheadline.weight(tab == selection ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(tab == selection ? .accentColor : .secondary)
                    .accessibilityAddTraits(tab == selection ? .isSelected : [])
                    .accessibilityIdentifier("club.detail.tab." + tab.rawValue)
                }
            }
        }
    }
}

extension ClubDetailTab {
    var titleKey: LocalizedStringKey {
        switch self {
        case .posts: return "club.detail.tab.posts"
        case .events: return "club.detail.tab.events"
        case .overview: return "club.detail.tab.overview"
        case .manage: return "club.detail.tab.manage"
        }
    }
}
