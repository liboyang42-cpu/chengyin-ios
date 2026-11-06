import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exclusive caller for the existing theme-draft request read.
/// Sends GET `api/ai/theme/draft/request?requestId=` with the request id already held by
/// `MerchantNPCKnowledgeAuthorFlow` and the logged-in member token.
/// A hit is passed into `recoverFromDraftRead` only when the returned request id and member id match.
/// A mismatch or `NOT_FOUND` leaves the phase unchanged and does not publish.
/// This type does not POST a theme draft, does not call the model, does not change quota,
/// does not publish, and does not invent a request id.
/// An invalid request id is rejected before the read.
@MainActor public final class MerchantNPCThemeDraftRequestRead {
    public static let path = "api/ai/theme/draft/request"
    public static let notFound = "NOT_FOUND"

    private struct Hit: Equatable {
        let memberID: Int64
        let requestID: String
        let state: String
    }

    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let memberID: () -> Int64?
    private let token: () -> String?

    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                memberID: @escaping () -> Int64?, token: @escaping () -> String?) {
        self.configuration = configuration
        self.transport = transport
        self.memberID = memberID
        self.token = token
    }

    /// Read the held request. Returns a fact only for a matching hit. Does not publish.
    public func readAndRecover(_ flow: MerchantNPCKnowledgeAuthorFlow) async throws -> MerchantNPCDraftReadFact? {
        guard let heldMember = flow.heldThemeDraftMemberID, heldMember > 0,
              let heldRequest = flow.heldThemeDraftRequestID,
              MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(heldRequest),
              let loggedIn = memberID(), loggedIn == heldMember,
              let credential = token(), AuthRequestBuilder.isValidToken(credential) else {
            return nil
        }
        let response = try await send(requestID: heldRequest, token: credential)
        guard memberID() == loggedIn, token() == credential,
              flow.heldThemeDraftMemberID == heldMember, flow.heldThemeDraftRequestID == heldRequest else {
            return try miss(flow, memberID: heldMember, requestID: heldRequest)
        }
        guard let hit = Self.matched(body: response.0, status: response.1, memberID: loggedIn, requestID: heldRequest) else {
            return try miss(flow, memberID: heldMember, requestID: heldRequest)
        }
        return try flow.recoverFromDraftRead(memberID: hit.memberID, requestID: hit.requestID, read: { member, id in
            guard member == hit.memberID, id == hit.requestID, hit.state != Self.notFound else { return nil }
            return MerchantNPCDraftReadFact(requestID: id, state: hit.state)
        })
    }

    private func miss(_ flow: MerchantNPCKnowledgeAuthorFlow, memberID: Int64, requestID: String) throws -> MerchantNPCDraftReadFact? {
        try flow.recoverFromDraftRead(memberID: memberID, requestID: requestID, read: { _, _ in nil })
    }

    private func send(requestID: String, token: String) async throws -> (Data, Int) {
        guard MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(requestID),
              let request = makeRequest(requestID: requestID, token: token) else {
            throw APIError.invalidRequest
        }
        return try await transport.send(request)
    }

    private func makeRequest(requestID: String, token: String) -> URLRequest? {
        guard MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(requestID),
              AuthRequestBuilder.isValidToken(token),
              var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let prefix = components.path == "/" ? "" : components.path
        guard !prefix.split(separator: "/").contains("..") else { return nil }
        components.path = prefix + "/" + Self.path
        components.queryItems = [URLQueryItem(name: "requestId", value: requestID)]
        guard let url = components.url, url.path == "/" + Self.path else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }

    /// A hit requires the returned request id and member id to match the held pair.
    /// `NOT_FOUND` is not a hit. When the body omits memberId, the member the server
    /// scoped this read to is the logged-in member whose token was sent.
    private static func matched(body: Data, status: Int, memberID: Int64, requestID: String) -> Hit? {
        guard (200..<300).contains(status), body.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["code"] as? Int == 200,
              let data = object["data"] as? [String: Any],
              let returnedRequest = data["requestId"] as? String, returnedRequest == requestID,
              let state = data["state"] as? String, !state.isEmpty, state != notFound else { return nil }
        let returnedMember: Int64
        if data.keys.contains("memberId") {
            guard let parsed = exactMember(data["memberId"]), parsed == memberID else { return nil }
            returnedMember = parsed
        } else {
            returnedMember = memberID
        }
        guard returnedMember == memberID, returnedMember > 0 else { return nil }
        return Hit(memberID: returnedMember, requestID: returnedRequest, state: state)
    }

    private static func exactMember(_ value: Any?) -> Int64? {
        if let number = value as? Int { return Int64(exactly: number).flatMap { $0 > 0 ? $0 : nil } }
        if let number = value as? Int64 { return number > 0 ? number : nil }
        if let text = value as? String {
            guard let parsed = Int64(text), parsed > 0, String(parsed) == text else { return nil }
            return parsed
        }
        if let number = value as? NSNumber {
            let parsed = number.int64Value
            guard parsed > 0, number.stringValue == String(parsed) else { return nil }
            return parsed
        }
        return nil
    }
}
