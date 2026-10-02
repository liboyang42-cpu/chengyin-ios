import SwiftUI

@MainActor final class GrowthCenterScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = GrowthCenterReadModel<Value>()
    var isLoading: Bool { state.isLoading }
    var loadedKey: GrowthCenterLoadKey? { state.loadedKey }
    func value(key: GrowthCenterLoadKey) -> Value? { state.visibleValue(key: key) }
    func issue(key: GrowthCenterLoadKey) -> GrowthCenterIssue? { state.visibleIssue(key: key) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func load(key: GrowthCenterLoadKey, currentKey: () -> GrowthCenterLoadKey, operation: () async throws -> Value) async {
        revision &+= 1
        await state.load(key: key, currentKey: currentKey, operation: operation)
        revision &+= 1
    }
}
struct GrowthCenterIssueView: View {
    let issue: GrowthCenterIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                if case .server(let message) = issue { Text(verbatim: message) }
                else { Text(LocalizedStringKey(issue.localizationKey)) }
            } icon: { Image(systemName: issue == .login ? "lock" : "info.circle") }
            .accessibilityIdentifier("growth.issue")
            if let retry, issue != .login, issue != .notConfigured {
                Button("growth.retry", action: retry).buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("growth.retry")
            }
        }.padding(.vertical, 8)
    }
}
struct GrowthCenterName: View {
    let name: String?
    let fallback: LocalizedStringKey
    var body: some View {
        if let name = GrowthCenterFormatting.nonempty(name) { Text(verbatim: name) }
        else { Text(fallback) }
    }
}
struct GrowthCenterInteger: View {
    let value: Int?
    var body: some View {
        if let value = GrowthCenterFormatting.nonnegative(value) { Text(value, format: .number).monospacedDigit() }
        else { Text("growth.unknown").accessibilityLabel(Text("growth.unknownValue")) }
    }
}
struct GrowthCenterReadLifecycle: ViewModifier {
    let key: GrowthCenterLoadKey
    let refresh: () async -> Void
    let cancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var needsRefresh = false
    func body(content: Content) -> some View {
        content
            .transaction { if reduceMotion { $0.animation = nil } }
            .task(id: key) { await refresh() }
            .refreshable { await refresh() }
            .onAppear { visible = true; needsRefresh = false }
            .onDisappear { visible = false; cancel() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { needsRefresh = true }
                else if phase == .active, visible, needsRefresh {
                    needsRefresh = false
                    Task { await refresh() }
                }
            }
    }
}
