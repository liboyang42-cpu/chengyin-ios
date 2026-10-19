import Foundation
import CryptoKit

/// Reform plan v9 U01: professional-topic image/video media is accepted per stage. Selection and local
/// processing exist; every remote stage stays unavailable until a topic-level upload / moderation /
/// readback contract is reviewed and its endpoint is placed on the per-market allowlist (currently empty).
/// Mini-program pages/publish/fabu has no video field; video URLs never go into `imgUrl` / `imgArr`.
public enum ProjectTopicMediaStage: String, CaseIterable, Equatable, Sendable {
    case selection, processing, upload, moderation, save, recovery, read, playback
}

public enum ProjectTopicMediaStageStatus: String, Equatable, Sendable {
    /// Implemented locally; not proof of a remote publish.
    case localOnly
    /// Code path exists but is switched off by configuration.
    case disabled
    /// No reviewed server contract exists; nothing may be invented.
    case noContract
}

public enum ProjectTopicMediaUploadBlock: Equatable, Sendable {
    case noReviewedEndpoint, disabledByConfiguration, emptySelection, awaitingReadback
}

/// Stable identity for one confirmed local selection. The same draft + bytes always yields the same
/// request ID, so a retry after an uncertain outcome reuses it instead of creating a duplicate asset.
public struct ProjectTopicMediaUploadRequest: Equatable, Sendable {
    public let requestID: String
    public let kinds: [ProjectTopicMediaKind]
    public let digests: [String]
}

public struct ProjectTopicMediaUploadPlan: Equatable {
    public enum Outcome: Equatable { case none, uncertain(requestID: String) }
    /// Exact reviewed upload path for the active market. Nil while the allowlist is empty.
    public let approvedUploadPath: String?
    public let uploadEnabled: Bool
    public private(set) var outcome: Outcome = .none

    public init(approvedUploadPath: String? = nil, uploadEnabled: Bool = false) {
        self.approvedUploadPath = approvedUploadPath; self.uploadEnabled = uploadEnabled
    }

    public static func status(of stage: ProjectTopicMediaStage) -> ProjectTopicMediaStageStatus {
        switch stage {
        case .selection, .processing, .recovery: return .localOnly
        case .upload: return .disabled
        case .moderation, .save, .read, .playback: return .noContract
        }
    }

    public static func request(for items: [ProjectTopicMediaFacts], identity: ProjectEditDraftIdentity) -> ProjectTopicMediaUploadRequest? {
        guard !items.isEmpty, items.allSatisfy({ ProjectTopicMediaFacts.validDigest($0.contentSHA256) }) else { return nil }
        let owner = identity.topicID.map { "topic:\($0)" } ?? "draft:" + (identity.draftUUID ?? "")
        let material = ([owner] + items.map { $0.kind.rawValue + ":" + $0.contentSHA256 }).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(requestID: "topic-media-" + digest.prefix(32), kinds: items.map(\.kind), digests: items.map(\.contentSHA256))
    }

    /// Why an upload cannot start now. Nil only when a reviewed endpoint, an enabled flag, a non-empty
    /// selection and no unresolved prior attempt all hold.
    public func block(for request: ProjectTopicMediaUploadRequest?) -> ProjectTopicMediaUploadBlock? {
        guard let request else { return .emptySelection }
        if case .uncertain(let pending) = outcome, pending == request.requestID { return .awaitingReadback }
        guard let path = approvedUploadPath, !path.isEmpty else { return .noReviewedEndpoint }
        guard uploadEnabled else { return .disabledByConfiguration }
        return nil
    }

    /// A transport loss after send leaves the result unknown; the next step must be a readback, not a resend.
    public mutating func markUncertain(_ request: ProjectTopicMediaUploadRequest) { outcome = .uncertain(requestID: request.requestID) }
    /// Only a readback that names the same request ID may clear the uncertain state.
    public mutating func resolveReadback(requestID: String) {
        if case .uncertain(let pending) = outcome, pending == requestID { outcome = .none }
    }
}
