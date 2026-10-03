import SwiftUI

/// Embed in the caller's NavigationStack. The caller owns existing detail destinations.
@MainActor struct HomeFeedView: View {
    let reader: any HomeFeedReading
    /// Supply only from verified backend configuration, never language/device locale.
    var sourceTimeZone: TimeZone? = nil
    let onDestination: (HomeFeedDestination) -> Void
    @StateObject private var model = HomeFeedModel()
    @State private var kind: HomeFeedKind = .topics
    @State private var keyword = ""
    @State private var categoryID: Int?
    @State private var submittedKeyword = ""
    private var query: HomeFeedQuery { HomeFeedQuery(kind: kind, keyword: submittedKeyword, categoryID: categoryID) }
    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("homeFeed.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else {
                List {
                    if reader.isOfflineExample { Text("homeFeed.example").font(.caption) }
                    if model.loading { ProgressView("homeFeed.loading") }
                    bannerSection
                    feedSection(.recommended)
                    feedSection(.nearby)
                    feedSection(.upcoming)
                    Section {
                        Picker("homeFeed.content", selection: $kind) {
                            Text("homeFeed.topics").tag(HomeFeedKind.topics)
                            Text("homeFeed.activities").tag(HomeFeedKind.activities)
                        }.pickerStyle(.segmented).accessibilityIdentifier("homeFeed.kind")
                        Picker("homeFeed.category", selection: $categoryID) {
                            Text("homeFeed.allCategories").tag(Int?.none)
                            ForEach(model.categories) { category in Text(verbatim: category.name).tag(Optional(category.id)) }
                        }.accessibilityIdentifier("homeFeed.category")
                        if model.categoryFailed { retry("homeFeed.categoriesError", id: "categories") { await model.loadCategories(reader: reader) } }
                        ForEach(model.pagination.items) { item in row(item, section: "stream") }
                        if model.pageFailed { retry("homeFeed.loadError", id: "page") { await model.loadMore(reader: reader) } }
                        if model.loadingPage { ProgressView("homeFeed.loading") }
                        else if !model.pageFailed && model.pagination.items.isEmpty {
                            ContentUnavailableView("homeFeed.empty", systemImage: "magnifyingglass", description: Text("homeFeed.emptyHint"))
                                .accessibilityIdentifier("homeFeed.empty")
                        }
                        if model.pagination.hasMore && !model.loadingPage && !model.pageFailed {
                            Button("homeFeed.loadMore") { Task { await model.loadMore(reader: reader) } }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("homeFeed.loadMore")
                        }
                    } header: { Text("homeFeed.explore") }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(20)
                .searchable(text: $keyword, prompt: Text("homeFeed.search"))
                .onSubmit(of: .search) { submittedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
                .onChange(of: keyword) { _, value in if value.isEmpty { submittedKeyword = "" } }
                .onChange(of: query) { _, value in Task { await model.resetPage(reader: reader, query: value) } }
                .refreshable { await model.reload(reader: reader, query: query) }
            }
        }
        .appNavigationTitle("homeFeed.title")
        .task(id: reader.scope) { model.invalidate(); if reader.isConfigured { await model.reload(reader: reader, query: query) } }
        .onDisappear { model.invalidate() }
    }
    @ViewBuilder private var bannerSection: some View {
        if model.bannerFailed { retry("homeFeed.bannersError", id: "banners") { await model.loadBanners(reader: reader) } }
        if !model.banners.isEmpty {
            Section {
                ForEach(Array(model.banners.enumerated()), id: \.offset) { _, banner in
                    if let destination = banner.destination {
                        Button {
                            switch destination { case .activity(let id): onDestination(.activity(id)); case .topic(let id): onDestination(.topic(id)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                if let url = QuestifyCardArtwork.safeURL(banner.picUrl) { QuestifyCardArtwork(url: url) }
                                Label("homeFeed.openFeatured", systemImage: "arrow.up.right")
                                    .font(.headline).foregroundStyle(.primary)
                            }.questifyCardSurface()
                        }
                        .buttonStyle(QuestifyCardButtonStyle())
                        .questifyCardListRow()
                    } else if let url = QuestifyCardArtwork.safeURL(banner.picUrl) {
                        QuestifyCardArtwork(url: url).questifyCardSurface().questifyCardListRow()
                    }
                }
            } header: { Text("homeFeed.featured") }
        }
    }
    @ViewBuilder private func feedSection(_ section: HomeFeedSection) -> some View {
        Section {
            if section == .nearby { Text("homeFeed.noLocation").font(.caption).foregroundStyle(.secondary) }
            if model.failedSections.contains(section) {
                retry("homeFeed.loadError", id: section.rawValue) { await model.loadSection(section, reader: reader) }
            } else if let items = model.sections[section] {
                if items.isEmpty { Text("homeFeed.sectionEmpty").foregroundStyle(.secondary) }
                ForEach(items) { item in row(item, section: section.rawValue) }
            }
        } header: {
            switch section {
            case .recommended: Text("homeFeed.recommended")
            case .nearby: Text("homeFeed.activityHighlights")
            case .upcoming: Text("homeFeed.upcoming")
            }
        }
    }
    private func row(_ item: HomeFeedItem, section: String) -> some View {
        Button { onDestination(item.id) } label: { HomeFeedCard(item: item, sourceTimeZone: sourceTimeZone) }
            .buttonStyle(QuestifyCardButtonStyle())
            .accessibilityIdentifier("homeFeed.\(section).\(item.accessibilityKey)")
            .questifyCardListRow()
    }
    private func retry(_ message: LocalizedStringKey, id: String, action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(message)
            Button("homeFeed.retry") { Task { await action() } }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("homeFeed.retry.\(id)")
        }
    }
}

extension HomeFeedItem {
    var accessibilityKey: String {
        switch id { case .activity(let id): return "activity.\(id)"; case .topic(let id): return "topic.\(id)" }
    }
}

struct HomeFeedCard: View {
    let item: HomeFeedItem
    private let liveStart: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    init(item: HomeFeedItem, sourceTimeZone: TimeZone? = nil) {
        self.item = item
        if case .activity = item { liveStart = HomeFeedDate.parse(item.startDate, sourceTimeZone: sourceTimeZone) }
        else { liveStart = nil }
    }
    private var typeTitle: LocalizedStringKey {
        switch item { case .activity: return "homeFeed.activities"; case .topic: return "homeFeed.topics" }
    }
    private var typeSymbol: String {
        switch item { case .activity: return "figure.walk"; case .topic: return "map" }
    }
    @ViewBuilder var body: some View {
        if case .topic = item { imageTopicCard }
        else { standardCard }
    }
    private var imageTopicCard:some View {
        QuestifyImageEntityCard(imageSource:item.imageURL,title:item.name,subtitle:item.introduction,fallbackSymbol:"map") {
            if case .topic(let topic) = item { TopicTotalStops(count: topic.locationCount, identifier: "homeFeed.totalStops.\(topic.id)") }
            if item.isBeta { Text("homeFeed.beta").font(.caption.weight(.semibold)) }
            QuestifyImageEntityMetadata(label:"homeFeed.date",value:item.startDate ?? "—",systemImage:"calendar")
            QuestifyImageEntityMetadata(label:"homeFeed.place",value:item.place ?? "—",systemImage:"mappin")
            VStack(alignment:.leading,spacing:3) {
                Text("homeFeed.priceFrom").font(.caption)
                if let amount=item.amount,amount>=0 { Text(amount,format:.number.precision(.fractionLength(2))).font(.headline) }
                else { Text("homeFeed.unknown") }
                Text("homeFeed.currencyUnknown").font(.caption)
            }
        }
    }
    private var standardCard:some View {
        VStack(alignment: .leading, spacing: 14) {
            if let url = QuestifyCardArtwork.safeURL(item.imageURL) {
                QuestifyCardArtwork(url: url, height: dynamicTypeSize.isAccessibilitySize ? 132 : 164)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(typeTitle, systemImage: typeSymbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(QuestifyPalette.accent)
                if item.name.isEmpty { Text("homeFeed.untitled").font(.title3.weight(.semibold)) }
                else { Text(verbatim: item.name).font(.title3.weight(.semibold)) }
                VStack(alignment: .leading, spacing: 7) {
                    QuestifyMetadataLine(label: "homeFeed.date", value: item.startDate.flatMap { $0.isEmpty ? nil : $0 } ?? "—", systemImage: "calendar")
                    QuestifyMetadataLine(label: "homeFeed.place", value: item.place ?? "—", systemImage: "mappin.and.ellipse")
                }
                if let description = item.introduction, !description.isEmpty {
                    Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                }
            }
            Divider()
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text("homeFeed.priceFrom").font(.caption).foregroundStyle(.secondary)
                    if let amount = item.amount, amount >= 0 {
                        Text(amount, format: .number.precision(.fractionLength(2)))
                            .font(.headline).monospacedDigit()
                        Text("homeFeed.currencyUnknown").font(.caption).foregroundStyle(.secondary)
                    } else { Text("homeFeed.unknown").font(.headline) }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 6) {
                    if item.isBeta { QuestifyStatusBadge(title: "homeFeed.beta", systemImage: "flask") }
                    if let liveStart { HomeFeedLiveBadge(start: liveStart) }
                }
            }
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .questifyCardSurface()
    }
}

/// One initial entry and, only if needed, the source start boundary. No per-card 1 Hz timer.
private struct HomeFeedStartSchedule: TimelineSchedule {
    let start: Date
    func entries(from date: Date, mode: Mode) -> [Date] {
        start > date ? [date, start] : [date]
    }
}

private struct HomeFeedLiveBadge: View {
    let start: Date
    var body: some View {
        TimelineView(HomeFeedStartSchedule(start: start)) { context in
            // Preserves the source's start <= now rule. No timezone or end-state is inferred.
            if start <= context.date { QuestifyStatusBadge(title: "homeFeed.live", systemImage: "clock") }
        }
    }
}
