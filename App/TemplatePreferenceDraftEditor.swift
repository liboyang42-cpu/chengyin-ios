import SwiftUI

/// The source mini's dedicated JSON authoring flow, restricted to new local drafts.
@MainActor struct TemplatePreferenceDraftEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @State private var report: TemplatePreferenceDraftCheck?
    @State private var checking = false
    @State private var checkedSource: String?
    @State private var checkedIdentity: TemplateAuthoringIdentity?
    @State private var checkedSession: TemplateAuthoringSession?
    @State private var generation = UUID()
    @State private var replaceExample = false
    @State private var validationTask: Task<Void, Never>?
    @FocusState private var sourceFocused: Bool
    private var raw: String { model.draft.preferenceJson ?? "" }
    private var editable: Bool { model.canEdit && model.draft.id == nil && model.draft.validationMethod == .preference }
    private var currentReport: TemplatePreferenceDraftCheck? {
        guard editable, checkedSource.map({ $0.utf8.elementsEqual(raw.utf8) }) == true, checkedIdentity == model.coordinator.identity,
              checkedSession == model.coordinator.session else { return nil }
        return report
    }
    var body: some View {
        Group {
            if editable {
                Text("templateAuthor.preference.editorTitle").font(.headline)
                Text("templateAuthor.localConfigurationOnly").foregroundStyle(.secondary)
                Text("templateAuthor.preference.instructions").font(.caption)
                TextEditor(text: .init(get: { raw }, set: { value in
                    guard editable else { return }
                    invalidate()
                    model.draft.preferenceJson = value
                    model.changed()
                }))
                    .frame(minHeight: 220).font(.system(.body, design: .monospaced))
                    .focused($sourceFocused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("templateAuthor.preference.source")
                    .accessibilityIdentifier("templateAuthor.preference.source")
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            if sourceFocused {
                                Spacer()
                                Button("action.done") { sourceFocused = false }
                                    .accessibilityIdentifier("templateAuthor.preference.keyboardDone")
                            }
                        }
                    }
                Button("templateAuthor.preference.example") { replaceExample = true }
                    .accessibilityIdentifier("templateAuthor.preference.example")
                Button("templateAuthor.preference.check") { validate() }
                    .disabled(checking || !editable).accessibilityIdentifier("templateAuthor.preference.check")
                if checking { ProgressView("templateAuthor.preference.checking") }
                if let report = currentReport {
                    Text(LocalizedStringKey(report.messageKey)).accessibilityIdentifier("templateAuthor.preference.status")
                    if report.status != .valid { Text(verbatim: report.path).font(.caption) }
                    if report.canPreview {
                        Text("templateAuthor.preference.preview").font(.headline).accessibilityIdentifier("templateAuthor.preference.preview")
                        Text("templateAuthor.preference.previewScope").font(.caption)
                        ForEach(Array(report.fields.enumerated()), id: \.offset) { _, field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: field.path).font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: field.value).accessibilityIdentifier("templateAuthor.preference.field." + field.path)
                            }
                        }
                        if !report.unknownPaths.isEmpty {
                            Text("templateAuthor.preference.unknown").font(.caption)
                            ForEach(Array(report.unknownPaths.enumerated()), id: \.offset) { _, path in Text(verbatim: path).font(.caption) }
                        }
                    }
                } else if !checking { Text("templateAuthor.preference.unchecked").font(.caption).accessibilityIdentifier("templateAuthor.preference.unchecked") }
            } else { Text("templateAuthor.unavailable") }
        }
        .onChange(of: raw) { _, _ in invalidate() }
        .onChange(of: editable) { _, _ in invalidate(); replaceExample = false }
        .onChange(of: model.coordinator.identity) { _, _ in invalidate(); replaceExample = false }
        .onChange(of: model.coordinator.session) { _, _ in invalidate(); replaceExample = false }
        .onDisappear { sourceFocused = false; invalidate(); replaceExample = false }
        .confirmationDialog("templateAuthor.preference.replaceQuestion", isPresented: $replaceExample, titleVisibility: .visible) {
            Button("templateAuthor.preference.replace", role: .destructive) {
                guard editable else { return }
                invalidate()
                model.draft.preferenceJson = TemplatePreferenceDraftCheck.example; model.changed()
            }
            Button("templateAuthor.cancel", role: .cancel) {}
        }
    }
    private func invalidate() {
        validationTask?.cancel(); validationTask = nil
        generation = UUID(); report = nil; checking = false
        checkedSource = nil; checkedIdentity = nil; checkedSession = nil
    }
    private func validate() {
        guard editable else { return }
        let source = raw, stamp = UUID(), session = model.coordinator.session, identity = model.coordinator.identity
        generation = stamp; report = nil; checking = true
        validationTask?.cancel()
        validationTask = Task {
            let worker = Task.detached(priority: .userInitiated) { TemplatePreferenceDraftCheck.inspect(source) }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, generation == stamp, raw.utf8.elementsEqual(source.utf8), editable,
                  model.coordinator.session == session, model.coordinator.identity == identity else { return }
            checking = false; checkedSource = source; checkedIdentity = identity; checkedSession = session; report = result
        }
    }
}
