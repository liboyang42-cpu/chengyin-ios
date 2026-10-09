import SwiftUI

@MainActor final class MerchantTemplateSuggestionEditModel: ObservableObject {
    @Published private(set) var edit: MerchantTemplateSuggestionEdit?
    private let flow: MerchantTemplateAssistFlow
    init(flow: MerchantTemplateAssistFlow, edit: MerchantTemplateSuggestionEdit) { self.flow = flow; self.edit = edit }
    var isCurrent: Bool { edit.map { flow.canEditSuggestion($0.action) } ?? false }
    var canSave: Bool { edit.map(flow.canSaveSuggestionEdit) ?? false }
    func update(_ text: String) {
        guard isCurrent, var value = edit else { return }
        value.text = text; edit = value
    }
    @discardableResult func save() -> Bool {
        guard let edit, flow.saveSuggestionEdit(edit) else { return false }
        self.edit = nil; return true
    }
    func cancel() { edit = nil }
}

@MainActor struct MerchantTemplateSuggestionEditSheet: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @StateObject private var model: MerchantTemplateSuggestionEditModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(document: MerchantOperationsViewModel, flow: MerchantTemplateAssistFlow, edit: MerchantTemplateSuggestionEdit) {
        self.document = document; _model = StateObject(wrappedValue: .init(flow: flow, edit: edit))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("merchantSuggestionEdit.boundary").font(.footnote) }
                if let edit = model.edit, model.isCurrent {
                    Section(LocalizedStringKey(edit.action.field.titleKey)) {
                        Text("merchantSuggestionEdit.originalDraft").font(.caption)
                        if edit.originalDraft.isEmpty { Text("merchant.assist.diff.empty").foregroundStyle(.secondary) }
                        else { Text(verbatim: edit.originalDraft).textSelection(.enabled) }
                        Text("merchantSuggestionEdit.generated").font(.caption)
                        Text(verbatim: edit.generatedText).textSelection(.enabled)
                    }
                    Section("merchantSuggestionEdit.yourVersion") {
                        TextField("merchantSuggestionEdit.text", text: Binding(get: { model.edit?.text ?? "" }, set: model.update), axis: .vertical)
                            .lineLimit(3...12).accessibilityIdentifier("merchantSuggestionEdit.text")
                        if let issue = edit.issue {
                            Text(LocalizedStringKey("merchantSuggestionEdit.issue." + issue.rawValue)).foregroundStyle(.secondary)
                        }
                        Text("merchantSuggestionEdit.capacity").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("merchantSuggestionEdit.save") { if model.save() { dismiss() } }
                            .disabled(!model.canSave).accessibilityIdentifier("merchantSuggestionEdit.save")
                    }
                } else { Text("merchantSuggestionEdit.stale").accessibilityIdentifier("merchantSuggestionEdit.stale") }
            }
            .navigationTitle("merchantSuggestionEdit.title").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { close() } } }
        }
        .privacySensitive().accessibilityIdentifier("merchantSuggestionEdit.sheet")
        .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { model.cancel() }
    }
    private func close() { model.cancel(); dismiss() }
}
