import SwiftUI

struct FreeExploreBundleReadProvider {
    let revision: UUID
    let available: @MainActor () -> Bool
    let make: @MainActor (ProfileOrder, Int, any ProfileReading) -> FreeExploreBundleReadHost?
}
private struct FreeExploreBundleProviderKey: EnvironmentKey {
    static let defaultValue: FreeExploreBundleReadProvider? = nil
}
extension EnvironmentValues {
    var freeExploreBundleReadProvider: FreeExploreBundleReadProvider? {
        get { self[FreeExploreBundleProviderKey.self] }
        set { self[FreeExploreBundleProviderKey.self] = newValue }
    }
}

@MainActor struct FreeExploreBundleReadEntry: View {
    let order: ProfileOrder
    let requestedID: Int
    let origin: any ProfileReading
    @Environment(\.freeExploreBundleReadProvider) private var provider
    @State private var host: FreeExploreBundleReadHost?
    @State private var presented = false
    @State private var visible = false
    var body: some View {
        Group {
            if provider?.available() == true, origin.isConfigured,
               order.id == requestedID, order.memberID == origin.identity?.accountID {
                Section {
                    Button {
                        guard visible, !presented, let provider, provider.available(),
                              let created = provider.make(order, requestedID, origin) else { return }
                        host = created; presented = true
                    } label: { Text("title", tableName: "FreeExploreBundleLaunch") }
                    .accessibilityIdentifier("freeBundle.open")
                }
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false } // a push is NOT retirement
        .onChange(of: order) { _, _ in retire() }
        .onChange(of: requestedID) { _, _ in retire() }
        .onChange(of: origin.identity) { _, _ in retire() }
        .onChange(of: origin.isConfigured) { _, _ in retire() }
        .onChange(of: ObjectIdentifier(origin)) { _, _ in retire() }
        .onChange(of: provider?.revision) { _, _ in retire() }
        .onChange(of: provider?.available() == true) { _, available in if !available { retire() } }
        .onChange(of: presented) { _, value in if !value { retire() } }
        .navigationDestination(isPresented: $presented) {
            if let host { FreeExploreBundleReadDestination(host: host) }
        }
    }
    private func retire() { host?.retire(); host = nil; presented = false }
}

@MainActor private struct FreeExploreBundleReadDestination: View {
    @Bindable var host: FreeExploreBundleReadHost
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !host.current { Text("stale", tableName: "FreeExploreBundleLaunch") }
            else if let model = host.model { FreeExploreBundleLaunchView(model: model) }
            else if host.busy { ProgressView { Text("loading", tableName: "FreeExploreBundleLaunch") } }
            else if host.legacy { Text("legacy", tableName: "FreeExploreBundleLaunch") }
            else if host.failed {
                VStack {
                    Text("error", tableName: "FreeExploreBundleLaunch")
                    Button { Task { await host.load() } } label: { Text("recover", tableName: "FreeExploreBundleLaunch") }
                }
            }
        }
        .task { await host.load() }
        .onChange(of: host.current) { _, current in if !current { host.retire() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { host.retire() } }
        .onDisappear { host.retire() } // no writer/review sheets can open in this read-only host
    }
}
