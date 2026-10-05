import SwiftUI

@MainActor final class CooperationScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = CooperationReadModel<Value>()
    var isLoading: Bool { state.isLoading }
    func value(scope: UUID) -> Value? { state.visibleValue(scope: scope) }
    func issue(scope: UUID) -> CooperationIssue? { state.visibleIssue(scope: scope) }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func load(scope: UUID, currentScope: () -> UUID, operation: () async throws -> Value) async {
        revision &+= 1
        await state.load(scope: scope, currentScope: currentScope, operation: operation)
        revision &+= 1
    }
}
private struct CooperationLoadKey: Hashable {
    let scope: UUID
    let configured: Bool
    let authenticated: Bool
    let resource: String
}
/// Native List/NavigationStack transitions respect the system Reduce Motion setting.
/// No per-row timer, custom spring, animation package or invented success feedback.
@MainActor struct CooperationReadScreen<Value, Content: View>: View {
    let reader: any CooperationReading
    let resource: String
    let operation: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @StateObject private var model = CooperationScreenModel<Value>()
    @State private var refresh: UInt64 = 0
    private var key: CooperationLoadKey {
        CooperationLoadKey(scope: reader.scope, configured: reader.isConfigured, authenticated: reader.isAuthenticated, resource: "\(resource).\(refresh)")
    }
    var body: some View {
        let scope = reader.scope
        List {
            if !reader.isAuthenticated { CooperationIssueView(issue: .login) }
            else if !reader.isConfigured { CooperationIssueView(issue: .unconfigured) }
            else if let issue = model.issue(scope: scope) {
                CooperationIssueView(issue: issue, retry: issue.canRetry ? { refresh &+= 1 } : nil)
            } else if let value = model.value(scope: scope) {
                if reader.isOfflineExample { Label("cooperation.offline", systemImage: "network.slash").font(.footnote).foregroundStyle(.secondary) }
                content(value)
            } else { ProgressView("cooperation.loading").accessibilityIdentifier("cooperation.loading") }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            if reader.isAuthenticated && reader.isConfigured && model.value(scope: scope) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { refresh &+= 1 } label: { Label("cooperation.refresh", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("cooperation.refresh").disabled(model.isLoading)
                }
            }
        }
        .refreshable { await reload() }
        .task(id: key) { await reload() }
        .onDisappear { model.cancelPending() }
    }
    private func reload() async {
        guard reader.isConfigured, reader.isAuthenticated else { return }
        let scope = reader.scope
        await model.load(scope: scope, currentScope: { reader.scope }, operation: operation)
    }
}
struct CooperationIssueView: View {
    let issue: CooperationIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(LocalizedStringKey(issue.key), systemImage: issue == .login ? "lock" : symbol)
                .font(.headline).accessibilityIdentifier("cooperation.issue")
            if case .server(let text) = issue { Text(verbatim: text).textSelection(.enabled) }
            if case .forbidden(let message) = issue, let message, !message.isEmpty {
                Text(verbatim: message).textSelection(.enabled)
            }
            if let retry { Button("cooperation.retry", action: retry).accessibilityIdentifier("cooperation.retry") }
        }.padding(.vertical, 8)
    }
    private var symbol: String {
        if case .forbidden = issue { return "lock" }
        if case .unavailable = issue { return "tray" }
        return "exclamationmark.triangle"
    }
}
struct CooperationReadOnlyNotice: View {
    var body: some View {
        Label("cooperation.readOnly", systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cooperation.readOnly")
    }
}
struct CooperationName: View {
    let name: String?
    var fallback = "cooperation.unnamed"
    var body: some View {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: name) }
        else { Text(LocalizedStringKey(fallback)) }
    }
}
struct CooperationStatus: View {
    let key: String
    var symbol = "circle"
    var body: some View {
        Label(LocalizedStringKey(key), systemImage: symbol)
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct CooperationField: View {
    let key: String
    let value: String?
    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: value).textSelection(.enabled)
            }.padding(.vertical, 2).accessibilityElement(children: .combine)
        }
    }
}
struct CooperationTimeField: View {
    let key: String
    let value: CooperationSourceTime?
    var body: some View {
        if let value {
            switch value {
            case .text(let text): CooperationField(key: key, value: text)
            case .milliseconds:
                if let date = value.date {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary)
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
}
struct CooperationTopicReference: View {
    let id: Int
    var body: some View { CooperationField(key: "cooperation.topic", value: "#\(id)") }
}
struct CooperationCandidateLink: View {
    let topicID: Int
    let reader: any CooperationReading
    var body: some View {
        if topicID > 0 {
            NavigationLink {
                CooperationCandidatesView(topicID: topicID, reader: reader)
            } label: { Label("cooperation.candidates.title", systemImage: "person.2") }
                .accessibilityIdentifier("cooperation.candidates.\(topicID)")
        }
    }
}
