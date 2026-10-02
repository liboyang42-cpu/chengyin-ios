import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact source paths, multipart fields and receipt envelopes from im_api.dart.
/// Injectable only. Production composition must supply a bounded no-redirect transport.
public struct IMExpandedService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let approvedMediaOrigins: Set<String>
    private let writesEnabled: Bool
    public var isConfigured: Bool { writesEnabled }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approvedMediaOrigins: Set<String>, writesEnabled: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.approvedMediaOrigins = approvedMediaOrigins; self.writesEnabled = writesEnabled
    }
    public func perform(_ mutation: IMMutation, token: String) async throws -> IMMutationReceipt {
        guard writesEnabled else { throw APIError.notConfigured }
        let path: String
        var fields: [String: String]
        switch mutation {
        case .start(let id):
            guard id > 0 else { throw APIError.invalidRequest }; path = "start"; fields = ["target_member_id": String(id)]
        case .read(let id):
            guard id > 0 else { throw APIError.invalidRequest }; path = "read"; fields = ["conversation_id": String(id)]
        case .mute(let id, let muted):
            guard id > 0 else { throw APIError.invalidRequest }; path = "mute"; fields = ["conversation_id": String(id), "muted": muted ? "1" : "0"]
        case .send(let intent):
            path = "send"; fields = try intent.payload.wireFields(approvedOrigins: approvedMediaOrigins)
            fields["conversation_id"] = String(intent.scope.conversationID); fields["client_message_id"] = intent.clientMessageID
        }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/im/\(path)"), fields: fields, token: token)
        let data = try await response(request)
        switch mutation {
        case .start:
            struct Receipt: Decodable { struct Body: Decodable { let conversationId: Int }; let data: Body }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.data.conversationId > 0 else { throw APIError.malformedResponse }
            return .started(conversationID: receipt.data.conversationId)
        case .read: return .read
        case .mute(_, let muted): return .muted(muted)
        case .send(let intent):
            struct Receipt: Decodable { let data: MessagingMessage }
            guard let message = try? JSONDecoder().decode(Receipt.self, from: data).data,
                  message.conversationID == intent.scope.conversationID, message.senderID == intent.scope.identity.accountID,
                  String(message.type ?? 0) == fields["msg_type"], message.content == fields["content"],
                  message.extraJSON == fields["extra_json"] else { throw APIError.malformedResponse }
            return .sent(message)
        }
    }
    public func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, token: String) async throws -> URL {
        guard writesEnabled else { throw APIError.notConfigured }
        guard consent.selectionID == selection.id, consent.scope == selection.scope, consent.purpose == .upload else { throw IMCapabilityGap.consentRequired }
        try selection.validateImage()
        let boundary = "im-" + UUID().uuidString
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"), fields: [:], token: token)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.\(selection.fileExtension)\"\r\nContent-Type: \(selection.mimeType)\r\n\r\n".utf8)
        body.append(selection.bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let data = try await response(request)
        struct Receipt: Decodable { let url: String }
        guard let raw = try? JSONDecoder().decode(Receipt.self, from: data).url, let url = URL(string: raw),
              let origin = SocialMessageMediaService.origin(url), approvedMediaOrigins.contains(origin),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment == nil else { throw APIError.malformedResponse }
        return url
    }
    private func response(_ input: URLRequest) async throws -> Data {
        var request = input
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
        guard let header else { throw APIError.malformedResponse }
        guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
        return data
    }
}
