import SwiftUI

@MainActor
struct DiscoveryTemplateDetailView: View {
    let id: Int
    let reader: any DiscoveryReading
    @StateObject private var detail = DiscoveryLoader<DiscoveryPlayTemplate>()

    init(id: Int, reader: any DiscoveryReading) { self.id = id; self.reader = reader }

    var body: some View {
        Group {
            if !reader.isConfigured {
                ContentUnavailableView("discovery.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if detail.isLoading {
                ProgressView("discovery.loading")
            } else if let error = detail.error {
                DiscoveryErrorView(error: error) { Task { await reload() } }
            } else if let item = detail.value {
                List {
                    Section {
                        if let image = item.imgUrl, !image.isEmpty { DiscoveryArtwork(source: image, height: 210) }
                        DiscoveryTitle(text: item.title, fallback: "discovery.untitledPlay").font(.title2.bold())
                        DiscoveryPlayMetadata(item: item)
                    }
                    textSection("discovery.introduction", text: item.description)
                    textSection("discovery.rules", text: item.ruleInstructions)
                    textSection("discovery.materials", text: item.requiredMaterials)
                    textSection("discovery.location", text: item.usageLocation)
                    if let verification = item.verification {
                        Section("discovery.verification") { Text(verification.label) }
                    }
                    if let note = item.creatorNote {
                        Section("discovery.creator") {
                            if let image = item.storyImg, !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                DiscoveryArtwork(source: image, height: 160)
                            }
                            Text(note).textSelection(.enabled)
                        }
                    }
                    Section { Text("discovery.readOnlyHint").font(.footnote).foregroundStyle(.secondary) }
                }
                .refreshable { await reload() }
                .accessibilityIdentifier("discovery.detail.content")
            }
        }
        .navigationTitle("discovery.playDetails")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) { if reader.isConfigured { await reload() } }
    }
    @ViewBuilder private func textSection(_ title: LocalizedStringKey, text: String?) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section(title) { Text(text).textSelection(.enabled) }
        }
    }
    private func reload() async { await detail.load { try await reader.discoveryPlayTemplate(id: id) } }
}

/// Source has no independent read-only topic-template detail call. This displays only shelf data.
struct DiscoveryTopicTemplatePreview: View {
    let item: DiscoveryTopicTemplate
    var body: some View {
        List {
            Section {
                if let image = item.imgUrl, !image.isEmpty { DiscoveryArtwork(source: image, height: 210) }
                DiscoveryTitle(text: item.name, fallback: "discovery.untitledTopic").font(.title2.bold())
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle).textSelection(.enabled)
                }
                DiscoveryTopicMetadata(item: item)
            }
            Section { Text("discovery.topicPreviewHint").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("discovery.topicPreview")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("discovery.topicPreview.content")
    }
}
