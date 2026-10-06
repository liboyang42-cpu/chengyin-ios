import Foundation

/// One explicitly opened author-image presentation owns its actual read task and exact reference.
/// It does not alter the current selection or authorize player access.
@MainActor public final class OwnedTopicCoverImageFlow {
    public enum State: Equatable { case idle, loading, ready(Data), failed(OwnedTopicCoverFailure), unauthorized, closed }
    public let id = UUID()
    public let asset: OwnedTopicCoverAsset
    public let session: ProjectEditSession
    public private(set) var state: State = .idle
    private let source: any OwnedTopicCoverServing
    private let stillPresented: () -> Bool
    private var ownedTask: Task<Data, Error>?
    private var requestID: UUID?
    public init(asset: OwnedTopicCoverAsset, session: ProjectEditSession, source: any OwnedTopicCoverServing, stillPresented: @escaping () -> Bool) {
        self.asset = asset; self.session = session; self.source = source; self.stillPresented = stillPresented
    }
    public var isCurrent: Bool { state != .closed && asset.ownerMemberID == session.accountID && stillPresented() && source.isCurrent(session: session) }
    public func load() async {
        guard ownedTask == nil, state != .closed else { return }
        guard isCurrent, source.permits(.readAsset, session: session) else { state = .failed(.notConfigured); return }
        let original = UUID(); requestID = original; state = .loading
        let task = Task { [source, asset, session] in try await source.content(asset, session: session) }; ownedTask = task
        defer { if requestID == original { requestID = nil; ownedTask = nil } }
        do {
            let bytes = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == original else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            state = .ready(bytes)
        } catch {
            guard requestID == original else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            if error as? APIError == .unauthorized { state = .unauthorized }
            else { state = .failed(error as? OwnedTopicCoverFailure ?? .unavailable) }
        }
    }
    public func close() { ownedTask?.cancel(); ownedTask = nil; requestID = nil; state = .closed }
}

extension ApprovedTopicSelectedCover {
    public var ownedAsset: OwnedTopicCoverAsset {
        // This capture has already passed the strict8-field reference decoder. No URL conversion occurs.
        .init(assetID: assetID, sourceVersion: sourceVersion, contentHash: contentHash, ownerMemberID: ownerMemberID)
    }
}
