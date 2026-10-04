import SwiftUI

@MainActor struct SessionMemberTemplateDetailView: View {
    let id: MemberPlayTemplateID
    @EnvironmentObject private var session: AppSession
    var body: some View {
        MemberTemplateDetailView(id: id, reader: session.playerJourneyReader)
            .id(session.playerJourneyReader.scope)
    }
}
/// Owned-shelf-only reader. Participation keeps its existing broader member-detail service.
@MainActor struct SessionOwnedMemberTemplateDetailView: View {
    let id: MemberPlayTemplateID
    @EnvironmentObject private var session: AppSession
    var body: some View {
        MemberTemplateDetailView(id: id, reader: session.makeOwnedMemberTemplateReader())
            .id(session.templateShelfViewIdentity)
    }
}
/// A navigation destination rather than an editing sheet: back never commits a draft.
@MainActor struct MemberTemplateDetailView: View {
    let id: MemberPlayTemplateID
    let reader: any MemberTemplateReading
    var imageReader: (any RetainedPublicImageReading)? = nil
    @State private var detail: MemberTemplateDetail?
    @State private var failure: String?
    @State private var message: String?
    @State private var loading = false
    @State private var generation = UUID()
    var body: some View {
        List {
            if loading { ProgressView("memberTemplate.loading") }
            if let failure {
                Section {
                    if let message { Text(verbatim: message) } else { Text(LocalizedStringKey(failure)) }
                    Button("action.retry") { Task { await load() } }.disabled(loading)
                }
            }
            if let detail {
                let item = detail.overview
                Section {
                    if !item.title.isEmpty { Text(verbatim: item.title).font(.title2.bold()) }
                    else { Text("discovery.untitledPlay").font(.title2.bold()) }
                    DiscoveryPlayMetadata(item: item)
                    if let draft = detail.draftStatus {
                        if draft == 0 { Text("memberTemplate.draft") }
                        else if draft == 1 { Text("memberTemplate.published") }
                    }
                    if !detail.gallery.isEmpty {
                        NativeMediaGalleryEntry(sources: detail.gallery, scope: reader.scope,
                            titleKey: "memberTemplate.title", reader: imageReader)
                    }
                }
                textSection("discovery.introduction", value: item.description)
                textSection("discovery.rules", value: item.ruleInstructions)
                textSection("discovery.materials", value: item.requiredMaterials)
                textSection("discovery.location", value: item.usageLocation)
                if let verification = item.verification { Section("discovery.verification") { Text(verification.label) } }
                if !detail.story.isEmpty {
                    Section("memberTemplate.story") {
                        ForEach(detail.story) { part in
                            VStack(alignment: .leading, spacing: 10) {
                                if let tag = part.tag { Text(verbatim: tag).font(.caption.weight(.semibold)) }
                                if let text = part.text { Text(verbatim: text).textSelection(.enabled) }
                                if !part.images.isEmpty {
                                    NativeMediaGalleryEntry(sources: part.images, scope: reader.scope,
                                        titleKey: "memberTemplate.story", reader: imageReader)
                                }
                            }
                        }
                    }
                } else { textSection("memberTemplate.story", value: item.storyText) }
                textSection("discovery.creator", value: item.publisher)
                Section { Text("memberTemplate.readBoundary").font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle("memberTemplate.title").navigationBarTitleDisplayMode(.inline)
        .privacySensitive().accessibilityIdentifier("memberTemplate.detail")
        .task(id: reader.scope) { detail = nil; await load() }
        .refreshable { await load() }
        .onDisappear { generation = UUID(); detail = nil }
    }
    @ViewBuilder private func textSection(_ label: LocalizedStringKey, value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Section(label) { Text(verbatim: value).textSelection(.enabled) } }
    }
    private func load() async {
        let request = UUID(); generation = request; let scope = reader.scope
        loading = true; failure = nil; message = nil; detail = nil
        defer { if generation == request { loading = false } }
        do {
            let value = try await reader.memberTemplate(id: id)
            guard !Task.isCancelled, generation == request, reader.scope == scope, value.id == id else { return }
            detail = value
        } catch {
            guard !Task.isCancelled, generation == request, reader.scope == scope else { return }
            if error as? APIError == .unauthorized { failure = "memberTemplate.login" }
            else if error as? APIError == .notConfigured { failure = "memberTemplate.notConfigured" }
            else { failure = "memberTemplate.failed"; message = (error as? PlayerJourneyFailure)?.message }
        }
    }
}
