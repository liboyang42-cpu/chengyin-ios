import SwiftUI

/// Embed in the caller's NavigationStack. The caller owns existing detail destinations.
@MainActor struct HomeFeedView: View {
    let reader: any HomeFeedReading
    var unavailableMessageKey: String? = nil
    /// Supply only from verified backend configuration, never language/device locale.
    var sourceTimeZone: TimeZone? = nil
    var viewerNickname: String? = nil
    var viewerAvatar: String? = nil
    var selectedCity: String? = nil
    var showsHeroBanners: Bool = false
    var continuationCards: [HomeIndexParityPresentation.ContinuationCard] = []
    var continuationReadAvailability: HomeContinuationReadAvailability = .available
    var onActionBanner: ((HomeIndexParityPresentation.ActionBanner) -> Void)? = nil
    var onContinuation: ((HomeIndexParityPresentation.ContinuationCard) -> Void)? = nil
    var onRetryContinuation: (() -> Void)? = nil
    let onDestination: (HomeFeedDestination) -> Void
    @Environment(\.locale) private var locale
    @StateObject private var model = HomeFeedModel()
    @State private var kind: HomeFeedKind = .topics
    @State private var keyword = ""
    @State private var categoryID: Int?
    @State private var submittedKeyword = ""
    private var query: HomeFeedQuery { HomeFeedQuery(kind: kind, keyword: submittedKeyword, categoryID: categoryID) }
    var body: some View {
        let binding = model.bind(reader, available: unavailableMessageKey == nil)
        let permit = model.permit(reader)
        ZStack {
            if !reader.isConfigured || unavailableMessageKey != nil {
                ContentUnavailableView("homeFeed.unavailable", systemImage: "network.slash", description: Text(LocalizedStringKey(unavailableMessageKey ?? "auth.notConfigured")))
                    .accessibilityIdentifier("homeFeed.configurationUnavailable")
            } else if !model.matches(reader) {
                ProgressView("homeFeed.loading")
            } else {
                List {
                    if model.loading { ProgressView("homeFeed.loading") }
                    if showsHeroBanners || viewerNickname != nil || selectedCity != nil || onActionBanner != nil {
                        HomeHeroHeaderSectionView(nickname: viewerNickname, selectedCity: selectedCity, avatarSource: viewerAvatar) { banner in
                            if banner.id == "activity_list" { kind = .activities }
                            onActionBanner?(banner)
                        }
                    }
                    bannerSection
                    feedSection(.recommended)
                    if !continuationCards.isEmpty || (continuationReadAvailability != .available && continuationReadAvailability != .unauthenticated) {
                        PlayContinuationBannerView(
                            cards: continuationCards,
                            readAvailability: continuationReadAvailability,
                            onSelectCard: { card in
                                guard model.canOpen(reader) else { return }
                                if let onContinuation {
                                    onContinuation(card)
                                } else {
                                    onDestination(card.destination)
                                }
                            },
                            onOpen: { destination in
                                if model.canOpen(reader) { onDestination(destination) }
                            },
                            onRetry: onRetryContinuation
                        )
                    }
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
                        if model.categoryFailed { retry("homeFeed.categoriesError", id: "categories") { model.schedule(.categories, reader: reader, permit: permit) } }
                        ForEach(model.pagination.items) { item in row(item, section: "stream") }
                        if model.pageFailed { retry("homeFeed.loadError", id: "page") { model.schedule(.page, reader: reader, permit: permit) } }
                        if model.loadingPage { ProgressView("homeFeed.loading") }
                        else if !model.pageFailed && model.pagination.items.isEmpty {
                            ContentUnavailableView("homeFeed.empty", systemImage: "magnifyingglass", description: Text("homeFeed.emptyHint"))
                                .accessibilityIdentifier("homeFeed.empty")
                        }
                        if model.pagination.hasMore && !model.loadingPage && !model.pageFailed {
                            Button("homeFeed.loadMore") { model.schedule(.page, reader: reader, permit: permit) }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("homeFeed.loadMore")
                        } else if !model.pagination.hasMore && !model.loadingPage && !model.pageFailed && !model.pagination.items.isEmpty {
                            Text(verbatim: HomeIndexParityPresentation.noMoreFooterCopy(locale: locale))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityIdentifier("homeFeed.noMoreFooter")
                        }
                    } header: { Text("homeFeed.explore") }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(20)
                .searchable(text: $keyword, prompt: Text("homeFeed.search"))
                .onSubmit(of: .search) { submittedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
                .onChange(of: keyword) { _, value in if value.isEmpty { submittedKeyword = "" } }
                .onChange(of: query) { _, value in model.schedule(.query(value), reader: reader, permit: permit) }
                .refreshable { await model.reload(reader: reader, query: query) }
            }
        }
        .appNavigationTitle("homeFeed.title")
        .task(id: binding) { await model.resume(reader: reader, query: query, available: unavailableMessageKey == nil, expectedBinding: binding) }
        .onDisappear { model.suspend() }
    }
    @ViewBuilder private var bannerSection: some View {
        let permit = model.permit(reader)
        if model.bannerFailed { retry("homeFeed.bannersError", id: "banners") { model.schedule(.banners, reader: reader, permit: permit) } }
        if !model.banners.isEmpty {
            // Mirrors the mini-program hero swiper: full-width covers, paged, no captions.
            Section {
                TabView {
                    ForEach(Array(model.banners.enumerated()), id: \.offset) { _, banner in
                        if let destination = banner.destination {
                            Button {
                                guard model.canOpen(reader) else { return }
                                switch destination { case .activity(let id): onDestination(.activity(id)); case .topic(let id): onDestination(.topic(id)) }
                            } label: {
                                bannerArtwork(banner)
                            }
                            .buttonStyle(QuestifyCardButtonStyle())
                            .accessibilityLabel(Text("homeFeed.openFeatured"))
                        } else {
                            bannerArtwork(banner)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: model.banners.count > 1 ? .always : .never))
                .frame(height: 196)
                .questifyCardListRow()
            } header: { Text("homeFeed.featured") }
        }
    }
    private func bannerArtwork(_ banner: DiscoveryBanner) -> some View {
        Group {
            if let url = QuestifyCardArtwork.safeURL(banner.picUrl) {
                QuestifyCardArtwork(url: url, height: 196)
            } else {
                // A clean placeholder with no text when the banner has no usable cover.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 196)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, model.banners.count > 1 ? 24 : 0)
    }
    @ViewBuilder private func feedSection(_ section: HomeFeedSection) -> some View {
        let permit = model.permit(reader)
        Section {
            if model.failedSections.contains(section) {
                retry("homeFeed.loadError", id: section.rawValue) { model.schedule(.section(section), reader: reader, permit: permit) }
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
        Button { if model.canOpen(reader) { onDestination(item.id) } } label: { HomeFeedCard(item: item, sourceTimeZone: sourceTimeZone) }
            .buttonStyle(QuestifyCardButtonStyle())
            .accessibilityIdentifier("homeFeed.\(section).\(item.accessibilityKey)")
            .questifyCardListRow()
    }
    private func retry(_ message: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(message)
            Button("homeFeed.retry", action: action)
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
    private let sourceTimeZone: TimeZone?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    init(item: HomeFeedItem, sourceTimeZone: TimeZone? = nil) {
        self.item = item
        self.sourceTimeZone = sourceTimeZone
    }
    private var typeSymbol: String {
        switch item { case .activity: return "figure.walk"; case .topic: return "map" }
    }
    /// Mini-program `v2-fcard` + `v2-status`: cover and title, one date · place line, then the starting price.
    var body: some View {
        QuestifyImageEntityCard(imageSource: safeImageSource, title: item.name, fallbackSymbol: typeSymbol,
                                minimumHeight: dynamicTypeSize.isAccessibilitySize ? 300 : 260) {
            if let meta = metaLine {
                Text(verbatim: meta).foregroundStyle(.white.opacity(0.8))
            }
            if let price = priceText {
                Text("playx.finishRoute.priceFrom \(price)").font(.headline).monospacedDigit()
            }
        }
    }
    /// Only a safe https cover reaches the card; anything else shows the clean placeholder.
    private var safeImageSource: String? {
        if let url = QuestifyCardArtwork.safeURL(item.imageURL) { return url.absoluteString }
        return nil
    }
    private var metaLine: String? {
        let place = item.place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [startDateText, place].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    /// Like the mini-program, a time without a zone reads as written; an explicit offset shows in local time.
    private var startDateText: String? {
        let utc = TimeZone(secondsFromGMT: 0)!
        let displayZone: TimeZone
        let date: Date
        if let absolute = HomeFeedDate.parse(item.startDate, sourceTimeZone: sourceTimeZone) {
            date = absolute; displayZone = timeZone
        } else if let wallClock = HomeFeedDate.parse(item.startDate, sourceTimeZone: utc) {
            date = wallClock; displayZone = utc
        } else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = displayZone
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().locale(locale)
        if calendar.component(.year, from: date) != calendar.component(.year, from: Date()) {
            style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale)
        }
        style.timeZone = displayZone
        return date.formatted(style)
    }
    /// Unknown or negative amounts hide the price instead of printing a placeholder.
    private var priceText: String? {
        guard let amount = item.amount, amount >= 0 else { return nil }
        return amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}
