import Foundation
import SwiftUI

@MainActor struct NativeWebhookEndpointEditor: View {
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
                TextField(nativeWebhookLocalized("d7.webhook.field.name"), text: $draft.name).textInputAutocapitalization(.sentences).accessibilityIdentifier("webhook.endpoint.name")
                Toggle(nativeWebhookLocalized("d7.webhook.field.on"), isOn: $draft.active).accessibilityIdentifier("webhook.endpoint.active")
                TextField(nativeWebhookLocalized("d7.webhook.editor.rateLimit"), text: $draft.rateLimit)
                    .keyboardType(.numberPad).accessibilityIdentifier("webhook.endpoint.rateLimit")
                if rateLimitInvalid {
                    Text(nativeWebhookLocalized("d7.webhook.editor.rateLimit.error")).font(.footnote).foregroundStyle(.red)
                }
                SecureField(nativeWebhookLocalized("d7.webhook.editor.avatar"), text: $draft.avatarURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("webhook.endpoint.avatarURL")
            }
            Section(nativeWebhookLocalized("d7.webhook.field.allowedIPs")) {
                TextEditor(text: $draft.allowedIPs).font(.body.monospaced()).frame(minHeight:96)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(nativeWebhookLocalized("d7.webhook.editor.allowedIPs.label"))
                    .accessibilityIdentifier("webhook.endpoint.allowedIPs")
                if ipCount > 32 {
                    Text(nativeWebhookLocalized("d7.webhook.editor.allowedIPs.error")).font(.footnote).foregroundStyle(.red)
                }
            }
            NativeWebhookStatusSection(model: model)
            Section {
                Button(nativeWebhookLocalized("d7.webhook.save")) { model.save(draft, original: resource) }.nativeChannelFlowAction()
                    .disabled(!canSave).accessibilityIdentifier("webhook.endpoint.save")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .nativeChannelFlowPage()
        .navigationTitle(resource == nil ? nativeWebhookLocalized("d7.webhook.add") : nativeWebhookLocalized("d7.webhook.editor.editTitle"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("d7.webhook.cancel")) { model.dismissSheet() } } }
        .onDisappear { draft.url = ""; draft.avatarURL = ""; draft.allowedIPs = "" }
        .accessibilityIdentifier("webhook.endpoint.editor")
    }
    private var ipCount: Int { draft.allowedIPs.split(whereSeparator: { $0 == "\n" || $0 == "," }).count }
    private var rateLimitInvalid: Bool {
        guard !draft.rateLimit.isEmpty else { return false }
        guard let rate = Int(draft.rateLimit) else { return true }
        return !(1...300).contains(rate)
    }
    private var canSave: Bool {
        guard model.canMutate, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rate = Int(draft.rateLimit), (1...300).contains(rate) else { return false }
        return draft.allowedIPs.split(whereSeparator: { $0 == "\n" || $0 == "," }).count <= 32
    }
}
