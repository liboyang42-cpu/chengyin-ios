import SwiftUI

@MainActor
private final class WeChatAppAuthModel: ObservableObject {
    let coordinator: WeChatAppAuthCoordinator
    @Published var phase: WeChatAppAuthCoordinator.Phase
    @Published var issue: WeChatAppAuthError?
    init(_ coordinator: WeChatAppAuthCoordinator) {
        self.coordinator = coordinator; phase = coordinator.phase; issue = coordinator.issue
        coordinator.onChange = { [weak self] in
            guard let self else { return }
            self.phase = coordinator.phase; self.issue = coordinator.issue
        }
    }
}

/// Additive CN-only host control; existing password/phone/Apple affordances stay intact.
@MainActor
struct WeChatAppAuthSection: View {
    @StateObject private var model: WeChatAppAuthModel
    let context: AuthChannelSessionSnapshot
    init(coordinator: WeChatAppAuthCoordinator, context: AuthChannelSessionSnapshot) {
        _model = StateObject(wrappedValue: WeChatAppAuthModel(coordinator)); self.context = context
    }
    var body: some View {
        Section {
            Button { model.coordinator.start() } label: {
                Label("auth.wechat.signIn", systemImage: "bubble.left.and.bubble.right")
                    .frame(minHeight: 44)
            }
            .disabled(!model.coordinator.canStart)
            .accessibilityIdentifier("auth.wechat.signIn")
            .accessibilityHint(Text("auth.wechat.hint"))
            if model.coordinator.isWorking {
                ProgressView("auth.wechat.working")
                Button("action.cancel") { model.coordinator.cancel() }
                    .accessibilityIdentifier("auth.wechat.cancel")
            } else if !model.coordinator.canStart {
                Text("auth.wechat.notConfigured").foregroundStyle(.secondary)
                    .accessibilityIdentifier("auth.wechat.gate")
            }
            if let issue = model.issue {
                Text(LocalizedStringKey(issue.localizationKey)).foregroundStyle(.red)
                    .accessibilityIdentifier("auth.wechat.error")
            }
        }
        .onChange(of: context) { _, _ in model.coordinator.cancel() }
        .onDisappear { model.coordinator.cancel() }
    }
}
