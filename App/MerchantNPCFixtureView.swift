#if DEBUG
import SwiftUI

@MainActor final class MerchantNPCFixtureTransport: MerchantNPCHTTPTransport {
    var failUnknown = false
    var calls: [MerchantNPCHTTPRequest] = []
    func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
        calls.append(request)
        if failUnknown { throw MerchantNPCFailure.unknownOutcome }
        let body: String
        if request.path.hasSuffix("/script") {
            body = #"{"code":200,"data":{"available":true,"script":["SYNTHETIC authorization statement — never record","Synthetic line 2","Synthetic line 3","Synthetic line 4","Synthetic line 5"],"consentIndex":0}}"#
        } else if request.path.hasSuffix("merchant-chat") {
            let sent = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            guard let id = sent?["requestId"] as? String else { throw MerchantNPCFailure.invalid }
            let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": id,
                "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "safeText": "Synthetic merchant-row reply", "retryable": false]])
            body = String(decoding: data, as: UTF8.self)
        } else if request.path.hasSuffix("generate") {
            body = #"{"code":200,"data":{"jobId":41,"status":"PENDING","style":"realistic"}}"#
        } else { body = #"{"code":200,"msg":"Synthetic acceptance only","data":null}"# }
        return .init(status: 200, body: Data(body.utf8))
    }
}
@MainActor struct MerchantNPCFixtureView: View {
    private let scope = MerchantNPCScope(accountID: 901, namespace: "synthetic.invalid", epoch: UUID(), merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
    private let transport = MerchantNPCFixtureTransport()
    private var grants: MerchantNPCGrants {
        var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true
        // This fixture exercises text and status only; real capture/upload/cloning remains unavailable.
        return value
    }
    var body: some View {
        List {
            Text("merchantNPC.synthetic")
            NavigationLink("merchantNPC.chatTitle") {
                MerchantNPCChatView(coordinator: .init(scope: scope, client: .init(transport: transport), currentScope: { scope }, grants: { grants }))
            }.accessibilityIdentifier("merchantNPC.fixture.chat")
            NavigationLink("merchantNPC.resourcesTitle") {
                MerchantNPCResourceEditor(coordinator: .init(scope: scope, client: .init(transport: transport), reader: MerchantOperationsFixtureReader(), currentScope: { scope }, grants: { grants }))
            }.accessibilityIdentifier("merchantNPC.fixture.resources")
        }.navigationTitle("merchantNPC.synthetic")
    }
}
#endif
