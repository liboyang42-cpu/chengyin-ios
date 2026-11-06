import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable transport only. There are no default hosts, sessions, hidden retries,
/// payment fallbacks, or credential configuration in this membership slice.
public struct ClubActionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let reader: ClubService
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
        reader = ClubService(configuration: configuration, transport: transport)
    }
    func accepts(_ approval: ClubOrdinaryAdmissionApproval) -> Bool { approval.baseURL == configuration.baseURL }
    func detail(id: Int, token: String) async throws -> ClubRecord {
        try await reader.detail(id: id, token: token)
    }
    // Session writer is the public dispatch boundary and revalidates a fresh detail.
    func perform(_ action: ClubAction, clubID: Int, token: String, joinMessage: String = "", original: ClubOrdinaryAdmissionPending? = nil) async throws -> ClubActionReceipt {
        var request: URLRequest
        do {
            guard clubID > 0, AuthRequestBuilder.isValidToken(token), ClubApplicationMessage.isValid(joinMessage, for: action) else { throw APIError.invalidRequest }
            request = URLRequest(url: configuration.baseURL.appendingPathComponent(action == .leave ? "api/club/quit" : "api/club/join"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(token, forHTTPHeaderField: "Authorization")
            // Current /join and /quit both accept @RequestBody Club.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var fields: [String: Any] = ["id": clubID]
            if action == .apply { fields["joinMessage"] = joinMessage }
            if let original {
                guard original.clubID == clubID, original.action == action, original.hasOriginalReceipt else { throw APIError.invalidRequest }
                let reviewed = ClubOrdinaryAdmissionPending(accountID: original.accountID, clubID: clubID,
                    requestID: original.requestID, action: action, hasOriginalReceipt: true, message: joinMessage)
                guard original == reviewed else { throw APIError.invalidRequest }
                request.setValue(original.requestID.uuidString.lowercased(), forHTTPHeaderField: "X-Club-Admission-Request-Id")
                request.setValue(action.rawValue, forHTTPHeaderField: "X-Club-Admission-Action")
                request.setValue(original.payloadSHA256, forHTTPHeaderField: "X-Club-Admission-Payload-SHA256")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        } catch { throw ClubActionWriteError.notSent(.invalidRequest) }
        guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch is CancellationError { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        catch let error as URLError where error.code == .cancelled {
            throw ClubActionWriteError.outcomeUnknown(.cancelled)
        } catch { throw ClubActionWriteError.outcomeUnknown(.transport) }
        guard !Task.isCancelled else { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
        let envelope = try? JSONDecoder().decode(Response.self, from: data)
        let failure = ClubActionResponseFailure(httpStatus: (200..<300).contains(status) ? nil : status,
                                                 code: envelope?.code, message: envelope?.msg)
        if status == 401 || status == 403 { throw ClubActionWriteError.rejected(failure) }
        guard (200..<300).contains(status) else { throw ClubActionWriteError.outcomeUnknown(.response(failure)) }
        guard let envelope, let code = envelope.code else { throw ClubActionWriteError.outcomeUnknown(.malformedResponse) }
        guard code == 200 else { throw ClubActionWriteError.rejected(failure) }
        if let original {
            guard let fact = try? JSONDecoder().decode(OriginalEnvelope.self, from: data).data,
                  fact.matches(original), fact.state == "APPLIED" else { throw ClubActionWriteError.outcomeUnknown(.malformedResponse) }
            return ClubActionReceipt(state: fact.membershipState, message: envelope.msg)
        }
        return ClubActionReceipt(state: envelope.data?.state, message: envelope.msg)
    }
    func recover(_ pending: ClubOrdinaryAdmissionPending, token: String) async throws -> ClubOrdinaryAdmissionOriginalReceipt {
        guard pending.hasOriginalReceipt else { throw APIError.notConfigured }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/club/admission/receipt"), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: ["clubId": pending.clubID, "requestId": pending.requestID.uuidString.lowercased(), "action": pending.action.rawValue, "payloadSHA256": pending.payloadSHA256])
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        let response = try? JSONDecoder().decode(Response.self, from: data)
        if status == 401 || response?.code == 401 { throw ClubReadFailure.unauthorized(message: response?.msg) }
        guard (200..<300).contains(status), response?.code == 200,
              let fact = try? JSONDecoder().decode(OriginalEnvelope.self, from: data).data, fact.matches(pending) else { throw APIError.malformedResponse }
        return fact
    }
    private struct OriginalEnvelope: Decodable { let data: ClubOrdinaryAdmissionOriginalReceipt }
    private struct Response: Decodable {
        let code: Int?, msg: String?, data: Payload?
        enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decode(Int.self, forKey: .code)
            msg = try? c.decode(String.self, forKey: .msg)
            data = try? c.decode(Payload.self, forKey: .data)
        }
    }
    private struct Payload: Decodable { let state: String? }
}
