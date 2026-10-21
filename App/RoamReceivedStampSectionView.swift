import SwiftUI

/// Renders the I11 `"集章册"` / `"收到的章"` stamp section backed by `RoamReceivedStampReader`
/// and `RoamAlbumPager`, preserving honest sign-in-required and not-configured states when the
/// underlying reader is unconfigured.
@MainActor struct RoamReceivedStampSectionView: View {
    @State private var model: RoamReceivedStampPresentation

    init(model: RoamReceivedStampPresentation) {
        _model = State(initialValue: model)
    }

    init(
        receivedReader: (any RoamExperienceReading)? = nil,
        collectedReader: (any RoamExperienceReading)? = nil,
        initialTab: RoamReceivedStampTab = .received
    ) {
        _model = State(
            initialValue: RoamReceivedStampPresentation(
                receivedReader: receivedReader,
                collectedReader: collectedReader,
                initialTab: initialTab
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker(
                    selection: Binding(
                        get: { model.selectedTab },
                        set: { tab in
                            model.selectTab(tab)
                            Task { await model.loadNextIfNeeded() }
                        }
                    )
                ) {
                    ForEach(model.tabs) { tab in
                        Text(verbatim: tab.title)
                            .tag(tab)
                            .accessibilityIdentifier(tab.accessibilityID)
                    }
                } label: {
                    Text(verbatim: model.selectedTab.title)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("roam.receivedStamp.tabPicker")

                if let activeReader = model.activeReader {
                    RoamExperienceNotice(offline: activeReader.isOfflineExample)
                }

                switch model.activeAvailability {
                case .signInRequired:
                    VStack(alignment: .leading, spacing: 8) {
                        RoamExperienceIssue(error: APIError.unauthorized)
                        if let subtitle = model.activeAvailability.statusSubtitle {
                            Text(verbatim: subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("roam.receivedStamp.signInRequired")

                case .notConfigured:
                    VStack(alignment: .leading, spacing: 8) {
                        RoamExperienceIssue(error: APIError.notConfigured)
                        if let subtitle = model.activeAvailability.statusSubtitle {
                            Text(verbatim: subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("roam.receivedStamp.notConfigured")

                case .ready:
                    readyContent
                }
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: model.selectedTab.title))
        .task(id: model.selectedTab) {
            await model.loadNextIfNeeded()
        }
        .refreshable {
            await model.refresh()
        }
        .onDisappear {
            model.cancelPending()
        }
        .accessibilityIdentifier("roam.receivedStamp.section")
    }

    @ViewBuilder private var readyContent: some View {
        if let total = model.totalCount {
            Text(verbatim: "\(model.selectedTab.title) · 共 \(total) 枚")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("roam.receivedStamp.total")
        }

        if let error = model.error {
            RoamExperienceIssue(error: error) {
                Task { await model.loadNextIfNeeded() }
            }
        }

        if model.isEmptyStateVisible {
            ContentUnavailableView {
                Label {
                    Text(verbatim: model.selectedTab.emptyTitle)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
            } description: {
                Text(verbatim: model.selectedTab.emptySubtitle)
            }
            .accessibilityIdentifier("roam.receivedStamp.empty")
        }

        let offline = model.activeReader?.isOfflineExample ?? false
        ForEach(model.visibleStamps) { stamp in
            NavigationLink {
                RoamStampDetailView(stamp: stamp, offline: offline)
            } label: {
                RoamStampCard(stamp: stamp, offline: offline)
            }
            .buttonStyle(QuestifyCardButtonStyle())
            .accessibilityIdentifier("roam.receivedStamp.row")
        }

        if model.isLoading {
            ProgressView("roam.loading")
                .accessibilityIdentifier("roam.receivedStamp.loading")
        }

        if model.hasMore && !model.isLoading && !model.visibleStamps.isEmpty {
            Button("roam.experience.loadMore") {
                Task { await model.loadNextIfNeeded() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("roam.receivedStamp.loadMore")
        }
    }
}
