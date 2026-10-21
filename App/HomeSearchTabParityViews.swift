import SwiftUI

/// Hero greeting, city badge, and 3 fixed action banners (`成为俱乐部`, `成为商家`, `和朋友报名活动`) for Home (`pages/index/index`).
@MainActor
struct HomeHeroHeaderSectionView: View {
    var nickname: String? = nil
    var selectedCity: String? = nil
    var isNationwide: Bool = false
    var onSelectBanner: ((HomeIndexParityPresentation.ActionBanner) -> Void)? = nil

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: HomeIndexParityPresentation.greetingText(nickname: nickname))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("homeIndex.hero.greeting")
                    Spacer()
                    Label {
                        Text(verbatim: HomeIndexParityPresentation.citySelectorLabel(selectedCity: selectedCity, isNationwide: isNationwide))
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeIndex.hero.city")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HomeIndexParityPresentation.fixedActionBanners) { banner in
                            Button {
                                onSelectBanner?(banner)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(verbatim: banner.title)
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("homeIndex.actionBanner.\(banner.id)")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Home continuation banner (`继续游戏` / `继续探索`) backed by `HomeIndexParityPresentation.ContinuationCard`.
@MainActor
struct PlayContinuationBannerView: View {
    let cards: [HomeIndexParityPresentation.ContinuationCard]
    var onOpen: ((HomeFeedDestination) -> Void)? = nil

    var body: some View {
        Section {
            ForEach(cards) { card in
                Button {
                    onOpen?(card.destination)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: card.kind.badgeTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(QuestifyPalette.accent)
                            Text(verbatim: card.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let subtitle = card.subtitle {
                                Text(verbatim: subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(QuestifyPalette.accent)
                    }
                    .questifyCardSurface()
                }
                .buttonStyle(QuestifyCardButtonStyle())
                .accessibilityIdentifier("homeIndex.continuation.\(card.id)")
                .questifyCardListRow()
            }
        } header: {
            Text(verbatim: "继续游戏 / 继续探索")
        }
    }
}

/// Shelf header view for Home (`pages/index`) sections (`精选路线`, `近期活动`, `热门主题`, `现成玩法`).
@MainActor
struct HomeIndexShelfHeaderView: View {
    let shelf: HomeIndexParityPresentation.ShelfKind
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: shelf.title)
                .font(.headline)
                .accessibilityIdentifier("homeIndex.shelfHeader.\(shelf.rawValue)")
            Spacer()
            if let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(verbatim: shelf.actionHint)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeIndex.shelfAction.\(shelf.rawValue)")
            }
        }
    }
}

/// Horizontal result tabs bar with count badges for Global Search (`pages/search2`).
@MainActor
struct GlobalSearchResultTabsBar: View {
    let tabs: [GlobalSearchParityPresentation.ResultTabDescriptor]
    @Binding var selectedKind: GlobalSearchParityPresentation.ResultTabKind

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    let isSelected = tab.kind == selectedKind
                    Button {
                        selectedKind = tab.kind
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: tab.title)
                            if let badge = tab.badgeText {
                                Text(verbatim: badge)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .accentColor : .secondary)
                    .accessibilityIdentifier("globalSearch.tab.\(tab.kind.rawValue)")
                }
            }
        }
    }
}

/// Empty, loading, or error state view for Home (`pages/index`).
@MainActor
struct HomeIndexEmptyStateView: View {
    enum Phase: Equatable {
        case loading
        case empty
        case error
    }

    let phase: Phase
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            switch phase {
            case .loading:
                ProgressView()
                Text(verbatim: HomeIndexParityPresentation.loadingCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeIndex.state.loading")
            case .empty:
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.emptyStateTitle)
                    .font(.headline)
                Text(verbatim: HomeIndexParityPresentation.emptyStateHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.empty")
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.errorCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.error")
                if let onRetry {
                    Button(action: onRetry) {
                        Text(verbatim: HomeIndexParityPresentation.retryButtonTitle)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("homeIndex.state.retry")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
