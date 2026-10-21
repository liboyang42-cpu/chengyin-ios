import SwiftUI

/// Read-only detail screen for a public `story_node` (`MapSourceType.storyNode`).
/// Verifies parent `TopicDetail` (`topicID`), unlocked `TopicChapter` (`chapterID`), and `TopicNode` (`nodeID`)
/// via `TopicReading.detail(id:)` without creating a play Run, auto-registering, or executing node tasks.
@MainActor
struct MapPublicStoryNodeDetailView: View {
    let destination: MapPublicStoryNodeDestination
    let reader: any TopicReading
    var topicDestination: ((Int) -> AnyView)? = nil

    @State private var detail: TopicDetail?
    @State private var loadedKey: LoadKey?
    @State private var issue: TopicScreenIssue?
    @State private var loading = false
    @State private var generation = 0
    @State private var loads = SignedInContentDetailLoadOwner()

    private struct LoadKey: Hashable {
        let nodeID: Int
        let topicID: Int
        let chapterID: Int
        let scope: UUID
        let configured: Bool
    }

    private var key: LoadKey {
        LoadKey(
            nodeID: destination.nodeID,
            topicID: destination.topicID,
            chapterID: destination.chapterID,
            scope: reader.scope,
            configured: reader.isConfigured
        )
    }

    private var resolvedChapterAndNode: (chapter: TopicChapter, node: TopicNode)? {
        guard let detail, detail.id == destination.topicID,
              let chapter = detail.chapters.first(where: { $0.id == destination.chapterID }),
              let node = chapter.nodes.first(where: { $0.id == destination.nodeID }) else {
            return nil
        }
        return (chapter, node)
    }

    var body: some View {
        Group {
            if !reader.isConfigured {
                TopicIssueView(issue: .notConfigured)
            } else if loading || loadedKey != key {
                ProgressView(String(localized: "mapPublicLayers.storyNode.loading", table: "MapPublicLayers"))
                    .accessibilityIdentifier("mapPublicLayers.storyNode.loading")
            } else if let issue {
                TopicIssueView(issue: issue) {
                    loads.start { await load() }
                }
            } else if let detail, let resolved = resolvedChapterAndNode {
                nodeContent(detail: detail, chapter: resolved.chapter, node: resolved.node)
            } else {
                ContentUnavailableView(
                    String(localized: "mapPublicLayers.storyNode.unavailable", table: "MapPublicLayers"),
                    systemImage: "lock.shield",
                    description: Text(String(localized: "mapPublicLayers.storyNode.unavailableDetail", table: "MapPublicLayers"))
                )
                .accessibilityIdentifier("mapPublicLayers.storyNode.unavailable")
            }
        }
        .appNavigationTitle("mapPublicLayers.storyNode.navigationTitle")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await loads.run { await load() } }
        .onDisappear {
            loads.cancel()
            generation += 1
            loading = false
        }
        .onChange(of: key) { _, _ in
            detail = nil
            issue = nil
        }
    }

    private func nodeContent(detail: TopicDetail, chapter: TopicChapter, node: TopicNode) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: node.name.isEmpty ? destination.nodeName : node.name)
                        .font(.title2.bold())
                        .accessibilityIdentifier("mapPublicLayers.storyNode.title")

                    HStack(spacing: 8) {
                        Label(
                            String(localized: "mapPublicLayers.source.story_node", table: "MapPublicLayers"),
                            systemImage: "book.pages"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(verbatim: "node #\(node.id) · topic #\(detail.id) · chapter #\(chapter.id)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mapPublicLayers.storyNode.domainIDs")
                    }

                    if let address = node.address ?? destination.address, !address.isEmpty {
                        Label {
                            Text(verbatim: address)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("mapPublicLayers.storyNode.address")
                    }

                    if let hours = node.businessTime, !hours.isEmpty {
                        LabeledContent(String(localized: "mapPublicLayers.storyNode.businessHours", table: "MapPublicLayers")) {
                            Text(verbatim: hours)
                        }
                        .font(.subheadline)
                    }
                }
            }

            Section(String(localized: "mapPublicLayers.storyNode.parentSection", table: "MapPublicLayers")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: detail.name)
                        .font(.headline)
                        .accessibilityIdentifier("mapPublicLayers.storyNode.parentThemeName")
                    Text(verbatim: chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mapPublicLayers.storyNode.parentChapterTitle")
                    if let chapterDesc = chapter.description, !chapterDesc.isEmpty {
                        Text(verbatim: chapterDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let topicDestination {
                    NavigationLink {
                        topicDestination(detail.id)
                    } label: {
                        Label(
                            String(localized: "mapPublicLayers.storyNode.openParentTheme", table: "MapPublicLayers"),
                            systemImage: "sparkles"
                        )
                    }
                    .accessibilityIdentifier("mapPublicLayers.storyNode.openParentTheme")
                }
            }

            if let narrative = node.description ?? destination.summary, !narrative.isEmpty {
                Section(String(localized: "mapPublicLayers.storyNode.narrativeSection", table: "MapPublicLayers")) {
                    Text(verbatim: narrative)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("mapPublicLayers.storyNode.narrative")
                }
            }

            if let template = node.template {
                Section(String(localized: "mapPublicLayers.storyNode.templateSection", table: "MapPublicLayers")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: template.title)
                            .font(.headline)
                        if let duration = template.duration {
                            LabeledContent(String(localized: "mapPublicLayers.storyNode.templateDuration", table: "MapPublicLayers")) {
                                Text(verbatim: "\(duration) min")
                            }
                        }
                        if let players = template.players, !players.isEmpty {
                            LabeledContent(String(localized: "mapPublicLayers.storyNode.templatePlayers", table: "MapPublicLayers")) {
                                Text(verbatim: players)
                            }
                        }
                        if let difficulty = template.difficulty, !difficulty.isEmpty {
                            LabeledContent(String(localized: "mapPublicLayers.storyNode.templateDifficulty", table: "MapPublicLayers")) {
                                Text(verbatim: difficulty)
                            }
                        }
                    }
                    .accessibilityIdentifier("mapPublicLayers.storyNode.template")
                }
            }

            if !node.merchants.isEmpty {
                Section(String(localized: "mapPublicLayers.storyNode.merchantsSection", table: "MapPublicLayers")) {
                    ForEach(Array(node.merchants.enumerated()), id: \.offset) { _, merchant in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: merchant.name).font(.subheadline.weight(.medium))
                            if let hours = merchant.businessTime, !hours.isEmpty {
                                Text(verbatim: hours).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Label(
                    String(localized: "mapPublicLayers.storyNode.readOnlyNotice", table: "MapPublicLayers"),
                    systemImage: "eye"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mapPublicLayers.storyNode.readOnlyNotice")
            }
        }
        .accessibilityIdentifier("mapPublicLayers.storyNode.detailList")
    }

    private func load() async {
        guard reader.isConfigured else { return }
        let requestedKey = key
        generation += 1
        let currentGen = generation
        loading = true
        issue = nil
        do {
            let value = try await reader.topicDetail(id: destination.topicID)
            guard !Task.isCancelled, currentGen == generation, requestedKey == key else { return }
            detail = value
            loadedKey = requestedKey
            loading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, currentGen == generation, requestedKey == key else { return }
            detail = nil
            issue = TopicScreenIssue(error)
            loadedKey = requestedKey
            loading = false
        }
    }
}
