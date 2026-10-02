import SwiftUI

@MainActor
struct TopicDetailView: View {
    let id: Int
    let reader: any TopicReading
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
    private struct Key: Hashable { let id: Int; let scope: UUID; let configured: Bool }
    private var key: Key { Key(id: id, scope: reader.scope, configured: reader.isConfigured) }
    var body: some View {
        Group {
            if !reader.isConfigured { TopicIssueView(issue: .notConfigured) }
            else if loading || loadedKey != key { ProgressView("topic.loading") }
            else if let issue { TopicIssueView(issue: issue) { Task { await load() } } }
            else if let detail { content(detail) }
        }
        .appNavigationTitle("topic.detail")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await load() }
        .onDisappear { generation += 1; loading = false }
        .sheet(isPresented: $showsReview) {
            NavigationStack { ContextualReviewComposer(target: .topic(id), owner: reviewOwner) { Task { await load() } } }
        }
        .onChange(of: key) { _, _ in showingSelfPlay = false }
        .sheet(isPresented: $showingSelfPlay) {
            if let detail {
                if let selfPlayDestination { selfPlayDestination(detail) }
                else { TopicSelfPlayUnavailableSheet(topic: detail) }
            }
        }
    }
    private func content(_ value: TopicDetail) -> some View {
        List {
            Section {
                if reader.isOfflineExample { Text("topic.offlineExample").font(.caption) }
                Text(verbatim: value.name).font(.title2.bold())
                if value.betaFlag == 1 { Text("topic.beta") }
                if let subtitle = value.subtitle { Text(verbatim: subtitle) }
                if let introduction = value.introduction { Text(verbatim: introduction).textSelection(.enabled) }
                if let audio = value.audioURL, !audio.isEmpty { PlatformAudioHost(rawURL: audio, scope: reader.scope, makeModel: makeAudio) }
                if let club = value.clubName { Text(verbatim: club) }
                if let initiator = value.initiatorName { LabeledContent("topic.initiator", value: initiator) }
                if !value.categoryNames.isEmpty { Text(verbatim: value.categoryNames.joined(separator: " · ")) }
                if let start = value.startDate { LabeledContent("topic.start", value: start) }
                if let end = value.endDate { LabeledContent("topic.end", value: end) }
                if let count = value.merchantCount { LabeledContent("topic.merchants", value: String(count)) }
                if let seconds = value.totalTimeSeconds { LabeledContent("topic.durationSeconds", value: String(seconds)) }
                if let rating = value.averageRating { LabeledContent("topic.rating", value: String(rating)) }
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
                }
            }
            Section("topic.chapters") {
                if value.chapters.isEmpty { Text("topic.noChapters") }
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
                            LabeledContent("topic.stops", value: String(chapter.nodes.count)).font(.caption)
                        }
                    }.accessibilityIdentifier("topic.chapter.\(chapter.id)")
                }
            }
            Section("topic.tickets") {
                if value.tickets.isEmpty { Text("topic.noTickets") }
                ForEach(Array(value.tickets.enumerated()), id: \.offset) { _, ticket in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: ticket.name).font(.headline)
                        TopicPrice(value: ticket.price, label: "topic.price")
                        if let start = ticket.startTime { LabeledContent("topic.start", value: start) }
                        if let end = ticket.endTime { LabeledContent("topic.end", value: end) }
                        if let meeting = ticket.meetingPoint { Text(verbatim: meeting) }
                        if let remaining = ticket.remaining { LabeledContent("topic.remaining", value: String(remaining)) }
                        if let refund = ticket.refundRule { Text(verbatim: refund).font(.footnote) }
                    }
                }
            }
            Section("topic.comments") {
                Button("context.review.title") { showsReview = true }.accessibilityIdentifier("topic.openReview")
                if value.comments.isEmpty { Text("topic.noComments") }
                ForEach(Array(value.comments.enumerated()), id: \.offset) { _, comment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: comment.memberNickname).font(.headline)
                        LabeledContent("topic.rating", value: String(comment.rating))
                        Text(verbatim: comment.contents).textSelection(.enabled)
                        Text(verbatim: comment.createTime).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable { await load() }
        .accessibilityIdentifier("topic.detail.content")
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
            guard operation == generation, captured == key else { return }
            detail = result; loadedKey = captured
        } catch is CancellationError { }
        catch {
            guard operation == generation, captured == key else { return }
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
    var body: some View {
        Group {
            if scope != reader.scope { TopicIssueView(issue: .unavailable) }
            else {
                List {
                    Section {
                        Text(verbatim: chapter.title).font(.title2)
                        if let description = chapter.description { Text(verbatim: description).textSelection(.enabled) }
                    }
                    ForEach(Array(chapter.nodes.enumerated()), id: \.offset) { _, node in
                        Section {
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
