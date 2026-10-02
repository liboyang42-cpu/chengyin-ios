import Foundation

/// Concrete host bridge. Closures are supplied explicitly; all defaults remain dormant.
/// Snapshot closure must use current-account reads, never user-entered permission flags.
@MainActor public final class OfficialActionInjectedAccess: OfficialActionAccess {
    private let current: () -> OfficialActionIdentity?
    private let read: (OfficialActionCommand) async throws -> OfficialActionSnapshot
    private let write: (OfficialActionCommand) async throws -> OfficialActionReceipt
    public let enabled: Bool
    public var identity: OfficialActionIdentity? { current() }
    public init(enabled: Bool = false, current: @escaping () -> OfficialActionIdentity?,
                read: @escaping (OfficialActionCommand) async throws -> OfficialActionSnapshot,
                write: @escaping (OfficialActionCommand) async throws -> OfficialActionReceipt) {
        self.enabled = enabled; self.current = current; self.read = read; self.write = write
    }
    public func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot { try await read(command) }
    public func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt {
        guard enabled else { throw OfficialActionFailure.disabled }
        return try await write(command)
    }
}
