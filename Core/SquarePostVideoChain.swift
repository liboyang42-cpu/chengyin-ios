import Foundation
import CryptoKit

// U01 (reform plan v9) post media chain, video half. The mini-program Square pages are image-only,
// so this is new App scope, not a parity port. Facts used here:
// - backend `CommunityPostServiceImpl.registerMedia` accepts mediaType VIDEO with objectKey, mimeType,
//   byteSize (<= 200 MiB), width, height, durationMs and a verified upload receipt;
// - the only upload transport (`POST api/common/uploadOSS`) accepts JPEG/PNG only, so no reviewed video
//   byte upload exists. Upload therefore stays unavailable; nothing here dispatches a request.

/// Read model for a registered post video (`media[]` row with media_type VIDEO).
public struct SquarePostVideo: Equatable, Identifiable {
    public let id: Int
    /// Playable object key or URL exactly as the server returned it; never rewritten to a guessed host.
    public let source: String
    public let poster: String?
    public let width: Int?
    public let height: Int?
    public let durationMilliseconds: Int?
    public let mimeType: String?
    public let review: SquareMediaReviewState
    static func rows(_ media: [SquareValue]) -> [Self] {
        media.compactMap { row in
            guard (row.first("media_type", "mediaType").string ?? "") == "VIDEO",
                  let id = row.first("id", "mediaId").integer, id > 0,
                  let source = row.first("derived_object_key", "derivedObjectKey", "object_key", "objectKey").nonempty else { return nil }
            func positive(_ value: SquareValue) -> Int? { value.integer.flatMap { $0 > 0 ? $0 : nil } }
            return .init(id: id, source: source, poster: row.first("poster_object_key", "posterObjectKey", "cover_url", "coverUrl").nonempty,
                         width: positive(row["width"]), height: positive(row["height"]),
                         durationMilliseconds: positive(row.first("duration_ms", "durationMs")),
                         mimeType: row.first("mime_type", "mimeType").nonempty,
                         review: .init(state: row.first("review_state", "reviewState").nonempty, reason: row.first("review_reason", "reviewReason").nonempty))
        }
    }
}

/// Source upload/asset review vocabulary (`reviewState`, `reviewReason`; `GET api/media/asset/{id}`).
public enum SquareMediaReviewState: Equatable {
    case approved, pending, rejected(reason: String?), unavailable, unknown
    public init(state: String?, reason: String?) {
        switch state?.uppercased() {
        case nil: self = .approved  // registered media rows without a review field are already published content
        case "APPROVED"?: self = .approved
        case "PENDING"?, "REVIEWING"?, "CHECKING"?: self = .pending
        case "REJECTED"?: self = .rejected(reason: reason)
        case "UNAVAILABLE"?: self = .unavailable
        default: self = .unknown
        }
    }
    /// Only approved media may be attached to a publish request (source: non-APPROVED fails that file).
    public var canAttach: Bool { self == .approved }
    /// Source retry path: rejected or unavailable assets may be resubmitted for review.
    public var canRequestReview: Bool { if case .rejected = self { return true }; return self == .unavailable }
}

/// Facts the App inspector reads from the actual local file (AVFoundation), never caller claims.
public struct SquarePostVideoInspection: Equatable {
    public let byteCount: Int64
    public let mimeType: String
    public let durationMilliseconds: Int64
    public let width: Int, height: Int
    public let hasVideoTrack: Bool
    public let isPlayable: Bool
    public init(byteCount: Int64, mimeType: String, durationMilliseconds: Int64, width: Int, height: Int, hasVideoTrack: Bool, isPlayable: Bool) {
        self.byteCount = byteCount; self.mimeType = mimeType; self.durationMilliseconds = durationMilliseconds
        self.width = width; self.height = height; self.hasVideoTrack = hasVideoTrack; self.isPlayable = isPlayable
    }
    public enum Rejection: Hashable { case policyUnavailable, mimeNotAllowed, noBytes, byteLimit, durationLimit, noVideoTrack, notPlayable, invalidDimensions }
    /// Checks against an injected policy. A missing video rule is `policyUnavailable`, never "unlimited".
    public func rejections(policy: SquarePostLocalMediaPolicy?) -> [Rejection] {
        guard let policy, let allowed = policy.mimeTypes[.video], !allowed.isEmpty,
              let maximumBytes = policy.maximumVideoBytes, let maximumDuration = policy.maximumVideoDurationMilliseconds else { return [.policyUnavailable] }
        var result: [Rejection] = []
        if !allowed.contains(mimeType) { result.append(.mimeNotAllowed) }
        if byteCount <= 0 { result.append(.noBytes) } else if byteCount > maximumBytes { result.append(.byteLimit) }
        if durationMilliseconds <= 0 || durationMilliseconds > maximumDuration { result.append(.durationLimit) }
        if !hasVideoTrack { result.append(.noVideoTrack) }
        if !isPlayable { result.append(.notPlayable) }
        if width <= 0 || height <= 0 || width.multipliedReportingOverflow(by: height).overflow { result.append(.invalidDimensions) }
        return result
    }
}

/// Why the upload step cannot run. Upload stays disabled until a reviewed video transport exists.
public enum SquarePostVideoUploadAvailability: Equatable {
    case unavailable(Blocker)
    public enum Blocker: String, Equatable { case noReviewedVideoUploadEndpoint, notApproved, policyUnavailable }
    /// The only existing upload transport (`api/common/uploadOSS`) is JPEG/PNG; no video endpoint is approved.
    public static func current(policy: SquarePostLocalMediaPolicy?) -> Self {
        policy?.maximumVideoBytes == nil ? .unavailable(.policyUnavailable) : .unavailable(.noReviewedVideoUploadEndpoint)
    }
}

/// Body for `POST api/v1/community/media/register` (VIDEO). Built only from an upload receipt, which no
/// current transport can produce for video; kept so a reviewed transport can be connected without guessing fields.
public struct SquarePostVideoRegistration: Equatable {
    public static let path = "api/v1/community/media/register"
    public static let serverByteCeiling: Int64 = 200 * 1024 * 1024  // registerMedia rejects larger files
    public let uploadRequestID: String
    public let objectKey: String
    public let uploadReceipt: String
    public let inspection: SquarePostVideoInspection
    public init(uploadRequestID: String, objectKey: String, uploadReceipt: String, inspection: SquarePostVideoInspection) throws {
        guard (8...80).contains(uploadRequestID.count), !objectKey.isEmpty, objectKey.count <= 500, !objectKey.contains(";"),
              !uploadReceipt.isEmpty, inspection.byteCount > 0, inspection.byteCount <= Self.serverByteCeiling,
              inspection.mimeType.hasPrefix("video/") else { throw SquarePostLocalMediaIssue.invalidMetadata }
        self.uploadRequestID = uploadRequestID; self.objectKey = objectKey; self.uploadReceipt = uploadReceipt; self.inspection = inspection
    }
    public var body: [String: Any] {
        ["uploadRequestId": uploadRequestID, "mediaType": "VIDEO", "objectKey": objectKey, "uploadReceipt": uploadReceipt,
         "mimeType": inspection.mimeType, "byteSize": inspection.byteCount, "width": inspection.width,
         "height": inspection.height, "durationMs": inspection.durationMilliseconds]
    }
}

/// Save/restore of a composer's local media list (images and videos) for one account-scoped draft.
/// Only registry references, hashes and inspected facts are stored; never file paths, bytes or URLs.
public struct SquarePostMediaDraftItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: String  // "image" | "video"
    public let registryID: UUID
    public let sha256: String
    public let byteCount: Int64
    public let mimeType: String
    public let width: Int, height: Int
    public let durationMilliseconds: Int64?
    public init(id: UUID = UUID(), kind: SquarePostLocalMediaKind, registryID: UUID, sha256: String, byteCount: Int64,
                mimeType: String, width: Int, height: Int, durationMilliseconds: Int64?) {
        self.id = id; self.kind = kind.rawValue; self.registryID = registryID; self.sha256 = sha256; self.byteCount = byteCount
        self.mimeType = mimeType; self.width = width; self.height = height; self.durationMilliseconds = durationMilliseconds
    }
    public var mediaKind: SquarePostLocalMediaKind? { SquarePostLocalMediaKind(rawValue: kind) }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public enum SquarePostMediaRestoreStatus: Equatable { case ready, missing, changed, invalid }

@MainActor public final class SquarePostMediaDraftStore {
    private struct Envelope: Codable { let version: Int; let ownerKey: String; let draftID: String; let items: [SquarePostMediaDraftItem] }
    private let storage: any SquareWorkspacePrivateStorage
    public init(storage: any SquareWorkspacePrivateStorage) { self.storage = storage }
    private func key(_ session: SquareWorkspaceSession, _ draftID: String) -> String {
        "square.postMedia.v1." + Data((session.ownerKey + "|" + draftID).utf8).base64EncodedString()
    }
    public func save(_ items: [SquarePostMediaDraftItem], session: SquareWorkspaceSession, draftID: String) throws {
        guard !draftID.isEmpty, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ $0.mediaKind != nil && $0.sha256.count == 64 && $0.byteCount > 0 }) else { throw SquarePostLocalMediaIssue.invalidMetadata }
        try storage.write(JSONEncoder().encode(Envelope(version: 1, ownerKey: session.ownerKey, draftID: draftID, items: items)), key: key(session, draftID))
    }
    /// Restores in saved order. `fileDigest` reads the App registry; nil means the local file is gone.
    public func restore(session: SquareWorkspaceSession, draftID: String,
                        fileDigest: (UUID) -> (sha256: String, byteCount: Int64)?) throws -> [(SquarePostMediaDraftItem, SquarePostMediaRestoreStatus)] {
        guard let data = try storage.read(key: key(session, draftID)) else { return [] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.ownerKey == session.ownerKey, envelope.draftID == draftID else { throw SquareWorkspaceFailure.sessionChanged }
        return envelope.items.map { item in
            guard item.mediaKind != nil else { return (item, .invalid) }
            guard let actual = fileDigest(item.registryID) else { return (item, .missing) }
            return (item, actual.sha256 == item.sha256 && actual.byteCount == item.byteCount ? .ready : .changed)
        }
    }
    public func clear(session: SquareWorkspaceSession, draftID: String) throws {
        try storage.write(JSONEncoder().encode(Envelope(version: 1, ownerKey: session.ownerKey, draftID: draftID, items: [])), key: key(session, draftID))
    }
}
