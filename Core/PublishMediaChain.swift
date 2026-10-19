import Foundation

/// Reform plan v9 U01 / W02.1: posts and App professional-theme publishing accept
/// images or videos. Selection, processing, upload, review, save, restore, read and
/// playback are separate stages, each with its own evidence. The mini-program image
/// field is not treated as a complete App media chain (its story blocks are image
/// and audio only; square posts are image only), so video is new App scope.
///
/// Client contract only: no upload endpoint is reviewed for video, so nothing here
/// sends bytes. Size/duration limits are server facts and must be injected from a
/// reviewed profile; there is intentionally no default profile.
public enum PublishMediaIssue: Error, Equatable {
    case invalid, unsupportedKind, tooLarge, tooLong, tooMany, outOfOrder, staleProfile, mismatchedReadback
}

public enum PublishMediaKind: String, Codable, Sendable {
    case image = "IMAGE", video = "VIDEO"
    public init(uniformType: String) throws {
        switch uniformType {
        case "public.jpeg", "public.png", "public.heic", "org.webmproject.webp": self = .image
        case "public.mpeg-4", "com.apple.quicktime-movie": self = .video
        default: throw PublishMediaIssue.unsupportedKind // SVG/HTML/GIF animation etc. are not accepted.
        }
    }
}

/// Server-issued limits; versioned so a changed profile invalidates local checks.
public struct PublishMediaProfile: Decodable, Equatable, Sendable {
    public let profileVersion: String
    public let maxItems: Int
    public let maxImageBytes: Int64
    public let maxVideoBytes: Int64
    public let maxVideoMilliseconds: Int64
    public func validate() throws {
        guard ReformWire.label(profileVersion, limit: 64), (1...50).contains(maxItems),
              maxImageBytes > 0, maxVideoBytes > 0, maxVideoMilliseconds > 0 else { throw PublishMediaIssue.invalid }
    }
}

/// Ordered stages. A later stage is only recorded after the earlier one has evidence.
public enum PublishMediaStage: Int, Comparable, CaseIterable, Sendable {
    case selected = 0, processed, uploaded, reviewed, saved, readable, playable
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PublishMediaItem: Equatable, Identifiable, Sendable {
    public enum Review: String, Decodable, Sendable { case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED" }
    public let id: UUID
    public let kind: PublishMediaKind
    public let byteCount: Int64
    /// Videos only; images must not carry a duration.
    public let durationMilliseconds: Int64?
    public private(set) var stage: PublishMediaStage = .selected
    /// Local SHA-256 of processed bytes; the server readback must match it.
    public private(set) var processedSHA256: String?
    public private(set) var assetId: String?
    public private(set) var review: Review?
    public private(set) var posterAssetId: String?

    public init(id: UUID = UUID(), kind: PublishMediaKind, byteCount: Int64, durationMilliseconds: Int64?, profile: PublishMediaProfile) throws {
        try profile.validate()
        guard byteCount > 0 else { throw PublishMediaIssue.invalid }
        switch kind {
        case .image:
            guard durationMilliseconds == nil else { throw PublishMediaIssue.invalid }
            guard byteCount <= profile.maxImageBytes else { throw PublishMediaIssue.tooLarge }
        case .video:
            guard let durationMilliseconds, durationMilliseconds > 0 else { throw PublishMediaIssue.invalid }
            guard byteCount <= profile.maxVideoBytes else { throw PublishMediaIssue.tooLarge }
            guard durationMilliseconds <= profile.maxVideoMilliseconds else { throw PublishMediaIssue.tooLong }
        }
        self.id = id; self.kind = kind; self.byteCount = byteCount; self.durationMilliseconds = durationMilliseconds
    }

    /// Local transcode/metadata strip finished.
    public mutating func markProcessed(sha256: String) throws {
        guard stage == .selected, ReformWire.sha256(sha256) else { throw PublishMediaIssue.outOfOrder }
        processedSHA256 = sha256; stage = .processed
    }
    /// Upload acknowledged with the server's asset id and the digest it computed.
    public mutating func markUploaded(assetId: String, serverSHA256: String) throws {
        guard stage == .processed, ReformWire.id(assetId) else { throw PublishMediaIssue.outOfOrder }
        guard serverSHA256 == processedSHA256 else { throw PublishMediaIssue.mismatchedReadback }
        self.assetId = assetId; stage = .uploaded
    }
    /// Moderation outcome. Rejected media can never advance to saved.
    public mutating func markReviewed(_ outcome: Review, posterAssetId: String? = nil) throws {
        guard stage == .uploaded, outcome != .pending else { throw PublishMediaIssue.outOfOrder }
        if kind == .video, outcome == .approved { guard let posterAssetId, ReformWire.id(posterAssetId) else { throw PublishMediaIssue.invalid } }
        else if posterAssetId != nil { throw PublishMediaIssue.invalid }
        review = outcome; self.posterAssetId = posterAssetId; stage = .reviewed
    }
    /// The post/theme draft save referenced this asset.
    public mutating func markSaved(referencedAssetId: String) throws {
        guard stage == .reviewed, review == .approved else { throw PublishMediaIssue.outOfOrder }
        guard referencedAssetId == assetId else { throw PublishMediaIssue.mismatchedReadback }
        stage = .saved
    }
    /// An independent readback after save (or after restore) returned the same asset.
    public mutating func markReadable(readbackAssetId: String, readbackSHA256: String) throws {
        guard stage == .saved else { throw PublishMediaIssue.outOfOrder }
        guard readbackAssetId == assetId, readbackSHA256 == processedSHA256 else { throw PublishMediaIssue.mismatchedReadback }
        stage = .readable
    }
    /// Player reported a decoded first frame (video) or rendered image.
    public mutating func markPlayable() throws {
        guard stage == .readable else { throw PublishMediaIssue.outOfOrder }
        stage = .playable
    }
}

/// An ordered selection for one post or theme draft. Mixed image/video is allowed.
public struct PublishMediaSelection: Equatable, Sendable {
    public let profile: PublishMediaProfile
    public private(set) var items: [PublishMediaItem] = []
    public init(profile: PublishMediaProfile) throws { try profile.validate(); self.profile = profile }
    public mutating func append(_ item: PublishMediaItem) throws {
        guard items.count < profile.maxItems else { throw PublishMediaIssue.tooMany }
        guard !items.contains(where: { $0.id == item.id }) else { throw PublishMediaIssue.invalid }
        items.append(item)
    }
    public mutating func remove(id: UUID) { items.removeAll { $0.id == id } }
    public mutating func update(_ item: PublishMediaItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index].kind == item.kind else { throw PublishMediaIssue.invalid }
        items[index] = item
    }
    /// A newer server profile invalidates local checks; items must be re-validated.
    public func requireProfile(_ current: PublishMediaProfile) throws {
        guard current == profile else { throw PublishMediaIssue.staleProfile }
    }
    /// Publishing may only reference media that reached at least `saved` with approved review.
    public var publishable: Bool { !items.isEmpty && items.allSatisfy { $0.stage >= .saved && $0.review == .approved } }
    /// Restore after relaunch: only saved-and-read assets survive; everything earlier
    /// must be reselected because local temp files are not durable evidence.
    public func restorable() -> [PublishMediaItem] { items.filter { $0.stage >= .readable } }
}
