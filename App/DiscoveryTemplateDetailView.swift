import SwiftUI

@MainActor
struct DiscoveryTemplateDetailView: View {
    let id: Int
    let reader: any DiscoveryReading
    let authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)?
    let authoringRevision: UInt64
    let imageReader: any RetainedPublicImageReading
    @StateObject private var detail = DiscoveryLoader<DiscoveryPlayTemplate>()
    @State private var galleryScope = UUID()
    @State private var loadedKey: RequestKey?
    @State private var readerChange: UInt64 = 0
    private struct RequestKey: Equatable {
        let id: Int
        let reader: ObjectIdentifier
        let scope: String
        let authoringRevision: UInt64
    }
    private var requestKey: RequestKey {
        _ = readerChange // Read-only ObservableObject dependencies must invalidate this view too.
        return .init(id: id, reader: ObjectIdentifier(reader), scope: reader.discoveryPresentationIdentity,
                     authoringRevision: authoringRevision)
    }

    init(id: Int, reader: any DiscoveryReading, authoringFactory: ((DiscoveryPlayTemplate) -> TemplateAuthoringCoordinator)? = nil, authoringRevision: UInt64 = 0, imageReader: (any RetainedPublicImageReading)? = nil) {
        self.id = id; self.reader = reader; self.authoringFactory = authoringFactory; self.authoringRevision = authoringRevision
        self.imageReader = imageReader ?? RetainedPublicImageReader()
    }

    var body: some View {
        Group {
            if !reader.isConfigured {
                ContentUnavailableView("discovery.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if detail.isLoading || loadedKey != requestKey {
                ProgressView("discovery.loading")
            } else if let error = detail.error {
                DiscoveryErrorView(error: error) { Task { await reload() } }
            } else if let item = detail.value {
                List {
                    Section {
                        DiscoveryTitle(text: item.title, fallback: "discovery.untitledPlay").font(.title2.bold())
                        DiscoveryPlayMetadata(item: item)
                    }
                    DiscoveryPlayTemplatePresentationView(presentation: .init(item), scope: galleryScope, imageReader: imageReader)
                    textSection("discovery.introduction", text: item.description)
                    textSection("discovery.rules", text: item.ruleInstructions)
                    textSection("discovery.materials", text: item.requiredMaterials)
                    textSection("discovery.location", text: item.usageLocation)
                    if let verification = item.verification {
                        Section("discovery.verification") { Text(verification.label) }
                    }
                    if let authoringFactory {
                        Section {
                            NavigationLink {
                                TemplateAuthoringView(coordinator: authoringFactory(item), sessionRevision: authoringRevision, metadataReader: reader)
                            } label: { Label("templateAuthor.adopt", systemImage: "doc.on.doc") }
                                .accessibilityIdentifier("templateAuthor.adopt")
                        }
                    }
                    Section { Text("discovery.readOnlyHint").font(.footnote).foregroundStyle(.secondary) }
                }
                .refreshable { await reload() }
                .accessibilityIdentifier("discovery.detail.content")
            }
        }
        .appNavigationTitle("discovery.playDetails")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestKey) { if reader.isConfigured { await reload() } }
        .onReceive(reader.discoveryPresentationChanges) { readerChange &+= 1 }
    }
    @ViewBuilder private func textSection(_ title: LocalizedStringKey, text: String?) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section(title) { Text(text).textSelection(.enabled) }
        }
    }
    private func reload() async {
        let requested = requestKey
        galleryScope = UUID(); loadedKey = nil
        await detail.load {
            let value = try await reader.discoveryPlayTemplate(id: requested.id)
            guard !Task.isCancelled, requested.scope == reader.discoveryPresentationIdentity else { throw CancellationError() }
            guard value.id == requested.id else { throw APIError.malformedResponse }
            return value
        }
        guard !Task.isCancelled, requested == requestKey else { return }
        loadedKey = requested
    }
}

/// Uses only the server's public template projection. Included games are inert previews.
@MainActor
struct DiscoveryTopicTemplatePreview: View {
    @State private var detail: PublicTopicTemplateCoordinator
    init(coordinator: PublicTopicTemplateCoordinator) { _detail = State(initialValue: coordinator) }
    var body: some View {
        Group {
            if detail.isInvalidated {
                ContentUnavailableView("discovery.templateSessionChanged", systemImage: "person.crop.circle.badge.exclamationmark",
                                       description: Text("discovery.templateReopen"))
            } else if detail.isLoading {
                ProgressView("discovery.loading")
            } else if let error = detail.error {
                DiscoveryErrorView(error: error) { Task { await detail.load() } }
            } else if let item = detail.value {
                List {
                    Section {
                        if let image = item.imgUrl, !image.isEmpty { DiscoveryArtwork(source: image, height: 210) }
                        DiscoveryTitle(text: item.name ?? "", fallback: "discovery.untitledTopic").font(.title2.bold())
                        optionalText(item.subtitle)
                        TopicTotalStops(count: item.locationCount, identifier: "discovery.publicTotalStops")
                        if let count = item.templateCount { LabeledContent("discovery.publicGames", value: String(count)) }
                        if let seconds = item.totalTime { LabeledContent("discovery.publicSeconds", value: String(seconds)) }
                        optionalText(item.addressName)
                        optionalText(item.version)
                    }
                    if let text = item.description, !text.isEmpty { Section("discovery.introduction") { Text(text) } }
                    if let text = item.playerPromise, !text.isEmpty { Section("discovery.playerPromise") { Text(text) } }
                    ForEach(item.chapters) { chapter in
                        Section {
                            DiscoveryTitle(text: chapter.name ?? "", fallback: "discovery.publicChapter").font(.headline)
                            optionalText(chapter.description)
                            if let count = chapter.nodeCount { LabeledContent("discovery.publicStations", value: String(count)) }
                            if !chapter.routeShape.isEmpty {
                                PublicTemplateSilhouette(points: chapter.routeShape)
                                    .frame(height: 140)
                                    .accessibilityLabel(Text("discovery.publicSilhouette"))
                            }
                            // The public endpoint intentionally withholds node IDs.
                            ForEach(Array(chapter.nodes.enumerated()), id: \.offset) { _, node in
                                VStack(alignment: .leading, spacing: 6) {
                                    DiscoveryTitle(text: node.name ?? "", fallback: "discovery.publicStation").font(.subheadline.bold())
                                    optionalText(node.hookTeaser)
                                    optionalText(node.addressName)
                                    optionalText(node.interactionType)
                                }.accessibilityElement(children: .combine)
                            }
                            if let status = chapter.recruitStatus {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("discovery.publicRecruitment").font(.headline)
                                    optionalText(status.state)
                                    if let count = status.remainingMerchantCount {
                                        LabeledContent("discovery.publicRemaining", value: String(count))
                                    }
                                }.accessibilityIdentifier("discovery.publicRecruitment")
                            }
                        }
                    }
                    if !item.games.isEmpty {
                        Section("discovery.publicGames") {
                            ForEach(item.games) { game in
                                VStack(alignment: .leading, spacing: 6) {
                                    DiscoveryTitle(text: game.title ?? "", fallback: "discovery.untitledPlay").font(.headline)
                                    optionalText(game.players)
                                    optionalText(game.difficulty)
                                    optionalText(game.interactionType)
                                }
                            }
                        }
                    }
                    if item.chapters.isEmpty && item.games.isEmpty {
                        Section { Text("discovery.publicEmpty") }
                    }
                    Section { Text("discovery.publicProjectionHint").font(.footnote).foregroundStyle(.secondary) }
                }
                .refreshable { await detail.load() }
                .accessibilityIdentifier("discovery.topicPreview.content")
            } else { ProgressView("discovery.loading") }
        }
        .appNavigationTitle("discovery.topicPreview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await detail.load() }
        .onDisappear { detail.clear() }
    }
    @ViewBuilder private func optionalText(_ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(value).textSelection(.enabled) }
    }
}

private struct PublicTemplateSilhouette: View {
    let points: [PublicTemplateShapePoint]
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for (index, point) in points.enumerated() {
                    let position = CGPoint(x: 12 + point.x * max(0, geometry.size.width - 24),
                                           y: 12 + point.y * max(0, geometry.size.height - 24))
                    if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                }
            }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }.accessibilityElement(children: .ignore)
    }
}
