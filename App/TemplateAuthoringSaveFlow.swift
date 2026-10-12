import SwiftUI

@MainActor final class TemplateAuthoringSaveFlowController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let generation: UUID
        let signal: TemplateAuthoringSavedResultSignal
    }
    typealias Scheduler = @MainActor (Int, @escaping @MainActor () -> Void) -> (() -> Void)
    private let coordinator: TemplateAuthoringCoordinator
    private let schedule: Scheduler
    private var generation = UUID()
    private var active = false
    private var latest: TemplateAuthoringSavedResultObservation?
    private var admitted: (session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity)?
    private var cancelTimer: (() -> Void)?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var showingLibrary = false
    init(coordinator: TemplateAuthoringCoordinator, schedule: Scheduler? = nil) {
        self.coordinator = coordinator; self.schedule = schedule ?? Self.liveSchedule
    }
    static func liveSchedule(_ milliseconds: Int, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }; action()
        }
        return { task.cancel() }
    }
    func activate() { guard !active else { return }; active = true; generation = UUID(); observeVisit(); refresh() }
    func suspend() { active = false; invalidate() }
    func retire() { suspend(); latest = nil; admitted = nil }
    func accept(_ observation: TemplateAuthoringSavedResultObservation?) {
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
        cancelTimer = schedule(TemplateAuthoringSavedResult.displayMilliseconds, closeAction(value))
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

/// One pushed destination changes from the ordinary editor to the existing own-library screen.
/// The launch's direct library/prefab links and the central NavigationStack remain untouched.
@MainActor struct TemplateAuthoringSaveFlow: View {
    let coordinator: TemplateAuthoringCoordinator
    let sessionRevision: UInt64
    let metadataReader: (any DiscoveryReading)?
    let imageSelectionApproved: () -> Bool
    let library: () -> AnyView
    @StateObject private var controller: TemplateAuthoringSaveFlowController
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: TemplateAuthoringCoordinator, sessionRevision: UInt64, metadataReader: (any DiscoveryReading)?,
         imageSelectionApproved: @escaping () -> Bool, library: @escaping () -> AnyView) {
        self.coordinator = coordinator; self.sessionRevision = sessionRevision; self.metadataReader = metadataReader
        self.imageSelectionApproved = imageSelectionApproved; self.library = library
        _controller = StateObject(wrappedValue: .init(coordinator: coordinator))
    }
    var body: some View {
        Group {
            if controller.showingLibrary { library() }
            else {
                TemplateAuthoringView(coordinator: coordinator, sessionRevision: sessionRevision, metadataReader: metadataReader,
                                      imageSelectionApproved: imageSelectionApproved)
            }
        }
        .onPreferenceChange(TemplateAuthoringSavedResultPreferenceKey.self) { controller.accept($0) }
        .sheet(item: controller.presentationBinding()) { value in
            TemplateAuthoringSavedResultPanel(result: value.signal.result, close: controller.closeAction(value))
        }
        .onAppear { controller.activate() }
        .onDisappear { controller.retire() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.activate() } else { controller.suspend() } }
        .accessibilityIdentifier("templateSavedResult.flow")
    }
}
