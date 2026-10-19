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
    private(set) var snapshotToken = UUID()
    var canOfferMerchant: Bool { isForeground && presentation?.isActive == true }
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
        snapshotToken = UUID()
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


/// Backend merchantId is the canonical mms_merchant row, not a member or store ID.
@MainActor struct NonCashRewardMerchantSelection: Identifiable {
    let id = UUID()
    let reward: NonCashReward
    let merchantID: PublicMerchantRowID
    let rewardScope: UUID
    let merchantScope: UUID
    let snapshotToken: UUID
    let presentation: NonCashRewardReadLifetime
    static func merchantRow(_ raw: String) -> PublicMerchantRowID? {
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
              raw.first != "0", let wide = Int64(raw), wide > 0,
              let value = Int(exactly: wide), String(value) == raw else { return nil }
        return PublicMerchantRowID(value)
    }
    static func capture(model: NonCashRewardDetailScreenModel, rewardReader: any NonCashRewardReading,
                        merchantReader: any PublicMerchantHomeReading, snapshotToken: UUID,
                        presentation: NonCashRewardReadLifetime?) -> Self? {
        guard let presentation, presentation.isActive, model.presentation === presentation,
              model.canOfferMerchant, model.snapshotToken == snapshotToken,
              rewardReader.isAuthenticated, rewardReader.isConfigured, merchantReader.isConfigured,
              rewardReader.isOfflineExample == merchantReader.isOfflineExample,
              !model.isLoading, let reward = model.value(scope: rewardReader.scope),
              let merchantID = merchantRow(reward.merchantId) else { return nil }
        return .init(reward: reward, merchantID: merchantID, rewardScope: rewardReader.scope,
            merchantScope: merchantReader.scope, snapshotToken: snapshotToken, presentation: presentation)
    }
    func isCurrent(model: NonCashRewardDetailScreenModel, rewardReader: any NonCashRewardReading,
                   merchantReader: any PublicMerchantHomeReading) -> Bool {
        presentation.isActive && model.presentation === presentation && model.canOfferMerchant
            && model.snapshotToken == snapshotToken && !model.isLoading
            && rewardReader.scope == rewardScope && merchantReader.scope == merchantScope
            && rewardReader.isAuthenticated && rewardReader.isConfigured && merchantReader.isConfigured
            && rewardReader.isOfflineExample == merchantReader.isOfflineExample
            && model.value(scope: rewardScope) == reward
    }
}
@MainActor struct NonCashRewardMerchantNavigation {
    private(set) var selection: NonCashRewardMerchantSelection?
    private(set) var closing: NonCashRewardMerchantSelection?
    var canOpen: Bool { selection == nil && closing == nil }
    mutating func open(_ next: NonCashRewardMerchantSelection) {
        guard canOpen else { return }; selection = next
    }
    mutating func close(_ id: UUID) {
        guard let selected = selection, selected.id == id else { return }
        closing = selected; selection = nil
    }
    mutating func finish(_ id: UUID) -> NonCashRewardMerchantSelection? {
        guard let old = closing, old.id == id else { return nil }
        closing = nil; return old
    }
    mutating func cancel() { selection = nil; closing = nil }
}
/// Public-home has no auth-expiry callback; the wrapper still rejects stale results.
@MainActor struct NonCashRewardMerchantReader: PublicMerchantHomeReading {
    let base: any PublicMerchantHomeReading
    let selection: NonCashRewardMerchantSelection
    let current: () -> Bool
    var scope: UUID { selection.id }
    var isConfigured: Bool { current() && base.isConfigured && base.scope == selection.merchantScope }
    var isOfflineExample: Bool { base.isOfflineExample }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        guard isConfigured, target == .legacyMerchantRowID(selection.merchantID) else { throw CancellationError() }
        do {
            let value = try await base.home(target)
            guard !Task.isCancelled, isConfigured, value.id == selection.merchantID.rawValue else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, isConfigured else { throw CancellationError() }
            throw error
        }
    }
}
