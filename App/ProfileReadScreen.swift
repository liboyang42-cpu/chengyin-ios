import SwiftUI

/// A concrete root exists before the task starts. Refresh/retry/disappearance advance the
/// generation, so a slower response cannot replace a newer result or resurrect a dismissed page.
@MainActor
struct ProfileReadScreen<Value, Content: View>: View {
    let reader: any ProfileReading
    let accessibilityPrefix: String
    let requestID: Int?
    let load: () async throws -> Value
    let content: (Value) -> Content
    @State private var model = ProfileReadPresentation<Value>()
    private var readKey: ProfileReadPresentationOwner {
        .init(reader: reader, identity: reader.identity, configured: reader.isConfigured,
              surface: accessibilityPrefix, requestID: requestID)
    }
    private var snapshot: ProfileReadPresentation<Value>.Snapshot { model.snapshot(for: readKey) }
    private var issue: ProfileLoadIssue? { snapshot.error.map(ProfileLoadIssue.init) }
    @State private var loadOwner = ManualMapReadTaskOwner()

    init(reader: any ProfileReading, accessibilityPrefix: String, requestID: Int? = nil,
         load: @escaping () async throws -> Value,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.reader = reader
        self.accessibilityPrefix = accessibilityPrefix
        self.requestID = requestID
        self.load = load
        self.content = content
    }

    var body: some View {
        ZStack {
            if reader.identity == nil {
                ContentUnavailableView("profile.signInRequired", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("auth.expired"))
                    .accessibilityIdentifier(accessibilityPrefix + ".signIn")
            } else if !reader.isConfigured {
                ContentUnavailableView("profile.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
                    .accessibilityIdentifier(accessibilityPrefix + ".unavailable")
            } else if !snapshot.started || snapshot.isLoading {
                ProgressView("profile.loading").accessibilityIdentifier(accessibilityPrefix + ".loading")
            } else if let issue {
                ContentUnavailableView {
                    Label {
                        Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier(accessibilityPrefix + ".error")
                    } icon: { Image(systemName: "exclamationmark.circle") }
                } description: {
                    if let message = issue.message { Text(verbatim: message) }
                    else { Text(LocalizedStringKey(issue.detailKey)) }
                } actions: {
                    if issue.canRetry {
                        Button("action.retry") { loadOwner.start { await reload() } }
                            .accessibilityIdentifier(accessibilityPrefix + ".retry")
                    }
                }
            } else if let value = snapshot.value {
                content(value)
            } else {
                Button("action.retry") { loadOwner.start { await reload() } }
                    .accessibilityIdentifier(accessibilityPrefix + ".retry")
            }
        }
        .refreshable { await loadOwner.run { await reload() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("profile.refresh", systemImage: "arrow.clockwise") { loadOwner.start { await reload() } }
                    .disabled(snapshot.isLoading || !snapshot.started || !reader.isConfigured || reader.identity == nil)
                    .accessibilityIdentifier(accessibilityPrefix + ".refresh")
            }
        }
        .task(id: readKey) {
            guard !Task.isCancelled else { return }
            loadOwner.activate(); model.activate(owner: readKey, source: reader)
            await loadOwner.run { await reload() }
        }
        .onDisappear {
            // Keep the immutable list snapshot while its NavigationLink destination is
            // pushed. Removing that link here can unexpectedly pop native navigation.
            // Account replacement destroys the root; a new appearance refreshes the data.
            loadOwner.deactivate(); model.suspend()
        }
    }
    private func reload() async {
        let captured = readKey
        await model.load(owner: captured, currentOwner: { readKey }) { try await load() }
    }
}

private struct ProfileLoadIssue {
    let titleKey: String
    let detailKey: String
    let message: String?
    let canRetry: Bool
    init(_ error: Error) {
        let failure = error as? ProfileReadFailure
        if error as? APIError == .unauthorized || failure?.isUnauthorized == true {
            titleKey = "profile.signInRequired"; detailKey = "auth.expired"; message = nil; canRetry = false
        } else if error as? APIError == .notConfigured {
            titleKey = "profile.unavailable"; detailKey = "auth.notConfigured"; message = nil; canRetry = false
        } else {
            titleKey = "profile.loadFailed"
            detailKey = error as? APIError == .malformedResponse ? "auth.invalidResponse" : "profile.retryHint"
            message = failure?.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            canRetry = true
        }
    }
}

/// Server strings remain literal text. Empty strings do not produce unlabeled rows.
struct ProfileOptionalRow: View {
    let key: LocalizedStringKey
    let value: String?
    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent(key) { Text(verbatim: value).textSelection(.enabled) }
        }
    }
}

struct ProfileEmptyState: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    let symbol: String
    let identifier: String
    var body: some View {
        ContentUnavailableView {
            Label { Text(title).accessibilityIdentifier(identifier) } icon: { Image(systemName: symbol) }
        } description: { Text(hint) }
    }
}
