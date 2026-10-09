import Foundation

public struct MerchantNPCHTTPRequest {
    public let path: String
    public let method: String
    public let body: Data
    public let scope: MerchantNPCScope
    public var contentType: String { "application/json" }
}
public struct MerchantNPCHTTPResponse {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}
@MainActor public protocol MerchantNPCHTTPTransport {
    func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse
}
@MainActor public struct MerchantNPCDormantTransport: MerchantNPCHTTPTransport {
    public init() {}
    public func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse { throw MerchantNPCFailure.disabled }
}
@MainActor public struct MerchantNPCHTTPClient {
    private let transport: any MerchantNPCHTTPTransport
    public init(transport: (any MerchantNPCHTTPTransport)? = nil) { self.transport = transport ?? MerchantNPCDormantTransport() }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let msg: String?; let data: T? }
    private struct Empty: Decodable { init(from decoder: Decoder) throws {} }
    private func post<T: Decodable>(_ path: String, fields: [String: Any], scope: MerchantNPCScope, as type: T.Type) async throws -> (T?, String?) {
        guard scope.accountID > 0, !scope.namespace.isEmpty else { throw MerchantNPCFailure.invalid }
        let request = MerchantNPCHTTPRequest(path: path, method: "POST", body: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), scope: scope)
        let response: MerchantNPCHTTPResponse
        do { response = try await transport.perform(request) }
        catch let error as MerchantNPCFailure where error == .disabled { throw error }
        catch { throw MerchantNPCFailure.unknownOutcome }
        if response.status >= 500 { throw MerchantNPCFailure.unknownOutcome }
        guard (200..<300).contains(response.status) else {
            if let envelope = try? JSONDecoder().decode(Envelope<Empty>.self, from: response.body) { throw MerchantNPCFailure.rejected(code: response.status, message: envelope.msg) }
            throw MerchantNPCFailure.rejected(code: response.status, message: nil)
        }
        // Decode the business status before data, so malformed data cannot hide server rejection text.
        guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any], let code = object["code"] as? Int else { throw MerchantNPCFailure.malformed }
        guard code == 200 else { throw MerchantNPCFailure.rejected(code: code, message: object["msg"] as? String) }
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: response.body) else { throw MerchantNPCFailure.malformed }
        return (envelope.data, envelope.msg)
    }
    public func chat(message: String, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCReply {
        let result = try await post("/api/ai/npc/merchant-chat", fields: ["requestId": requestID.uuidString, "bizId": scope.merchantRowID.rawValue, "message": message], scope: scope, as: MerchantNPCReply.self)
        guard let reply = result.0 else { throw MerchantNPCFailure.malformed }
        try reply.validate(requestID: requestID)
        return reply
    }
    public func voiceScript(scope: MerchantNPCScope) async throws -> MerchantNPCVoiceScript {
        let result = try await post("/api/merchant/npc/voice/script", fields: [:], scope: scope, as: MerchantNPCVoiceScript.self)
        guard let script = result.0 else { throw MerchantNPCFailure.malformed }; return script
    }
    public func perform(_ action: MerchantNPCResourceAction, scope: MerchantNPCScope) async throws -> MerchantNPCResourceReceipt {
        switch action {
        case .enroll(let samples, let requestID):
            guard samples.count == 5, samples.enumerated().allSatisfy({ $0.element.scope == scope && $0.element.kind == .voiceSample(index: $0.offset) }) else { throw MerchantNPCFailure.invalid }
            let result = try await post("/api/merchant/npc/voice/enroll", fields: ["sampleUrls": samples.map { $0.url.absoluteString }, "requestId": requestID.uuidString], scope: scope, as: Empty.self)
            return .accepted(message: result.1)
        case .revoke(let requestID):
            let result = try await post("/api/merchant/npc/voice/revoke", fields: ["requestId": requestID.uuidString], scope: scope, as: Empty.self)
            return .accepted(message: result.1)
        case .avatar(let image, let style):
            guard image.scope == scope, image.kind == .avatarImage, !style.isEmpty else { throw MerchantNPCFailure.invalid }
            let result = try await post("/api/merchant/npc/avatar/generate", fields: ["imageUrl": image.url.absoluteString, "style": style], scope: scope, as: MerchantAvatarResource.Job.self)
            guard let job = result.0 else { throw MerchantNPCFailure.malformed }; return .avatarJob(job)
        }
    }
}
