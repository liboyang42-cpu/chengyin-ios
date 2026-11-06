import SwiftUI
import Observation

@MainActor struct ProfileWeeklyPointsAccess {
    let reader: any ProfileWeeklyPointsReading
    let owner: SocialAccountIdentity
    func owns(memberID: Int, accountReader: any SocialAccountReading, isCurrent: Bool) -> Bool {
        memberID > 0 && owner.accountID == memberID && accountReader.identity == owner && isCurrent
    }
}

@MainActor @Observable final class ProfileWeeklyPointsScreenModel {
    enum State: Equatable { case unavailable, loading, failed, signIn, changed, content(ProfileWeeklyPoints) }
    private let reader: any ProfileWeeklyPointsReading
    private let isCurrent: @MainActor () -> Bool
    private var loadedIdentity: ProfileReadIdentity?
    private var storedState: State = .loading
    private var generation: UInt64 = 0
    private(set) var visible = false
    private var active = true
    @ObservationIgnored private var task: Task<Void, Never>?
    var identity: ProfileReadIdentity? { reader.identity }
    var state: State {
        guard visible, active, isCurrent() else { return .changed }
        guard reader.identity != nil else { return .signIn }
        guard reader.isConfigured else { return .unavailable }
        guard loadedIdentity == reader.identity else { return .loading }
        return storedState
    }
    init(reader: any ProfileWeeklyPointsReading, isCurrent: @escaping @MainActor () -> Bool) {
        self.reader = reader; self.isCurrent = isCurrent
    }
    func appear(active: Bool) {
        if visible {
            if self.active != active { sceneChanged(active: active) }
            return
        }
        visible = true; self.active = active; refresh()
    }
    func disappear() { visible = false; retire() }
    func sceneChanged(active: Bool) {
        self.active = active
        if active && visible { refresh() } else { retire() }
    }
    func refresh() {
        guard visible, active else { return }
        task?.cancel()
        task = Task { @MainActor [weak self] in await self?.reload() }
    }
    private func retire() {
        generation &+= 1; task?.cancel(); task = nil; loadedIdentity = nil; storedState = .loading
    }
    func reload() async {
        guard !Task.isCancelled, visible, active, isCurrent() else { return }
        generation &+= 1; let capturedGeneration = generation
        loadedIdentity = nil; storedState = .loading
        guard let captured = reader.identity, reader.isConfigured else { return }
        func current() -> Bool {
            !Task.isCancelled && visible && active && isCurrent() && generation == capturedGeneration &&
                reader.isConfigured && reader.identity == captured
        }
        do {
            let value = try await reader.weeklyPoints()
            guard current() else { return }
            loadedIdentity = captured; storedState = .content(value)
        } catch {
            guard current(), !(error is CancellationError) else { return }
            loadedIdentity = captured
            storedState = error as? APIError == .unauthorized ? .signIn : .failed
        }
    }
}

@MainActor struct ProfileWeeklyPointsEntry: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let access: ProfileWeeklyPointsAccess
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        if access.owns(memberID: memberID, accountReader: accountReader, isCurrent: isCurrent()) {
            let revision = accountReader.presentationRevision
            ProfileWeeklyPointsSection(reader: access.reader, isCurrent: {
                isCurrent() && accountReader.identity == access.owner &&
                    accountReader.presentationRevision == revision && access.reader.identity?.accountID == memberID &&
                    access.reader.identity?.epoch == access.owner.epoch
            }).id("\(memberID)-\(access.owner.epoch)-\(revision)-\(ObjectIdentifier(access.reader))")
        }
    }
}

@MainActor struct ProfileWeeklyPointsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ProfileWeeklyPointsScreenModel
    init(reader: any ProfileWeeklyPointsReading, isCurrent: @escaping @MainActor () -> Bool) {
        _model = State(initialValue: .init(reader: reader, isCurrent: isCurrent))
    }
    var body: some View {
        Section("profile.weekly.title") {
            // One stable child owns the lifecycle, including loading and unavailable states.
            VStack(alignment: .leading, spacing: 10) {
                switch model.state {
                case .loading: ProgressView("profile.loading").accessibilityIdentifier("profile.weekly.loading")
                case .unavailable:
                    Text("profile.weekly.unavailable").foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.weekly.unavailable")
                case .signIn: Text("profile.signInRequired").accessibilityIdentifier("profile.weekly.signIn")
                case .changed: Text("social.changed").accessibilityIdentifier("profile.weekly.changed")
                case .failed:
                    Text("profile.loadFailed").accessibilityIdentifier("profile.weekly.error")
                    Button("action.retry") { model.refresh() }.accessibilityIdentifier("profile.weekly.retry")
                case .content(let value):
                    LabeledContent("profile.weekly.points", value: String(value.weekPoints))
                        .accessibilityIdentifier("profile.weekly.points")
                    LabeledContent("profile.weekly.rank", value: value.rankPercentage)
                        .accessibilityIdentifier("profile.weekly.rank")
                    Button("profile.refresh") { model.refresh() }.accessibilityIdentifier("profile.weekly.refresh")
                }
            }
            .onAppear { model.appear(active: scenePhase == .active) }
            .onDisappear { model.disappear() }
            .onChange(of: scenePhase) { _, phase in model.sceneChanged(active: phase == .active) }
            .onChange(of: model.identity) { _, _ in model.refresh() }
        }
    }
}
