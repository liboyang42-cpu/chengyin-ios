import Foundation

public struct MerchantNPCScope: Equatable {
    public let accountID: Int
    public let namespace: String
    public let epoch: UUID
    public let merchantRowID: PublicMerchantRowID
    public let accessRevision: UUID
    public init(accountID: Int, namespace: String, epoch: UUID, merchantRowID: PublicMerchantRowID, accessRevision: UUID) {
        self.accountID = accountID; self.namespace = namespace; self.epoch = epoch; self.merchantRowID = merchantRowID; self.accessRevision = accessRevision
    }
}
public struct MerchantNPCGrants: Equatable {
    public var server = false
    public var provider = false
    public var legal = false
    public var resourceOwnership = false
    public var voiceCloning = false
    public var mediaTransmission = false
    public init() {}
    public var chatAllowed: Bool { server && provider && legal }
    public var resourceAllowed: Bool { chatAllowed && resourceOwnership && mediaTransmission }
}
public enum MerchantNPCFailure: Error, Equatable {
    case disabled, staleScope, invalid, reviewRequired, unknownOutcome, malformed
    case rejected(code: Int, message: String?)
}
public struct MerchantNPCReply: Decodable, Equatable {
    public let outcomeStatus: String
    public let safeText: String?
    public let errorCode: String?
    public let retryable: Bool?
    public let retryAfterSeconds: Int?
    public let audioUrl: String?
    public var succeeded: Bool { outcomeStatus == "SUCCEEDED" }
    public var canRetry: Bool { retryable == true || outcomeStatus == "PROCESSING" }
    public var successAudioURL: String? { succeeded ? audioUrl : nil }
}
public struct MerchantNPCVoiceScript: Decodable, Equatable {
    public let available: Bool
    public let script: [String]
    public let consentIndex: Int
    public var isUsable: Bool { available && script.count == 5 && consentIndex == 0 && script.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
/// A legacy upload URL is not a server media-registration receipt. This value records
/// provenance from an approved, scoped uploader; it does not manufacture a receipt ID.
public struct MerchantNPCMediaReference: Equatable {
    public enum Kind: Equatable { case avatarImage, voiceSample(index: Int) }
    public let scope: MerchantNPCScope
    public let selectionID: UUID
    public let kind: Kind
    public let url: URL
    public init(scope: MerchantNPCScope, selectionID: UUID, kind: Kind, url: URL, approvedHosts: Set<String>) throws {
        guard url.scheme == "https", let host = url.host, approvedHosts.contains(host), url.user == nil, url.password == nil, url.fragment == nil else { throw MerchantNPCFailure.invalid }
        self.scope = scope; self.selectionID = selectionID; self.kind = kind; self.url = url
    }
}
public enum MerchantNPCResourceAction: Equatable {
    case enroll(samples: [MerchantNPCMediaReference], requestID: UUID)
    case revoke(requestID: UUID)
    case avatar(image: MerchantNPCMediaReference, style: String)
}
public struct MerchantNPCResourceReview: Equatable, Identifiable {
    public let id: UUID
    public let scope: MerchantNPCScope
    public let action: MerchantNPCResourceAction
    public let ownsVoice: Bool
    public let explicitConsent: Bool
    public let script: MerchantNPCVoiceScript?
}
/// Enrollment/revoke responses contain msg only. They never prove resource readiness.
public enum MerchantNPCResourceReceipt: Equatable {
    case accepted(message: String?)
    case avatarJob(MerchantAvatarResource.Job)
}
public enum MerchantNPCResourceOutcome: Equatable { case idle, reviewed, sending, accepted(MerchantNPCResourceReceipt), unknown, rejected }
