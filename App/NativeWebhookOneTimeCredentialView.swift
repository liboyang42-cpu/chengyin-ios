import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reads only the coordinator's ephemeral value. Copy writes a local-only pasteboard item
/// that expires; there is no sharing, URL opening or storage.
@MainActor struct NativeWebhookOneTimeCredentialView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var shownRequestID: NativeWebhookRequestID?
    var body: some View {
        Form {
            if let credential = model.coordinator?.credential, model.available {
                Section {
                    NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized("d7.webhook.secret.once")),message:Text(verbatim:nativeWebhookLocalized("d7.webhook.secret.once.message")),symbol:"key.horizontal")
                        .accessibilityIdentifier("webhook.credential.warning")
                }
                Section(nativeWebhookLocalized("d7.webhook.secret")) {
                    Text(verbatim: credential.secret).font(.body.monospaced()).fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
                        .accessibilityLabel(nativeWebhookLocalized("d7.webhook.secret")).accessibilityValue(nativeWebhookLocalized("d7.webhook.secret.hiddenValue"))
                        .accessibilityIdentifier("webhook.credential.secret")
                    Button { copy(credential.secret) } label: { Label(nativeWebhookLocalized("d7.webhook.copy"), systemImage: "doc.on.doc") }
                        .accessibilityIdentifier("webhook.credential.copySecret")
                }
                if let url = credential.endpointURL {
                    Section(nativeWebhookLocalized("d7.webhook.field.url")) {
                        Text(verbatim: url).font(.body.monospaced()).fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
                            .accessibilityLabel(nativeWebhookLocalized("d7.webhook.field.url")).accessibilityValue(nativeWebhookLocalized("d7.webhook.secret.hiddenValue"))
                            .accessibilityIdentifier("webhook.credential.endpointURL")
                        Button { copy(url) } label: { Label(nativeWebhookLocalized("d7.webhook.copy"), systemImage: "doc.on.doc") }
                            .accessibilityIdentifier("webhook.credential.copyURL")
                    }
                }
                if let time = credential.oldTokenInvalidAfter {
                    Section { NativeWebhookTimeRow(label: nativeWebhookLocalized("d7.webhook.secret.oldExpires"), time: time) }
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.done")) { model.dismissSheet() }.nativeChannelFlowAction()
                        .accessibilityIdentifier("webhook.credential.clear")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                ContentUnavailableView(nativeWebhookLocalized("d7.webhook.secret.gone"), systemImage: "key.horizontal",
                    description: Text(verbatim: nativeWebhookLocalized("d7.webhook.secret.gone.message")))
                Button(nativeWebhookLocalized("d7.webhook.close")) { model.dismissSheet() }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("d7.webhook.secret.title"))
        .privacySensitive()
        .onAppear { shownRequestID = model.coordinator?.credential?.requestID }
        .onDisappear {
            if let shownRequestID, model.coordinator?.credential?.requestID == shownRequestID {
                model.coordinator?.clearSecret()
            }
        }
        .accessibilityIdentifier("webhook.credential")
    }
    private func copy(_ value: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
    }
}
