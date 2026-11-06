import Foundation
import Observation

public struct NativeFriendProgressAuthority: Equatable {
    public let identity: NativeChannelProgressIdentity
    public let friendID: Int64
    public let relationshipVersion: String
    public let authorizationVersion: String
    public init(identity: NativeChannelProgressIdentity, friendID: Int64, relationshipVersion: String, authorizationVersion: String) throws {
        guard friendID > 0, friendID != identity.actorID, !relationshipVersion.isEmpty, !authorizationVersion.isEmpty else { throw NativeChannelProgressError.invalid }
        self.identity = identity; self.friendID = friendID; self.relationshipVersion = relationshipVersion; self.authorizationVersion = authorizationVersion
    }
}
public struct NativeFriendProgressItem: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let topicID: Int64
    public let activityID: Int64
    public let meter: NativeChannelProgressMeter
    public init(id: String, title: String, topicID: Int64, activityID: Int64, meter: NativeChannelProgressMeter) throws {
        guard !id.isEmpty, !title.isEmpty, topicID > 0, activityID >= 0, meter.visible,
              meter.topicId == topicID, meter.activityId == activityID else { throw NativeChannelProgressError.invalid }
        self.id = id; self.title = title; self.topicID = topicID; self.activityID = activityID; self.meter = meter
    }
}
public enum NativeFriendProgressProjection: Equatable { case hidden, unconfirmed, visible([NativeFriendProgressItem]) }
/// The first-party friend adapter uses the original actor-to-peer relationship and minimal aggregate index.
/// CHANNEL/TEAM contexts cannot implement this protocol by substitution.
@MainActor public protocol NativeFriendProgressIndexProviding: AnyObject {
    var authority: NativeFriendProgressAuthority? { get }
    func friendProgressIndex() async throws -> NativeFriendProgressProjection
    func retireOperations()
}
public enum NativeFriendProgressCardState: Equatable { case awaitingIndex, loading, hidden, unconfirmed, visible([NativeFriendProgressItem]), closed }
@MainActor @Observable public final class NativeFriendProgressCard {
    @ObservationIgnored private let source: (any NativeFriendProgressIndexProviding)?
    private let captured: NativeFriendProgressAuthority?
    private var generation: UInt64 = 0
    private var active = false
    private var privacyRevision = NativeProgressPrivacyInvalidation.revision
    @ObservationIgnored private var authorityTask: Task<Void, Never>?
    private var rawState: NativeFriendProgressCardState = .awaitingIndex
    public var state: NativeFriendProgressCardState {
        guard active else { return .closed }
        guard let source else { return .awaitingIndex }
        return !privacyBlocked && privacyRevision == NativeProgressPrivacyInvalidation.revision && captured != nil && source.authority == captured ? rawState : .closed
    }
    private var privacyBlocked: Bool {
        guard let identity = captured?.identity else { return true }
        return NativeProgressPrivacyInvalidation.blocked(owner: NativeProgressPrivacyInvalidation.owner(origin: identity.origin, namespace: identity.namespace, actor: identity.actorID))
    }
    public init(source: (any NativeFriendProgressIndexProviding)?) {
        self.source = source; captured = source?.authority
        // Local authority observation only; not progress/network polling.
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self else { return }
                if self.active && self.captured != nil && self.source?.authority != self.captured { self.invalidate(); return }
                // Reuse the existing local observer; no new timer/network polling or privacy truth source.
                if self.active && self.privacyRevision != NativeProgressPrivacyInvalidation.revision {
                    self.generation &+= 1; self.rawState = .closed; self.source?.retireOperations()
                    await self.activate()
                }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    public func activate() async {
        active = true
        guard let source else { rawState = .awaitingIndex; return }
        guard let captured, source.authority == captured else { invalidate(); return }
        privacyRevision = NativeProgressPrivacyInvalidation.revision
        guard !privacyBlocked else { rawState = .closed; return }
        let policyStamp = privacyRevision
        generation &+= 1; let stamp = generation; rawState = .loading
        do {
            let value = try await source.friendProgressIndex()
            guard active, generation == stamp, policyStamp == NativeProgressPrivacyInvalidation.revision, source.authority == captured, !Task.isCancelled else { return }
            switch value {
            case .hidden: rawState = .hidden
            case .unconfirmed: rawState = .unconfirmed
            case .visible(let rows):
                guard rows.count <= 50, Set(rows.map(\.id)).count == rows.count,
                      rows.allSatisfy({ $0.meter.subjectId == captured.friendID && $0.meter.visible && $0.meter.revision?.isEmpty == false &&
                          $0.meter.currentNodeId == nil && $0.meter.completedNodeIds == nil &&
                          $0.meter.visibility?.aggregate == "FRIEND" && $0.meter.visibility?.detail == "SELF" &&
                          $0.meter.percent.map({ (0...100).contains($0) }) == true && $0.meter.required.map({ $0 > 0 }) == true && $0.meter.done.map({ $0 >= 0 }) == true }) else { throw NativeChannelProgressError.malformed }
                rawState = .visible(rows)
            }
        } catch {
            guard active, generation == stamp, policyStamp == NativeProgressPrivacyInvalidation.revision, source.authority == captured else { return }
            if case NativeChannelProgressError.server(let status, _) = error, status == 401 || status == 403 { invalidate() }
            else { rawState = .unconfirmed }
        }
    }
    public func invalidate() { active = false; generation &+= 1; rawState = .closed; source?.retireOperations() }
}
