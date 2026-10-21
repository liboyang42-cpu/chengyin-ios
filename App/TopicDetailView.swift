import SwiftUI

@MainActor
struct TopicDetailView: View {
    let id: Int
    let reader: any TopicReading
    var activityDestination: ((Int) -> AnyView)? = nil
    var publicMerchant: PublicMerchantHomeContext? = nil
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var publisherDestination: ((TopicDetail) -> AnyView)? = nil
    var reviewOwner: ContextualReviewCoordinator? = nil
    @State private var showsReview = false
    var selfPlayDestination: ((TopicDetail) -> AnyView)? = nil
    @State private var showingSelfPlay = false
    @State private var detail: TopicDetail?
    @State private var loadedKey: Key?
    @State private var issue: TopicScreenIssue?
    @State private var loading = false
    @State private var generation = 0
    @State private var loads = SignedInContentDetailLoadOwner()
    @Environment(\.topicPricingDestination) private var pricingDestination
    @State private var showsPricing = false
    @State private var showingSessionSelection = false
    private struct Key: Hashable { let id: Int; let scope: UUID; let configured: Bool }
    private var key: Key { Key(id: id, scope: reader.scope, configured: reader.isConfigured) }
    var body: some View {
        Group {
            if !reader.isConfigured { TopicIssueView(issue: .notConfigured) }
            else if loading || loadedKey != key { ProgressView("topic.loading") }
            else if let issue { TopicIssueView(issue: issue) { loads.start { await load() } } }
            else if let detail { content(detail) }
        }
        .appNavigationTitle("topic.detail")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await loads.run { await load() } }
        .onDisappear { loads.cancel(); generation += 1; loading = false }
        .sheet(isPresented: $showsReview) {
            NavigationStack { ContextualReviewComposer(target: .topic(id), owner: reviewOwner) { loads.start { await load() } } }
        }
        .onChange(of: key) { _, _ in showingSelfPlay = false; showingSessionSelection = false }
        .sheet(isPresented: $showingSelfPlay) {
            if let detail {
                if let selfPlayDestination { selfPlayDestination(detail) }
                else { TopicSelfPlayUnavailableSheet(topic: detail) }
            }
        }
    }
    private func content(_ value: TopicDetail) -> some View {
        ScrollViewReader { proxy in
        List {
            Section {
                if reader.isOfflineExample { Text("topic.offlineExample").font(.caption) }
                TopicXcxHero(topic: value)
                let covers = value.images.isEmpty ? (value.imageURL.map { [$0] } ?? []) : Array(value.images.prefix(9))
                if covers.isEmpty { Text("topicXcx.coverHint").font(.caption).foregroundStyle(.secondary) }
                else { NativeMediaGalleryEntry(sources: covers, scope: key.scope, titleKey: "media.destination.squareImages", compact: true) }
                Text(verbatim: value.name).font(.title2.bold())
                TopicXcxStatBar(cells: TopicXcxFacts.statBar(value))
                TopicXcxTabs(proxy: proxy)
                TopicTotalStops(count: value.locationCount, identifier: "topic.totalStops")
                if value.betaFlag == 1 {
                    // Source topic-beta block: badge plus feedback note.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("topic.source.betaBadge").font(.subheadline.bold())
                        Text("topic.source.betaNote").font(.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                }
                if let subtitle = value.subtitle { Text(verbatim: subtitle) }
                if let introduction = value.introduction { Text(verbatim: introduction).textSelection(.enabled) }
                if let audio = value.audioURL, !audio.isEmpty { PlatformAudioHost(rawURL: audio, scope: reader.scope, makeModel: makeAudio) }
                if let club = value.clubName { Text(verbatim: club) }
                if !value.categoryNames.isEmpty { Text(verbatim: value.categoryNames.joined(separator: " · ")) }
                if let start = value.startDate { LabeledContent("topic.start", value: start) }
                if let end = value.endDate { LabeledContent("topic.end", value: end) }
                if let count = value.merchantCount { LabeledContent("topic.merchants", value: String(count)) }
                if let seconds = value.totalTimeSeconds { LabeledContent("topic.durationSeconds") { TopicXcxDurationText(seconds: seconds) } }
            }.id(TopicXcxTab.details.anchor)
            if let records = reader as? any TopicThemeRecordsReading {
                // Source 我的游玩记录 row; always shown, the sheet handles empty/sign-in states.
                Section {
                    NavigationLink { TopicThemeRecordsView(topicID: value.id, topicName: value.name, reader: records) } label: {
                        Label("topicXcx.records.title", systemImage: "clock")
                    }.accessibilityIdentifier("topic.records.entry")
                }
            }
            if let venue = TopicXcxFacts.venue(value.addressName) {
                Section("topicXcx.section.venue") {
                    Label { VStack(alignment: .leading) { Text(verbatim: venue.name); if let address = venue.address { Text(verbatim: address).font(.caption) } } } icon: { Image(systemName: "mappin.circle") }
                }
            }
            let includes = TopicXcxFacts.includes(value)
            if !includes.isEmpty { Section("topicXcx.section.contents") { TopicXcxIncludes(rows: includes) } }
            if value.templateCount != 0 { TopicXcxTemplatesSection(templates: TopicXcxFacts.nodeTemplates(value)) }
            let lineup = TopicXcxFacts.lineup(value)
            if !lineup.isEmpty { Section("topicXcx.section.lineup") { TopicXcxLineup(members: lineup) } }
            if let activities = value.activities {
                Section("topic.activities") {
                    if activities.isEmpty { Text("topic.noActivities").accessibilityIdentifier("topic.activities.empty") }
                    ForEach(activities) { activity in
                        if let activityDestination {
                            NavigationLink { activityDestination(activity.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    TopicXcxSessionChip(startDate: activity.startDate)
                                    Text(verbatim: activity.name).font(.headline)
                                    if let address = activity.addressName { Text(verbatim: address) }
                                    if let start = activity.startDate { LabeledContent("topic.start", value: start) }
                                    if let end = activity.endDate { LabeledContent("topic.end", value: end) }
                                }
                            }.accessibilityIdentifier("topic.activity.\(activity.id)")
                        } else { Text(verbatim: activity.name) }
                    }
                }
            }
            if let publisherDestination { publisherDestination(value) }
            Section("topic.availability") {
                Text(LocalizedStringKey("topic.availability." + String(value.availability.rawValue)))
                if value.merchantClosed { Label("topic.closedNotice", systemImage: "storefront") }
                if value.selfPlay == 1 {
                    TopicPrice(value: value.selfPlayPrice, label: "topic.selfPlayPrice")
                    Button("contextSelfPlay.title") { showingSelfPlay = true }
                        .disabled(!value.canOfferPurchase).accessibilityIdentifier("contextSelfPlay.open")
                }
                Text("topic.readOnly").font(.footnote).foregroundStyle(.secondary)
            }
            if value.showStoryPaywall {
                Section("topic.lockedStory") {
                    Label("topic.lockedNotice", systemImage: "lock")
                    LabeledContent("topic.lockedChapters", value: String(value.lockedChapterCount)).accessibilityIdentifier("topic.lockedChapters")
                    Text("topicXcx.paywall.detail").font(.footnote)
                    if value.selfPlay == 1 {
                        Button("topicXcx.paywall.unlock") { showingSelfPlay = true }.disabled(!value.canOfferPurchase).accessibilityIdentifier("topic.paywall.unlock")
                    }
                    Text("topicXcx.paywall.recover").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("topic.chapters") {
                if value.chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("topic.noChapters")
                        Text("topicXcx.nodes.emptyDetail").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                // Index identity preserves source order even when backend IDs are absent/duplicated.
                ForEach(Array(value.chapters.enumerated()), id: \.offset) { _, chapter in
                    NavigationLink {
                        TopicChapterView(chapter: chapter, reader: reader, scope: key.scope, publicMerchant: publicMerchant, makeExternalMaps: makeExternalMaps)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: chapter.title)
                            if let minutes = chapter.totalTimeMinutes {
                                LabeledContent("topic.durationMinutes", value: String(minutes)).font(.caption)
                            }
                            LabeledContent("topic.visibleChapterStops", value: String(chapter.nodes.count)).font(.caption)
                        }
                    }.accessibilityIdentifier("topic.chapter.\(chapter.id)")
                }
            }.id(TopicXcxTab.nodes.anchor)
            TopicXcxRouteSection(topic: value).id(TopicXcxTab.route.anchor)
            Section("topic.source.sessions") {
                if value.tickets.isEmpty { Text("topic.noTickets") }
                ForEach(Array(value.tickets.enumerated()), id: \.offset) { _, ticket in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: ticket.name).font(.headline)
                        TopicPrice(value: ticket.price, label: "topic.price")
                        if let session = TopicXcxFacts.sessionTime(start: ticket.startTime, end: ticket.endTime) { Text(verbatim: session) }
                        else {
                            if let start = ticket.startTime { LabeledContent("topic.start", value: start) }
                            if let end = ticket.endTime { LabeledContent("topic.end", value: end) }
                        }
                        if let meeting = ticket.meetingPoint { Text("topic.source.meetingPoint \(meeting)") }
                        if let refund = ticket.refundRule { Text("topic.source.refundRule \(refund)").font(.footnote) }
                        if let remaining = ticket.remaining { Text("topic.source.seatsLeft \(remaining)") }
                        else { Text("topic.source.seatsUnknown").foregroundStyle(.secondary) }
                    }
                }
                if !value.tickets.isEmpty { Text("topic.source.sessionNote").font(.caption).foregroundStyle(.secondary) }
            }.id("topicXcx.anchor.sessions")
            Section("topic.comments") {
                if (value.commentCount ?? value.comments.count) == 0 {
                    // Source ratings empty state.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("topicXcx.reviews.emptyTitle").font(.headline)
                        Text("topicXcx.reviews.emptyDetail").font(.footnote).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("topic.reviews.emptyPrompt")
                }
                Button("context.review.title") { showsReview = true }.accessibilityIdentifier("topic.openReview")
                TopicReviewsContent(reviews: value.reviews)
            }
        }
        .refreshable { await loads.run { await load() } }
        .safeAreaInset(edge: .bottom) {
            TopicXcxActionBar(topic: value, openSessions: { if !showingSessionSelection { showingSessionSelection = true } },
                              openSelfPlay: { showingSelfPlay = true },
                              openPricing: pricingDestination == nil ? nil : { showsPricing = true })
        }
        .sheet(isPresented: $showingSessionSelection, onDismiss: { loads.start { await load() } }) {
            TopicSessionSelectionView(detail: value, scope: key.scope, activityDestination: activityDestination)
        }
        .sheet(isPresented: $showsPricing) { if let pricingDestination { NavigationStack { pricingDestination(value.id) } } }
        .accessibilityIdentifier("topic.detail.content")
        }
    }
    private func load() async {
        generation += 1
        let operation = generation, captured = key
        detail = nil; issue = nil; loadedKey = nil
        guard reader.isConfigured else { loading = false; return }
        loading = true
        defer { if operation == generation { loading = false } }
        do {
            let result = try await reader.topicDetail(id: id)
            try Task.checkCancellation()
            guard operation == generation, captured == key, !Task.isCancelled else { return }
            detail = result; loadedKey = captured
        } catch is CancellationError { }
        catch {
            guard operation == generation, captured == key, !Task.isCancelled else { return }
            issue = TopicScreenIssue(error); loadedKey = captured
        }
    }
}

@MainActor
struct TopicChapterView: View {
    let chapter: TopicChapter
    let reader: any TopicReading
    let scope: UUID
    var publicMerchant: PublicMerchantHomeContext? = nil
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    private var itinerary: TopicChapterItinerary { TopicChapterItinerary(chapter: chapter) }
    var body: some View {
        Group {
            if scope != reader.scope { TopicIssueView(issue: .unavailable) }
            else {
                List {
                    Section {
                        Text(verbatim: chapter.title).font(.title2)
                        if let description = chapter.description { Text(verbatim: description).textSelection(.enabled) }
                        if itinerary.hasWalkingEstimates {
                            Text("topic.itinerary.estimateNotice").font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("topic.itinerary.notice")
                        }
                    }
                    ForEach(itinerary.stops) { stop in
                        let node = stop.node
                        Section {
                            if let minutes = stop.estimatedWalkingMinutes {
                                TopicWalkingEstimate(minutes: minutes, position: stop.id)
                            }
                            LabeledContent("topic.itinerary.stopNumber", value: String(stop.id + 1)).font(.caption)
                            Text(verbatim: node.name).font(.headline)
                            if let description = node.description { Text(verbatim: description).textSelection(.enabled) }
                            if let address = node.address { Text(verbatim: address) }
                            PlatformExternalMapHost(destination: .init(name: node.name, address: node.address, latitude: node.latitude, longitude: node.longitude), scope: scope, makeModel: makeExternalMaps)
                            if let hours = node.businessTime { Text(verbatim: hours) }
                            if let template = node.template {
                                Text(verbatim: template.title)
                                if let difficulty = template.difficulty { Text(verbatim: difficulty) }
                                if let players = template.players { Text(verbatim: players) }
                                if let duration = template.duration { LabeledContent("topic.durationMinutes", value: String(duration)) }
                            }
                            TopicXcxNodeFootView(node: node)
                            ForEach(Array(node.merchants.enumerated()), id: \.offset) { _, merchant in
                                if let owner = PublicMerchantOwnerID(merchant.memberID), let publicMerchant {
                                    NavigationLink { PublicMerchantHomeView(target: .ownerMemberID(owner), context: publicMerchant) } label: {
                                        Text(verbatim: merchant.name)
                                    }.accessibilityIdentifier("merchant.publicHome.topicEntry")
                                } else { Text(verbatim: merchant.name) }
                                if let hours = merchant.businessTime { Text(verbatim: hours).font(.caption) }
                            }
                        }
                    }
                    Section { Text("topic.readOnly").font(.footnote) }
                }
            }
        }.appNavigationTitle("topic.chapter").navigationBarTitleDisplayMode(.inline)
    }
}
