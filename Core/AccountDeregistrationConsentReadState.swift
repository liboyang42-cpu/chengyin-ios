import Foundation

/// Local journal projection only. It makes no claim about a server result, realm or version.
public enum AccountDeregistrationConsentReadState: Equatable {
    case unread
    case none
    case unknown(requestID: String)
    case unavailable

    public var allowsNewConsent: Bool { self == .none }
    public var requestID: String? {
        if case .unknown(let requestID) = self { return requestID }
        return nil
    }
    public var messageKey: String {
        switch self {
        case .unread: return "cancellationConsent.unread"
        case .none: return "cancellationConsent.none"
        case .unknown: return "cancellationConsent.unknown"
        case .unavailable: return "cancellationConsent.unavailable"
        }
    }
}

/// The original consent POST contract; no application receipt or invented actor fields.
/// occurredAt is non-identity metadata and is deliberately not parsed or used to settle.
struct AccountDeregistrationConsentACK: Decodable {
    let requestID: String
    let docType: String
    let docVersion: String
    let scene: String
    let eventType: String

    private enum CodingKeys: String, CodingKey {
        case requestId, docType, docVersion, scene, eventType, scopeType, scopeId
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try fields.decode(String.self, forKey: .requestId)
        docType = try fields.decode(String.self, forKey: .docType)
        docVersion = try fields.decode(String.self, forKey: .docVersion)
        scene = try fields.decode(String.self, forKey: .scene)
        eventType = try fields.decode(String.self, forKey: .eventType)
        // Reject every actual value, including empty strings, zero, booleans and wrong types.
        for key in [CodingKeys.scopeType, .scopeId] where fields.contains(key) {
            guard try fields.decodeNil(forKey: key) else { throw ComplianceFailure.readbackMismatch }
        }
    }
    @MainActor func confirm(requestID expectedID: String, displayedVersion: String) throws -> ComplianceConsent {
        guard AccountDeregistrationOriginalClient.validUUID(expectedID),
              requestID.utf8.elementsEqual(expectedID.utf8),
              docType == "account_cancellation_notice", scene == "account_cancel", eventType == "AGREE",
              !displayedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              docVersion.utf8.elementsEqual(displayedVersion.utf8) else { throw ComplianceFailure.readbackMismatch }
        return ComplianceConsent(docType: docType, docVersion: docVersion, scene: scene,
                                 scopeType: nil, scopeId: nil, eventType: eventType, occurredAt: nil)
    }
}
