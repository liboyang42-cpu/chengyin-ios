import SwiftUI

/// A concrete root exists before the task starts. Refresh/retry/disappearance advance the
/// generation, so a slower response cannot replace a newer result or resurrect a dismissed page.
@MainActor
struct ProfileReadScreen<Value, Content: View>: View {
    let reader: any ProfileReading
    let accessibilityPrefix: String
    let load: () async throws -> Value
    let content: (Value) -> Content
    /// Nil keeps the shared Profile copy; a screen may supply its source-specific copy.
    let issueCopy: ProfileReadIssueCopy?
    @State private var value: Value?
    @State private var isLoading = true
    @State private var issue: ProfileLoadIssue?
    @State private var generation: UInt64 = 0
    @State private var loadOwner = ManualMapReadTaskOwner()

    init(reader: any ProfileReading, accessibilityPrefix: String,
         issueCopy: ProfileReadIssueCopy? = nil,
         load: @escaping () async throws -> Value,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.reader = reader
        self.accessibilityPrefix = accessibilityPrefix
        self.issueCopy = issueCopy
        self.load = load
        self.content = content
    }

    var body: some View {
        ZStack {
            if reader.identity == nil {
                ContentUnavailableView(LocalizedStringKey(issueCopy?.signInTitleKey ?? "profile.signInRequired"), systemImage: "person.crop.circle.badge.exclamationmark", description: Text(LocalizedStringKey(issueCopy?.signInDetailKey ?? "auth.expired")))
                    .accessibilityIdentifier(accessibilityPrefix + ".signIn")
            } else if !reader.isConfigured {
                ContentUnavailableView("profile.unavailable", systemImage: "network.slash", description: Text("auth.notConfigured"))
                    .accessibilityIdentifier(accessibilityPrefix + ".unavailable")
            } else if isLoading {
                ProgressView(LocalizedStringKey(issueCopy?.loadingKey ?? "profile.loading")).accessibilityIdentifier(accessibilityPrefix + ".loading")
            } else if let issue {
                ContentUnavailableView {
                    Label {
                        Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier(accessibilityPrefix + ".error")
                    } icon: { Image(systemName: "exclamationmark.circle") }
                } description: {
                    if let message = issue.message { Text(verbatim: message) }
                    else if !issue.detailKey.isEmpty { Text(LocalizedStringKey(issue.detailKey)) }
                } actions: {
                    if issue.canRetry {
                        Button("action.retry") { loadOwner.start { await reload() } }
                            .accessibilityIdentifier(accessibilityPrefix + ".retry")
                    }
                }
            } else if let value {
                content(value)
            }
        }
        .refreshable { await loadOwner.run { await reload() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("profile.refresh", systemImage: "arrow.clockwise") { loadOwner.start { await reload() } }
                    .disabled(isLoading || !reader.isConfigured || reader.identity == nil)
                    .accessibilityIdentifier(accessibilityPrefix + ".refresh")
            }
        }
        .task(id: reader.identity) { loadOwner.activate(); await loadOwner.run { await reload() } }
        .onDisappear {
            // Keep the immutable list snapshot while its NavigationLink destination is
            // pushed. Removing that link here can unexpectedly pop native navigation.
            // Account replacement destroys the root; a new appearance refreshes the data.
            loadOwner.deactivate(); generation &+= 1
        }
    }
    private func reload() async {
        generation &+= 1
        let request = generation
        value = nil; issue = nil; isLoading = true
        guard reader.isConfigured, reader.identity != nil else { isLoading = false; return }
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await load()
            guard generation == request, !Task.isCancelled else { return }
            value = result
        } catch is CancellationError {
            // Navigation/session changes discard the result; they are not networking errors.
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            issue = issueCopy.map { ProfileLoadIssue(error, copy: $0) } ?? ProfileLoadIssue(error)
        }
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
    /// Screen-specific source copy. Sign-in and not-configured remain non-retryable;
    /// a 403 keeps any server message, generic failures use the fixed source wording.
    init(_ error: Error, copy: ProfileReadIssueCopy) {
        switch ProfileReadIssueCopy.kind(of: error) {
        case .signIn:
            titleKey = copy.signInTitleKey; detailKey = copy.signInDetailKey; message = nil; canRetry = false
        case .forbidden:
            let failure = error as? ProfileReadFailure
            titleKey = copy.forbiddenTitleKey; detailKey = ""
            message = failure?.message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            canRetry = true
        case .malformed:
            titleKey = copy.failureTitleKey; detailKey = copy.malformedDetailKey; message = nil; canRetry = true
        case .failure:
            if error as? APIError == .notConfigured {
                titleKey = "profile.unavailable"; detailKey = "auth.notConfigured"; message = nil; canRetry = false
            } else {
                titleKey = copy.failureTitleKey; detailKey = copy.failureDetailKey; message = nil; canRetry = true
            }
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
