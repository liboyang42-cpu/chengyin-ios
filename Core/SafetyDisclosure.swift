import Foundation

// Reform plan v9 §15 / W09.2–W09.8: client-side safety, privacy and content contracts.
// These types present server decisions and fixed copy; none of them verifies presence,
// approves content, grants consent or decides that a node is safe.

// MARK: AI identity (W09.5)

/// Separate AI surfaces must never share disclosure or data scope (W04/G01).
public enum AIIdentitySurface: String, CaseIterable, Equatable {
    case publicMerchantNPC, themeNPC, merchantPrivateAssistant, creatorCopilot
}

/// Every AI surface shows that replies are AI-generated and cannot commit prices,
/// stock, orders, rewards or redemption — those come from the server and authorised staff.
public struct AIIdentityDisclosure: Equatable {
    public let surface: AIIdentitySurface
    public var titleKey: String { "opsSafety.ai.title" }
    public var boundaryKeys: [String] {
        // Scope lines reuse the mini-program's resident NPC notices (npc-chat) and its
        // "AI 生成内容,请核对后再发布" draft label; the boundary lines are W09.5 additions.
        var keys: [String]
        switch surface {
        case .publicMerchantNPC: keys = ["opsSafety.ai.scope.merchant"]
        case .themeNPC: keys = ["opsSafety.ai.scope.progress"]
        case .merchantPrivateAssistant, .creatorCopilot: keys = ["opsSafety.ai.scope.draft"]
        }
        keys += ["opsSafety.ai.notHuman", "opsSafety.ai.noCommitments", "opsSafety.ai.mayBeWrong"]
        switch surface {
        case .publicMerchantNPC, .themeNPC: keys.append("opsSafety.ai.storyStillCompletable")
        case .merchantPrivateAssistant, .creatorCopilot: keys.append("opsSafety.ai.draftOnly")
        }
        return keys
    }
    public init(surface: AIIdentitySurface) { self.surface = surface }
}

/// W09.6: order addresses, phone numbers and identity numbers are not sent to a model by
/// default. This screen only detects likely sensitive patterns in text the user is about
/// to send so the UI can ask before sending; it never edits, uploads or logs the text.
public enum AIOutgoingSensitiveKind: String, CaseIterable, Equatable {
    case mainlandMobile, residentIdentity, email
    public var copyKey: String { "opsSafety.ai.sensitive." + rawValue }
}

public enum AIOutgoingTextScreen {
    public static let maximumScannedUTF8 = 16_384
    public static func findings(in text: String) -> Set<AIOutgoingSensitiveKind> {
        guard text.utf8.count <= maximumScannedUTF8 else { return Set(AIOutgoingSensitiveKind.allCases) }
        // Normalise full-width digits and common separators so "138 0013 8000" is found.
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let compact = folded.replacingOccurrences(of: "[\\s\\-]", with: "", options: .regularExpression)
        var result = Set<AIOutgoingSensitiveKind>()
        if compact.range(of: "(?<![0-9])1[3-9][0-9]{9}(?![0-9])", options: .regularExpression) != nil { result.insert(.mainlandMobile) }
        if compact.range(of: "(?<![0-9])[1-9][0-9]{16}[0-9Xx](?![0-9A-Za-z])", options: .regularExpression) != nil { result.insert(.residentIdentity) }
        if folded.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) != nil { result.insert(.email) }
        return result
    }
}

/// W09.5/W09.6: binds one sensitive-text confirmation to the exact text, the current request
/// and the current account/session scope. The held text lives in memory only until it is
/// confirmed, cancelled or invalidated; it is never persisted, logged or sent by this type.
/// Any change of text, request or scope makes an earlier confirmation unusable.
public struct AIOutgoingSendGate<Scope: Equatable, Request: Equatable> {
    public enum Decision: Equatable { case proceed, confirm(Set<AIOutgoingSensitiveKind>) }
    private struct Binding { let text: String; let scope: Scope; let request: Request }
    private var pending: Binding?
    public init() {}
    public var hasPendingConfirmation: Bool { pending != nil }
    /// Screens the FINAL text. Clean text proceeds; otherwise a confirmation is armed for exactly this text.
    public mutating func evaluate(text: String, scope: Scope, request: Request) -> Decision {
        let findings = AIOutgoingTextScreen.findings(in: text)
        guard !findings.isEmpty else { pending = nil; return .proceed }
        pending = Binding(text: text, scope: scope, request: request)
        return .confirm(findings)
    }
    /// Single use. True only when text, request and scope all still match what was shown.
    public mutating func confirm(text: String, scope: Scope, request: Request) -> Bool {
        defer { pending = nil }
        guard let held = pending, held.text.utf8.elementsEqual(text.utf8),
              held.scope == scope, held.request == request else { return false }
        return true
    }
    /// Go back and edit, page exit, or account/session change.
    public mutating func cancel() { pending = nil }
}

// MARK: Offline safety (W09.8)

/// Review categories from W09.8. A server code outside this list is kept verbatim.
public enum OfflineSafetyCategory: Equatable, Hashable {
    case businessHours, night, roadTraffic, weather, restrictedArea, crowding, photoConsent, emergencyExit
    case unrecognized(String)
    static let codes: [String: OfflineSafetyCategory] = [
        "BUSINESS_HOURS": .businessHours, "NIGHT": .night, "ROAD_TRAFFIC": .roadTraffic, "WEATHER": .weather,
        "RESTRICTED_AREA": .restrictedArea, "CROWDING": .crowding, "PHOTO_CONSENT": .photoConsent, "EMERGENCY_EXIT": .emergencyExit
    ]
    public init(code: String) { self = Self.codes[code] ?? .unrecognized(code) }
    public var copyKey: String {
        switch self {
        case .businessHours: return "opsSafety.offline.businessHours"
        case .night: return "opsSafety.offline.night"
        case .roadTraffic: return "opsSafety.offline.roadTraffic"
        case .weather: return "opsSafety.offline.weather"
        case .restrictedArea: return "opsSafety.offline.restrictedArea"
        case .crowding: return "opsSafety.offline.crowding"
        case .photoConsent: return "opsSafety.offline.photoConsent"
        case .emergencyExit: return "opsSafety.offline.emergencyExit"
        case .unrecognized: return "opsSafety.offline.unrecognized"
        }
    }
}

/// A server-provided alternative. The client never synthesises a route, place or
/// coordinate; without one it shows the support entry only.
public struct OfflineAlternative: Equatable {
    public let nodeID: Int
    public let title: String
    public let requiresPurchase: Bool
}

public enum OfflineNodeSafetyState: Equatable {
    case open
    /// Stopping takes effect immediately: starting or continuing that node is unavailable.
    case stopped(categories: [OfflineSafetyCategory], alternative: OfflineAlternative?)
    case unknown

    public var permitsStart: Bool { if case .open = self { return true }; return false }
    /// W09.8 asks for a no-purchase alternative; a paid alternative is not offered as one.
    public var noPurchaseAlternative: OfflineAlternative? {
        guard case let .stopped(_, alternative?) = self, !alternative.requiresPurchase else { return nil }
        return alternative
    }
}

/// Proposed node safety envelope, pending backend review (no endpoint exists):
/// {"code":200,"data":{"nodeId":7,"status":"STOPPED","categories":["NIGHT"],
///  "alternative":{"nodeId":8,"title":"…","requiresPurchase":false}}}
public enum OfflineNodeSafetyDecoder {
    private struct Envelope: Decodable { let code: Int?; let data: Payload? }
    private struct Payload: Decodable {
        let nodeId: Int?; let status: String?; let categories: [String]?; let alternative: Alternative?
    }
    private struct Alternative: Decodable { let nodeId: Int?; let title: String?; let requiresPurchase: Bool? }
    public static func decode(_ data: Data, expectedNodeID: Int) -> OfflineNodeSafetyState {
        guard data.count <= 65_536, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.code == 200, let payload = envelope.data, payload.nodeId == expectedNodeID, expectedNodeID > 0 else { return .unknown }
        switch payload.status {
        case "OPEN": return .open
        case "STOPPED":
            let categories = (payload.categories ?? []).prefix(16).map(OfflineSafetyCategory.init(code:))
            var alternative: OfflineAlternative?
            if let raw = payload.alternative, let id = raw.nodeId, id > 0, id != expectedNodeID,
               let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 120,
               let paid = raw.requiresPurchase {
                alternative = .init(nodeID: id, title: title, requiresPurchase: paid)
            }
            return .stopped(categories: Array(categories), alternative: alternative)
        default: return .unknown
        }
    }
}

// MARK: Presence evidence (W09.2–W09.3)

/// GPS, static QR and photos are each not reliable proof of presence. The client lists
/// what it submitted; only the server combines evidence and decides.
public enum PresenceEvidenceKind: String, CaseIterable, Equatable {
    case gps, staticQR, photo, dynamicCode, serverChallenge, merchantConfirmation, deviceIntegritySignal
    /// No single kind is sufficient on its own, including device integrity signals.
    public var sufficientAlone: Bool { false }
}

/// Server review outcome. Weak GPS or accessibility needs go to review or an alternative,
/// never to an accusation: there is deliberately no "cheating" case.
public enum PresenceReviewOutcome: Equatable {
    case accepted, needsReview, alternativeOffered, unknown
    public init(code: String?) {
        switch code {
        case "ACCEPTED": self = .accepted
        case "NEEDS_REVIEW": self = .needsReview
        case "ALTERNATIVE_OFFERED": self = .alternativeOffered
        default: self = .unknown
        }
    }
    public var copyKey: String {
        switch self {
        case .accepted: return "opsSafety.presence.accepted"
        case .needsReview: return "opsSafety.presence.needsReview"
        case .alternativeOffered: return "opsSafety.presence.alternativeOffered"
        case .unknown: return "opsSafety.presence.unknown"
        }
    }
}
