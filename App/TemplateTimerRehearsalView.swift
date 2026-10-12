import SwiftUI
import Combine

typealias TemplateTimerCancellation = @MainActor () -> Void

/// Schedulers enqueue ticks; cancellation may leave already-enqueued callbacks to be fenced.
@MainActor protocol TemplateTimerRehearsalScheduler {
    func schedule(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> TemplateTimerCancellation
}
@MainActor struct TemplateTimerSystemScheduler: TemplateTimerRehearsalScheduler {
    func schedule(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> TemplateTimerCancellation {
        let subscription = Timer.publish(every: interval, on: .main, in: .common).autoconnect().sink { _ in
            Task { @MainActor in tick() }
        }
        return { subscription.cancel() }
    }
}

@MainActor final class TemplateTimerRehearsalController: ObservableObject {
    enum Action { case start, pauseResume, stop, reset }
    private let model: TemplateAuthoringModel
    let kind: TemplateTimerRehearsal.Kind
    let mode: TemplateTimerRehearsal.Mode
    private let clock: @MainActor () -> Double
    private let scheduler: any TemplateTimerRehearsalScheduler
    private var cancelTick: TemplateTimerCancellation?
    private var observation: AnyCancellable?
    private(set) var isVisible = false
    private var sceneActive = false
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID(), generation = UUID(), tickGeneration = UUID()
    private var active = false
    @Published private var state: TemplateTimerRehearsal?
    init(model: TemplateAuthoringModel, kind: TemplateTimerRehearsal.Kind, mode: TemplateTimerRehearsal.Mode,
         clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 },
         scheduler: (any TemplateTimerRehearsalScheduler)? = nil) {
        self.model = model; self.kind = kind; self.mode = mode; self.clock = clock
        self.scheduler = scheduler ?? TemplateTimerSystemScheduler()
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft && model.canEdit && !model.busy && model.review == nil }
    private var hasLease: Bool {
        active && canReload && owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleState: TemplateTimerRehearsal? { hasLease ? state : nil }
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
              let next = TemplateTimerRehearsal(model.draft.advanced, kind: kind, mode: mode) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; state = next; active = true
    }
    func retire() { generation = UUID(); stopTicks(); active = false; state = nil; source = nil }
    private func stopTicks() { tickGeneration = UUID(); cancelTick?(); cancelTick = nil }
    private func startTicks() {
        let stamp = tickGeneration
        cancelTick = scheduler.schedule(interval: kind == .countdown ? 1 : 0.05) { [weak self] in
            guard let self, self.tickGeneration == stamp else { return }
            guard self.hasLease, var next = self.state, next.phase == .running else { self.retire(); return }
            next.tick(at: self.clock())
            if next.phase != .running { self.stopTicks(); self.generation = UUID() }
            self.state = next
        }
    }
    func action(_ action: Action) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.hasLease, self.generation == stamp, var next = self.state else { return }
            switch action {
            case .start: guard next.canStart else { return }
            case .pauseResume: guard next.canPauseResume else { return }
            case .stop: guard next.canStop else { return }
            case .reset: break
            }
            self.generation = UUID(); self.stopTicks()
            switch action {
            case .start: next.start(at: self.clock())
            case .pauseResume:
                if next.phase == .paused { next.resume(at: self.clock()) } else { next.pause(at: self.clock()) }
            case .stop: next.stop(at: self.clock())
            case .reset: next.reset()
            }
            self.state = next
            if next.phase == .running { self.startTicks() }
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

@MainActor struct TemplateTimerRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateTimerRehearsalController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, kind: TemplateTimerRehearsal.Kind, mode: TemplateTimerRehearsal.Mode) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, kind: kind, mode: mode))
    }
    var body: some View {
        Form {
            Section {
                Text("templateTimer.localOnly").font(.callout)
                Text("templateTimer.background").font(.footnote).foregroundStyle(.secondary)
                if controller.mode == .sourceExample { Text("templateTimer.exampleOnly").font(.footnote) }
            }
            if let state = controller.visibleState {
                Section {
                    Text(verbatim: state.kicker).font(.title2)
                    LabeledContent("templateTimer.target", value: seconds(state.targetSeconds))
                    if state.kind == .stopwatch {
                        LabeledContent("templateTimer.round", value: String(state.round))
                        LabeledContent("templateTimer.tolerance", value: seconds(state.toleranceMs / 1000))
                        if let left = state.triesRemaining { LabeledContent("templateTimer.remainingTries", value: String(left)) }
                        else { Text("templateTimer.unlimited") }
                        Text("templateTimer.blindRule").font(.footnote)
                    }
                }
                Section {
                    if state.kind == .countdown {
                        Text(verbatim: countdown(state.remainingSeconds)).font(.largeTitle.monospacedDigit())
                            .accessibilityIdentifier("templateTimer.countdown")
                        ProgressView(value: state.progress)
                        if state.phase == .finished { Text(verbatim: state.doneText).accessibilityIdentifier("templateTimer.doneText") }
                    } else if state.isMasked {
                        Text("templateTimer.hidden").font(.largeTitle).accessibilityIdentifier("templateTimer.masked")
                    } else {
                        Text(verbatim: seconds(state.elapsedMs / 1000)).font(.largeTitle.monospacedDigit())
                            .accessibilityIdentifier("templateTimer.stopwatch")
                    }
                    if state.phase == .paused { Text("templateTimer.paused") }
                    if let reason = state.abortReason {
                        Text(LocalizedStringKey(reason == .timeout ? "templateTimer.timeout" : "templateTimer.clockInvalid"))
                    }
                }
                if let result = state.result {
                    Section("templateTimer.localResult") {
                        Text(LocalizedStringKey("templateTimer.tier." + result.tier.rawValue))
                        Text(LocalizedStringKey("templateTimer.timing." + result.timing.rawValue))
                        LabeledContent("templateTimer.deviation", value: seconds(result.deviationSeconds))
                        if !state.canStart { Text("templateTimer.resetToRestart").font(.footnote) }
                    }
                }
                Section {
                    if state.canStart {
                        if state.phase == .finished || state.phase == .result {
                            Button("templateTimer.again", action: controller.action(.start)).accessibilityIdentifier("templateTimer.again")
                        } else {
                            Button("templateTimer.start", action: controller.action(.start)).accessibilityIdentifier("templateTimer.start")
                        }
                    }
                    if state.canPauseResume {
                        if state.phase == .paused {
                            Button("templateTimer.resume", action: controller.action(.pauseResume)).accessibilityIdentifier("templateTimer.resume")
                        } else {
                            Button("templateTimer.pause", action: controller.action(.pauseResume)).accessibilityIdentifier("templateTimer.pause")
                        }
                        Button("templateTimer.stop", action: controller.action(.stop)).disabled(!state.canStop)
                            .accessibilityIdentifier("templateTimer.stop")
                    }
                    Button("creator.reset", action: controller.action(.reset)).accessibilityIdentifier("templateTimer.reset")
                }
            } else {
                Section {
                    Text("templateTimer.unavailable")
                    Button("templateTimer.reload") { controller.reload() }.disabled(!controller.canReload)
                        .accessibilityIdentifier("templateTimer.reload")
                }
            }
        }.navigationTitle(LocalizedStringKey(controller.kind.labelKey)).privacySensitive()
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.close", action: controller.closeAction { dismiss() }).accessibilityIdentifier("templateTimer.close")
            } }
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
    private func seconds(_ value: Double) -> String { String(format: "%.2f", value) }
    private func countdown(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
}
