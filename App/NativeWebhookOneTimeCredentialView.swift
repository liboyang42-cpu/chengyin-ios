import Foundation
import SwiftUI

/// Reads only the coordinator's ephemeral value. There is no clipboard, sharing, URL opening or storage.
@MainActor struct NativeWebhookOneTimeCredentialView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var shownRequestID: NativeWebhookRequestID?
    var body: some View {
        Form {
            if let credential = model.coordinator?.credential, model.available {
                Section {
                    NativeChannelFlowNotice(title:Text("仅显示一次"),message:Text(verbatim:nativeWebhookLocalized("凭据仅在当前页面显示一次。关闭页面、切换后台或授权变化后会清除；普通查询和原请求恢复不能取回。")),symbol:"key.horizontal")
                        .accessibilityIdentifier("webhook.credential.warning")
                    NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("原请求编号")),value:credential.requestID.rawValue)
                }
                Section(nativeWebhookLocalized("签名密钥")) {
                    Text(verbatim: credential.secret).font(.body.monospaced()).fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
                        .accessibilityLabel(nativeWebhookLocalized("一次性签名密钥")).accessibilityValue(nativeWebhookLocalized("敏感内容"))
                        .accessibilityIdentifier("webhook.credential.secret")
                }
                if let url = credential.endpointURL {
                    Section(nativeWebhookLocalized("完整入站 URL")) {
                        Text(verbatim: url).font(.body.monospaced()).fixedSize(horizontal:false,vertical:true).textSelection(.disabled)
                            .accessibilityLabel(nativeWebhookLocalized("一次性入站 URL")).accessibilityValue(nativeWebhookLocalized("敏感内容"))
                            .accessibilityIdentifier("webhook.credential.endpointURL")
                    }
                }
                if let time = credential.oldTokenInvalidAfter {
                    Section { LabeledContent(nativeWebhookLocalized("旧凭据失效时间"), value: time.rawValue) }
                }
                Section {
                    Button(nativeWebhookLocalized("已查看，清除凭据")) { model.dismissSheet() }.nativeChannelFlowAction()
                        .accessibilityIdentifier("webhook.credential.clear")
                }
            } else {
                Section { Text(nativeWebhookLocalized("首次凭据已清除或未取得。若需要新凭据，请另行确认轮换。")) }
                Button(nativeWebhookLocalized("关闭")) { model.dismissSheet() }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("一次性凭据"))
        .privacySensitive()
        .onAppear { shownRequestID = model.coordinator?.credential?.requestID }
        .onDisappear {
            if let shownRequestID, model.coordinator?.credential?.requestID == shownRequestID {
                model.coordinator?.clearSecret()
            }
        }
        .accessibilityIdentifier("webhook.credential")
    }
}
