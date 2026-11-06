import SwiftUI

/// One navigation visit never silently adopts a replacement session.
@MainActor struct SessionCityMerchantValueView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        CityMerchantValueBoardHost(reader: session.makeCityPlayerReader(), identity: session.cityPlayerReadIdentity,
            context: session.currentRuntimeDependencyContext)
    }
}
@MainActor private struct CityMerchantValueBoardHost: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @State var reader: CityPlayerReader
    let identity: String
    let context: RuntimeDependencyContext?
    @State private var originalIdentity: String?
    @State private var originalContext: RuntimeDependencyContext?
    @State private var retired = false
    @State private var work: Task<Void, Never>?
    private var current: Bool {
        guard !retired, let originalIdentity, let originalContext, let live = session.currentRuntimeDependencyContext else { return false }
        return originalIdentity == identity && ContentDraftContextFence.matches(originalContext, live) && originalContext.session == live.session
    }
    var body: some View {
        Group {
            if current, let selected = reader.pointMapContext {
                CityMerchantValueSlot(read: selected.snapshot, reader: reader).id(selected.readID)
            } else if current, reader.state == .loading { ProgressView() }
            else {
                VStack {
                    CityMerchantValueCopy.text(current && reader.state == .notPublished ? "notPublished" : "disabled")
                    Button { reload() } label: { CityMerchantValueCopy.text("refresh") }
                        .disabled(!current || phase != .active || !reader.isConfigured)
                }
            }
        }
        .navigationTitle(CityMerchantValueCopy.string("merchantTitle"))
        .onAppear {
            guard originalIdentity == nil, !retired else { return }
            originalIdentity = identity; originalContext = context; reload()
        }
        .onChange(of: identity) { _, _ in retire() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in if !current { retire() } }
        .onChange(of: phase) { _, value in if value != .active { work?.cancel(); reader.cancel() } }
        .onDisappear { retire() }
    }
    private func reload() {
        guard current, phase == .active else { return }
        work?.cancel(); work = Task { await reader.load() }
    }
    private func retire() { retired = true; work?.cancel(); work = nil; reader.cancel() }
}
@MainActor private struct CityMerchantValueSlot: View {
    @EnvironmentObject private var session: AppSession
    let read: CityReadSnapshot
    let reader: CityPlayerReader
    @State private var model: CityMerchantValueController?
    @State private var resolved = false
    var body: some View {
        Group {
            if let model, model.configured { CityMerchantValueView(model: model, boardTitle: read.board.title) }
            else { CityMerchantValueCopy.text("disabled") }
        }
        .task {
            guard !resolved else { return }; resolved = true
            model = session.makeCityMerchantValueController(read: read, reader: reader)
        }
        .onDisappear { model?.suspend() }
    }
}
