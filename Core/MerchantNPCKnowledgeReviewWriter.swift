import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Knowledge-review writer for `MerchantNPCOriginalReviewPublishing`.
///
/// This is the contract being written, not a route discovered in the supplied sources.
/// `POST api/merchant/npc/knowledge-review` sends the request id the caller already
/// passed and the four draft fields name, greeting, persona, and knowledge.
/// The call uses the held https `APIConfiguration` and the logged-in member token.
/// The token is the Authorization header. It is not placed in the URL.
///
/// A POST is accepted only when its requestId equals the submitted id and the member
/// matches. After that acceptance, this sends
/// `GET api/merchant/npc/knowledge-review/request?requestId=` with that same request id.
/// The token stays in the Authorization header and is not placed in the URL.
/// The GET success envelope is parsed for requestId, memberId, name, greeting,
/// persona, and knowledge. The four fields are recovered only when the returned
/// requestId equals the submitted id and the member id matches. Any other body
/// leaves the read closed and does not publish. A missing requestId does not fall back to the submitted id.
/// A missing memberId does not fall back to the logged-in
/// member. This does not mint a second id.
///
/// `publishApproved` throws waitingSource for `MerchantNpcKnowledgeDraftService.http`
/// and does not send a publish request. A nil approval is not published.
/// Missing review permission does not publish.
///
/// This type does not call `POST api/ai/theme/draft`, `POST api/merchant/npc/save`,
/// `api/merchant/npc/save/result`, or merchant authoring generate/createDraft.
/// It does not wrap `MerchantNPCOriginalDraftWriter` or `MerchantNPCThemeDraftRequestRead`.
@MainActor public final class MerchantNPCKnowledgeReviewWriter: MerchantNPCOriginalReviewPublishing {
    /// Contract being written. Not a discovered route.
    public static let path = "api/merchant/npc/knowledge-review"
    /// Read of the request this POST accepted. The query is the same request id.
    public static let readPath = "api/merchant/npc/knowledge-review/request"

    private struct Submission {
        let request: URLRequest
        let memberID: Int64
        let token: String
        let requestID: UUID
        let name: String
        let greeting: String
        let persona: String
        let knowledge: String
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

    /// POST the four draft fields and the given request id. After acceptance, GET that request.
    /// Does not publish.
    public func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
        guard let prepared = try makeSubmission(draft, requestID: requestID, scope: scope) else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        let response: (Data, Int)
        do {
            response = try await transport.send(prepared.request)
        } catch {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        guard memberID() == prepared.memberID, token() == prepared.token,
              Self.matches(body: response.0, status: response.1, requestID: prepared.requestID.uuidString, memberID: prepared.memberID),
              let readRequest = makeReadRequest(token: prepared.token, requestID: prepared.requestID) else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        let read: (Data, Int)
        do {
            read = try await transport.send(readRequest)
        } catch {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        guard memberID() == prepared.memberID, token() == prepared.token,
              Self.recovered(body: read.0, status: read.1, requestID: prepared.requestID.uuidString, memberID: prepared.memberID,
                             name: prepared.name, greeting: prepared.greeting, persona: prepared.persona, knowledge: prepared.knowledge) else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        let facts = (try? draft.validatedPublicFactsJSON()) ?? Data([prepared.name, prepared.greeting, prepared.persona, prepared.knowledge].joined(separator: "\n").utf8)
        return MerchantNPCOriginalReviewTicket(requestID: requestID, scope: scope, factsHash: MerchantNPCDraftDigest.hex(facts))
    }

    /// Missing review permission and a nil approval do not publish. No publish request is sent.
    public func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
        _ = ticket.requestID
        _ = scope.accountID
        throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
    }

    /// JSON keys are the given request id and the four draft fields. Does not POST when one is missing.
    private func makeSubmission(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) throws -> Submission? {
        guard scope.accountID > 0,
              let member = memberID(), member > 0,
              let credential = token(), AuthRequestBuilder.isValidToken(credential),
              let name = Self.field(draft, "name"),
              let greeting = Self.field(draft, "greeting"),
              let persona = Self.field(draft, "persona"),
              let knowledge = Self.field(draft, "knowledge") else { return nil }
        let payload: [String: String] = [
            "requestId": requestID.uuidString,
            "name": name,
            "greeting": greeting,
            "persona": persona,
            "knowledge": knowledge
        ]
        guard let request = try makeRequest(token: credential, payload: payload) else { return nil }
        return Submission(request: request, memberID: member, token: credential, requestID: requestID,
                          name: name, greeting: greeting, persona: persona, knowledge: knowledge)
    }

    private func makeRequest(token: String, payload: [String: String]) throws -> URLRequest? {
        guard AuthRequestBuilder.isValidToken(token),
              var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let prefix = components.path == "/" ? "" : components.path
        guard !prefix.split(separator: "/").contains("..") else { return nil }
        components.path = prefix + "/" + Self.path
        components.queryItems = nil
        guard let url = components.url, url.path == "/" + Self.path, url.query == nil,
              !url.absoluteString.contains(token) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }

    /// GET the accepted request. The query is only requestId. The token is not in the URL.
    private func makeReadRequest(token: String, requestID: UUID) -> URLRequest? {
        guard AuthRequestBuilder.isValidToken(token),
              var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let prefix = components.path == "/" ? "" : components.path
        guard !prefix.split(separator: "/").contains("..") else { return nil }
        components.path = prefix + "/" + Self.readPath
        components.queryItems = [URLQueryItem(name: "requestId", value: requestID.uuidString)]
        guard let url = components.url, url.path == "/" + Self.readPath,
              !url.absoluteString.contains(token) else { return nil }
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

    /// Acceptance is the written contract: HTTP 200..<300, top-level code 200, and data.requestId
    /// plus data.memberId equal to the submitted pair. A different id is not a ticket.
    private static func matches(body: Data, status: Int, requestID: String, memberID: Int64) -> Bool {
        guard (200..<300).contains(status), body.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["code"] as? Int == 200,
              object["errorCode"] == nil,
              let data = object["data"] as? [String: Any],
              let returned = data["requestId"] as? String, returned == requestID,
              let member = exactMember(data["memberId"]), member == memberID, member > 0 else { return false }
        return true
    }

    /// The four posted fields, and only when this body is the success envelope for that request and member.
    /// Any other body is not a recovery.
    private static func recovered(body: Data, status: Int, requestID: String, memberID: Int64,
                                  name: String, greeting: String, persona: String, knowledge: String) -> Bool {
        guard (200..<300).contains(status), body.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["code"] as? Int == 200,
              object["errorCode"] == nil,
              let data = object["data"] as? [String: Any],
              let returned = data["requestId"] as? String, returned == requestID,
              let member = exactMember(data["memberId"]), member == memberID, member > 0,
              data["name"] as? String == name,
              data["greeting"] as? String == greeting,
              data["persona"] as? String == persona,
              data["knowledge"] as? String == knowledge else { return false }
        return true
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

    /// One FAQ row per field, the values already on the draft. A duplicate or a missing field is not invented.
    private static func field(_ draft: MerchantNPCKnowledgeDraft, _ name: String) -> String? {
        var found: String?
        for row in draft.faq where row.question == name {
            guard found == nil else { return nil }
            found = row.answer
        }
        return found
    }
}
