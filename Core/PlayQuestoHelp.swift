import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// BE-16 hint ladder (spec UG-05..09, §十一). Source of truth: ApiPlayHelpController,
// PlayHelpViewVO{runId,nodeId,enabled,layers[]}, PlayHelpUsagePolicy.LevelView,
// PlayHelpUseVO and PlayHelpReceiptReadModel on integrate/questo-ui-20261110.
// Nothing here computes cost, quota, score or unlock state: every value is a server fact.

/// Layer form. Unknown or future types are never guessed: they render as unavailable.
public enum PlayHelpLayerType: Equatable {
    case text, image, letter, digit, answer, skip
    case unsupported(String)
    init(wire: String) {
        switch wire {
        case "TEXT": self = .text
        case "IMAGE": self = .image
        case "LETTER": self = .letter
        case "DIGIT": self = .digit
        case "ANSWER": self = .answer
        case "SKIP": self = .skip
        default: self = .unsupported(wire) // LOCATION is refused at save time; still never usable here.
        }
    }
    public var isKnown: Bool { if case .unsupported = self { return false }; return true }
    /// Localisation suffix for the layer row title.
    public var key: String {
        switch self {
        case .text: return "text"; case .image: return "image"; case .letter: return "letter"
        case .digit: return "digit"; case .answer: return "answer"; case .skip: return "skip"
        case .unsupported: return "unsupported"
        }
    }
}

/// One `layers[]` row. No hint body or answer is ever present on this surface.
public struct PlayHelpLayer: Equatable, Identifiable {
    public let level: Int
    public let type: PlayHelpLayerType
    public let usable: Bool
    public let unlocked: Bool
    public let free: Bool
    public let costPoints: Int
    /// Retired per-layer quota kept only for old runs; never shown as a run counter.
    public let legacyFreeQuota: Int
    public let reason: String?
    public var id: Int { level }

    init(raw: PlayWireValue) throws {
        guard let level = raw["level"].integer, level > 0, let type = raw["type"].text,
              let usable = raw["usable"].bool, let unlocked = raw["unlocked"].bool, let free = raw["free"].bool,
              let cost = raw["costPoints"].integer, cost >= 0 else { throw PlayExperienceError.malformed }
        self.level = level; self.type = PlayHelpLayerType(wire: type); self.usable = usable
        self.unlocked = unlocked; self.free = free; costPoints = cost
        legacyFreeQuota = max(0, raw["freeQuota"].integer ?? 0)
        let reason = raw["reason"].text
        self.reason = reason == nil || reason == "OK" ? nil : reason
    }

    /// The three button states the spec allows, plus review of an already unlocked layer.
    public enum ButtonState: Equatable {
        /// 重看 · 免费 (re-viewing never charges and never consumes the shared quota).
        case review
        /// 免费 (first unlock covered by the run's shared free quota, or explicitly priced 0).
        case free
        /// 消耗 N 积分.
        case cost(Int)
        /// Disabled with a reason; includes unknown types and SKIP rows (SKIP has its own route).
        case unavailable(String?)
        /// Earlier layer not yet unlocked: 需先看上一层.
        case needsPrevious
    }
}

/// `GET /api/play/help` (route run) or `/api/play/help/advanced` (advanced session).
public struct PlayHelpView: Equatable {
    public let runID: Int
    public let nodeID: Int
    public let enabled: Bool
    /// Author order, exactly as sent. Never re-sorted or padded.
    public let layers: [PlayHelpLayer]

    public init(data: PlayWireValue) throws {
        guard let run = data["runId"].integer, run > 0, let node = data["nodeId"].integer, node > 0,
              let enabled = data["enabled"].bool, let rows = data["layers"].array else { throw PlayExperienceError.malformed }
        let layers = try rows.map(PlayHelpLayer.init(raw:))
        guard Set(layers.map(\.level)).count == layers.count, enabled == !layers.isEmpty else { throw PlayExperienceError.malformed }
        runID = run; nodeID = node; self.enabled = enabled; self.layers = layers
    }

    /// Hint rows only. SKIP is a separate, irreversible action shown apart from the ladder.
    public var hintLayers: [PlayHelpLayer] { layers.filter { $0.type != .skip } }

    /// Skip is offered only when the frozen ladder has a usable SKIP layer. The server still decides.
    public var skipAvailable: Bool { layers.contains { $0.type == .skip && $0.usable } }

    public func state(of layer: PlayHelpLayer) -> PlayHelpLayer.ButtonState {
        guard layer.type.isKnown, layer.type != .skip else { return .unavailable(layer.reason) }
        if layer.unlocked { return .review }
        guard layer.usable else { return .unavailable(layer.reason) }
        // Layers unlock in author order: an earlier usable hint that is still locked gates this one.
        let earlier = hintLayers.prefix { $0.level != layer.level }
        if earlier.contains(where: { $0.usable && !$0.unlocked }) { return .needsPrevious }
        return layer.free || layer.costPoints == 0 ? .free : .cost(layer.costPoints)
    }
}

/// `POST /api/play/help/use` receipt. `content` is only this layer's approved content.
public struct PlayHelpUse: Equatable {
    public let runID: Int, nodeID: Int, level: Int
    public let type: PlayHelpLayerType
    public let content: String
    public let applied: Bool
    public let alreadyUnlocked: Bool
    public let chargedPoints: Int
    public let balanceAfter: Int64
    public init(data: PlayWireValue) throws {
        guard let run = data["runId"].integer, let node = data["nodeId"].integer, let level = data["level"].integer, level > 0,
              let type = data["type"].text, let content = data["content"].text,
              let applied = data["applied"].bool, let already = data["alreadyUnlocked"].bool,
              let charged = data["chargedPoints"].integer, charged >= 0, let balance = data["balanceAfter"].integer else { throw PlayExperienceError.malformed }
        runID = run; nodeID = node; self.level = level; self.type = PlayHelpLayerType(wire: type); self.content = content
        self.applied = applied; alreadyUnlocked = already; chargedPoints = charged; balanceAfter = Int64(balance)
    }
    /// Show a points line only when the server actually charged.
    public var showsCharge: Bool { chargedPoints > 0 }
}

/// `helpReceipt` (completion payload, skip payload, or the read-only receipt routes).
public struct PlayHelpReceipt: Equatable {
    public enum ScoreState: Equatable { case scored, notScored, unknown(String) }
    public struct Level: Equatable { public let level: Int; public let type: PlayHelpLayerType; public let free: Bool; public let pointsCharged: Int }
    public let scoreState: ScoreState
    /// nil whenever the server sends null (NOT_SCORED). Never substituted with 0.
    public let baseScore: Int?, bonus: Int?, helpDeduction: Int?, skipDeduction: Int?, netScore: Int?
    public let pointsCharged: Int?
    public let skipped: Bool
    public let assisted: Bool
    public let levels: [Level]
    public init(data: PlayWireValue) throws {
        guard let state = data["scoreState"].text else { throw PlayExperienceError.malformed }
        switch state { case "SCORED": scoreState = .scored; case "NOT_SCORED": scoreState = .notScored; default: scoreState = .unknown(state) }
        baseScore = data["baseScore"].integer; bonus = data["bonus"].integer
        helpDeduction = data["helpDeduction"].integer; skipDeduction = data["skipDeduction"].integer
        netScore = data["netScore"].integer; pointsCharged = data["pointsCharged"].integer
        skipped = data["skipped"].bool == true; assisted = data["assisted"].bool == true
        levels = try (data["levels"].array ?? []).map {
            guard let level = $0["level"].integer, let type = $0["type"].text else { throw PlayExperienceError.malformed }
            return Level(level: level, type: PlayHelpLayerType(wire: type), free: $0["free"].bool == true, pointsCharged: max(0, $0["pointsCharged"].integer ?? 0))
        }
    }
    /// Score rows are shown only for SCORED with a real net score. NOT_SCORED shows 本题不计分.
    public var showsScore: Bool { scoreState == .scored && netScore != nil }
}

/// Server refusal of a help write. Only `reasonCode` drives logic; `msg` is mirrored verbatim.
public struct PlayHelpRefusal: Error, Equatable {
    public let code: Int
    public let message: String?
    public let reasonCode: String?
    public var pointsInsufficient: Bool { reasonCode == "POINTS_INSUFFICIENT" }
}

/// Outcome of one help/skip write. `.unknown` keeps the original requestId for a receipt check.
public enum PlayHelpWriteOutcome<Value: Equatable>: Equatable {
    case done(Value)
    case refused(PlayHelpRefusal)
    case unknown(requestID: String)
}

/// One stable requestId per intent (run, node, level/skip). An unknown result re-reads with the
/// SAME id; only a definite server answer releases it. Switching account or run discards it.
public struct PlayHelpIntentLedger: Equatable {
    public struct Intent: Hashable { public let runID: Int; public let nodeID: Int; public let level: Int? }
    private var ids: [Intent: String] = [:]
    public init() {}
    public mutating func requestID(for intent: Intent, make: () -> String = { UUID().uuidString }) -> String {
        if let existing = ids[intent] { return existing }
        let id = make(); ids[intent] = id; return id
    }
    public func pending(_ intent: Intent) -> String? { ids[intent] }
    public mutating func settle(_ intent: Intent) { ids[intent] = nil }
    public mutating func reset() { ids = [:] }
}

/// Which run the panel speaks for. Route runs use `topic_route_session.id`; advanced runs use the
/// advanced session id. The client never sends a scope kind; the server resolves it.
public enum PlayHelpScope: Equatable {
    case route(runID: Int)
    case advanced(sessionID: Int)
}

/// Dormant adapter for /api/play/help*. Default-off like every other production play route:
/// `enabled` comes from a reviewed deployment grant, never from login.
public struct PlayHelpService {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    public let enabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
    }

    public func view(_ scope: PlayHelpScope, nodeID: Int, token: String) async throws -> PlayHelpView {
        let (path, query) = route(scope, nodeID: nodeID, suffix: "")
        guard case .done(let data) = try await send(get(path, query: query, token: token)) else { throw PlayExperienceError.unknownResult }
        let view = try PlayHelpView(data: data)
        guard view.nodeID == nodeID else { throw PlayExperienceError.malformed }
        return view
    }

    public func use(_ scope: PlayHelpScope, nodeID: Int, level: Int, requestID: String, token: String) async throws -> PlayHelpWriteOutcome<PlayHelpUse> {
        guard level > 0, Self.validRequestID(requestID) else { throw APIError.invalidRequest }
        var body = scopeBody(scope, nodeID: nodeID)
        body["level"] = .int(level); body["action"] = .string("HELP"); body["requestId"] = .string(requestID)
        let (path, _) = route(scope, nodeID: nodeID, suffix: "/use")
        switch try await send(post(path, json: body, token: token)) {
        case .done(let data):
            let use = try PlayHelpUse(data: data)
            guard use.nodeID == nodeID, use.level == level else { throw PlayExperienceError.malformed }
            return .done(use)
        case .refused(let refusal): return .refused(refusal)
        case .unknown: return .unknown(requestID: requestID)
        }
    }

    /// Skip has its own route; HELP is never rewritten as SKIP.
    public func skip(_ scope: PlayHelpScope, nodeID: Int, requestID: String, token: String) async throws -> PlayHelpWriteOutcome<PlayHelpReceipt?> {
        guard Self.validRequestID(requestID) else { throw APIError.invalidRequest }
        var body = scopeBody(scope, nodeID: nodeID); body["requestId"] = .string(requestID)
        let (path, _) = route(scope, nodeID: nodeID, suffix: "/skip")
        switch try await send(post(path, json: body, token: token)) {
        case .done(let data):
            guard data["skipped"].bool == true else { throw PlayExperienceError.malformed }
            var receipt: PlayHelpReceipt?
            if data["helpReceipt"].object != nil { receipt = try PlayHelpReceipt(data: data["helpReceipt"]) }
            return .done(receipt)
        case .refused(let refusal): return .refused(refusal)
        case .unknown: return .unknown(requestID: requestID)
        }
    }

    public func receipt(_ scope: PlayHelpScope, nodeID: Int, token: String) async throws -> PlayHelpReceipt {
        let (path, query) = route(scope, nodeID: nodeID, suffix: "/receipt")
        guard case .done(let data) = try await send(get(path, query: query, token: token)) else { throw PlayExperienceError.unknownResult }
        return try PlayHelpReceipt(data: data)
    }

    static func validRequestID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
    }

    // Route runs: /api/play/help{,/use,/skip,/receipt}; advanced: /api/play/help/advanced{,/use,/skip,/receipt}.
    private func route(_ scope: PlayHelpScope, nodeID: Int, suffix: String) -> (String, [String: String]) {
        switch scope {
        case .route(let run): return ("api/play/help" + suffix, ["runId": String(run), "nodeId": String(nodeID)])
        case .advanced(let session): return ("api/play/help/advanced" + suffix, ["sessionId": String(session), "nodeId": String(nodeID)])
        }
    }
    private func scopeBody(_ scope: PlayHelpScope, nodeID: Int) -> [String: PlayWireValue] {
        switch scope {
        case .route(let run): return ["runId": .string(String(run)), "nodeId": .string(String(nodeID))]
        case .advanced(let session): return ["sessionId": .string(String(session)), "nodeId": .string(String(nodeID))]
        }
    }
    private func base(_ path: String, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    private func get(_ path: String, query: [String: String], token: String) throws -> URLRequest {
        var request = try base(path, token: token)
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.url = components.url; request.httpMethod = "GET"; return request
    }
    private func post(_ path: String, json: [String: PlayWireValue], token: String) throws -> URLRequest {
        var request = try base(path, token: token)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(json); return request
    }

    private enum Raw { case done(PlayWireValue), refused(PlayHelpRefusal), unknown }
    /// Transport failure, non-2xx, or a malformed body after a write can follow a committed fact,
    /// so they are `.unknown` (re-check with the same requestId), never a failure.
    private func send(_ request: URLRequest) async throws -> Raw {
        guard enabled else { throw PlayExperienceError.disabled }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) } catch { return .unknown }
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        let code = envelope?["code"].tolerantInteger
        if status == 401 || code == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status), let envelope, let code else { return .unknown }
        // B5 terminal/unknown contract: 520 with receiptState PENDING/UNKNOWN is still unknown.
        if code == 520 || ["PENDING", "UNKNOWN"].contains(envelope["receiptState"].text ?? "") { return .unknown }
        guard code == 200 else {
            return .refused(PlayHelpRefusal(code: code, message: envelope["msg"].text, reasonCode: envelope["reasonCode"].text))
        }
        return .done(envelope["data"])
    }
}
