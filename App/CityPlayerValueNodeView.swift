import SwiftUI

struct CityPlayerValueSourceSelection: Identifiable { let id = UUID(); let visit: CityPlayerValueVisit }

@MainActor struct CityPlayerValueNodeHost: View {
    let visit: CityPlayerValueVisit
    let factory: (CityPlayerValueVisit) -> CityPlayerValueNodeRuntime?
    @State private var runtime: CityPlayerValueNodeRuntime?
    @State private var resolved = false
    var body: some View {
        Group {
            if let runtime { CityPlayerValueNodeView(runtime: runtime) }
            else { CityPlayerValueCopy.text("sourceDisabled") }
        }.task { guard !resolved else { return }; resolved = true; runtime = factory(visit) }
            .navigationTitle(CityPlayerValueCopy.string("sourceAction"))
    }
}
@MainActor struct CityPlayerValueNodeView: View {
    let runtime: CityPlayerValueNodeRuntime
    @Environment(\.scenePhase) private var scenePhase
    @State private var node: RoamNodeDetail?
    @State private var poster: RoamPosterCoordinator?
    @State private var failed = false
    @State private var loading = false
    @State private var work: Task<Void, Never>?
    @State private var generation = UUID()
    var body: some View {
        Group {
            if !runtime.isCurrent { CityPlayerValueCopy.text("sourceDisabled") }
            else if let node, let poster {
                VStack(spacing: 8) {
                    RoamPosterScanView(node: node, coordinator: poster, cameraEnabled: runtime.cameraEnabled,
                        voucherDestination: { AnyView(VerificationCodeView(model: runtime.voucher(), title: node.name)) })
                    if failed { CityPlayerValueCopy.text("sourceReadFailed") }
                    Button { start(recover: true) } label: { CityPlayerValueCopy.text("recoverSource") }
                        .disabled(loading).accessibilityIdentifier("cityValue.recoverSource")
                    CityPlayerValueCopy.text("sourceNoSuccessClaim").font(.footnote).padding(.horizontal)
                }
            } else {
                VStack { if loading { ProgressView() }; if failed { CityPlayerValueCopy.text("sourceReadFailed") }
                    Button { start(recover: false) } label: { CityPlayerValueCopy.text("refresh") }.disabled(loading)
                }
            }
        }.task { start(recover: false) }
            .onDisappear { stop() }
            .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
            .accessibilityIdentifier("cityValue.source")
    }
    private func start(recover: Bool) {
        guard !loading, scenePhase == .active, runtime.isCurrent else { return }
        let ticket = generation; loading = true; failed = false
        work = Task {
            do {
                let value: RoamNodeDetail
                if recover { value = try await runtime.recoverCompletion() } else { value = try await runtime.detail() }
                guard ticket == generation, !Task.isCancelled, runtime.isCurrent else { return }
                poster?.cancel(); node = value; poster = try runtime.poster(node: value); loading = false
            } catch { if ticket == generation, !Task.isCancelled { loading = false; failed = true } }
        }
    }
    private func stop() { generation = UUID(); work?.cancel(); work = nil; loading = false; poster?.cancel(); runtime.stop() }
}
