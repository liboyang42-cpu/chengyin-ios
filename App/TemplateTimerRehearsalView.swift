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

// This editor changes local configuration only. It never runs a gameplay timer.
enum TemplateTimerOutcome: String, CaseIterable {
    case failed = "FAILED", expired = "EXPIRED"
}

struct TemplateTimerOutcomeDraft {
    var enabled: Bool
    var seconds: String
    var outcome: String
    init?(_ source: TemplateAdvancedDraft) {
        guard let timer = source.value["timer"]?.object,
              case .bool(let enabled)? = timer["enabled"],
              case .string(let outcome)? = timer["timeoutResult"] else { return nil }
        let seconds: String
        switch timer["durationSeconds"] {
        case .number(let value)? where value.isFinite:
            seconds = value.rounded() == value ? String(format: "%.0f", value) : String(value)
        case .string(let value)?: seconds = value
        default: return nil
        }
        self.enabled = enabled; self.seconds = seconds; self.outcome = outcome
    }
    var duration: Int? {
        let value = seconds.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(value), (10...86400).contains(number) else { return nil }
        return number
    }
    var isValid: Bool { duration != nil && TemplateTimerOutcome(rawValue: outcome) != nil }
    func applying(to original: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard let duration, TemplateTimerOutcome(rawValue: outcome) != nil else { return nil }
        var next = original
        next.advanced.set("timer", "enabled", .bool(enabled))
        next.advanced.set("timer", "durationSeconds", .number(Double(duration)))
        next.advanced.set("timer", "timeoutResult", .string(outcome))
        return next
    }
}

@MainActor final class TemplateTimerOutcomeController: ObservableObject {
    private let model: TemplateAuthoringModel
    private var observation: AnyCancellable?
    private var generation = UUID()
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private var metadata = UUID(), media = UUID()
    private(set) var isVisible = false
    private var sceneActive = false
    @Published private(set) var draft: TemplateTimerOutcomeDraft?
    @Published private(set) var statusKey: String?
    init(model: TemplateAuthoringModel) {
        self.model = model
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    private var canLoad: Bool {
        isVisible && sceneActive && model.canEdit && !model.busy && model.review == nil
    }
    private var current: Bool {
        canLoad && owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleDraft: TemplateTimerOutcomeDraft? { current ? draft : nil }
    var canSave: Bool { visibleDraft?.isValid == true }
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        if draft == nil { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive
        sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive { reload() }
    }
    func reload() {
        retire()
        guard canLoad, let source = TemplateSamplePreview.snapshot(model.draft),
              let next = TemplateTimerOutcomeDraft(model.draft.advanced) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        self.source = source; draft = next
    }
    func retire() {
        generation = UUID(); draft = nil; source = nil; owner = nil; identity = nil; statusKey = nil
    }
    private func binding<Value>(_ key: WritableKeyPath<TemplateTimerOutcomeDraft, Value>, stale: Value) -> Binding<Value> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp, let current = self.visibleDraft else { return stale }
            return current[keyPath: key]
        }, set: { [weak self] value in
            guard let self, self.generation == stamp, var current = self.visibleDraft else { return }
            current[keyPath: key] = value; self.draft = current; self.statusKey = nil
        })
    }
    var enabledBinding: Binding<Bool> { binding(\.enabled, stale: false) }
    var secondsBinding: Binding<String> { binding(\.seconds, stale: "") }
    var outcomeBinding: Binding<String> { binding(\.outcome, stale: "") }
    func saveAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, let value = self.visibleDraft,
                  let next = value.applying(to: self.model.draft) else { return }
            let owner = self.owner, identity = self.identity
            // One assignment preserves every unrelated field. Saving uses the existing local store only.
            self.model.draft = next; self.model.changed(); self.model.save()
            guard self.canLoad, self.model.coordinator.session == owner,
                  self.model.coordinator.identity == identity else { self.retire(); return }
            let result = self.model.coordinator.messageKey
            self.reload(); self.statusKey = result
        }
    }
    func cancelAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation, session = model.coordinator.session, identity = model.coordinator.identity
        return { [weak self] in
            guard let self, self.isVisible, self.sceneActive, self.generation == stamp,
                  self.model.coordinator.session == session, self.model.coordinator.identity == identity else { return }
            self.retire(); dismiss()
        }
    }
    func reloadAction() -> () -> Void {
        let stamp = generation, session = model.coordinator.session, identity = model.coordinator.identity
        return { [weak self] in
            guard let self, self.generation == stamp,
                  self.model.coordinator.session == session, self.model.coordinator.identity == identity else { return }
            self.reload()
        }
    }
}

// Keep this destination's two supported languages self-contained, without shared catalog changes.
enum TemplateTimerOutcomeText: CaseIterable {
    case title, scope, enabled, seconds, outcome, failed, expired, unknown, validation, preview, disabled, save, cancel, unavailable, reload
    func value(_ locale: Locale) -> String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        switch self {
        case .title: return chinese ? "限时挑战配置" : "Time-limit configuration"
        case .scope: return chinese ? "仅编辑本地配置。不会启动计时、提交结果、发放奖励或发布。" : "Edit local configuration only. This does not start a timer, submit a result, award a reward or publish."
        case .enabled: return chinese ? "启用限时挑战" : "Enable time limit"
        case .seconds: return chinese ? "时长（秒）" : "Duration in seconds"
        case .outcome: return chinese ? "超时结果" : "Timeout outcome"
        case .failed: return chinese ? "失败" : "Failed"
        case .expired: return chinese ? "已超时" : "Expired"
        case .unknown: return chinese ? "未知结果，请明确选择" : "Unrecognized outcome; choose explicitly"
        case .validation: return chinese ? "请输入10至86400的整数秒，并明确选择超时结果。" : "Enter a whole number from 10 to 86400 seconds and choose a timeout outcome."
        case .preview: return chinese ? "配置预览" : "Configuration preview"
        case .disabled: return chinese ? "限时挑战未启用；仍保留配置。" : "Time limit is disabled; configuration is retained."
        case .save: return chinese ? "保存到本地草稿" : "Save to local draft"
        case .cancel: return chinese ? "取消未保存的更改" : "Cancel unsaved changes"
        case .unavailable: return chinese ? "配置已改变或当前无法编辑。原始草稿未被此页面替换。" : "The configuration changed or cannot be edited now. This page has not replaced the original draft."
        case .reload: return chinese ? "重新读取当前配置" : "Reload current configuration"
        }
    }
}

@MainActor struct TemplateTimerOutcomeEntryLabel: View {
    @Environment(\.locale) private var locale
    var body: some View { Text(verbatim: TemplateTimerOutcomeText.title.value(locale)) }
}

@MainActor struct TemplateTimerOutcomeEditorView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateTimerOutcomeController
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    private func text(_ key: TemplateTimerOutcomeText) -> String { key.value(locale) }
    var body: some View {
        Form {
            Section { Text(verbatim: text(.scope)).font(.callout) }
            if let value = controller.visibleDraft {
                Section {
                    Toggle(text(.enabled), isOn: controller.enabledBinding).accessibilityIdentifier("templateTimerOutcome.enabled")
                    TextField(text(.seconds), text: controller.secondsBinding)
                        .keyboardType(.numberPad).accessibilityIdentifier("templateTimerOutcome.seconds")
                    Picker(text(.outcome), selection: controller.outcomeBinding) {
                        if TemplateTimerOutcome(rawValue: value.outcome) == nil {
                            Text(verbatim: text(.unknown)).tag(value.outcome)
                        }
                        Text(verbatim: text(.failed)).tag(TemplateTimerOutcome.failed.rawValue)
                        Text(verbatim: text(.expired)).tag(TemplateTimerOutcome.expired.rawValue)
                    }.accessibilityIdentifier("templateTimerOutcome.outcome")
                    if !value.isValid { Text(verbatim: text(.validation)).accessibilityIdentifier("templateTimerOutcome.invalid") }
                }
                Section(text(.preview)) {
                    if !value.enabled { Text(verbatim: text(.disabled)) }
                    LabeledContent(text(.seconds), value: value.seconds)
                    LabeledContent(text(.outcome), value: value.outcome)
                }
                Section {
                    Button(text(.save), action: controller.saveAction()).disabled(!controller.canSave)
                        .accessibilityIdentifier("templateTimerOutcome.saveLocal")
                }
            } else {
                Section {
                    Text(verbatim: text(.unavailable))
                    Button(text(.reload), action: controller.reloadAction()).accessibilityIdentifier("templateTimerOutcome.reload")
                }
            }
            if let status = controller.statusKey {
                Section { Text(LocalizedStringKey(status)).accessibilityIdentifier("templateTimerOutcome.status") }
            }
            Section {
                Button(text(.cancel), action: controller.cancelAction { dismiss() })
                    .accessibilityIdentifier("templateTimerOutcome.cancel")
            }
        }.navigationTitle(text(.title))
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
