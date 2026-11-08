import Foundation
import Observation

/// A rendering key, never an authorization grant. The original reader validates access.
public struct ProfileReadPresentationOwner: Hashable {
    public let readerID: ObjectIdentifier
    public let identity: ProfileReadIdentity?
    public let configured: Bool
    public let surface: String
    public let requestID: Int?
    public init(reader: AnyObject, identity: ProfileReadIdentity?, configured: Bool,
                surface: String, requestID: Int? = nil) {
        readerID = ObjectIdentifier(reader); self.identity = identity; self.configured = configured
        self.surface = surface; self.requestID = requestID
    }
    fileprivate var canRead: Bool { configured && (identity?.accountID ?? 0) > 0 }
}

/// Retains an accepted same-owner list while its NavigationLink is pushed. A replaced
/// reader, request, viewer or approval masks all content/error/loading before a task runs.
@MainActor @Observable public final class ProfileReadPresentation<Value> {
    public struct Snapshot {
        public fileprivate(set) var value: Value?
        public fileprivate(set) var error: Error?
        public fileprivate(set) var isLoading = false
        public fileprivate(set) var started = false
    }
    private var owner: ProfileReadPresentationOwner?
    private var value = Snapshot()
    private var active = false
    private var generation = UUID()
    @ObservationIgnored private var source: AnyObject?
    public init() {}
    public func snapshot(for current: ProfileReadPresentationOwner) -> Snapshot {
        owner == current && current.canRead ? value : Snapshot()
    }
    public func activate(owner: ProfileReadPresentationOwner, source: AnyObject) {
        guard ObjectIdentifier(source) == owner.readerID else { return }
        generation = UUID(); self.owner = owner; self.source = source
        value = Snapshot(); active = true
    }
    public func suspend() {
        generation = UUID(); active = false; value.isLoading = false
        // Do not remove an accepted list's NavigationLinks when detail is pushed.
    }
    public func load(owner: ProfileReadPresentationOwner, currentOwner: () -> ProfileReadPresentationOwner,
                     operation: () async throws -> Value) async {
        guard !Task.isCancelled, active, self.owner == owner, owner.canRead,
              source.map(ObjectIdentifier.init) == owner.readerID, currentOwner() == owner else { return }
        let ticket = UUID(); generation = ticket
        value = Snapshot(); value.started = true; value.isLoading = true
        do {
            let result = try await operation()
            try Task.checkCancellation()
            guard accepts(ticket, owner: owner, current: currentOwner()) else { return }
            value.value = result
        } catch {
            guard accepts(ticket, owner: owner, current: currentOwner()) else { return }
            if error is CancellationError || Task.isCancelled { value.isLoading = false; return }
            value.error = error
        }
        value.isLoading = false
    }
    private func accepts(_ ticket: UUID, owner: ProfileReadPresentationOwner, current: ProfileReadPresentationOwner) -> Bool {
        active && ticket == generation && self.owner == owner && owner == current && current.canRead
            && source.map(ObjectIdentifier.init) == owner.readerID
    }
}
