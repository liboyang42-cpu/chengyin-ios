import SwiftUI

@MainActor final class CooperationScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = CooperationReadModel<Value>()
    private var task: Task<Void, Never>?
    var isLoading: Bool { state.isLoading }
    var loadedScope: UUID? { state.loadedScope }
    var loadedOwner: CooperationReadOwner? { state.loadedOwner }
    var presentation: CooperationReadPresentation? { state.presentation }
    func value(owner: CooperationReadOwner) -> Value? { state.visibleValue(owner: owner) }
    func issue(owner: CooperationReadOwner) -> CooperationIssue? { state.visibleIssue(owner: owner) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func beginPresentation(owner: CooperationReadOwner) -> CooperationReadPresentation? {
        task?.cancel(); task = nil
        let permit = state.beginPresentation(owner: owner); revision &+= 1
        return permit
    }
    func endPresentation(preservingValues: Bool = true) {
        task?.cancel(); task = nil
        state.endPresentation(preservingValues: preservingValues); revision &+= 1
    }
    func accepts(_ permit: CooperationReadPresentation, currentOwner: CooperationReadOwner) -> Bool {
        state.accepts(permit, currentOwner: currentOwner)
    }
    @discardableResult func schedule(presentation: CooperationReadPresentation?, currentOwner: CooperationReadOwner,
                  operation: @escaping @MainActor (CooperationReadPresentation) async -> Void) -> Task<Void, Never>? {
        guard let presentation, accepts(presentation, currentOwner: currentOwner) else { return nil }
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, self.accepts(presentation, currentOwner: currentOwner) else { return }
            await operation(presentation)
        }
        return task
    }
    func refresh(presentation: CooperationReadPresentation?, currentOwner: CooperationReadOwner,
                 operation: @escaping @MainActor (CooperationReadPresentation) async -> Void) async {
        guard let pending = schedule(presentation: presentation, currentOwner: currentOwner, operation: operation) else { return }
        await withTaskCancellationHandler { await pending.value } onCancel: { pending.cancel() }
    }
    func load(presentation: CooperationReadPresentation, currentOwner: () -> CooperationReadOwner,
              operation: () async throws -> Value) async {
        guard !Task.isCancelled, accepts(presentation, currentOwner: currentOwner()) else { return }
        revision &+= 1
        await state.load(presentation: presentation, currentOwner: currentOwner, operation: operation)
        revision &+= 1
    }
}

/// Native List/NavigationStack transitions respect the system Reduce Motion setting.
/// No per-row timer, custom spring, animation package or invented success feedback.
@MainActor struct CooperationReadScreen<Value, Content: View>: View {
    let reader: any CooperationReading
    let resource: String
    let operation: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @StateObject private var model = CooperationScreenModel<Value>()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    private var key: CooperationReadOwner { CooperationReadOwner(reader: reader, resource: resource) }
    var body: some View {
        let owner = key
        let permit = model.presentation
        List {
            if !reader.isAuthenticated { CooperationIssueView(issue: .login) }
            else if !reader.isConfigured { CooperationIssueView(issue: .unconfigured) }
            else if let issue = model.issue(owner: owner) {
                CooperationIssueView(issue: issue, retry: issue.canRetry ? { schedule(permit) } : nil)
            } else if let value = model.value(owner: owner) {
                if reader.isOfflineExample { Label("cooperation.offline", systemImage: "network.slash").font(.footnote).foregroundStyle(.secondary) }
                content(value)
            } else { ProgressView("cooperation.loading").accessibilityIdentifier("cooperation.loading") }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            if reader.isAuthenticated && reader.isConfigured && model.value(owner: owner) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { schedule(permit) } label: { Label("cooperation.refresh", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("cooperation.refresh").disabled(model.isLoading)
                }
            }
        }
        .refreshable {
            await model.refresh(presentation: permit, currentOwner: key) { await load($0) }
        }
        .onAppear { isVisible = true; replacePresentation() }
        .onDisappear { isVisible = false; model.endPresentation() }
        .onChange(of: key) { _, _ in replacePresentation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.endPresentation(preservingValues: false) }
            else if phase == .active && isVisible && model.presentation == nil { replacePresentation() }
        }
    }
    private func replacePresentation() {
        guard isVisible, scenePhase == .active else { model.endPresentation(preservingValues: false); return }
        schedule(model.beginPresentation(owner: key))
    }
    private func schedule(_ permit: CooperationReadPresentation?) {
        model.schedule(presentation: permit, currentOwner: key) { await load($0) }
    }
    private func load(_ permit: CooperationReadPresentation) async {
        guard isVisible, scenePhase == .active, !Task.isCancelled,
              model.accepts(permit, currentOwner: key) else { return }
        await model.load(presentation: permit, currentOwner: { key }, operation: operation)
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
/// Formerly a standing "handling isn't available here yet" footnote. Screens show the actions they
/// support and hide the rest, so this renders nothing.
struct CooperationReadOnlyNotice: View {
    var body: some View { EmptyView() }
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
    @Environment(\.locale) private var locale
    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            RevolutInsetRow(title: appLocalized(String.LocalizationValue(stringLiteral: key), locale: locale), value: value)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
        }
    }
}
struct CooperationTimeField: View {
    let key: String
    let value: CooperationSourceTime?
    @Environment(\.locale) private var locale
    var body: some View {
        if let value {
            switch value {
            case .text(let text): CooperationField(key: key, value: text)
            case .milliseconds:
                if let date = value.date {
                    RevolutInsetRow(title: appLocalized(String.LocalizationValue(stringLiteral: key), locale: locale),
                                    value: date.formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
                        .accessibilityElement(children: .combine)
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
