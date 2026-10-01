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
                                .accessibilityIdentifier("homeFeed.loadMore")
                        }
                    } header: { Text("homeFeed.explore") }
                }
                .searchable(text: $keyword, prompt: Text("homeFeed.search"))
                .onSubmit(of: .search) { submittedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
                .onChange(of: keyword) { _, value in if value.isEmpty { submittedKeyword = "" } }
                .onChange(of: query) { _, value in Task { await model.resetPage(reader: reader, query: value) } }
                .refreshable { await model.reload(reader: reader, query: query) }
            }
        }
        .navigationTitle("homeFeed.title")
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
                            VStack(alignment: .leading) { DiscoveryArtwork(source: banner.picUrl); Text("homeFeed.openFeatured") }
                        }.buttonStyle(.plain)
                    } else { DiscoveryArtwork(source: banner.picUrl) }
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
            .buttonStyle(.plain).accessibilityIdentifier("homeFeed.\(section).\(item.accessibilityKey)")
    }
    private func retry(_ message: LocalizedStringKey, id: String, action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(message)
            Button("homeFeed.retry") { Task { await action() } }.accessibilityIdentifier("homeFeed.retry.\(id)")
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
    var sourceTimeZone: TimeZone?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if item.name.isEmpty { Text("homeFeed.untitled").font(.headline) }
                    else { Text(verbatim: item.name).font(.headline) }
                    if let description = item.introduction, !description.isEmpty { Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                    if item.isBeta { Text("homeFeed.beta").font(.caption.bold()) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if item.isLive(at: context.date, sourceTimeZone: sourceTimeZone) { Text("homeFeed.live").font(.caption.bold()).foregroundStyle(.red) }
                    }
                }
                Spacer(minLength: 8)
                DiscoveryArtwork(source: item.imageURL).frame(width: 96, height: 100).clipped().accessibilityHidden(true)
            }
            LabeledContent { VStack(alignment: .trailing) {
                if let amount = item.amount, amount >= 0 { Text(amount, format: .number.precision(.fractionLength(2))); Text("homeFeed.currencyUnknown").font(.caption) }
                else { Text("homeFeed.unknown") }
            }} label: { Text("homeFeed.priceFrom") }
            LabeledContent { Text(verbatim: item.startDate.flatMap { $0.isEmpty ? nil : $0 } ?? "—") } label: { Text("homeFeed.date") }
            LabeledContent { Text(verbatim: item.place ?? "—") } label: { Text("homeFeed.place") }
        }.padding(.vertical, 8)
    }
}
