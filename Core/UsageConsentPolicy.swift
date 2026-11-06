import Foundation

/// Mini-program app.js + utils/compliance/usage-consent.js: before sign-in the user sees a
/// privacy gate (暂不同意 / 同意并继续) with an unchecked agreement checkbox. Agreeing stores
/// the document versions locally; declining keeps guest browsing without any sign-in.
/// A version bump makes the stored choice stale, so the gate shows again.
public enum UsageConsentDocument: String, CaseIterable, Codable {
    case privacyPolicy = "privacy_policy"
    case userServiceAgreement = "user_service_agreement"

    /// Versions the mini-program stores (cy_usage_choice_v1) and the server whitelists for
    /// scene app_launch. The server remains authoritative and rejects a stale version.
    public var currentVersion: String {
        switch self {
        case .privacyPolicy: return "v2.1"
        case .userServiceAgreement: return "v2.2"
        }
    }
}

public protocol UsageConsentStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Data?, forKey key: String)
}

public enum UsageConsentFailure: Error, Equatable {
    /// Mini-program: 请先阅读并勾选用户服务协议
    case agreementNotChecked
}

/// One AGREE record per document for scene app_launch, with a request ID that stays
/// stable across relaunches until the server confirms it (uncertain outcomes reuse it).
public struct UsageConsentRecordRequest: Equatable {
    public let accountID: Int
    public let document: UsageConsentDocument
    public let requestID: String
    public let scene = "app_launch"
    public let eventType = "AGREE"
}

public final class UsageConsentPolicy {
    static let choiceKey = "questify.usageConsent.choice.v1"
    static func pendingKey(accountID: Int) -> String { "questify.usageConsent.pending.v1." + String(accountID) }

    /// Live recording goes through /api/compliance/consents, which is not on the reviewed
    /// per-market endpoint allowlist. Until it is, records are planned but never dispatched.
    public static let liveRecordingApproved = false

    private let storage: UsageConsentStorage
    private let makeRequestID: () -> String
    public init(storage: UsageConsentStorage, makeRequestID: @escaping () -> String = { "consent-" + UUID().uuidString.lowercased() }) {
        self.storage = storage; self.makeRequestID = makeRequestID
    }

    private var storedChoice: [String: String]? {
        guard let data = storage.data(forKey: Self.choiceKey) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Granted only when every current document version matches what was agreed.
    public var granted: Bool {
        guard let choice = storedChoice else { return false }
        return UsageConsentDocument.allCases.allSatisfy { choice[$0.rawValue] == $0.currentVersion }
    }

    public func agree(agreementChecked: Bool) throws {
        guard agreementChecked else { throw UsageConsentFailure.agreementNotChecked }
        let choice = Dictionary(uniqueKeysWithValues: UsageConsentDocument.allCases.map { ($0.rawValue, $0.currentVersion) })
        storage.set(try? JSONEncoder().encode(choice), forKey: Self.choiceKey)
    }

    /// Mini-program declineUsageConsent removes the stored choice; browsing stays available.
    public func decline() { storage.set(nil, forKey: Self.choiceKey) }

    /// Records still owed to the server for this account. Request IDs persist per account and
    /// document, so a lost response is retried with the same ID instead of a new record.
    public func pendingRecords(accountID: Int) -> [UsageConsentRecordRequest] {
        guard granted, accountID > 0 else { return [] }
        var ids = pendingIDs(accountID: accountID)
        var changed = false
        let requests = UsageConsentDocument.allCases.map { document -> UsageConsentRecordRequest in
            if ids[document.rawValue] == nil { ids[document.rawValue] = makeRequestID(); changed = true }
            return UsageConsentRecordRequest(accountID: accountID, document: document, requestID: ids[document.rawValue]!)
        }
        if changed { storage.set(try? JSONEncoder().encode(ids), forKey: Self.pendingKey(accountID: accountID)) }
        return requests.filter { !confirmed(accountID: accountID).contains($0.document.rawValue) }
    }

    /// Only an exact server echo of the same request ID, document, scene and current version confirms.
    public func confirm(_ request: UsageConsentRecordRequest, echoedRequestID: String?, echoedDocType: String?,
                        echoedScene: String?, echoedVersion: String?) -> Bool {
        guard echoedRequestID == request.requestID, echoedDocType == request.document.rawValue,
              echoedScene == request.scene, echoedVersion == request.document.currentVersion else { return false }
        var ids = pendingIDs(accountID: request.accountID)
        ids["confirmed." + request.document.rawValue] = request.requestID
        storage.set(try? JSONEncoder().encode(ids), forKey: Self.pendingKey(accountID: request.accountID))
        return true
    }

    private func pendingIDs(accountID: Int) -> [String: String] {
        guard let data = storage.data(forKey: Self.pendingKey(accountID: accountID)) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private func confirmed(accountID: Int) -> Set<String> {
        Set(pendingIDs(accountID: accountID).keys.filter { $0.hasPrefix("confirmed.") }.map { String($0.dropFirst("confirmed.".count)) })
    }
}

/// Decides whether the launch gate is shown. Signed-in restorations are not interrupted;
/// declining once keeps the gate closed until the next launch or an explicit sign-in attempt.
public enum UsageConsentGateDecision {
    public static func showAtLaunch(granted: Bool, signedIn: Bool, declinedThisLaunch: Bool) -> Bool {
        !granted && !signedIn && !declinedThisLaunch
    }
    public static func signInRequiresGate(granted: Bool) -> Bool { !granted }
}
