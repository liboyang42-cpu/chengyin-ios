import Foundation

public enum RoamPosterAvailability: Equatable {
    case available, offline, completed, needsRedemption, unsupported
    public init(node: RoamNodeDetail) {
        if node.completed { self = .completed }
        else if node.needRedeem { self = .needsRedemption }
        else if !node.isPublished { self = .offline }
        else if node.canInteract == false || node.validationMethod != 4 { self = .unsupported }
        else { self = .available }
    }
}
public struct RoamPosterReceipt: Decodable, Equatable {
    public let needRedeem: Bool
    public let alreadyClaimed: Bool
    enum CodingKeys: String, CodingKey { case needRedeem, alreadyClaimed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The payload must explicitly tell us whether redemption remains; code=200 alone is not completion.
        needRedeem = try c.decode(Bool.self, forKey: .needRedeem)
        alreadyClaimed = try c.decodeIfPresent(Bool.self, forKey: .alreadyClaimed) ?? false
    }
}
@MainActor public final class RoamPosterCoordinator {
    public enum Phase: Equatable { case ready, locating, review, preflighting, submitting, unknown, completed, needsRedemption, unavailable, failed }
    public private(set) var phase: Phase = .ready
    private let scope: RetainedImageScope
    private let node: () -> RoamNodeDetail?
    private let refreshNode: (() async throws -> RoamNodeDetail)?
    private let location: any RoamDeviceLocationProviding
    private let executor: any RoamMediaMutationExecuting
    private let journal: any OperationPendingJournal
    private let now: () -> Date
    private var generation = 0
    private var command: RoamExperienceMutation?
    private var expires: Date?
    private let owner: String
    private let target: String
    public var changed: (() -> Void)?
    public init(scope: RetainedImageScope, poiID: Int, node: @escaping () -> RoamNodeDetail?, location: any RoamDeviceLocationProviding,
                executor: any RoamMediaMutationExecuting, journal: any OperationPendingJournal, refreshNode: (() async throws -> RoamNodeDetail)? = nil, now: @escaping () -> Date = Date.init) {
        self.scope = scope; self.node = node; self.refreshNode = refreshNode; self.location = location; self.executor = executor; self.journal = journal; self.now = now
        owner = "roam-poster:\(scope.namespace ?? ""):\(scope.realm):\(scope.accountID)"; target = "poi:\(poiID)"
        do { if try journal.pending(ownerKey: owner, targetKey: target) != nil { phase = .unknown } }
        catch { phase = .unavailable }
    }
    public var available: Bool {
        guard executor.enabled, executor.scope == scope, let value = node() else { return false }
        return RoamPosterAvailability(node: value) == .available
    }
    public func scanned(_ code: String, purposeAccepted: Bool) async {
        guard phase == .ready || phase == .failed, available, purposeAccepted,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, code.utf8.count <= 8192,
              let snapshot = node() else { return }
        generation += 1; let ticket = generation; phase = .locating; changed?()
        do {
            if let refreshNode {
                let fresh = try await refreshNode()
                guard fresh.poiId == snapshot.poiId, RoamPosterAvailability(node: fresh) == .available else { throw APIError.invalidRequest }
            }
            guard ticket == generation, !Task.isCancelled, available else { return }
            let fix = try await location.currentFix()
            guard !Task.isCancelled, ticket == generation, available, node() == snapshot else { return }
            // Never substitute a manual search center or relabel Apple's WGS84 as GCJ02.
            guard fix.datum == .gcj02, fix.accuracyMeters <= 100,
                  (0...30).contains(now().timeIntervalSince(fix.measuredAt)) else { throw APIError.invalidRequest }
            command = .completeNode(poiID: snapshot.poiId, fix: fix, answer: "", photoURL: "", code: code)
            expires = fix.measuredAt.addingTimeInterval(30); phase = .review
        } catch { if ticket == generation { phase = .failed } }
        changed?()
    }
    public func submit() async {
        // Consume the one-use review synchronously, before any suspension or change callback.
        // A repeated confirmation is a no-op, including while the current node read is suspended.
        guard phase == .review else { return }
        guard available, let command, let expires, now() <= expires else {
            self.command = nil; self.expires = nil; phase = .failed; changed?(); return
        }
        generation += 1; let ticket = generation
        self.command = nil; self.expires = nil; phase = .preflighting; changed?()
        do {
            try Task.checkCancellation()
            guard ticket == generation, phase == .preflighting else { return }
            if let refreshNode {
                let fresh = try await refreshNode()
                guard fresh.poiId == node()?.poiId, RoamPosterAvailability(node: fresh) == .available else { throw APIError.invalidRequest }
            }
            try Task.checkCancellation()
            guard ticket == generation, phase == .preflighting else { return }
            guard available, now() <= expires else { throw APIError.invalidRequest }
        } catch {
            guard ticket == generation, phase == .preflighting else { return }
            // No journal or mutation has been touched. A canceled/failed preflight requires a new scan.
            phase = error is CancellationError ? .ready : .failed; changed?(); return
        }
        do {
            guard ticket == generation, phase == .preflighting, !Task.isCancelled else { return }
            guard try journal.pending(ownerKey: owner, targetKey: target) == nil else { phase = .unknown; changed?(); return }
            let pending = OperationPendingRecord(ownerKey: owner, targetKey: target)
            try journal.write(pending); phase = .submitting; changed?()
            // A synchronous UI callback may cancel after the write-ahead record. Keep that lock.
            guard ticket == generation, phase == .submitting else { return }
            try Task.checkCancellation()
            do {
                let bytes = try await executor.execute(command)
                guard !Task.isCancelled, ticket == generation, executor.scope == scope else {
                    if ticket == generation { phase = .unknown; changed?() }; return
                }
                let receipt = try RoamMutationReceiptDecoder.value(RoamPosterReceipt.self, from: bytes)
                try journal.clear(pending)
                phase = receipt.needRedeem ? .needsRedemption : .completed
            } catch let error as RetainedImageFailure {
                guard ticket == generation else { return }
                if case .rejected = error { try journal.clear(pending); phase = .failed }
                else { phase = .unknown }
            } catch { if ticket == generation { phase = .unknown } }
        } catch { if ticket == generation { phase = .unknown } }
        changed?()
    }
    public func cancel() {
        generation += 1; location.stop(); command = nil; expires = nil
        if phase == .submitting || phase == .unknown { phase = .unknown }
        else if phase != .unavailable { phase = .ready }
        changed?()
    }
}
