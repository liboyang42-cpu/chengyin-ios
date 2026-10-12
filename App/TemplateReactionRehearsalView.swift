import SwiftUI
import Combine

@MainActor final class TemplateReactionRehearsalController: ObservableObject {
    enum Action { case tap, reset }
    private let model: TemplateAuthoringModel
    let mode: TemplateReactionRehearsal.Mode
    private let clock: @MainActor () -> Double
    private let delayUnit: @MainActor () -> Double
    private let scheduler: any TemplateTimerRehearsalScheduler
    private var cancelWait: TemplateTimerCancellation?
    private var observation: AnyCancellable?
    private(set) var isVisible = false
    private var sceneActive = false
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID(), generation = UUID(), waitGeneration = UUID()
    private var active = false
    @Published private var state: TemplateReactionRehearsal?
    init(model: TemplateAuthoringModel, mode: TemplateReactionRehearsal.Mode,
         clock: @escaping @MainActor () -> Double = { floor(ProcessInfo.processInfo.systemUptime * 1000) },
         delayUnit: @escaping @MainActor () -> Double = { Double.random(in: 0..<1) },
         scheduler: (any TemplateTimerRehearsalScheduler)? = nil) {
        self.model = model; self.mode = mode; self.clock = clock; self.delayUnit = delayUnit
        self.scheduler = scheduler ?? TemplateTimerSystemScheduler()
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft && model.canEdit && !model.busy && model.review == nil }
    private var hasLease: Bool {
        active && canReload && owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleState: TemplateReactionRehearsal? { hasLease ? state : nil }
    // NavigationStack can retain this destination while another page is on top.
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        // Repeated visible appearance must preserve a current local run or presentation.
        if !active { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive
        sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive || !active { reload() }
    }
    func reload() {
        retire()
        guard canReload, let source = TemplateSamplePreview.snapshot(model.draft),
              let next = TemplateReactionRehearsal(model.draft.advanced, mode: mode) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; state = next; active = true
    }
    func retire() { generation = UUID(); stopWait(); active = false; state = nil; source = nil }
    private func stopWait() { waitGeneration = UUID(); cancelWait?(); cancelWait = nil }
    /// Reuse the sealed timer scheduler as a cancellable single-shot; fence queued duplicate delivery.
    private func scheduleSignal(after milliseconds: Double) {
        let stamp = waitGeneration
        cancelWait = scheduler.schedule(interval: milliseconds / 1000) { [weak self] in
            guard let self, self.waitGeneration == stamp else { return }
            guard self.hasLease, var next = self.state, next.phase == .waiting else { self.retire(); return }
            let now = self.clock(); next.signal(at: now)
            self.stopWait()
            if next.phase != .waiting { self.generation = UUID() }
            self.state = next
            if next.phase == .waiting, let deadline = next.waitUntil {
                self.scheduleSignal(after: deadline - now)
            }
        }
    }
    func action(_ action: Action) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, var next = self.state else { return }
            if case .tap = action, !next.canTap { return }
            self.generation = UUID(); self.stopWait()
            var waitDelay: Double?
            switch action {
            case .reset: next.reset()
            case .tap:
                let now = self.clock()
                if next.canArm {
                    next.arm(at: now, delayUnit: self.delayUnit())
                    waitDelay = next.waitUntil.map { $0 - now }
                }
                else { next.tap(at: now) }
            }
            self.state = next
            if next.phase == .waiting, let waitDelay {
                // arm() validated both clock and delay; do not draw or read the clock twice.
                self.scheduleSignal(after: waitDelay)
            }
        }
    }
    func closeAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp else { return }
            self.retire(); dismiss()
        }
    }
}

@MainActor struct TemplateReactionRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateReactionRehearsalController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, mode: TemplateReactionRehearsal.Mode) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, mode: mode))
    }
    var body: some View {
        Form {
            Section {
                Text("templateReaction.localOnly").font(.callout)
                Text("templateReaction.background").font(.footnote).foregroundStyle(.secondary)
                if controller.mode == .sourceExample { Text("templateReaction.exampleOnly").font(.footnote) }
            }
            if let state = controller.visibleState {
                Section {
                    Text(verbatim: state.kicker).font(.title2)
                    LabeledContent("templateReaction.rounds", value: String(state.rounds))
                    LabeledContent("templateReaction.goal", value: milliseconds(state.goalMs))
                    LabeledContent("templateReaction.round", value: String(state.round))
                    Text("templateReaction.rule").font(.footnote)
                }
                Section {
                    Button(action: controller.action(.tap)) {
                        VStack(spacing: 16) {
                            Text(LocalizedStringKey(stageKey(state))).font(.largeTitle.bold())
                            Text(LocalizedStringKey(hintKey(state))).font(.callout)
                        }.frame(maxWidth: .infinity, minHeight: 180).padding()
                            .background(stageColor(state).opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!state.canTap)
                        .accessibilityIdentifier("templateReaction.stage")
                        .accessibilityLabel(LocalizedStringKey(stageKey(state)))
                        .accessibilityHint(LocalizedStringKey(hintKey(state)))
                    if let last = state.times.last {
                        LabeledContent("templateReaction.last", value: milliseconds(last))
                    }
                }
                if !state.times.isEmpty {
                    Section("templateReaction.readings") {
                        ForEach(Array(state.times.enumerated()), id: \.offset) { index, value in
                            HStack { Text(verbatim: String(index + 1)); Spacer(); Text(verbatim: milliseconds(value)) }
                        }
                    }
                }
                if let matched = state.matched, let best = state.bestMs {
                    Section("templateReaction.localResult") {
                        LabeledContent("templateReaction.best", value: milliseconds(best))
                        Text(LocalizedStringKey(matched ? "templateReaction.matched" : "templateReaction.missed"))
                    }
                }
                Button("creator.reset", action: controller.action(.reset)).accessibilityIdentifier("templateReaction.reset")
            } else {
                Section {
                    Text("templateReaction.unavailable")
                    Button("templateReaction.reload") { controller.reload() }.disabled(!controller.canReload)
                        .accessibilityIdentifier("templateReaction.reload")
                }
            }
        }.navigationTitle("templateReaction.rehearse").privacySensitive()
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.close", action: controller.closeAction { dismiss() }).accessibilityIdentifier("templateReaction.close")
            } }
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
    private func milliseconds(_ value: Double) -> String { String(format: "%.0f ms", value) }
    private func stageColor(_ state: TemplateReactionRehearsal) -> Color {
        switch state.phase { case .signal: return .green; case .waiting, .early: return .red; default: return .secondary }
    }
    private func stageKey(_ state: TemplateReactionRehearsal) -> String {
        switch state.phase {
        case .idle: return state.times.isEmpty ? "templateReaction.start" : "templateReaction.next"
        case .waiting: return "templateReaction.wait"
        case .signal: return "templateReaction.tap"
        case .early: return "templateReaction.early"
        case .finished: return "templateReaction.finished"
        case .aborted: return "templateReaction.clockInvalid"
        }
    }
    private func hintKey(_ state: TemplateReactionRehearsal) -> String {
        switch state.phase {
        case .idle: return "templateReaction.readyHint"
        case .waiting: return "templateReaction.waitHint"
        case .signal: return "templateReaction.tapHint"
        case .early: return state.earlyReason == .belowHumanMinimum ? "templateReaction.tooFast" : "templateReaction.retryHint"
        case .finished, .aborted: return "templateReaction.resetHint"
        }
    }
}
