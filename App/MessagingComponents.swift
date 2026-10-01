import SwiftUI

struct MessagingLoadIssue {
    let titleKey: String
    let detailKey: String
    let message: String?
    let canRetry: Bool
    let isTerminal: Bool
    init(_ error: Error) {
        let failure = error as? MessagingReadFailure
        if error as? APIError == .unauthorized || failure?.isUnauthorized == true {
            titleKey = "messaging.signInRequired"; detailKey = "messaging.signInHint"
            message = nil; canRetry = false; isTerminal = true
        } else if error as? APIError == .notConfigured {
            titleKey = "messaging.unavailable"; detailKey = "messaging.unconfiguredHint"
            message = nil; canRetry = false; isTerminal = true
        } else if failure?.isClosed == true {
            titleKey = "messaging.closed"; detailKey = "messaging.closedHint"
            message = nil; canRetry = false; isTerminal = true
        } else if error as? APIError == .invalidRequest {
            titleKey = "messaging.missing"; detailKey = "messaging.missingHint"
            message = nil; canRetry = false; isTerminal = true
        } else {
            titleKey = "messaging.loadFailed"
            detailKey = error as? APIError == .malformedResponse ? "messaging.invalidResponse" : "messaging.retryHint"
            // Server text is literal and never evaluated as a localization key or markup.
            message = failure?.message.flatMap { $0.isEmpty ? nil : $0 }
            canRetry = true; isTerminal = false
        }
    }
}

struct MessagingIssueView: View {
    let issue: MessagingLoadIssue
    let identifier: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label { Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier(identifier) }
                icon: { Image(systemName: issue.canRetry ? "exclamationmark.circle" : "lock") }
        } description: {
            if let message = issue.message { Text(verbatim: message) }
            else { Text(LocalizedStringKey(issue.detailKey)) }
        } actions: {
            if issue.canRetry {
                Button("messaging.retry", action: retry).accessibilityIdentifier(identifier + ".retry")
            }
        }
    }
}

struct MessagingEmptyView: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    let identifier: String
    var body: some View {
        ContentUnavailableView {
            Label { Text(title).accessibilityIdentifier(identifier) } icon: { Image(systemName: "bubble.left.and.bubble.right") }
        } description: { Text(hint) }
    }
}

@MainActor
struct MessagingReadScreen<Value, Content: View>: View {
    let reader: any MessagingReading
    let accessibilityPrefix: String
    let load: () async throws -> Value
    let content: (Value) -> Content
    @State private var value: Value?
    @State private var loadedIdentity: MessagingReadIdentity?
    @State private var isLoading = true
    @State private var issue: MessagingLoadIssue?
    @State private var generation: UInt64 = 0

    init(reader: any MessagingReading, accessibilityPrefix: String,
         load: @escaping () async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.reader = reader; self.accessibilityPrefix = accessibilityPrefix
        self.load = load; self.content = content
    }
    var body: some View {
        ZStack {
            if !reader.isConfigured {
                MessagingIssueView(issue: .init(APIError.notConfigured), identifier: accessibilityPrefix + ".unconfigured", retry: {})
            } else if reader.identity == nil {
                MessagingIssueView(issue: .init(APIError.unauthorized), identifier: accessibilityPrefix + ".signedOut", retry: {})
            } else if isLoading {
                ProgressView("messaging.loading").accessibilityIdentifier(accessibilityPrefix + ".loading")
            } else if let issue {
                MessagingIssueView(issue: issue, identifier: accessibilityPrefix + ".error") { Task { await reload() } }
            } else if let value, loadedIdentity == reader.identity {
                content(value)
            } else {
                ProgressView("messaging.loading")
            }
        }
        .privacySensitive()
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("messaging.refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    .disabled(isLoading || !reader.isConfigured || reader.identity == nil)
                    .accessibilityIdentifier(accessibilityPrefix + ".refresh")
            }
        }
        .task(id: reader.identity) {
            // Native Back navigation retains the list/search/scroll snapshot for this epoch.
            if loadedIdentity == nil || loadedIdentity != reader.identity { await reload() }
        }
        .onDisappear { generation &+= 1 }
    }
    private func reload() async {
        generation &+= 1
        let request = generation, identity = reader.identity
        value = nil; loadedIdentity = nil; issue = nil; isLoading = true
        guard reader.isConfigured, identity != nil else { isLoading = false; return }
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await load()
            guard generation == request, !Task.isCancelled, identity == reader.identity else { return }
            value = result; loadedIdentity = identity
        } catch is CancellationError {
            // A dismissed or superseded screen cannot resurrect private content.
        } catch {
            guard generation == request, !Task.isCancelled, identity == reader.identity else { return }
            issue = MessagingLoadIssue(error)
        }
    }
}

struct MessagingConversationName: View {
    let conversation: MessagingConversation?
    var body: some View {
        if let name = conversation?.counterparty?.nickname, !name.isEmpty { Text(verbatim: name) }
        else {
            switch conversation?.kind {
            case .system: Text("messaging.system")
            case .merchant: Text("messaging.official")
            case .group: Text("messaging.group")
            default: Text("messaging.member")
            }
        }
    }
}

struct MessagingConversationKindLabel: View {
    let kind: MessagingConversationKind
    var body: some View {
        switch kind {
        case .direct: Text("messaging.kind.direct")
        case .system: Text("messaging.kind.system")
        case .merchant: Text("messaging.kind.merchant")
        case .group: Text("messaging.kind.group")
        case .unknown: Text("messaging.kind.unknown")
        }
    }
}

struct MessagingPreview: View {
    let conversation: MessagingConversation
    var body: some View {
        if let text = conversation.lastMessageText, !text.isEmpty { Text(verbatim: text) }
        else if conversation.lastMessageType == 2 { Text("messaging.image") }
        else if conversation.lastMessageType == 3 { Text("messaging.card") }
    }
}

struct MessagingOptionalRow: View {
    let title: LocalizedStringKey
    let value: String?
    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent(title) { Text(verbatim: value).textSelection(.enabled) }
        }
    }
}

struct MessagingSenderName: View {
    let message: MessagingMessage
    let conversation: MessagingConversation?
    let accountID: Int
    var body: some View {
        if message.senderID == accountID { Text("messaging.you") }
        else if let name = message.senderName, !name.isEmpty { Text(verbatim: name) }
        else if message.senderID == 0 { Text("messaging.system") }
        else { MessagingConversationName(conversation: conversation) }
    }
}
