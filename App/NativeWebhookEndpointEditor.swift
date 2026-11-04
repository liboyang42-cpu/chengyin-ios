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
            Section(nativeWebhookLocalized("端点设置")) {
                TextField(nativeWebhookLocalized("名称"), text: $draft.name).textInputAutocapitalization(.sentences).accessibilityIdentifier("webhook.endpoint.name")
                Toggle(nativeWebhookLocalized("启用"), isOn: $draft.active).accessibilityIdentifier("webhook.endpoint.active")
                TextField(nativeWebhookLocalized("每分钟上限（1–300）"), text: $draft.rateLimit)
                    .keyboardType(.numberPad).accessibilityIdentifier("webhook.endpoint.rateLimit")
                SecureField(nativeWebhookLocalized("头像 URL（可选）"), text: $draft.avatarURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("webhook.endpoint.avatarURL")
            }
            Section(nativeWebhookLocalized("允许的 IP")) {
                TextEditor(text: $draft.allowedIPs).font(.body.monospaced()).frame(minHeight:96)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(nativeWebhookLocalized("允许的 IP，每行一个"))
                    .accessibilityIdentifier("webhook.endpoint.allowedIPs")
                Text(nativeWebhookLocalized("每行一个 IP，也可用逗号分隔，最多 32 个。留空表示未设置 IP 限制。")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text(nativeWebhookLocalized("完整入站 URL 和签名密钥仅在新建或轮换成功后显示一次。"))
            }
            NativeWebhookStatusSection(model: model)
            Section {
                Button(nativeWebhookLocalized("核对并保存")) { model.save(draft, original: resource) }.nativeChannelFlowAction()
                    .disabled(!canSave).accessibilityIdentifier("webhook.endpoint.save")
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(resource == nil ? nativeWebhookLocalized("新建端点") : nativeWebhookLocalized("编辑端点"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("取消")) { model.dismissSheet() } } }
        .onDisappear { draft.url = ""; draft.avatarURL = ""; draft.allowedIPs = "" }
        .accessibilityIdentifier("webhook.endpoint.editor")
    }
    private var canSave: Bool {
        guard model.canMutate, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rate = Int(draft.rateLimit), (1...300).contains(rate) else { return false }
        return draft.allowedIPs.split(whereSeparator: { $0 == "\n" || $0 == "," }).count <= 32
    }
}
