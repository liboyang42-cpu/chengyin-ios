import SwiftUI

@MainActor struct TemplatePreferenceRemovalPanel: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplatePreferenceRemovalController
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        let capture = controller.capture()
        let original = controller.currentPresentation
        Button {
            guard let capture else { return }; controller.open(capture)
        } label: { Text("preferenceRemoval.open", tableName: "TemplatePreferenceRemoval") }
            .disabled(capture == nil || original != nil)
            .accessibilityIdentifier("preferenceRemoval.open")
            .sheet(item: Binding(get: { controller.currentPresentation }, set: { value in
                if value == nil, let original { controller.close(original) }
            })) { original in
                TemplatePreferenceRemovalSheet(model: model, controller: controller, original: original)
            }
            .onChange(of: model.metadataGeneration) { _, _ in controller.retire() }
            .onChange(of: model.coordinator.session) { _, _ in controller.retire() }
            .onChange(of: model.coordinator.identity) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}

@MainActor private struct TemplatePreferenceRemovalSheet: View {
    @ObservedObject var model: TemplateAuthoringModel
    @ObservedObject var controller: TemplatePreferenceRemovalController
    let original: TemplatePreferenceRemovalController.Presentation
    private func text(_ key: String) -> Text {
        Text(LocalizedStringKey("preferenceRemoval." + key), tableName: "TemplatePreferenceRemoval")
    }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original), let document = original.document {
                    Section { text("scope"); text("minimum"); text("recheck").font(.caption).foregroundStyle(.secondary) }
                    if let intent = controller.review, intent.presentationID == original.id {
                        Section {
                            text("confirmTitle").font(.headline)
                            Text(verbatim: intent.label)
                            text("confirmHint")
                            Button(role: .destructive) { controller.confirm(intent, in: original) } label: { text("confirm") }
                                .accessibilityIdentifier("preferenceRemoval.confirm")
                            Button { controller.cancel(intent, in: original) } label: { text("cancel") }
                                .accessibilityIdentifier("preferenceRemoval.cancel")
                        }.accessibilityIdentifier("preferenceRemoval.review")
                    } else {
                        ForEach(document.questions) { question in
                            Section {
                                Text(verbatim: question.title).font(.headline)
                                Button(role: .destructive) { controller.request(.question(question.id), in: original) } label: { text("question") }
                                    .disabled(!document.canRemoveQuestion)
                                    .accessibilityIdentifier("preferenceRemoval.question." + String(question.id))
                                ForEach(question.options) { option in
                                    VStack(alignment: .leading) {
                                        Text(verbatim: option.text)
                                        Button(role: .destructive) {
                                            controller.request(.option(question: question.id, index: option.id), in: original)
                                        } label: { text("option") }
                                            .disabled(!question.canRemoveOption)
                                            .accessibilityIdentifier("preferenceRemoval.option." + String(question.id) + "." + String(option.id))
                                    }
                                }
                            }
                        }
                    }
                } else { text("unavailable").accessibilityIdentifier("preferenceRemoval.unavailable") }
            }.id(controller.review?.id ?? original.id)
            .navigationTitle(Text("preferenceRemoval.title", tableName: "TemplatePreferenceRemoval"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { controller.close(original) } label: { text("close") }
                }
            }
        }.onDisappear { controller.close(original) }
    }
}
