import SwiftUI

@MainActor final class TemplateAuthoringPublishFlowController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let generation: UUID
        let signal: TemplateAuthoringPublishResultSignal
    }
    typealias Scheduler = TemplateAuthoringSaveFlowController.Scheduler
    private let coordinator: TemplateAuthoringCoordinator
    private let schedule: Scheduler
    private var generation = UUID()
    private var active = false
    private var latest: TemplateAuthoringPublishResultObservation?
    private var admitted: (session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity)?
    private var cancelTimer: (() -> Void)?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var showingLibrary = false
    init(coordinator: TemplateAuthoringCoordinator, schedule: Scheduler? = nil) {
        self.coordinator = coordinator; self.schedule = schedule ?? TemplateAuthoringSaveFlowController.liveSchedule
    }
    func activate() { guard !active else { return }; active = true; generation = UUID(); observeVisit(); refresh() }
    func suspend() { active = false; invalidate() }
    func retire() { suspend(); latest = nil; admitted = nil }
    func accept(_ observation: TemplateAuthoringPublishResultObservation?) {
        guard !showingLibrary else { return }
        latest = observation
        if presentation?.signal != observation?.signal { invalidate() }
        observeVisit(); refresh()
    }
    private func observeVisit() {
        guard active, let latest, let session = latest.session else { return }
        if let admitted, (!TemplateAuthoringSavedResult.exactSession(admitted.session, session) || admitted.identity != latest.identity) {
            self.admitted = nil; invalidate()
        }
        if latest.state == .editing, latest.editableNow() { admitted = (session, latest.identity) }
    }
    private func invalidate() { generation = UUID(); cancelTimer?(); cancelTimer = nil; presentation = nil }
    private func refresh() {
        guard active, !showingLibrary, presentation == nil, let signal = latest?.signal, let admitted,
              admitted.identity == signal.result.receipt.identity, TemplateAuthoringSavedResult.exactSession(admitted.session, signal.result.session),
              signal.isCurrent(), signal.result.isCurrent(in: coordinator) else { return }
        let value = Presentation(generation: generation, signal: signal); presentation = value
        cancelTimer = schedule(TemplateAuthoringPublishResult.displayMilliseconds, closeAction(value))
    }
    func closeAction(_ value: Presentation) -> () -> Void {
        { [weak self] in
            guard let self, self.active, !self.showingLibrary, self.presentation?.id == value.id,
                  self.generation == value.generation, value.signal.isCurrent(), value.signal.result.isCurrent(in: self.coordinator) else { return }
            self.invalidate(); self.latest = nil; self.showingLibrary = true
        }
    }
    func presentationBinding() -> Binding<Presentation?> {
        // A stale SwiftUI dismissal setter cannot erase a newer receipt panel.
        .init(get: { [weak self] in self?.presentation }, set: { _ in })
    }
}

/// A normal-entry modifier observes only new publish receipts. Existing draft-save flow stays intact.
@MainActor struct TemplateAuthoringPublishCompletion: ViewModifier {
    let coordinator: TemplateAuthoringCoordinator
    let library: () -> AnyView
    @StateObject private var controller: TemplateAuthoringPublishFlowController
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: TemplateAuthoringCoordinator, library: @escaping () -> AnyView) {
        self.coordinator = coordinator; self.library = library
        _controller = StateObject(wrappedValue: .init(coordinator: coordinator))
    }
    func body(content: Content) -> some View {
        Group {
            if controller.showingLibrary { library() }
            else { content }
        }
        .onPreferenceChange(TemplateAuthoringPublishResultPreferenceKey.self) { controller.accept($0) }
        .sheet(item: controller.presentationBinding()) { value in
            TemplateAuthoringPublishResultPanel(result: value.signal.result, close: controller.closeAction(value))
        }
        .onAppear { controller.activate() }
        .onDisappear { controller.retire() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.activate() } else { controller.suspend() } }
        .accessibilityIdentifier("templatePublishResult.flow")
    }
}
