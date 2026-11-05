import Foundation
import SwiftUI

@MainActor struct NativeWebhookSubscriptionEditor: View {
    @ObservedObject var model: NativeWebhookViewModel
    let resource: NativeWebhookResource?
    @State private var draft: NativeWebhookEditorDraft
    init(model: NativeWebhookViewModel, resource: NativeWebhookResource?) {
        self.model = model; self.resource = resource
        _draft = State(initialValue: NativeWebhookEditorDraft(resource: resource))
    }
    var body: some View {
        Form {
            Section {
                TextField(nativeWebhookLocalized("d7.webhook.field.name"), text: $draft.name).textInputAutocapitalization(.sentences).accessibilityIdentifier("webhook.subscription.name")
                Toggle(nativeWebhookLocalized("d7.webhook.field.on"), isOn: $draft.active).accessibilityIdentifier("webhook.subscription.active")
            }
            Section(nativeWebhookLocalized("d7.webhook.field.url")) {
                if resource != nil {
                    if let host = resource?.urlHost { LabeledContent(nativeWebhookLocalized("d7.webhook.editor.currentURL"), value: host) }
                    Toggle(nativeWebhookLocalized("d7.webhook.editor.changeURL"), isOn: $draft.replaceURL)
                        .accessibilityIdentifier("webhook.subscription.replaceURL")
                }
                if resource == nil || draft.replaceURL {
                    SecureField(nativeWebhookLocalized("d7.webhook.editor.httpsURL"), text: $draft.url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhook.subscription.url")
                }
            }
            Section(nativeWebhookLocalized("d7.webhook.events")) {
                if let options = model.coordinator?.context?.eventCatalogue.options {
                    ForEach(options) { option in
                        Toggle(isOn: Binding(get: { draft.events.contains(option.id) }, set: { selected in
                            if selected { draft.events.insert(option.id) } else { draft.events.remove(option.id) }
                        })) {
                            Text(option.title).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("webhook.subscription.event.\(option.id)")
                    }
                    let retained = draft.events.subtracting(Set(options.map(\.id)))
                    if !retained.isEmpty {
                        Text(nativeWebhookLocalized("d7.webhook.events.retired")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(retained.sorted(), id: \.self) { Text(verbatim: $0).fixedSize(horizontal: false, vertical: true) }
                    }
                } else {
                    Text(nativeWebhookLocalized("d7.webhook.events.unavailable"))
                        .accessibilityIdentifier("webhook.events.unavailable")
                    ForEach(draft.events.sorted(), id: \.self) { Text(verbatim: $0).fixedSize(horizontal: false, vertical: true) }
                }
            }
            NativeWebhookStatusSection(model: model)
            Section {
                Button(nativeWebhookLocalized("d7.webhook.save")) { model.save(draft, original: resource) }.nativeChannelFlowAction()
                    .disabled(!canSave).accessibilityIdentifier("webhook.subscription.save")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .nativeChannelFlowPage()
        .navigationTitle(resource == nil ? nativeWebhookLocalized("d7.webhook.add") : nativeWebhookLocalized("d7.webhook.editor.editTitle"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("d7.webhook.cancel")) { model.dismissSheet() }.accessibilityIdentifier("webhook.subscription.cancel") } }
        .onChange(of: draft.replaceURL) { enabled in if !enabled { draft.url = "" } }
        .onDisappear { draft.url = ""; draft.avatarURL = "" }
        .accessibilityIdentifier("webhook.subscription.editor")
    }
    private var canSave: Bool {
        guard model.canMutate, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.events.isEmpty, resource != nil || !draft.url.isEmpty,
              !draft.replaceURL || !draft.url.isEmpty else { return false }
        if let options = model.coordinator?.context?.eventCatalogue.options {
            return draft.events.isSubset(of: Set(options.map(\.id)))
        }
        return resource != nil && draft.events == Set(resource?.events ?? [])
    }
}
