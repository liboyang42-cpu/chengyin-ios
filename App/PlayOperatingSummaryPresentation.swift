import SwiftUI

/// A presentation fence around the existing reader, not a new endpoint or gameplay grant.
/// Current normal navigation permits a summary before the route is completed; retain that contract.
struct PlayOperatingSummarySource {
    private let owner: PlayExperiencePresentationKey
    private let snapshot: PlaySnapshot
    private let interaction: PlayInteractionContext
    private let coordinator: ObjectIdentifier
    @MainActor init?(runtime: PlayExperienceCoordinator, summary: PlayOperatingSummaryCoordinator) {
        guard let interaction = runtime.interactionContext, let snapshot = runtime.snapshot,
              snapshot.result.topicID == summary.topicID else { return nil }
        owner = PlayExperiencePresentationKey(model: runtime)
        self.snapshot = snapshot; self.interaction = interaction; coordinator = ObjectIdentifier(summary)
    }
    @MainActor func accepts(_ runtime: PlayExperienceCoordinator, summary: PlayOperatingSummaryCoordinator,
                            currentSummary: () -> PlayOperatingSummaryCoordinator?) -> Bool {
        owner == PlayExperiencePresentationKey(model: runtime) && runtime.hasCurrentMediaSnapshot
            && runtime.interactionContext == interaction && runtime.snapshot == snapshot
            && ObjectIdentifier(summary) == coordinator
            && currentSummary() === summary
    }
}

/// Retains only a verified display copy for this visible page. The original coordinator
/// remains the sole owner of endpoint capabilities, tag writes and unresolved tag IDs.
@MainActor final class PlayOperatingSummaryPresentation: ObservableObject {
    struct Revocation: Equatable {
        let id: UUID
        let tagID: Int
        fileprivate let read: UUID
        fileprivate let model: ObjectIdentifier
    }
    @Published private(set) var summary: PlayOperatingSummary?
    @Published private(set) var review: Revocation?
    @Published private(set) var loading = false
    private var active = false
    private var generation = UUID()
    private var modelID: ObjectIdentifier?
    private var task: Task<Void, Never>?

    func activate() { active = true }
    func retire() {
        active = false; generation = UUID(); task?.cancel(); task = nil
        summary = nil; review = nil; loading = false; modelID = nil
        // Never clear unresolvedTagIDs, infer a rejected write, or automatically resend.
    }
    func displayedSummary(model: PlayOperatingSummaryCoordinator, current: () -> Bool) -> PlayOperatingSummary? {
        guard active, !loading, current(), modelID == ObjectIdentifier(model),
              model.issue == nil, model.phase == "ready" || model.phase == "unknown",
              model.summary == summary else { return nil }
        return summary
    }
    func load(model: PlayOperatingSummaryCoordinator, current: @escaping @MainActor () -> Bool) async {
        await perform(model: model, current: current) { await model.load() }
    }
    func prepareRevocation(tagID: Int, model: PlayOperatingSummaryCoordinator, current: () -> Bool) {
        review = nil
        guard let displayed = displayedSummary(model: model, current: current),
              model.phase == "ready", model.issue == nil, model.unresolvedTagIDs.isEmpty,
              displayed.tags.contains(where: { $0.id == tagID && !$0.revoked }) else { return }
        review = .init(id: UUID(), tagID: tagID, read: generation, model: ObjectIdentifier(model))
    }
    func cancelRevocation() { review = nil }
    func revoke(_ value: Revocation, model: PlayOperatingSummaryCoordinator,
                current: @escaping @MainActor () -> Bool) async {
        guard review == value else { return }
        review = nil // Consume even a now-invalid review; restored permission cannot replay it.
        guard value.read == generation, value.model == ObjectIdentifier(model),
              let displayed = displayedSummary(model: model, current: current),
              model.phase == "ready", model.issue == nil, model.unresolvedTagIDs.isEmpty,
              displayed.tags.contains(where: { $0.id == value.tagID && !$0.revoked }) else { return }
        await perform(model: model, current: current) { await model.revoke(tagID: value.tagID) }
    }
    private func perform(model: PlayOperatingSummaryCoordinator, current: @escaping @MainActor () -> Bool,
                         operation: @escaping @MainActor () async -> Void) async {
        guard active, current(), !Task.isCancelled, model.phase != "submitting" else { return }
        task?.cancel(); generation = UUID(); let stamp = generation
        modelID = ObjectIdentifier(model); summary = nil; review = nil; loading = true
        let work = Task { @MainActor in
            guard !Task.isCancelled, current() else { return }
            await operation()
        }
        task = work
        await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard generation == stamp else { return }
        task = nil; loading = false
        guard active, current(), !Task.isCancelled, !work.isCancelled,
              modelID == ObjectIdentifier(model), model.issue == nil,
              model.phase == "ready" || model.phase == "unknown",
              let received = model.summary, received.topicID == model.topicID else { return }
        summary = received
    }
}
