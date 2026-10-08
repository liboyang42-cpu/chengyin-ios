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
        } else if failure?.isForbidden == true {
            titleKey = "messaging.accessDenied"; detailKey = "messaging.accessDeniedHint"
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

struct MessagingReadScreenInput: Equatable {
    let readerID: ObjectIdentifier
    let identity: MessagingReadIdentity?
    let isConfigured: Bool
    let refreshRevision: UInt64
    @MainActor init(reader: any MessagingReading, refreshRevision: UInt64) {
        readerID = ObjectIdentifier(reader); identity = reader.identity
        isConfigured = reader.isConfigured; self.refreshRevision = refreshRevision
    }
}

struct MessagingReadScreenToken: Equatable {
    let id: UUID
    let appearance: UUID
    let input: MessagingReadScreenInput
}

/// The shipping read owner binds input/lifetime synchronously. An async task can
/// only consume its pre-created token; it cannot restart or rebind this owner.
@MainActor final class MessagingReadScreenModel<Value>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var loadedInput: MessagingReadScreenInput?
    @Published private(set) var isLoading = true
    @Published private(set) var issue: MessagingLoadIssue?
    @Published private(set) var appearance: UUID?
    @Published private(set) var invalidationRevision: UInt64 = 0
    private(set) var input: MessagingReadScreenInput?
    private var reader: (any MessagingReading)?
    private var queued: MessagingReadScreenToken?
    private var currentRequest: MessagingReadScreenToken?

    func appear(reader: any MessagingReading, refreshRevision: UInt64) -> MessagingReadScreenToken? {
        appearance = UUID(); queued = nil; currentRequest = nil
        self.reader = reader
        let next = MessagingReadScreenInput(reader: reader, refreshRevision: refreshRevision)
        input = next
        // A navigation return may retain its exact completed snapshot. Pending or
        // invalidated reads have no loadedInput and start a new appearance read.
        if next.isConfigured, next.identity != nil, loadedInput == next, value != nil {
            isLoading = false; issue = nil; return nil
        }
        clearSnapshot()
        return prepareRefresh(appearance: appearance, input: next)
    }
    func updateInput(reader: any MessagingReading, refreshRevision: UInt64,
                     appearance expected: UUID?) -> MessagingReadScreenToken? {
        guard let expected, appearance == expected else { return nil }
        let next = MessagingReadScreenInput(reader: reader, refreshRevision: refreshRevision)
        if let input, next.readerID == input.readerID, next.identity == input.identity,
           next.refreshRevision < input.refreshRevision { return nil }
        guard input != next else { return nil }
        self.reader = reader; input = next; queued = nil; currentRequest = nil
        clearSnapshot()
        return prepareRefresh(appearance: expected, input: next)
    }
    /// Button and refresh handlers must pass the appearance/input captured by
    /// their rendered view, rather than look up a replacement lifetime later.
    func prepareRefresh(appearance expected: UUID?, input expectedInput: MessagingReadScreenInput) -> MessagingReadScreenToken? {
        guard let expected, appearance == expected, input == expectedInput,
              matchesLiveReader(expectedInput) else { return nil }
        let token = MessagingReadScreenToken(id: UUID(), appearance: expected, input: expectedInput)
        queued = token; currentRequest = token
        clearSnapshot(); isLoading = true
        return token
    }
    func perform(_ token: MessagingReadScreenToken, load: () async throws -> Value) async {
        guard queued == token, hasCurrentBinding(token) else { return }
        queued = nil
        guard matchesLiveReader(token.input) else {
            clearSnapshot(); currentRequest = nil; return
        }
        guard !Task.isCancelled else {
            finishFailure(CancellationError(), token: token); return
        }
        do {
            let result = try await load()
            guard isCurrent(token) else { return }
            if Task.isCancelled { finishFailure(CancellationError(), token: token); return }
            value = result; loadedInput = token.input; issue = nil; isLoading = false
            currentRequest = nil
        } catch { finishFailure(error, token: token) }
    }
    /// A same-scope accepted mutation may invalidate cached data after its sheet
    /// closes. This records staleness only: no appearance, token or read is created.
    @discardableResult func invalidate(reader source: any MessagingReading,
                                       identity expected: MessagingReadIdentity) -> Bool {
        guard let input, input.readerID == ObjectIdentifier(source), input.identity == expected,
              source.identity == expected, matchesLiveReader(input) else { return false }
        queued = nil; currentRequest = nil
        clearSnapshot()
        invalidationRevision &+= 1
        return true
    }
    func disappear() {
        appearance = nil; queued = nil; currentRequest = nil; isLoading = false
        // Completed data remains scoped to loadedInput for Back navigation only.
    }
    private func clearSnapshot() {
        value = nil; loadedInput = nil; issue = nil; isLoading = false
    }
    private func matchesLiveReader(_ expected: MessagingReadScreenInput) -> Bool {
        guard let reader else { return false }
        return expected.identity != nil && expected.isConfigured && reader.isConfigured
            && ObjectIdentifier(reader) == expected.readerID && reader.identity == expected.identity
    }
    private func hasCurrentBinding(_ token: MessagingReadScreenToken) -> Bool {
        appearance == token.appearance && input == token.input && currentRequest == token
    }
    private func isCurrent(_ token: MessagingReadScreenToken) -> Bool {
        hasCurrentBinding(token) && matchesLiveReader(token.input)
    }
    private func finishFailure(_ error: Error, token: MessagingReadScreenToken) {
        guard isCurrent(token) else { return }
        value = nil; loadedInput = nil; issue = MessagingLoadIssue(error); isLoading = false
        currentRequest = nil
    }
}

@MainActor
struct MessagingReadScreen<Value, Content: View>: View {
    let reader: any MessagingReading
    let accessibilityPrefix: String
    let refreshRevision: UInt64
    let load: () async throws -> Value
    let content: (Value) -> Content
    @StateObject private var model: MessagingReadScreenModel<Value>

    init(reader: any MessagingReading, accessibilityPrefix: String, refreshRevision: UInt64 = 0,
         model: MessagingReadScreenModel<Value>? = nil,
         load: @escaping () async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.reader = reader; self.accessibilityPrefix = accessibilityPrefix
        self.refreshRevision = refreshRevision
        _model = StateObject(wrappedValue: model ?? MessagingReadScreenModel<Value>())
        self.load = load; self.content = content
    }
    var body: some View {
        let input = MessagingReadScreenInput(reader: reader, refreshRevision: refreshRevision)
        let appearance = model.appearance
        ZStack {
            if !reader.isConfigured {
                MessagingIssueView(issue: .init(APIError.notConfigured), identifier: accessibilityPrefix + ".unconfigured", retry: {})
            } else if reader.identity == nil {
                MessagingIssueView(issue: .init(APIError.unauthorized), identifier: accessibilityPrefix + ".signedOut", retry: {})
            } else if model.isLoading {
                ProgressView("messaging.loading").accessibilityIdentifier(accessibilityPrefix + ".loading")
            } else if let issue = model.issue {
                MessagingIssueView(issue: issue, identifier: accessibilityPrefix + ".error") {
                    queue(model.prepareRefresh(appearance: appearance, input: input))
                }
            } else if let value = model.value, model.loadedInput == input {
                content(value)
            } else {
                ProgressView("messaging.loading")
            }
        }
        .privacySensitive()
        .refreshable {
            guard let token = model.prepareRefresh(appearance: appearance, input: input) else { return }
            await model.perform(token, load: load)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("messaging.refresh", systemImage: "arrow.clockwise") {
                    queue(model.prepareRefresh(appearance: appearance, input: input))
                }
                    .disabled(model.isLoading || !reader.isConfigured || reader.identity == nil)
                    .accessibilityIdentifier(accessibilityPrefix + ".refresh")
            }
        }
        .onAppear { queue(model.appear(reader: reader, refreshRevision: refreshRevision)) }
        .onChange(of: input) { _, _ in
            queue(model.updateInput(reader: reader, refreshRevision: refreshRevision, appearance: appearance))
        }
        .onChange(of: model.invalidationRevision) { _, _ in
            // Only the currently rendered list may consume its own appearance.
            // Offscreen owners retain invalidation until their next appear.
            queue(model.prepareRefresh(appearance: appearance, input: input))
        }
        .onDisappear { model.disappear() }
    }
    private func queue(_ token: MessagingReadScreenToken?) {
        guard let token else { return }
        let owner = model, operation = load
        Task { await owner.perform(token, load: operation) }
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
        Text("messaging.previewUnavailable").foregroundStyle(.secondary)
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
