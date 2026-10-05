import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopOwnedPackageBrowser {
    public enum Phase: String { case idle, loading, ready, unavailable, failed, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var value: WorkshopOwnedPackage?
    public private(set) var issue: WorkshopOwnedIssue?
    private let reader: any WorkshopOwnedPackageReading
    private let lease: ContentDraftSessionLease
    private var presentation: WorkshopOwnedPresentationPermit?
    private var generation = UUID()
    private var lifetime: WorkshopOwnedReadLifetime?
    public init(reader: any WorkshopOwnedPackageReading, lease: ContentDraftSessionLease) { self.reader = reader; self.lease = lease }
    public func invalidate() { presentation?.revoke(); presentation = nil; lease.revoke(); lifetime?.revoke(); lifetime = nil; generation = UUID(); value = nil; issue = .staleSession; phase = .invalidated }
    private func current() -> Bool { guard lease.isCurrent else { invalidate(); return false }; return phase != .invalidated }
    public func present(claimId: String) -> WorkshopOwnedPresentationPermit? {
        guard current() else { return nil }
        close()
        guard WorkshopOwnedWire.identifier(claimId) else { issue = .invalid; phase = .failed; return nil }
        let permit = WorkshopOwnedPresentationPermit(claimID: claimId); presentation = permit; return permit
    }
    public func leave(_ permit: WorkshopOwnedPresentationPermit) {
        permit.revoke(); guard presentation === permit else { return }; close()
    }
    public func load(claimId: String, action: WorkshopOwnedActionPermit) async {
        guard let permit = action.presentation, presentation === permit, action.isLive, permit.claimID == claimId, !Task.isCancelled, current(), action.claim() else { return }
        lifetime?.revoke(); lifetime = nil; let ticket = UUID(); generation = ticket; value = nil; issue = nil
        guard WorkshopOwnedWire.identifier(claimId) else { issue = .invalid; phase = .failed; return }
        let readLifetime = WorkshopOwnedReadLifetime(action: action); lifetime = readLifetime; phase = .loading
        do {
            let result = try await reader.read(claimId: claimId, lifetime: readLifetime)
            guard action.isLive, current(), generation == ticket else { return }
            guard !Task.isCancelled else { close(); return }
            guard result.claimId == claimId else { throw WorkshopOwnedIssue.malformed }
            value = result; phase = result.availability == .metadataOnly ? .ready : .unavailable
        } catch {
            guard action.isLive, current(), generation == ticket else { return }
            guard !Task.isCancelled else { close(); return }
            issue = (error as? WorkshopOwnedIssue) ?? .unavailable
            phase = issue == .disabled || issue == .notFound ? .unavailable : .failed
        }
    }
    public func close() { presentation?.revoke(); presentation = nil; guard phase != .invalidated else { return }; lifetime?.revoke(); lifetime = nil; generation = UUID(); value = nil; issue = nil; phase = .idle }
}
