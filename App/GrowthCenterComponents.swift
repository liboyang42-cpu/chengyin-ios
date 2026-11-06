import SwiftUI

@MainActor final class GrowthCenterScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = GrowthCenterReadModel<Value>()
    let overviewReads = GrowthNormalReadTask()
    var isLoading: Bool { state.isLoading }
    var loadedKey: GrowthCenterLoadKey? { state.loadedKey }
    func value(key: GrowthCenterLoadKey) -> Value? { state.visibleValue(key: key) }
    func issue(key: GrowthCenterLoadKey) -> GrowthCenterIssue? { state.visibleIssue(key: key) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { overviewReads.cancel(); state.cancelPending(); revision &+= 1 }
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
            } icon: { Image(systemName: issue == .login ? "lock" : "info.circle").accessibilityHidden(true) }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("growth.issue")
            if let retry, issue != .login, issue != .notConfigured {
                Button("growth.retry", action: retry).buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
                    .accessibilityIdentifier("growth.retry")
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var foregroundRefresh: Task<Void, Never>?
    func body(content: Content) -> some View {
        content
            .transaction { if reduceMotion { $0.animation = nil } }
            .task(id: key) { await refreshWhenActive() }
            .refreshable {
                guard visible else { return }
                await refreshWhenActive()
            }
            .onAppear { visible = true }
            .onDisappear {
                visible = false
                foregroundRefresh?.cancel(); foregroundRefresh = nil
                cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    needsRefresh = true; cancel()
                    foregroundRefresh?.cancel(); foregroundRefresh = nil
                }
                else if phase == .active, visible, needsRefresh {
                    foregroundRefresh?.cancel()
                    foregroundRefresh = Task { @MainActor in
                        // A foreground notification can be queued just before leaving.
                        guard !Task.isCancelled, visible, scenePhase == .active else { return }
                        // Consume pending work only when this presentation can start it.
                        needsRefresh = false
                        await refresh()
                    }
                }
            }
    }
    private func refreshWhenActive() async {
        guard !Task.isCancelled else { return }
        // Identity/scope changes also restart .task while the app is backgrounded.
        // Defer that read instead of undoing the background cancellation.
        guard scenePhase == .active else { needsRefresh = true; return }
        needsRefresh = false
        await refresh()
    }
}

/// Keeps the original labels/values and their source semantics while avoiding
/// truncated two-column metrics at accessibility text sizes.
struct GrowthCenterMetricRow<Value: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let value: () -> Value
    init(_ title: LocalizedStringKey, @ViewBuilder value: @escaping () -> Value) {
        self.title = title; self.value = value
    }
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.secondary)
                    value()
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
            } else {
                LabeledContent { value() } label: { Text(title) }
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

/// Keeps a held anonymous producer distinct from the available personal records.
/// No legacy leaderboard, participant identity, synthetic rank or fallback is offered.
struct GrowthNormalLeaderboardHoldView: View {
    var body: some View {
        Label {
            Text("growthNormalEntry.leaderboard.hold", tableName: "GrowthNormalEntry")
        } icon: { Image(systemName: "lock").accessibilityHidden(true) }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .accessibilityIdentifier("growth.normal.leaderboard.hold")
    }
}
