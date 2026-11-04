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
            Section(nativeWebhookLocalized("订阅设置")) {
                TextField(nativeWebhookLocalized("名称"), text: $draft.name).textInputAutocapitalization(.sentences).accessibilityIdentifier("webhook.subscription.name")
                Toggle(nativeWebhookLocalized("启用"), isOn: $draft.active).accessibilityIdentifier("webhook.subscription.active")
                if resource != nil {
                    Toggle(nativeWebhookLocalized("替换目标 URL"), isOn: $draft.replaceURL)
                        .accessibilityIdentifier("webhook.subscription.replaceURL")
                    if let host = resource?.urlHost { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("当前目标域名")),value:host) }
                }
                if resource == nil || draft.replaceURL {
                    SecureField(nativeWebhookLocalized("完整 HTTPS URL"), text: $draft.url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhook.subscription.url")
                    Text(nativeWebhookLocalized("URL 只用于本次提交；恢复原请求时需要重新输入。")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(nativeWebhookLocalized("订阅事件")) {
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
                        Text(nativeWebhookLocalized("已有但当前目录未列出的事件，请先重新核对目录后保存。"))
                        ForEach(retained.sorted(), id: \.self) { Text($0).font(.caption).fixedSize(horizontal: false, vertical: true) }
                    }
                } else {
                    Text(nativeWebhookLocalized("事件目录不可用；保留原订阅，暂不能新增或更换事件。"))
                        .accessibilityIdentifier("webhook.events.unavailable")
                    ForEach(draft.events.sorted(), id: \.self) { Text($0).font(.caption).fixedSize(horizontal: false, vertical: true) }
                }
            }
            NativeWebhookStatusSection(model: model)
            Section {
                Button(nativeWebhookLocalized("核对并保存")) { model.save(draft, original: resource) }.nativeChannelFlowAction()
                    .disabled(!canSave).accessibilityIdentifier("webhook.subscription.save")
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(resource == nil ? nativeWebhookLocalized("新建订阅") : nativeWebhookLocalized("编辑订阅"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("取消")) { model.dismissSheet() }.accessibilityIdentifier("webhook.subscription.cancel") } }
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
