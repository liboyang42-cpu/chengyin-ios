import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An independently reviewed composition exit, never the generic HTTP route.
/// Conformance does not grant access: the concrete composition must recheck its
/// current deployment, owner and separately issued backpack approval at dispatch.
@MainActor public protocol PlayThemeBackpackTransport: HTTPTransport {
    func sendThemeBackpackRead(_ request: URLRequest, session: PlayExperienceSession,
                              scope: PlaySessionScope, topicID: Int) async throws -> (Data, Int)
    func sendThemeBackpackWrite(_ request: URLRequest,
                               permit: PlayThemeBackpackDispatchPermit) async throws -> (Data, Int)
}

/// The one canonical state read. GET may advance server state, so it is covered
/// by the dedicated backpack acceptance rather than an arbitrary `.reads` flag.
public enum PlayThemeBackpackReadRoute {
    public static func validate(_ request: URLRequest, baseURL: URL, session: PlayExperienceSession,
                                scope: PlaySessionScope, topicID: Int) throws {
        guard scope.isValid, topicID > 0, request.httpMethod == "GET",
              request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(session.token.utf8),
              let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 2 || items.count == 3,
              items.allSatisfy({ $0.value != nil }),
              Set(items.map(\.name)).count == items.count,
              Set(items.map(\.name)).isSubset(of: ["activityId", "topicId", "sessionId"]) else {
            throw APIError.invalidRequest
        }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        let activityID: Int
        switch scope {
        case .activity(let id): activityID = id
        case .topic(let id):
            guard id == topicID else { throw APIError.invalidRequest }
            activityID = 0
        }
        guard fields["topicId"] == String(topicID),
              fields["activityId"] == String(activityID) else { throw APIError.invalidRequest }
        var canonicalFields = ["topicId": String(topicID), "activityId": String(activityID)]
        if let value = fields["sessionId"] {
            guard let id = Int(value), id > 0, String(id) == value else { throw APIError.invalidRequest }
            canonicalFields["sessionId"] = value
        }
        var canonical = URLComponents(url: baseURL.appendingPathComponent("api/play/theme/state"), resolvingAgainstBaseURL: false)
        canonical?.queryItems = canonicalFields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let expected = canonical?.url,
              expected.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) else { throw APIError.invalidRequest }
    }
}

/// A non-publicly constructible, one-use exit ticket for the exact durable POST.
/// No public flag, protocol implementation or injected storage confers provenance.
@MainActor public final class PlayThemeBackpackDispatchPermit {
    public let session: PlayExperienceSession
    public let scope: PlaySessionScope
    public let topicID: Int
    public let requiresCompletedReceive: Bool
    private let snapshot: PlayThemeBackpackRecoverySnapshot
    private let recovery: PlayThemeBackpackRecoveryStore
    private let endpoint: URL
    private let ownerCurrent: () throws -> Void
    private var consumed = false

    init(session: PlayExperienceSession, snapshot: PlayThemeBackpackRecoverySnapshot,
         recovery: PlayThemeBackpackRecoveryStore, baseURL: URL,
         checkCurrent: @escaping () throws -> Void) {
        self.session = session; self.snapshot = snapshot; self.recovery = recovery
        scope = snapshot.value.intent.scope; topicID = snapshot.value.intent.topicID
        requiresCompletedReceive = snapshot.value.intent.requiresCompletedReceive
        endpoint = baseURL; ownerCurrent = checkCurrent
    }

    /// Called again by the composition after the response, before it can be shown.
    public func checkCurrent() throws {
        try ownerCurrent()
        try Task.checkCancellation()
    }

    public func consume(request: URLRequest, baseURL: URL, session: PlayExperienceSession) async throws {
        // Failure consumes this ticket too. A new attempt needs a new service-owned
        // permit and must still match the one persisted dispatch generation.
        guard !consumed else { throw PlayExperienceError.invalidAction }
        consumed = true
        try checkCurrent()
        let intent = snapshot.value.intent
        try intent.validate()
        guard session == self.session, intent.owner.matches(session),
              intent.scope == scope, intent.topicID == topicID,
              endpoint.absoluteString.utf8.elementsEqual(baseURL.absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.httpBody == intent.body,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(session.token.utf8),
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              baseURL.appendingPathComponent("api/play/theme/action").absoluteString.utf8.elementsEqual(url.absoluteString.utf8) else {
            throw PlayExperienceError.invalidAction
        }
        guard recovery.permitsSystemDispatch(to: baseURL), snapshot.value.state == .dispatching,
              snapshot.value.dispatchProcess == recovery.processID else { throw PlayExperienceError.persistenceUnavailable }
        try checkCurrent()
        guard try await recovery.read() == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        try checkCurrent()
    }
}
