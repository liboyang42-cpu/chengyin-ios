import Foundation
import CryptoKit

public enum SquarePostLocalMediaKind: String, Equatable, Hashable { case image, video }

/// A reference/version in the caller's owned local-file registry, never a URL or path.
/// Core does not verify that registry or decode a file; byte-bound metadata remains pending App decoding.
public struct SquarePostLocalMediaReference: Equatable, Hashable {
    public let id: UUID
    public let version: UUID
    public init(id: UUID = UUID(), version: UUID = UUID()) { self.id = id; self.version = version }
}

public enum SquarePostLocalMediaIssue: Error, Equatable {
    case closed, stale, invalidScope, invalidPolicy, invalidMetadata, wrongReference, wrongKind
    case noBytes, byteCountMismatch, byteCountOverflow, sourceBytesChanged, byteLimit, finished
    case itemLimit, imageLimit, videoLimit, mixedKinds, kindNotAllowed, mimeNotAllowed, durationLimit
    case inspectionFailed
}

enum SquarePostLocalMediaArithmetic {
    static func adding(_ current: Int64, _ increment: Int64) throws -> Int64 {
        guard current >= 0, increment >= 0 else { throw SquarePostLocalMediaIssue.invalidMetadata }
        let result = current.addingReportingOverflow(increment)
        guard !result.overflow else { throw SquarePostLocalMediaIssue.byteCountOverflow }
        return result.partialValue
    }
}

public struct SquarePostLocalMediaScope: Equatable {
    public let session: SquareWorkspaceSession
    public let draftID: String
    public let lane: SquareWorkspaceLane
    public init(session: SquareWorkspaceSession, draftID: String, lane: SquareWorkspaceLane) throws {
        guard session.accountID > 0, !session.namespace.isEmpty,
              !draftID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SquarePostLocalMediaIssue.invalidScope }
        self.session = session; self.draftID = draftID; self.lane = lane
    }
}

/// All limits are injected local rules. Missing values mean unknown, never unlimited.
/// This type has no server-capability, upload, moderation or publication authority.
public struct SquarePostLocalMediaPolicy: Equatable {
    public let revision: UUID
    public let mimeTypes: [SquarePostLocalMediaKind: Set<String>]
    public let maximumItems: Int?, maximumImages: Int?, maximumVideos: Int?
    public let allowsMixed: Bool?
    public let maximumImageBytes: Int64?, maximumVideoBytes: Int64?, maximumTotalBytes: Int64?
    public let maximumVideoDurationMilliseconds: Int64?
    public init(revision: UUID = UUID(), mimeTypes: [SquarePostLocalMediaKind: Set<String>],
                maximumItems: Int?, maximumImages: Int?, maximumVideos: Int?, allowsMixed: Bool?,
                maximumImageBytes: Int64?, maximumVideoBytes: Int64?, maximumTotalBytes: Int64?,
                maximumVideoDurationMilliseconds: Int64?) throws {
        guard [maximumItems, maximumImages, maximumVideos].allSatisfy({ $0.map { $0 >= 0 } ?? true }),
              [maximumImageBytes, maximumVideoBytes, maximumTotalBytes, maximumVideoDurationMilliseconds].allSatisfy({ $0.map { $0 > 0 } ?? true }),
              mimeTypes.allSatisfy({ pair in pair.value.allSatisfy { Self.validMIME($0, kind: pair.key) } }) else { throw SquarePostLocalMediaIssue.invalidPolicy }
        self.revision = revision; self.mimeTypes = mimeTypes
        self.maximumItems = maximumItems; self.maximumImages = maximumImages; self.maximumVideos = maximumVideos
        self.allowsMixed = allowsMixed; self.maximumImageBytes = maximumImageBytes; self.maximumVideoBytes = maximumVideoBytes
        self.maximumTotalBytes = maximumTotalBytes; self.maximumVideoDurationMilliseconds = maximumVideoDurationMilliseconds
    }
    static func validMIME(_ value: String, kind: SquarePostLocalMediaKind) -> Bool {
        let prefix = kind == .image ? "image/" : "video/"
        return value.hasPrefix(prefix) && value.count > prefix.count && value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || [45, 46, 43, 47].contains($0)
        } && value.filter({ $0 == "/" }).count == 1
    }
    func byteLimit(for kind: SquarePostLocalMediaKind) -> Int64? { kind == .image ? maximumImageBytes : maximumVideoBytes }
}

/// Caller-supplied descriptions are deliberately not inspection evidence.
public struct SquarePostLocalMediaDescription: Equatable {
    public let reference: SquarePostLocalMediaReference
    public let kind: SquarePostLocalMediaKind
    public let mimeType: String
    public let reportedByteCount: Int64
    public let width: Int, height: Int
    public let durationMilliseconds: Int64?
    public init(reference: SquarePostLocalMediaReference, kind: SquarePostLocalMediaKind, mimeType: String,
                reportedByteCount: Int64, width: Int, height: Int, durationMilliseconds: Int64?) {
        self.reference = reference; self.kind = kind; self.mimeType = mimeType; self.reportedByteCount = reportedByteCount
        self.width = width; self.height = height; self.durationMilliseconds = durationMilliseconds
    }
    var hasValidShape: Bool {
        guard reportedByteCount > 0, width > 0, height > 0,
              !width.multipliedReportingOverflow(by: height).overflow,
              SquarePostLocalMediaPolicy.validMIME(mimeType, kind: kind) else { return false }
        return kind == .image ? durationMilliseconds == nil : durationMilliseconds.map { $0 > 0 } == true
    }
}

public struct SquarePostLocalMediaInspectionToken: Equatable {
    public let id: UUID
    public let selectionID: UUID
    public let reference: SquarePostLocalMediaReference
    public let kind: SquarePostLocalMediaKind
    public let scope: SquarePostLocalMediaScope
    let owner: UUID
    let lease: UUID
    init(selectionID: UUID, reference: SquarePostLocalMediaReference, kind: SquarePostLocalMediaKind,
         scope: SquarePostLocalMediaScope, owner: UUID, lease: UUID) {
        id = UUID(); self.selectionID = selectionID; self.reference = reference; self.kind = kind
        self.scope = scope; self.owner = owner; self.lease = lease
    }
}

/// Minted only after Core counts/hashes actual supplied chunks and checks the reference/version.
/// It proves which bytes accompanied the description, not file ownership, decoding, safety or publication.
public struct SquarePostLocalMediaByteEvidence: Equatable {
    public let token: SquarePostLocalMediaInspectionToken
    public let description: SquarePostLocalMediaDescription
    public let byteCount: Int64
    public let sha256: String
    public var appDecodingPerformed: Bool { false }
    fileprivate init(token: SquarePostLocalMediaInspectionToken, description: SquarePostLocalMediaDescription, byteCount: Int64, sha256: String) {
        self.token = token; self.description = description; self.byteCount = byteCount; self.sha256 = sha256
    }
}

/// Incremental byte input avoids retaining a whole video in the selection model.
/// The future App adapter must read its own stable local reference/version before and after streaming.
public struct SquarePostLocalMediaByteInspection {
    public let token: SquarePostLocalMediaInspectionToken
    private let limit: Int64?
    /// Every value copy aliases this one attempt. Neither a failed prefix nor an
    /// already-consumed finish can be restored by copying an earlier wrapper.
    private final class Lifecycle {
        let lock = NSLock()
        var hasher = SHA256()
        var count: Int64 = 0
        var failure: SquarePostLocalMediaIssue?
        var finished = false
    }
    private let lifecycle = Lifecycle()
    init(token: SquarePostLocalMediaInspectionToken, limit: Int64?) { self.token = token; self.limit = limit }
    public mutating func append(_ ownedChunk: Data) throws {
        lifecycle.lock.lock(); defer { lifecycle.lock.unlock() }
        guard !lifecycle.finished else { throw SquarePostLocalMediaIssue.finished }
        if let failure = lifecycle.failure { throw failure }
        guard let increment = Int64(exactly: ownedChunk.count) else { lifecycle.failure = .byteCountOverflow; throw SquarePostLocalMediaIssue.byteCountOverflow }
        let next: Int64
        do { next = try SquarePostLocalMediaArithmetic.adding(lifecycle.count, increment) }
        catch { lifecycle.failure = .byteCountOverflow; throw SquarePostLocalMediaIssue.byteCountOverflow }
        if let limit, next > limit { lifecycle.failure = .byteLimit; throw SquarePostLocalMediaIssue.byteLimit }
        lifecycle.hasher.update(data: ownedChunk); lifecycle.count = next
    }
    public mutating func finish(_ description: SquarePostLocalMediaDescription) throws -> SquarePostLocalMediaByteEvidence {
        lifecycle.lock.lock(); defer { lifecycle.lock.unlock() }
        guard !lifecycle.finished else { throw SquarePostLocalMediaIssue.finished }
        lifecycle.finished = true
        if let failure = lifecycle.failure { throw failure }
        guard description.reference == token.reference else { throw SquarePostLocalMediaIssue.wrongReference }
        guard description.kind == token.kind else { throw SquarePostLocalMediaIssue.wrongKind }
        guard lifecycle.count > 0 else { throw SquarePostLocalMediaIssue.noBytes }
        guard description.reportedByteCount == lifecycle.count else { throw SquarePostLocalMediaIssue.byteCountMismatch }
        guard description.hasValidShape else { throw SquarePostLocalMediaIssue.invalidMetadata }
        return .init(token: token, description: description, byteCount: lifecycle.count,
                     sha256: lifecycle.hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
