import Foundation

/// Reform plan v9 §5 / W02: world, season, immutable theme release and content
/// ownership as separate identities. Client-side contract only: the suggested
/// server entities are not yet a reviewed API, so nothing here performs I/O.
/// A run is pinned to the exact release it started on; a newer release only
/// affects new runs, and a season ending never clears orders or entitlements.
public enum ThemeReleaseIssue: Error, Equatable { case invalid, drift, crossOwner, illegalTransition }

public enum SeasonLifecycle: String, Decodable, Sendable {
    case draft = "DRAFT", ready = "READY", active = "ACTIVE", ended = "ENDED", archived = "ARCHIVED"
    public func canAdvance(to next: SeasonLifecycle) -> Bool {
        switch (self, next) {
        case (.draft, .ready), (.ready, .active), (.active, .ended), (.ended, .archived): return true
        default: return false
        }
    }
    /// Season end freezes season scoring only. Purchases, orders, permanent
    /// entitlements and achievements are owned elsewhere and are never cleared here.
    public var acceptsNewSeasonScore: Bool { self == .active }
}

public enum ThemeReleaseStatus: String, Decodable, Sendable {
    case draft = "DRAFT", review = "REVIEW", approved = "APPROVED", published = "PUBLISHED", retired = "RETIRED"
    public func canAdvance(to next: ThemeReleaseStatus) -> Bool {
        switch (self, next) {
        case (.draft, .review), (.review, .draft), (.review, .approved), (.approved, .published), (.published, .retired): return true
        default: return false
        }
    }
    /// Hash is fixed once review approves the exact bytes.
    var requiresContentHash: Bool { [.approved, .published, .retired].contains(self) }
}

public struct SeasonRef: Decodable, Equatable, Sendable {
    public let seasonId, worldId, code, timezone, rulesVersion: String
    public let startsAt, endsAt: Int64
    public let lifecycle: SeasonLifecycle
    public func validate() throws {
        guard [seasonId, worldId].allSatisfy(ReformWire.id), ReformWire.label(code, limit: 64), ReformWire.label(rulesVersion, limit: 64),
              TimeZone(identifier: timezone) != nil, startsAt > 0, endsAt > startsAt else { throw ThemeReleaseIssue.invalid }
    }
}

public struct ThemeReleaseRef: Decodable, Equatable, Sendable {
    public let themeId, releaseId: String
    public let version: Int64
    public let schemaVersion: Int
    public let contentHash: String?
    public let status: ThemeReleaseStatus
    public func validate() throws {
        guard [themeId, releaseId].allSatisfy(ReformWire.id), ReformWire.version(version), version > 0, (1...999).contains(schemaVersion) else { throw ThemeReleaseIssue.invalid }
        if status.requiresContentHash { guard let contentHash, ReformWire.sha256(contentHash) else { throw ThemeReleaseIssue.invalid } }
        else if contentHash != nil { throw ThemeReleaseIssue.invalid }
    }
}

/// The exact release a run started on. Never re-pointed by a newer publication.
public struct RunReleasePin: Equatable, Sendable {
    public enum Reconciliation: Equatable, Sendable {
        /// Same release and hash.
        case unchanged
        /// A newer release exists for new runs; this run keeps its pin.
        case newerReleaseForNewRuns(ThemeReleaseRef)
        /// Entry retired for new runs; this run keeps playing its pinned bytes.
        case retiredForNewRuns
    }
    public let runId, themeId, releaseId, contentHash: String
    public let version: Int64
    public init(runId: String, release: ThemeReleaseRef) throws {
        try release.validate()
        guard ReformWire.id(runId), release.status == .published, let hash = release.contentHash else { throw ThemeReleaseIssue.invalid }
        self.runId = runId; themeId = release.themeId; releaseId = release.releaseId; contentHash = hash; version = release.version
    }
    /// Reads the theme's current release and decides what the pinned run may show.
    /// The same release id with different bytes is drift and is rejected, never adopted.
    public func reconcile(current: ThemeReleaseRef) throws -> Reconciliation {
        try current.validate()
        guard current.themeId == themeId else { throw ThemeReleaseIssue.invalid }
        if current.releaseId == releaseId {
            guard current.version == version, current.contentHash == contentHash else { throw ThemeReleaseIssue.drift }
            return current.status == .retired ? .retiredForNewRuns : .unchanged
        }
        guard current.version > version, current.status == .published || current.status == .retired else { throw ThemeReleaseIssue.drift }
        return current.status == .retired ? .retiredForNewRuns : .newerReleaseForNewRuns(current)
    }
}

/// §5 ownership: who owns a world/theme and which scope they may edit.
/// The App uses this only to hide edit affordances; the server re-checks.
public struct ContentOwnership: Decodable, Equatable, Sendable {
    public enum OwnerKind: String, Decodable, Sendable { case platform = "PLATFORM", merchant = "MERCHANT", club = "CLUB", creator = "CREATOR" }
    public let ownerKind: OwnerKind
    public let ownerId: String
    public let worldId: String
    public func validate() throws { guard ReformWire.id(ownerId), ReformWire.id(worldId) else { throw ThemeReleaseIssue.invalid } }
    /// Cross-owner and cross-world edits are refused locally before any request exists.
    public func permitsEdit(actorKind: OwnerKind, actorId: String, worldId target: String) throws {
        try validate()
        guard actorKind == ownerKind, actorId == ownerId, target == worldId else { throw ThemeReleaseIssue.crossOwner }
    }
}
