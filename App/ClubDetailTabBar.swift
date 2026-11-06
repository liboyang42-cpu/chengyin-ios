import SwiftUI

/// Mini-program `cy-tabs.club-view-tabs`: 帖子 / 活动 / 概览 (+ 管理 when allowed), as a native segmented picker.
struct ClubDetailTabBar: View {
    let tabs: [ClubDetailTab]
    let selection: ClubDetailTab
    let select: (ClubDetailTab) -> Void
    var body: some View {
        Section {
            Picker("club.detail", selection: Binding(get: { selection }, set: { select($0) })) {
                ForEach(tabs) { tab in
                    Text(tab.titleKey)
                        .accessibilityIdentifier("club.detail.tab." + tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
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

struct ClubDetailOverviewFactsGridView: View {
    let grid: ClubDetailOverviewFactsGrid
    var body: some View {
        HStack(spacing: 12) {
            ForEach(grid.items) { item in
                VStack(spacing: 4) {
                    Text(verbatim: item.label).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: item.value).font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("club.detail.fact.\(item.id)")
            }
        }
        .accessibilityIdentifier("club.detail.factsGrid")
    }
}
