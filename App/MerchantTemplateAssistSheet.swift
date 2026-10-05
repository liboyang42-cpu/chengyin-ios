import SwiftUI

struct MerchantTemplateAssistPresentation: Identifiable {
    let id = UUID()
    let flow: MerchantTemplateAssistFlow
}
@MainActor private final class MerchantTemplateAssistModel: ObservableObject {
    let flow: MerchantTemplateAssistFlow
    @Published private(set) var revision = 0
    init(flow: MerchantTemplateAssistFlow) {
        self.flow = flow
        flow.onChange = { [weak self] in self?.revision += 1 }
    }
}
@MainActor struct MerchantTemplateAssistSheet: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @StateObject private var model: MerchantTemplateAssistModel
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    init(document: MerchantOperationsViewModel, flow: MerchantTemplateAssistFlow) {
        self.document = document; _model = StateObject(wrappedValue: .init(flow: flow))
    }
    private var flow: MerchantTemplateAssistFlow { model.flow }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("merchant.assist.generatedNote", systemImage: "sparkles")
                    Text("merchant.assist.boundary").font(.footnote).foregroundStyle(.secondary)
                }
                Section("merchant.assist.request") {
                    TextField("merchant.assist.shopName", text: Binding(get: { flow.shopName }, set: { flow.shopName = $0 }))
                        .focused($focused).accessibilityIdentifier("merchant.assist.shopName")
                    TextField("merchant.assist.prompt", text: Binding(get: { flow.prompt }, set: { flow.prompt = $0 }), axis: .vertical)
                        .lineLimit(3...7).focused($focused).accessibilityIdentifier("merchant.assist.prompt")
                }.disabled(flow.busy || flow.result != nil)
                if !flow.isConfigured { Text("merchant.assist.disabled").accessibilityIdentifier("merchant.assist.disabled") }
                if flow.busy {
                    ProgressView("merchant.assist.working")
                    Button("action.cancel") { task?.cancel(); task = nil; flow.cancel() }.accessibilityIdentifier("merchant.assist.cancelRequest")
                } else if flow.result == nil {
                    Button(LocalizedStringKey(flow.failure?.retryable == true ? "merchant.assist.retry" : "merchant.assist.generate")) {
                        focused = false; task = Task { await flow.generate() }
                    }.disabled(!flow.canGenerate).accessibilityIdentifier("merchant.assist.generate")
                }
                if let failure = flow.failure {
                    Section {
                        Text(LocalizedStringKey(failure.messageKey)).accessibilityIdentifier("merchant.assist.failure")
                        if failure == .permission { Text("merchant.assist.permissionNextStep").font(.footnote) }
                    }
                }
                if let review = flow.visibleReview {
                    let result = review.result
                    MerchantTemplateSuggestionReviewPanel(review: review,
                        canChange: { flow.canChange($0, change: $1) }, canReject: flow.canReject,
                        change: { action, change in
                            focused = false
                            task = Task {
                                _ = await flow.change(action, change)
                                document.templateAssistChanged()
                            }
                        }, reject: flow.reject)
                    if !result.unsupportedKeys.isEmpty {
                        Section("merchant.assist.unsupported") {
                            Text("merchant.assist.unsupportedHint").font(.footnote)
                            ForEach(result.unsupportedKeys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: key).font(.caption).foregroundStyle(.secondary)
                                    Text(verbatim: result.display(key)).textSelection(.enabled)
                                }
                            }
                        }.accessibilityIdentifier("merchant.assist.unsupported")
                    }
                    Section {
                        Text("merchant.assist.diff.closeNote").font(.footnote)
                        DisclosureGroup("merchant.assist.diff.decodedResult") {
                            Text(verbatim: decodedResult(result)).textSelection(.enabled)
                                .accessibilityIdentifier("merchant.assist.diff.decodedResult")
                        }
                    }
                }
            }
            .appNavigationTitle("merchant.assist.title")
            .accessibilityIdentifier("merchant.assist.sheet")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.close") { close() }.accessibilityIdentifier("merchant.assist.close") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("action.done") { focused = false } }
            }
        }
        .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { task?.cancel(); flow.close() }
    }
    private func close() { task?.cancel(); task = nil; flow.close(); dismiss() }
    private func decodedResult(_ result: MerchantTemplateAssistResult) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result.response) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

}

@MainActor extension AppSession {
    func merchantTemplateAssistFlow(coordinator: MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow {
        let service = coordinator.reader.isOfflineExample ? nil : makePublishingAuxiliaryService(feature: .publishingAITemplate)
        return .init(coordinator: coordinator, client: service.map { MerchantTemplateAssistClient(service: $0) })
    }
}
