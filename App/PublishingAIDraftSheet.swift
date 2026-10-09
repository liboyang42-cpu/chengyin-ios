import SwiftUI

@MainActor private final class PublishingAIDraftModel: ObservableObject {
    let flow: PublishingAIDraftFlow
    @Published var revision = 0
    init(client: (any PublishingAIDraftServing)?, product: ProjectEditProduct) {
        flow = PublishingAIDraftFlow(client: client, product: product)
        flow.onChange = { [weak self] in self?.revision += 1 }
    }
}
@MainActor struct PublishingAIDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PublishingAIDraftModel
    let accept: (QuickPublishDraft) -> Void
    init(client: (any PublishingAIDraftServing)?, product: ProjectEditProduct, accept: @escaping (QuickPublishDraft) -> Void) {
        _model = StateObject(wrappedValue: PublishingAIDraftModel(client: client, product: product)); self.accept = accept
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("contextPublish.ai.notice")
                    TextField("contextPublish.ai.prompt", text: Binding(get: { model.flow.idea }, set: { model.flow.idea = $0; model.revision += 1 }), axis: .vertical)
                        .lineLimit(3...8).disabled(model.flow.busy).accessibilityIdentifier("contextPublish.ai.prompt")
                    if let key = model.flow.messageKey { Text(LocalizedStringKey(key)) }
                    if let message = model.flow.serverMessage { Text(verbatim: message) }
                    if model.flow.busy { ProgressView("contextPublish.ai.generating") }
                    Button("contextPublish.ai.generate") { Task { await model.flow.generate() } }
                        .disabled(!model.flow.canGenerate).accessibilityIdentifier("contextPublish.ai.generate")
                    if !model.flow.canGenerate && !model.flow.busy && model.flow.quotaReadState != .loading && model.flow.quota?.exhausted != true { Text("contextPublish.ai.unavailable").font(.caption) }
                }
                PublishingAIQuotaSection(flow: model.flow)
                if let result = model.flow.candidate, let candidateGeneration = model.flow.candidateGeneration {
                    Section(model.flow.candidateIsPrevious ? LocalizedStringKey("publishingAICandidate.previous") : LocalizedStringKey("contextPublish.ai.generated")) {
                        if model.flow.candidateIsPrevious { Text("publishingAICandidate.previousNotice").font(.footnote) }
                        if let sourceIdea = model.flow.candidateSourceIdea {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("publishingAICandidate.sourceIdea").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: sourceIdea).textSelection(.enabled)
                            }.accessibilityIdentifier("publishingAICandidate.sourceIdea")
                        }
                        Text(verbatim: result.draft.title).font(.headline)
                        if let subtitle = result.draft.subtitle { Text(verbatim: subtitle) }
                        Text(verbatim: result.draft.description)
                        Text("contextPublish.ai.placesUnconfirmed").font(.caption)
                        ForEach(result.draft.nodes) { node in VStack(alignment: .leading) { Text(verbatim: node.name); Text(verbatim: node.description).font(.caption) } }
                        Button(model.flow.candidateIsPrevious ? LocalizedStringKey("publishingAICandidate.usePrevious") : LocalizedStringKey("contextPublish.ai.use")) {
                            if let draft = model.flow.accept(candidateGeneration: candidateGeneration) { accept(draft); dismiss() }
                        }.disabled(!model.flow.canAcceptCandidate).accessibilityIdentifier("contextPublish.ai.use")
                    }
                }
            }.navigationTitle("contextPublish.ai.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { model.flow.close(); dismiss() } } }
            .task { await model.flow.loadQuota() }.onDisappear { model.flow.close() }
        }
    }
}
