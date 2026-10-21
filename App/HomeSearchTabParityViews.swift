import SwiftUI

/// Hero greeting, city badge, and 3 fixed action banners (`成为俱乐部`, `成为商家`, `和朋友报名活动`) for Home (`pages/index/index`).
@MainActor
struct HomeHeroHeaderSectionView: View {
    @Environment(\.locale) private var locale
    var nickname: String? = nil
    var selectedCity: String? = nil
    var isNationwide: Bool = false
    var onSelectBanner: ((HomeIndexParityPresentation.ActionBanner) -> Void)? = nil

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: HomeIndexParityPresentation.greetingText(nickname: nickname, locale: locale))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("homeIndex.hero.greeting")
                    Spacer()
                    Label {
                        Text(verbatim: HomeIndexParityPresentation.citySelectorLabel(selectedCity: selectedCity, isNationwide: isNationwide, locale: locale))
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
                                    Text(verbatim: banner.title(locale: locale))
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
    @Environment(\.locale) private var locale
    let cards: [HomeIndexParityPresentation.ContinuationCard]
    var onSelectCard: ((HomeIndexParityPresentation.ContinuationCard) -> Void)? = nil
    var onOpen: ((HomeFeedDestination) -> Void)? = nil

    var body: some View {
        Section {
            ForEach(cards) { card in
                Button {
                    if let onSelectCard {
                        onSelectCard(card)
                    } else {
                        onOpen?(card.destination)
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: card.kind.badgeTitle(locale: locale))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(QuestifyPalette.accent)
                            Text(verbatim: card.localizedTitle(locale: locale))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let subtitle = card.localizedSubtitle(locale: locale) {
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
            Text(verbatim: HomeIndexParityPresentation.continuationSectionTitle(locale: locale))
        }
    }
}

/// Shelf header view for Home (`pages/index`) sections (`精选路线`, `近期活动`, `热门主题`, `现成玩法`).
@MainActor
struct HomeIndexShelfHeaderView: View {
    @Environment(\.locale) private var locale
    let shelf: HomeIndexParityPresentation.ShelfKind
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: shelf.title(locale: locale))
                .font(.headline)
                .accessibilityIdentifier("homeIndex.shelfHeader.\(shelf.rawValue)")
            Spacer()
            if let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(verbatim: shelf.actionHint(locale: locale))
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

    @Environment(\.locale) private var locale
    let phase: Phase
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            switch phase {
            case .loading:
                ProgressView()
                Text(verbatim: HomeIndexParityPresentation.loadingCopy(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeIndex.state.loading")
            case .empty:
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.emptyStateTitle(locale: locale))
                    .font(.headline)
                Text(verbatim: HomeIndexParityPresentation.emptyStateHint(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.empty")
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(verbatim: HomeIndexParityPresentation.errorCopy(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .accessibilityIdentifier("homeIndex.state.error")
                if let onRetry {
                    Button(action: onRetry) {
                        Text(verbatim: HomeIndexParityPresentation.retryButtonTitle(locale: locale))
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

/// Role-aware consumer (`玩家视角`) ↔ merchant (`商家工作台`) root container switch banner (`components/tabBar`).
@MainActor
struct MerchantRootModeSwitchBannerView: View {
    let state: RootTabBarParity.TabBarState
    var canSwitchToMerchant: Bool = false
    var onSelectMode: ((RootTabBarParity.RoleMode) -> Void)? = nil
    var onSelectTab: ((RootTab) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onSelectMode?(.consumer)
                } label: {
                    Text(verbatim: RootTabBarParity.consumerModeTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .consumer ? QuestifyPalette.accent : .secondary)
                .accessibilityIdentifier("rootTabBar.mode.consumer")

                if canSwitchToMerchant || state.mode == .merchant {
                    Button {
                        onSelectMode?(.merchant)
                    } label: {
                        Text(verbatim: RootTabBarParity.merchantModeTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(state.mode == .merchant ? QuestifyPalette.accent : .secondary)
                    .accessibilityIdentifier("rootTabBar.mode.merchant")
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(state.tabs) { descriptor in
                    let isSelected = descriptor.rootTab == state.selectedTab
                    Button {
                        onSelectTab?(descriptor.rootTab)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: descriptor.systemImage)
                                .font(.subheadline)
                            Text(verbatim: descriptor.primaryTitle)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? QuestifyPalette.accent : .secondary)
                    .accessibilityIdentifier("rootTabBar.tab.\(state.mode.rawValue).\(descriptor.index)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("rootTabBar.containerSwitch")
    }
}

/// Floating publish button (`+ 发布`) for the Publish/Template tab (`pages/template`).
@MainActor
struct PublishTabFloatingButton: View {
    var title: String = PublishTabFloatingSheetParity.fabButtonTitle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(QuestifyPalette.accent, in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("publishTab.floatingButton")
    }
}

/// Floating publish capability sheet (`pages/template` + `/api/publish/home`).
@MainActor
struct PublishTabFloatingSheetView: View {
    let presentation: PublishTabFloatingSheetParity.SheetPresentation
    var onSelectAction: ((PublishTabFloatingSheetParity.ActionKind) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                if let quotaBadgeText = presentation.quotaBadgeText {
                    Section {
                        Label {
                            Text(verbatim: quotaBadgeText)
                                .font(.subheadline.weight(.medium))
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(QuestifyPalette.accent)
                        }
                        .accessibilityIdentifier("publishTab.sheet.quotaBadge")
                    }
                }

                Section {
                    ForEach(presentation.actions) { item in
                        Button {
                            guard item.isEnabled else { return }
                            onSelectAction?(item.kind)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(item.isEnabled ? QuestifyPalette.accent : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: item.title)
                                        .font(.headline)
                                        .foregroundStyle(item.isEnabled ? .primary : .secondary)
                                    Text(verbatim: item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let reason = item.disabledReason, !item.isEnabled {
                                        Text(verbatim: reason)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .accessibilityIdentifier("publishTab.sheet.disabledReason.\(item.id)")
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!item.isEnabled)
                        .accessibilityIdentifier("publishTab.sheet.action.\(item.id)")
                    }
                }
            }
            .navigationTitle(Text(verbatim: presentation.sheetTitle))
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onClose)
                            .accessibilityIdentifier("publishTab.sheet.close")
                    }
                }
            }
        }
    }
}
