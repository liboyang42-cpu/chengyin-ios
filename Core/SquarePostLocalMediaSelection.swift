import Foundation

/// The strongest result intentionally still requires a real App decoder.
public enum SquarePostLocalMediaAssessment: Equatable {
    case closed, empty, policyUnavailable, inspectionPending
    case rejected(SquarePostLocalMediaIssue)
    case metadataWithinPolicyAwaitingAppDecode
}
public enum SquarePostLocalMediaPhase: Equatable {
    case selected, inspecting(SquarePostLocalMediaInspectionToken), cancelled
    case failed(SquarePostLocalMediaIssue)
    case bytesBoundMetadata(SquarePostLocalMediaByteEvidence)
}
public struct SquarePostLocalMediaItem: Equatable, Identifiable {
    public let id: UUID
    public let reference: SquarePostLocalMediaReference
    public let kind: SquarePostLocalMediaKind
    public fileprivate(set) var phase: SquarePostLocalMediaPhase
}
public struct SquarePostLocalMediaSnapshot: Equatable {
    public let id: UUID
    public let scope: SquarePostLocalMediaScope
    public let policyRevision: UUID?
    public let items: [SquarePostLocalMediaItem]
    public let assessment: SquarePostLocalMediaAssessment
}

/// Reference-owned local state. Copying a reference cannot restore an earlier lease or attempt.
/// No picker, file IO, decoder, transport, receipt or publishing grant.
@MainActor public final class SquarePostLocalMediaSelection {
    public private(set) var scope: SquarePostLocalMediaScope
    public private(set) var policy: SquarePostLocalMediaPolicy?
    public private(set) var items: [SquarePostLocalMediaItem] = []
    private let owner = UUID()
    private var lease = UUID()
    private var revision = UUID()
    private var active = true
    private struct ByteIdentity: Equatable { let count: Int64; let sha256: String }
    private var byteIdentities: [SquarePostLocalMediaReference: ByteIdentity] = [:]
    public init(scope: SquarePostLocalMediaScope, policy: SquarePostLocalMediaPolicy? = nil) { self.scope = scope; self.policy = policy }
    public var snapshot: SquarePostLocalMediaSnapshot {
        .init(id: revision, scope: scope, policyRevision: policy?.revision, items: items, assessment: assessment)
    }
    public func isCurrent(_ snapshot: SquarePostLocalMediaSnapshot) -> Bool { active && snapshot == self.snapshot }
    @discardableResult public func append(reference: SquarePostLocalMediaReference, kind: SquarePostLocalMediaKind) throws -> UUID {
        guard active else { throw SquarePostLocalMediaIssue.closed }
        let item = SquarePostLocalMediaItem(id: UUID(), reference: reference, kind: kind, phase: .selected)
        items.append(item); changed(); return item.id
    }
    public func beginInspection(_ id: UUID) throws -> SquarePostLocalMediaByteInspection {
        guard active else { throw SquarePostLocalMediaIssue.closed }
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw SquarePostLocalMediaIssue.stale }
        let item = items[index]
        let token = SquarePostLocalMediaInspectionToken(selectionID: id, reference: item.reference, kind: item.kind,
            scope: scope, owner: owner, lease: lease)
        items[index].phase = .inspecting(token); changed()
        return .init(token: token, limit: policy?.byteLimit(for: item.kind))
    }
    @discardableResult public func complete(_ evidence: SquarePostLocalMediaByteEvidence) -> Bool {
        guard let index = currentIndex(evidence.token) else { return false }
        let identity = ByteIdentity(count: evidence.byteCount, sha256: evidence.sha256)
        if let previous = byteIdentities[evidence.token.reference], previous != identity {
            items[index].phase = .failed(.sourceBytesChanged); changed(); return false
        }
        byteIdentities[evidence.token.reference] = identity
        items[index].phase = .bytesBoundMetadata(evidence); changed(); return true
    }
    @discardableResult public func fail(_ token: SquarePostLocalMediaInspectionToken, issue: SquarePostLocalMediaIssue = .inspectionFailed) -> Bool {
        guard let index = currentIndex(token) else { return false }
        items[index].phase = .failed(issue); changed(); return true
    }
    @discardableResult public func cancelInspection(_ token: SquarePostLocalMediaInspectionToken) -> Bool {
        guard let index = currentIndex(token) else { return false }
        items[index].phase = .cancelled; changed(); return true
    }
    /// Returned references are no longer referenced here. The caller owns actual local cleanup.
    /// This says nothing about other owners, real file deletion or remote objects.
    @discardableResult public func remove(_ id: UUID) -> [SquarePostLocalMediaReference] {
        guard active, let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = items.remove(at: index).reference; changed()
        return items.contains(where: { $0.reference == removed }) ? [] : [removed]
    }
    @discardableResult public func replace(_ id: UUID, reference: SquarePostLocalMediaReference, kind: SquarePostLocalMediaKind) throws -> [SquarePostLocalMediaReference] {
        guard active else { throw SquarePostLocalMediaIssue.closed }
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw SquarePostLocalMediaIssue.stale }
        let old = items[index].reference
        // Even equal reference replacement retires the old attempt (ABA).
        items[index] = .init(id: id, reference: reference, kind: kind, phase: .selected); changed()
        return items.contains(where: { $0.reference == old }) ? [] : [old]
    }
    public func reorder(_ ids: [UUID]) throws {
        guard active else { throw SquarePostLocalMediaIssue.closed }
        guard ids.count == items.count, Set(ids).count == ids.count, Set(ids) == Set(items.map(\.id)) else { throw SquarePostLocalMediaIssue.stale }
        let indexed = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = ids.compactMap { indexed[$0] }; changed()
    }
    public func updatePolicy(_ policy: SquarePostLocalMediaPolicy?) {
        guard active else { return }
        self.policy = policy
        // Already byte-bound descriptions can be reevaluated. Old in-flight policy leases cannot finish.
        for index in items.indices { if case .inspecting = items[index].phase { items[index].phase = .selected } }
        changed()
    }
    @discardableResult public func clear() -> [SquarePostLocalMediaReference] {
        let released = references(); items = []; lease = UUID(); changed(); return released
    }
    @discardableResult public func invalidate() -> [SquarePostLocalMediaReference] {
        let released = clear(); active = false; return released
    }
    @discardableResult public func replaceScope(_ scope: SquarePostLocalMediaScope, policy: SquarePostLocalMediaPolicy? = nil) -> [SquarePostLocalMediaReference] {
        let released = clear(); byteIdentities = [:]; self.scope = scope; self.policy = policy; active = true; changed(); return released
    }
    private func currentIndex(_ token: SquarePostLocalMediaInspectionToken) -> Int? {
        guard active, token.owner == owner, token.lease == lease, token.scope == scope,
              let index = items.firstIndex(where: { $0.id == token.selectionID }),
              items[index].reference == token.reference, items[index].kind == token.kind,
              case .inspecting(let current) = items[index].phase, current == token else { return nil }
        return index
    }
    private func references() -> [SquarePostLocalMediaReference] {
        var seen = Set<SquarePostLocalMediaReference>()
        return items.compactMap { seen.insert($0.reference).inserted ? $0.reference : nil }
    }
    private func changed() { revision = UUID() }
    private var assessment: SquarePostLocalMediaAssessment {
        guard active else { return .closed }
        guard !items.isEmpty else { return .empty }
        guard let policy else { return .policyUnavailable }
        guard let maximum = policy.maximumItems, let totalLimit = policy.maximumTotalBytes else { return .policyUnavailable }
        if items.count > maximum { return .rejected(.itemLimit) }
        let images = items.filter { $0.kind == .image }.count, videos = items.count - images
        if images > 0 {
            guard let limit = policy.maximumImages, policy.maximumImageBytes != nil else { return .policyUnavailable }
            if images > limit { return .rejected(.imageLimit) }
        }
        if videos > 0 {
            guard let limit = policy.maximumVideos, policy.maximumVideoBytes != nil,
                  policy.maximumVideoDurationMilliseconds != nil else { return .policyUnavailable }
            if videos > limit { return .rejected(.videoLimit) }
        }
        if images > 0 && videos > 0 {
            guard let mixed = policy.allowsMixed else { return .policyUnavailable }
            if !mixed { return .rejected(.mixedKinds) }
        }
        var total: Int64 = 0
        for item in items {
            guard let allowed = policy.mimeTypes[item.kind], !allowed.isEmpty else { return .rejected(.kindNotAllowed) }
            let evidence: SquarePostLocalMediaByteEvidence
            switch item.phase {
            case .bytesBoundMetadata(let value): evidence = value
            case .failed(let issue): return .rejected(issue)
            default: return .inspectionPending
            }
            guard allowed.contains(evidence.description.mimeType) else { return .rejected(.mimeNotAllowed) }
            guard let byteLimit = policy.byteLimit(for: item.kind) else { return .policyUnavailable }
            if evidence.byteCount > byteLimit { return .rejected(.byteLimit) }
            do { total = try SquarePostLocalMediaArithmetic.adding(total, evidence.byteCount) }
            catch { return .rejected(.byteCountOverflow) }
            if item.kind == .video {
                guard let duration = evidence.description.durationMilliseconds,
                      let limit = policy.maximumVideoDurationMilliseconds else { return .policyUnavailable }
                if duration > limit { return .rejected(.durationLimit) }
            }
        }
        if total > totalLimit { return .rejected(.byteLimit) }
        return .metadataWithinPolicyAwaitingAppDecode
    }
}
