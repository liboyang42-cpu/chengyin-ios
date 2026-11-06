import SwiftUI
import Observation

/// One navigation lifetime retains the original in-memory UNKNOWN controller.
@MainActor @Observable final class CityPlayerValueHostOwner {
    let reader: CityValueBoundedMapReader
    private let current: () -> Bool
    private let factory: (CityValueBoundedCapture) -> CityPlayerValueController?
    private var retired = false
    private(set) var model: CityPlayerValueController?
    private(set) var originalCapture: CityValueBoundedCapture?
    private(set) var mappingChanged = false
    var isCurrent: Bool { !retired && current() }
    var canPresent: Bool { isCurrent && !mappingChanged && reader.capture == originalCapture && model?.configured == true }
    init(reader: CityValueBoundedMapReader, current: @escaping () -> Bool, factory: @escaping (CityValueBoundedCapture) -> CityPlayerValueController?) {
        self.reader = reader; self.current = current; self.factory = factory
    }
    func reload() async {
        guard isCurrent else { retire(); return }
        model?.suspend()
        await reader.load()
        guard isCurrent, !Task.isCancelled else { return }
        guard let capture = reader.capture else { return }
        if let originalCapture {
            // Never replace a pending original intent with a controller for another page.
            mappingChanged = capture != originalCapture
            if !mappingChanged, model?.configured == true { await model?.load() }
        } else {
            guard let next = factory(capture) else { return }
            originalCapture = capture; model = next
        }
    }
    func suspend() { model?.suspend(); reader.suspend() }
    func retire() { retired = true; suspend() }
}
@MainActor struct SessionCityPlayerValueView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @State private var owner: CityPlayerValueHostOwner?
    @State private var resolved = false
    @State private var retired = false
    @State private var work: Task<Void,Never>?
    var body: some View {
        Group {
            if let owner, owner.canPresent, let model = owner.model {
                CityPlayerValuePanel(model: model, source: { visit in
                    session.makeCityPlayerValueNodeRuntime(visit: visit, owner: owner)
                })
            } else {
                VStack(spacing: 12) {
                    CityPlayerValueCopy.text(owner?.reader.notPublished == true ? "notPublished" : "disabled")
                    if owner?.reader.loading == true { ProgressView() }
                    Button { reload() } label: { CityPlayerValueCopy.text("refresh") }
                        .disabled(retired || phase != .active || owner?.isCurrent != true)
                }
            }
        }
        .navigationTitle(CityPlayerValueCopy.string("title"))
        .onAppear { guard !resolved, !retired else { return }; resolved = true; owner = session.makeCityPlayerValueOwner(); reload() }
        .onChange(of: session.cityPlayerReadIdentity) { _, _ in retire() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in if owner?.isCurrent != true { retire() } }
        .onChange(of: phase) { _, value in
            if value != .active { work?.cancel(); work = nil; owner?.suspend() }
            // Foreground recovery is explicit: no implicit feedback or bind retry.
        }
        .onDisappear { retire() }
    }
    private func reload() {
        guard !retired, phase == .active, let owner, owner.isCurrent else { return }
        work?.cancel(); work = Task { await owner.reload() }
    }
    private func retire() { retired = true; work?.cancel(); work = nil; owner?.retire() }
}
