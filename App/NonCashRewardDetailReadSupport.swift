import SwiftUI
import Observation

@MainActor struct NonCashRewardDetailDestination: Identifiable {
    let selection: NonCashRewardDetailSelection
    var id: NonCashRewardDetailSelection.Identity { selection.id }
    func makeScreenModel() -> NonCashRewardDetailScreenModel { NonCashRewardDetailScreenModel(selection: selection) }
}
/// The presentation owns both queued work and in-flight detail reads. An offered
/// action belongs to one visible presentation, so Close -> reopen cannot revive it.
@MainActor final class NonCashRewardDetailScreenModel: ObservableObject {
    typealias OfferedRefresh = @MainActor () async -> Void
    @Published private var revision: UInt64 = 0
    let state: NonCashRewardDetailModel
    private(set) var presentation: NonCashRewardReadLifetime?
    private var isForeground = true
    private var offeredRead: NonCashRewardReadLifetime?
    private var task: Task<Void, Never>?
    init(selection: NonCashRewardDetailSelection) { state = NonCashRewardDetailModel(selection: selection) }
    var isLoading: Bool { state.isLoading }
    var loadedScope: UUID? { state.loadedScope }
    func value(scope: UUID) -> NonCashReward? { state.visibleValue(scope: scope)?.reward }
    func projection(scope: UUID) -> NonCashRewardDetailProjection? { state.visibleValue(scope: scope) }
    func issue(scope: UUID) -> AccountCollectionIssue? { state.visibleIssue(scope: scope) }
    @discardableResult func beginPresentation(foreground: Bool = true) -> NonCashRewardReadLifetime {
        presentation?.invalidate(); cancelPending()
        let permit = NonCashRewardReadLifetime()
        presentation = permit; isForeground = foreground; revision &+= 1
        return permit
    }
    @discardableResult func endPresentation(presentation permit: NonCashRewardReadLifetime?) -> Bool {
        guard let permit, presentation === permit else { return false }
        permit.invalidate(); presentation = nil; cancelPending(); return true
    }
    func setForeground(_ active: Bool, reader: any NonCashRewardReading, presentation permit: NonCashRewardReadLifetime?) {
        guard let permit, permit.isActive, presentation === permit else { return }
        isForeground = active
        if active { scheduleRefresh(reader: reader, presentation: permit) } else { cancelPending() }
    }
    func invalidate() { cancelPending() }
    func cancelPending() {
        offeredRead?.invalidate(); offeredRead = nil
        task?.cancel(); task = nil
        state.cancelPending(); revision &+= 1
    }
    /// Capture before creating a Task, not inside its deferred body.
    func offerRefresh(reader: any NonCashRewardReading, presentation permit: NonCashRewardReadLifetime?) -> OfferedRefresh? {
        guard let permit, permit.isActive, presentation === permit, isForeground else { return nil }
        cancelPending()
        let offer = NonCashRewardReadLifetime()
        offeredRead = offer
        return { [weak self] in
            guard let self, !Task.isCancelled, permit.isActive, self.presentation === permit, self.isForeground,
                  offer.isActive, self.offeredRead === offer else { return }
            self.revision &+= 1
            await self.state.refresh(reader: reader, offeredLifetime: offer)
            guard self.offeredRead === offer else { return }
            offer.invalidate(); self.offeredRead = nil; self.task = nil
            self.revision &+= 1
        }
    }
    func scheduleRefresh(reader: any NonCashRewardReading, presentation permit: NonCashRewardReadLifetime?) {
        guard let action = offerRefresh(reader: reader, presentation: permit) else { return }
        task = Task { await action() }
    }
    /// SwiftUI owns pull-to-refresh work; it still needs the same presentation offer.
    func refresh(reader: any NonCashRewardReading, presentation permit: NonCashRewardReadLifetime?) async {
        guard let action = offerRefresh(reader: reader, presentation: permit) else { return }
        await action()
    }
}
/// Captured by this appearance's callbacks before onAppear installs its permit.
/// A first-frame dismissal closes that permit; a late old dismissal cannot close a new one.
@MainActor @Observable final class NonCashRewardDetailViewPresentation {
    private(set) var permit: NonCashRewardReadLifetime?
    private(set) var isClosed = false
    func begin(model: NonCashRewardDetailScreenModel, foreground: Bool) -> NonCashRewardReadLifetime? {
        guard !isClosed else { return nil }
        if let permit { return model.presentation === permit ? permit : nil }
        let fresh = model.beginPresentation(foreground: foreground); permit = fresh; return fresh
    }
    @discardableResult func end(model: NonCashRewardDetailScreenModel) -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        return model.endPresentation(presentation: permit)
    }
}

struct NonCashRewardReadFactsView: View {
    let projection: NonCashRewardDetailProjection
    var body: some View {
        Section {
            LabeledContent("rewards.read.context") {
                Text(LocalizedStringKey("rewards.read.context." + projection.origin.contextType.rawValue))
                    .accessibilityIdentifier("rewards.read.context.value")
            }.accessibilityElement(children: .contain)
            sourceValue("rewards.read.contextId", value: projection.origin.contextId, id: "rewards.read.contextId.value")
            sourceValue("rewards.read.releaseId", value: projection.origin.releaseId, id: "rewards.read.releaseId.value")
            sourceValue(projection.origin.contextType == .theme ? "rewards.read.runId" : "rewards.read.seasonId",
                        value: projection.origin.instanceId, id: "rewards.read.instanceId.value")
            sourceValue("rewards.read.rulesVersion", value: projection.origin.rulesVersion, id: "rewards.read.rulesVersion.value")
            LabeledContent("rewards.read.awardedAt") { Text(projection.reward.awardedAt, format: .dateTime) }
            Text("rewards.read.sourceHint").font(.footnote).accessibilityIdentifier("rewards.read.sourceHint")
        } header: {
            Text("rewards.read.origin").accessibilityIdentifier("rewards.read.origin.header")
        }
        Section {
            LabeledContent("rewards.read.eligibility") { fact(projection.qualification, id: "rewards.read.eligibility.value") }
                .accessibilityElement(children: .contain)
            LabeledContent("rewards.read.claimProgress") { fact(projection.claimProgress, id: "rewards.read.claimProgress.value") }
                .accessibilityElement(children: .contain)
            LabeledContent("rewards.read.allocation") { fact(projection.allocation, id: "rewards.read.allocation.value") }
                .accessibilityElement(children: .contain)
            Text("rewards.read.qualificationHint").font(.footnote).accessibilityIdentifier("rewards.read.qualificationHint")
        } header: {
            Text("rewards.read.qualification").accessibilityIdentifier("rewards.read.qualification.header")
        }
    }
    private func sourceValue(_ label: String, value: String, id: String) -> some View {
        LabeledContent(LocalizedStringKey(label)) {
            Text(verbatim: value).accessibilityIdentifier(id)
        }.accessibilityElement(children: .contain)
    }
    private func fact(_ availability: NonCashRewardDetailProjection.FactAvailability, id: String) -> some View {
        switch availability {
        case .notProvided: return Text("rewards.read.notProvided").accessibilityIdentifier(id)
        }
    }
}
