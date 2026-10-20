import SwiftUI

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
