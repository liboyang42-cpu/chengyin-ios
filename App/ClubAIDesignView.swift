import SwiftUI

@MainActor private final class ClubAIDesignModel: ObservableObject {
    let flow: ClubAIDesignFlow
    @Published var revision = 0
    init(flow: ClubAIDesignFlow) { self.flow = flow }
}
@MainActor struct ClubAIDesignView: View {
    let clubID: Int
    let session: PublishingSession?
    let onAdopt: (ProjectEditDraft) -> Void
    @StateObject private var model: ClubAIDesignModel
    @State private var idea = ""
    @State private var style = ""
    @State private var minutes = ""
    @State private var generating = false
    @State private var operationID = UUID()
    @FocusState private var focused: Bool
    init(clubID: Int, session: PublishingSession?, flow: ClubAIDesignFlow, onAdopt: @escaping (ProjectEditDraft) -> Void) {
        self.clubID = clubID; self.session = session; self.onAdopt = onAdopt
        _model = StateObject(wrappedValue: ClubAIDesignModel(flow: flow))
    }
    private var input: ClubAIDesignInput? {
        if !minutes.isEmpty, Int(minutes) == nil { return nil }
        return try? .init(idea: idea, style: style, minutes: minutes.isEmpty ? nil : Int(minutes))
    }
    var body: some View {
        let _ = model.revision
        Form {
            Section("context.ai.idea") {
                TextField("context.ai.idea", text: $idea, axis: .vertical).lineLimit(3...7).focused($focused)
                TextField("context.ai.style", text: $style).focused($focused)
                TextField("context.ai.minutes", text: $minutes).keyboardType(.numberPad).focused($focused)
            }.disabled(generating)
            if !model.flow.isConfigured { Text("context.ai.disabled") }
            if generating {
                ProgressView("context.ai.generating")
                Button("action.cancel") { operationID = UUID(); generating = false; model.flow.cancel(); model.revision += 1 }
            } else {
                Button("context.ai.generate") {
                    guard let input else { return }; focused = false
                    let request = UUID(); operationID = request; generating = true
                    Task { await model.flow.generate(input); guard operationID == request else { return }; generating = false; model.revision += 1 }
                }.disabled(input == nil || !model.flow.canGenerate).accessibilityIdentifier("club.context.ai.generate")
            }
            if let failure = model.flow.failure {
                Text(LocalizedStringKey("context.ai.error." + String(describing: failure)))
            }
            if let result = model.flow.result {
                Section("context.ai.plan") {
                    Text(verbatim: result.title).font(.headline)
                    Text(verbatim: result.subtitle); Text(verbatim: result.storyline)
                    if !result.fitReason.isEmpty { Text(verbatim: result.fitReason) }
                    ForEach(Array(result.nodes.enumerated()), id: \.offset) { _, node in
                        VStack(alignment: .leading) { Text(verbatim: node.name).font(.headline); Text(verbatim: node.address); Text(verbatim: node.task) }
                    }
                    ForEach(Array(result.risks.enumerated()), id: \.offset) { _, risk in Text(verbatim: risk) }
                }
                Section("context.ai.suggestions") { ForEach(Array(result.merchantSuggestions.enumerated()), id: \.offset) { _, value in Text(verbatim: value) } }
                if !result.promoCopy.isEmpty { Section("context.ai.promo") { Text(verbatim: result.promoCopy).textSelection(.enabled) } }
                Section {
                    Text("context.ai.adoptHint")
                    Button("context.ai.adopt") { if let draft = try? model.flow.adopt(clubID: clubID) { onAdopt(draft) } }
                        .accessibilityIdentifier("club.context.ai.adopt")
                }
            }
        }.navigationTitle("context.ai.title").scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("action.done") { focused = false } } }
            .onChange(of: session) { _, _ in operationID = UUID(); generating = false; model.flow.cancel(); idea = ""; style = ""; minutes = ""; model.revision += 1 }
            .onDisappear { operationID = UUID(); generating = false; model.flow.cancel(); model.revision += 1 }
    }
}
/// Club owner context is supplied by a freshly read club detail. Adoption is a local draft;
/// ordinary project-editor validation, authorization and publish gates remain intact.
@MainActor struct SessionClubAIDesignView: View {
    @ObservedObject var session: AppSession
    let clubID: Int
    @State private var seed: ProjectEditDraft?
    @State private var openEditor = false
    var body: some View {
        ClubAIDesignView(clubID: clubID, session: session.publishingSession,
            flow: ClubAIDesignFlow(generator: session.makePublishingAuxiliaryService(feature: .publishingAIClub).map { ClubAIDesignGenerator(service: $0) }, current: { session.publishingSession })) {
                seed = $0; openEditor = true
            }
            .id(session.publishingSession?.epoch)
            .navigationDestination(isPresented: $openEditor) {
                if let seed {
                    ProjectEditView(coordinator: session.projectEditor(product: seed.product), sessionRevision: session.sessionRevision, seed: seed,
                        publisherClient: session.publisherLifecycleContext?.client)
                }
            }
            .onChange(of: session.publishingSession) { _, _ in seed = nil; openEditor = false }
    }
}
