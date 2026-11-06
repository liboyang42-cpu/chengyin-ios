import SwiftUI

/// A pushed visit never adopts a replacement account or approval. Reopen to obtain a new visit.
@MainActor struct SessionCityMerchantIntentView: View {
    @EnvironmentObject private var session: AppSession
    @State private var controller: CityMerchantOperationsController
    @State private var identity: String?
    @State private var context: RuntimeDependencyContext?
    @State private var retired = false
    init(factory: @MainActor () -> CityMerchantOperationsController) {
        _controller = State(initialValue: factory())
    }
    private var matches: Bool {
        guard !retired, let identity, identity != "disabled", let context,
              let live = session.currentRuntimeDependencyContext else { return false }
        return identity == session.cityMerchantIntentIdentity && ContentDraftContextFence.matches(context, live) && context.session == live.session
    }
    var body: some View {
        Group {
            if matches { CityMerchantOperationsView(controller: controller) }
            else { Text("cityMerchant.status.disabled", tableName: "CityMerchantOperations") }
        }
        .onAppear {
            guard identity == nil, !retired else { return }
            identity = session.cityMerchantIntentIdentity
            context = session.currentRuntimeDependencyContext
        }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in retire() }
        .onChange(of: session.cityMerchantIntentIdentity) { _, _ in retire() }
        .onDisappear { retire() }
        .task {
            // Only checks the local approval clock/revision. Never polls HTTP or submits work.
            while !Task.isCancelled {
                if identity != nil && !matches { retire(); return }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
        }
    }
    private func retire() {
        retired = true
        controller.invalidate()
    }
}
