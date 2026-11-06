import Foundation

/// Reform plan v9 H-W02 / U01 editor bridge:
/// Connects `ContentOwnership` cross-owner/cross-world edit refusal and `RunReleasePin`
/// immutability checks (`ThemeSeasonRelease.swift`) with `PublishMediaChain` stage
/// progression (`select -> process -> upload -> review -> save -> read -> play`),
/// video poster requirements on approval, read-back-only draft restoration, and
/// `ReformWorldCapabilities` default-off gating.
///
/// Client contract only: performs no network I/O and invents no default media profile.
public enum PublishMediaEditorBridgeIssue: Error, Equatable, Sendable {
    case capabilityDisabled(ReformWorldCapabilities.Feature)
    case releaseNotEditable(ThemeReleaseStatus)
    case itemNotFound(UUID)
    case mediaNotPublishable
}

public struct PublishMediaEditorActor: Equatable, Sendable {
    public let kind: ContentOwnership.OwnerKind
    public let actorId: String
    public let worldId: String

    public init(kind: ContentOwnership.OwnerKind, actorId: String, worldId: String) {
        self.kind = kind
        self.actorId = actorId
        self.worldId = worldId
    }
}

public struct PublishMediaEditorBridge: Equatable, Sendable {
    public let capabilities: ReformWorldCapabilities
    public let ownership: ContentOwnership
    public private(set) var releaseStatus: ThemeReleaseStatus
    public private(set) var selection: PublishMediaSelection

    public init(
        capabilities: ReformWorldCapabilities = .disabled,
        ownership: ContentOwnership,
        actor: PublishMediaEditorActor,
        releaseStatus: ThemeReleaseStatus = .draft,
        profile: PublishMediaProfile
    ) throws {
        guard capabilities.allows(.themeRelease) else {
            throw PublishMediaEditorBridgeIssue.capabilityDisabled(.themeRelease)
        }
        guard capabilities.allows(.publishMedia) else {
            throw PublishMediaEditorBridgeIssue.capabilityDisabled(.publishMedia)
        }
        try ownership.permitsEdit(actorKind: actor.kind, actorId: actor.actorId, worldId: actor.worldId)
        guard releaseStatus == .draft || releaseStatus == .review else {
            throw PublishMediaEditorBridgeIssue.releaseNotEditable(releaseStatus)
        }
        self.capabilities = capabilities
        self.ownership = ownership
        self.releaseStatus = releaseStatus
        self.selection = try PublishMediaSelection(profile: profile)
    }

    private func requireEditable(by actor: PublishMediaEditorActor, currentProfile: PublishMediaProfile? = nil) throws {
        guard capabilities.allows(.themeRelease) else {
            throw PublishMediaEditorBridgeIssue.capabilityDisabled(.themeRelease)
        }
        guard capabilities.allows(.publishMedia) else {
            throw PublishMediaEditorBridgeIssue.capabilityDisabled(.publishMedia)
        }
        try ownership.permitsEdit(actorKind: actor.kind, actorId: actor.actorId, worldId: actor.worldId)
        guard releaseStatus == .draft || releaseStatus == .review else {
            throw PublishMediaEditorBridgeIssue.releaseNotEditable(releaseStatus)
        }
        if let currentProfile {
            try selection.requireProfile(currentProfile)
        }
    }

    /// Stage 0 (`selected`): validates uniform type and server profile bounds before appending.
    @discardableResult
    public mutating func selectMedia(
        id: UUID = UUID(),
        uniformType: String,
        byteCount: Int64,
        durationMilliseconds: Int64? = nil,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        let kind = try PublishMediaKind(uniformType: uniformType)
        let item = try PublishMediaItem(
            id: id,
            kind: kind,
            byteCount: byteCount,
            durationMilliseconds: durationMilliseconds,
            profile: selection.profile
        )
        try selection.append(item)
        return item
    }

    /// Stage 1 (`processed`): records local SHA-256 digest of processed media bytes.
    @discardableResult
    public mutating func markProcessed(
        id: UUID,
        sha256: String,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markProcessed(sha256: sha256)
        try selection.update(item)
        return item
    }

    /// Stage 2 (`uploaded`): requires server SHA-256 readback to match processed SHA-256.
    @discardableResult
    public mutating func markUploaded(
        id: UUID,
        assetId: String,
        serverSHA256: String,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markUploaded(assetId: assetId, serverSHA256: serverSHA256)
        try selection.update(item)
        return item
    }

    /// Stage 3 (`reviewed`): enforces video poster asset requirement when approved; rejected items never advance to saved.
    @discardableResult
    public mutating func markReviewed(
        id: UUID,
        outcome: PublishMediaItem.Review,
        posterAssetId: String? = nil,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markReviewed(outcome, posterAssetId: posterAssetId)
        try selection.update(item)
        return item
    }

    /// Stage 4 (`saved`): binds draft save reference to the uploaded and approved asset id.
    @discardableResult
    public mutating func markSaved(
        id: UUID,
        referencedAssetId: String,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markSaved(referencedAssetId: referencedAssetId)
        try selection.update(item)
        return item
    }

    /// Stage 5 (`readable`): independent readback after save or restore confirms asset id and digest.
    @discardableResult
    public mutating func markReadable(
        id: UUID,
        readbackAssetId: String,
        readbackSHA256: String,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markReadable(readbackAssetId: readbackAssetId, readbackSHA256: readbackSHA256)
        try selection.update(item)
        return item
    }

    /// Stage 6 (`playable`): player decoded first video frame or rendered image.
    @discardableResult
    public mutating func markPlayable(
        id: UUID,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaItem {
        try requireEditable(by: actor)
        var item = try requireItem(id)
        try item.markPlayable()
        try selection.update(item)
        return item
    }

    /// Restores a draft after relaunch: retains only items that reached `readable` or `playable`.
    /// Any earlier stage (`selected`, `processed`, `uploaded`, `reviewed`, `saved` without readback) is discarded.
    public func restoreDraft(
        currentProfile: PublishMediaProfile,
        actor: PublishMediaEditorActor
    ) throws -> PublishMediaEditorBridge {
        try requireEditable(by: actor, currentProfile: currentProfile)
        var restored = try PublishMediaEditorBridge(
            capabilities: capabilities,
            ownership: ownership,
            actor: actor,
            releaseStatus: releaseStatus,
            profile: currentProfile
        )
        for item in selection.restorable() {
            try restored.selection.append(item)
        }
        return restored
    }

    /// Advances release status forward only; moving to `.approved` or `.published` requires publishable media.
    public mutating func advanceReleaseStatus(
        to next: ThemeReleaseStatus,
        actor: PublishMediaEditorActor
    ) throws {
        try requireEditable(by: actor)
        guard releaseStatus.canAdvance(to: next) else {
            throw ThemeReleaseIssue.illegalTransition
        }
        if next == .approved || next == .published {
            guard selection.publishable else {
                throw PublishMediaEditorBridgeIssue.mediaNotPublishable
            }
        }
        releaseStatus = next
    }

    /// Verifies `RunReleasePin` immutability against a current `ThemeReleaseRef` under `themeRelease` capability gating.
    public static func reconcilePinnedRun(
        _ pin: RunReleasePin,
        currentRelease: ThemeReleaseRef,
        capabilities: ReformWorldCapabilities = .disabled
    ) throws -> RunReleasePin.Reconciliation {
        guard capabilities.allows(.themeRelease) else {
            throw PublishMediaEditorBridgeIssue.capabilityDisabled(.themeRelease)
        }
        return try pin.reconcile(current: currentRelease)
    }

    private func requireItem(_ id: UUID) throws -> PublishMediaItem {
        guard let item = selection.items.first(where: { $0.id == id }) else {
            throw PublishMediaEditorBridgeIssue.itemNotFound(id)
        }
        return item
    }
}
