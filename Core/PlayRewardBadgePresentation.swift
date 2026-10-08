import Foundation
import Observation

/// A completion receipt points to a collection entry. It is not collection readback
/// and must not unlock a badge, mint a reward, or infer a missing badge's issuance.
public struct PlayRewardBadgeTarget: Hashable, Identifiable {
    public let code: String
    public let name: String?
    public var id: String { code }
    public init?(code: String, name: String? = nil) {
        guard !code.isEmpty, code.utf16.count <= 256,
              code == code.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.code = code
        self.name = name.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.utf16.count > 512 ? nil : value
        }
    }
    public static func targets(in receipt: PlayWireValue) -> [Self] {
        guard let rows = receipt["newBadges"].array else { return [] }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let code = row["code"].text, let target = Self(code: code, name: row["name"].text),
                  seen.insert(code).inserted else { return nil }
            return target
        }
    }
}

public enum PlayRewardBadgeFocus: Equatable {
    case identity(ProfileIdentityBadge)
    case achievement(ProfileMedal)
    case missingFromWall
    case incompleteWall
    case ambiguous

    public init(target: PlayRewardBadgeTarget, wall: ProfileBadgeWall) {
        // These are distinct collections. City template medals have no growth-code
        // authority. Never match by display name, template ID, or receipt artwork.
        let identities = wall.identities.filter { $0.badgeCode == target.code }
        let achievements = (wall.medals ?? []).filter { $0.isAchievement && $0.badgeCode == target.code }
        if identities.count + achievements.count > 1 { self = .ambiguous }
        else if let badge = identities.first { self = .identity(badge) }
        else if let badge = achievements.first { self = .achievement(badge) }
        else { self = wall.isPartial ? .incompleteWall : .missingFromWall }
    }
    public var statusKey: String {
        switch self {
        case .identity(let badge): return badge.unlocked ? "playBadge.confirmed" : "playBadge.locked"
        case .achievement: return "playBadge.confirmed"
        case .missingFromWall: return "playBadge.missing"
        case .incompleteWall: return "playBadge.incomplete"
        case .ambiguous: return "playBadge.ambiguous"
        }
    }
}

/// Only this query's current owner/approval may publish a read. Keeping a same-owner
/// immutable result on disappearance preserves native navigation; queued reads retire.
@MainActor @Observable public final class PlayRewardBadgeReadModel {
    public let target: PlayRewardBadgeTarget
    private let reader: any ProfileReading
    private let isCurrent: () -> Bool
    private let expectedOwner: ProfileReadIdentity?
    private var owner: ProfileReadIdentity?
    private var generation: UInt64 = 0
    private var storedFocus: PlayRewardBadgeFocus?
    private var storedIssue = false
    private var storedLoading = false
    private var active = false
    private var readTask: Task<ProfileBadgeWall, Error>?
    public var identity: ProfileReadIdentity? { isCurrent() && reader.identity == expectedOwner ? reader.identity : nil }
    public var isConfigured: Bool { reader.isConfigured }
    private var current: Bool { owner != nil && owner == expectedOwner && owner == reader.identity && reader.isConfigured && isCurrent() }
    public var focus: PlayRewardBadgeFocus? { current ? storedFocus : nil }
    public var failed: Bool { current && storedIssue }
    public var isLoading: Bool { current && storedLoading }
    public init(target: PlayRewardBadgeTarget, reader: any ProfileReading, isCurrent: @escaping () -> Bool = { true }) {
        self.target = target; self.reader = reader; self.isCurrent = isCurrent; expectedOwner = reader.identity
    }
    public func activate() { active = true }
    public func deactivate() { active = false; cancelPending() }
    public func cancelPending() {
        generation &+= 1; readTask?.cancel(); readTask = nil; storedLoading = false
    }
    public func load() async {
        // A retry queued before Back must not reactivate the destination.
        guard active, !Task.isCancelled else { return }
        cancelPending(); storedFocus = nil; storedIssue = false; owner = identity
        guard let captured = owner, reader.isConfigured else { return }
        let revision = generation; storedLoading = true
        let reader = reader
        let task = Task {
            try Task.checkCancellation()
            // The task may start after its parent captured the read owner. Recheck
            // the Play lease and profile owner immediately before invoking the reader.
            guard accepts(captured, revision) else { throw CancellationError() }
            return try await reader.profileBadges()
        }
        readTask = task
        defer { if generation == revision { storedLoading = false; readTask = nil } }
        do {
            let wall = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard accepts(captured, revision) else { return }
            storedFocus = PlayRewardBadgeFocus(target: target, wall: wall)
        } catch {
            guard accepts(captured, revision), !(error is CancellationError) else { return }
            storedIssue = true
        }
    }
    private func accepts(_ identity: ProfileReadIdentity, _ revision: UInt64) -> Bool {
        active && !Task.isCancelled && generation == revision && owner == identity && identity == expectedOwner
            && reader.identity == identity && reader.isConfigured && isCurrent()
    }
}
