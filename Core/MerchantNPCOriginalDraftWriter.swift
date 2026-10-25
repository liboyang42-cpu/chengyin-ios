import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original draft writer for the NPC author flow.
/// Calls the existing theme-draft submit, then the existing read.
///
/// Submit path is `ApiAiController.themeDraft`: class `@RequestMapping("/api/ai")`
/// plus `@PostMapping("/theme/draft")`. This is not a second path.
/// The body sends the request id this flow already holds and the four fields
/// already on the draft: name, greeting, persona, and knowledge.
///
/// A request id kept locally is not server acceptance. The read is
/// `MerchantNPCThemeDraftRequestRead` and uses only the request id the submit
/// response returned. A response that does not return one does not fall back
/// to the held id, a new UUID, or a hand-filled id.
/// A response that is not acceptance returns no receipt and does not publish.
/// A missing publisher does not publish the NPC.
@MainActor public final class MerchantNPCOriginalDraftWriter {
    public static let path = "api/ai/theme/draft"

    private struct Submission {
        let request: URLRequest
        let memberID: Int64
        let token: String
        let name: String
        let greeting: String
        let persona: String
        let knowledge: String
    }

    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let reader: MerchantNPCThemeDraftRequestRead
    private let memberID: () -> Int64?
    private let token: () -> String?

    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                reader: MerchantNPCThemeDraftRequestRead,
                memberID: @escaping () -> Int64?, token: @escaping () -> String?) {
        self.configuration = configuration
        self.transport = transport
        self.reader = reader
        self.memberID = memberID
        self.token = token
    }

    /// POST the held draft, then read with the request id the response returned.
    /// Returns the existing read's fact only when that response is acceptance.
    /// Does not invent a receipt and does not publish.
    public func submitHeldDraftThenRead(_ flow: MerchantNPCKnowledgeAuthorFlow) async throws -> MerchantNPCDraftReadFact? {
        guard let prepared = try makeSubmission(flow) else { return nil }
        let previous = flow.heldThemeDraftRequestID
        let response = try await transport.send(prepared.request)
        guard memberID() == prepared.memberID, token() == prepared.token,
              flow.heldThemeDraftMemberID == prepared.memberID,
              flow.authored?.name.value == prepared.name,
              flow.authored?.greeting.value == prepared.greeting,
              flow.authored?.persona.value == prepared.persona,
              flow.authored?.knowledge.value == prepared.knowledge else {
            return nil
        }
        guard let returned = Self.returnedRequestID(body: response.0, status: response.1),
              flow.holdThemeDraftRequest(memberID: prepared.memberID, requestID: returned) else {
            return nil
        }
        var fact: MerchantNPCDraftReadFact?
        do {
            fact = try await reader.readAndRecover(flow)
        } catch {
            if !Self.isAcceptance(body: response.0, status: response.1, requestID: returned), let previous {
                _ = flow.holdThemeDraftRequest(memberID: prepared.memberID, requestID: previous)
            }
            throw error
        }
        guard Self.isAcceptance(body: response.0, status: response.1, requestID: returned) else {
            if let previous {
                _ = flow.holdThemeDraftRequest(memberID: prepared.memberID, requestID: previous)
            }
            return nil
        }
        return fact
    }

    /// The id this flow already holds, plus the four field values already on the draft.
    private func makeSubmission(_ flow: MerchantNPCKnowledgeAuthorFlow) throws -> Submission? {
        guard let held = flow.heldThemeDraftRequestID,
              MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(held),
              let member = flow.heldThemeDraftMemberID, member > 0,
              let loggedIn = memberID(), loggedIn == member,
              let credential = token(), AuthRequestBuilder.isValidToken(credential),
              let authored = flow.authored else { return nil }
        let name = authored.name.value
        let greeting = authored.greeting.value
        let persona = authored.persona.value
        let knowledge = authored.knowledge.value
        let payload: [String: String] = [
            "requestId": held,
            "name": name,
            "greeting": greeting,
            "persona": persona,
            "knowledge": knowledge
        ]
        guard let request = try makeRequest(token: credential, payload: payload) else { return nil }
        return Submission(request: request, memberID: member, token: credential,
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
        guard let url = components.url, url.path == "/" + Self.path else { return nil }
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

    /// Top-level `requestId` from `ApiAiController.themeDraft`. Nested ids are not this field.
    private static func returnedRequestID(body: Data, status: Int) -> String? {
        guard status > 0, body.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let requestID = object["requestId"] as? String,
              MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(requestID) else { return nil }
        return requestID
    }

    /// Acceptance is the submit response itself: HTTP success, business code 200,
    /// `requestState` SUCCEEDED, and the same top-level request id. Anything else is not a receipt.
    private static func isAcceptance(body: Data, status: Int, requestID: String) -> Bool {
        guard (200..<300).contains(status), body.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["code"] as? Int == 200,
              object["errorCode"] == nil,
              object["requestState"] as? String == "SUCCEEDED",
              object["requestId"] as? String == requestID,
              MerchantNPCKnowledgeAuthorFlow.isThemeDraftRequestID(requestID) else { return false }
        return true
    }
}
