import SwiftUI

@MainActor private final class PaymentProviderReturnModel: ObservableObject {
    let flow: PaymentProviderReturnFlow
    @Published var revision = 0
    init(_ flow: PaymentProviderReturnFlow) { self.flow = flow; flow.onChange = { [weak self] in self?.revision += 1 } }
}
@MainActor struct PaymentProviderReturnSheet: View {
    @StateObject private var model: PaymentProviderReturnModel
    let finish: (PaymentProviderReturnPhase) -> Void
    init(flow: PaymentProviderReturnFlow, finish: @escaping (PaymentProviderReturnPhase) -> Void) {
        _model = StateObject(wrappedValue: PaymentProviderReturnModel(flow)); self.finish = finish
    }
    var body: some View {
        VStack(spacing: 20) {
            switch model.flow.phase {
            case .idle, .checking: ProgressView("contextSelfPlay.checking")
            case .paid, .accepted:
                Image(systemName: "checkmark.circle").font(.largeTitle).accessibilityHidden(true)
                Text(model.flow.phase == .paid ? "contextSelfPlay.paymentConfirmed" : "contextSelfPlay.passConfirmed").font(.title2)
            case .failed:
                Image(systemName: "info.circle").font(.largeTitle).accessibilityHidden(true)
                Text("contextSelfPlay.failed")
                Button("action.done") { finish(.failed) }.accessibilityIdentifier("contextSelfPlay.result.close")
            case .unknown, .accessDenied: ProgressView()
            }
        }.padding().interactiveDismissDisabled()
        .task { await model.flow.reconcile() }
        .task(id: model.flow.phase) {
            let phase = model.flow.phase
            if phase == .unknown || phase == .accessDenied { finish(phase) }
            else if phase == .paid || phase == .accepted {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard !Task.isCancelled, model.flow.phase == phase else { return }; finish(phase)
            }
        }
        .onDisappear { model.flow.leave() }
    }
}
