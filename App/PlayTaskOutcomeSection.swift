import SwiftUI
import Observation

@MainActor struct PlayTaskOutcomeSection: View {
    @Bindable var model: PlayExperienceCoordinator
    let nodeID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var actions = PlayTaskOutcomeActionGate()

    var body: some View {
        let owner = PlayTaskOutcomeActionGate.Key(model: model, nodeID: nodeID)
        let ticket = actions.ticket(model: model, nodeID: nodeID)
        let result = PlayTaskOutcomePresentation(snapshot: model.snapshot, nodeID: nodeID,
            phase: model.phase.rawValue, isCurrentRead: model.hasCurrentMediaSnapshot, unresolved: model.unresolved)
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: localized("state." + result.state.rawValue))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playTaskOutcome.state")
                if [.loading, .submitting, .needsReadback].contains(result.state) {
                    ProgressView().accessibilityLabel(Text(verbatim: localized("state." + result.state.rawValue)))
                }
                Text(verbatim: localized("detail." + result.state.rawValue))
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                if result.continuation != .none {
                    Text(verbatim: localized("continue." + result.continuation.rawValue))
                        .fixedSize(horizontal: false, vertical: true)
                    if let name = result.nextNodeName, !name.isEmpty {
                        Text(verbatim: name).font(.headline).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("playTaskOutcome.nextName")
                    }
                }
                Button {
                    Task { await actions.reload(ticket, model: model, nodeID: nodeID) }
                } label: { Text(verbatim: localized("refresh")) }
                    .buttonStyle(.borderless)
                    .disabled(ticket == nil || !PlayTaskOutcomeActionGate.canRead(model))
                    .accessibilityIdentifier("playTaskOutcome.refresh")
                Button {
                    guard actions.accepts(ticket, model: model, nodeID: nodeID) else { return }
                    dismiss()
                } label: { Text(verbatim: localized("back")) }
                    .buttonStyle(.borderless).disabled(ticket == nil)
                    .accessibilityIdentifier("playTaskOutcome.back")
            }.accessibilityElement(children: .contain)
                .onAppear { actions.appear(model: model, nodeID: nodeID, active: scenePhase == .active) }
                .onChange(of: owner) { _, _ in actions.synchronize(model: model, nodeID: nodeID) }
                .onChange(of: scenePhase) { _, value in actions.setActive(value == .active) }
                .onDisappear { actions.disappear() }
        } header: { Text(verbatim: localized("title")) }
    }

    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(key), table: "PlayTaskOutcome", locale: locale))
    }
}

/// Only local read/navigation gestures are offered here. The retained coordinator
/// prevents pointer reuse from letting an old callback borrow a replacement owner.
@MainActor @Observable final class PlayTaskOutcomeActionGate {
    struct Key: Equatable {
        let presentation: PlayExperiencePresentationKey
        let nodeID: Int
        @MainActor init(model: PlayExperienceCoordinator, nodeID: Int) {
            presentation = .init(model: model); self.nodeID = nodeID
        }
    }
    struct Ticket: Equatable { let key: Key; let visit: UUID }
    private var model: PlayExperienceCoordinator?
    private var key: Key?
    private var visit = UUID()
    private var visible = false
    private var active = false

    func appear(model: PlayExperienceCoordinator, nodeID: Int, active: Bool) {
        synchronize(model: model, nodeID: nodeID)
        visit = UUID(); visible = true; self.active = active
    }
    func synchronize(model: PlayExperienceCoordinator, nodeID: Int) {
        let next = Key(model: model, nodeID: nodeID)
        if self.model !== model || key != next { visit = UUID(); self.model = model; key = next }
    }
    func setActive(_ value: Bool) { if !value { visit = UUID() }; active = value }
    func disappear() { visit = UUID(); visible = false; active = false }
    func ticket(model: PlayExperienceCoordinator, nodeID: Int) -> Ticket? {
        let current = Key(model: model, nodeID: nodeID)
        guard visible, active, self.model === model, key == current else { return nil }
        return .init(key: current, visit: visit)
    }
    func accepts(_ offered: Ticket?, model: PlayExperienceCoordinator, nodeID: Int) -> Bool {
        guard let offered, let current = ticket(model: model, nodeID: nodeID) else { return false }
        return offered == current
    }
    static func canRead(_ model: PlayExperienceCoordinator) -> Bool {
        model.available && model.identity != nil && model.phase != .loading && model.phase != .submitting && model.phase != .reviewing
    }
    func reload(_ offered: Ticket?, model: PlayExperienceCoordinator, nodeID: Int) async {
        guard accepts(offered, model: model, nodeID: nodeID), Self.canRead(model) else { return }
        // Consume synchronously before load can suspend; a double tap cannot queue another read.
        visit = UUID()
        await model.load()
    }
}
