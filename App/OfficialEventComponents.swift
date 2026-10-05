import SwiftUI

enum OfficialScreenIssue {
    case unconfigured, unauthorized, noPublisherPermission, forbidden, unavailable, failed
    init(_ error: Error) {
        switch error {
        case APIError.notConfigured: self = .unconfigured
        case APIError.unauthorized: self = .unauthorized
        case OfficialReadFailure.noPublisherPermission: self = .noPublisherPermission
        case OfficialReadFailure.forbidden: self = .forbidden
        case OfficialReadFailure.unavailable: self = .unavailable
        default: self = .failed
        }
    }
    var key: LocalizedStringKey {
        switch self {
        case .unconfigured: return "official.notConfigured"
        case .unauthorized: return "official.signInRequired"
        case .noPublisherPermission: return "official.noPublisherPermission"
        case .forbidden: return "official.forbidden"
        case .unavailable: return "official.unavailable"
        case .failed: return "official.failed"
        }
    }
}
struct OfficialIssueView: View {
    let issue: OfficialScreenIssue
    var onLogin: (() -> Void)?
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(issue.key, systemImage: "info.circle")
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("official.issue")
            if case .unauthorized = issue, let onLogin {
                Button("official.signIn", action: onLogin).frame(minHeight: 44)
                    .accessibilityIdentifier("official.signIn")
            } else if case .failed = issue, let retry {
                Button("official.retry", action: retry).frame(minHeight: 44)
                    .accessibilityIdentifier("official.retry")
            }
        }.padding()
    }
}

/// A fresh key hides old data before the next task starts. Generation guards also reject
/// overlapping refreshes and completions after navigation dismissal. The host must redraw
/// its subtree for any session epoch/token/account change, including guest transitions.
@MainActor struct OfficialReadScreen<Value, Content: View>: View {
    let reader: any OfficialEventReading
    var isPrivate = false
    var requestID = ""
    var onLogin: (() -> Void)? = nil
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var issue: OfficialScreenIssue?
    @State private var loadedKey: Key?
    @State private var generation: UInt64 = 0
    @State private var loading = false
    private struct Key: Hashable {
        let scope: UUID
        let configured: Bool
        let authenticated: Bool
        let requestID: String
        let isPrivate: Bool
    }
    private var key: Key {
        Key(scope: reader.scope, configured: reader.isConfigured, authenticated: reader.isAuthenticated,
            requestID: requestID, isPrivate: isPrivate)
    }
    var body: some View {
        // Own loading/cancellation on a stable container, not Group's changing
        // branches, which can restart the initial read when an error appears.
        ZStack(alignment: .topLeading) {
            if isPrivate && !reader.isAuthenticated { OfficialIssueView(issue: .unauthorized, onLogin: onLogin) }
            else if !reader.isConfigured { OfficialIssueView(issue: .unconfigured) }
            else if loadedKey != key || loading { ProgressView("official.loading").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let issue { OfficialIssueView(issue: issue, onLogin: onLogin, retry: { Task { await refresh() } }) }
            else if let value { content(value) }
        }
        .task(id: key) { await refresh() }
        .refreshable { await refresh() }
        .onDisappear { generation &+= 1; loading = false }
    }
    private func refresh() async {
        generation &+= 1
        let operation = generation, captured = key
        value = nil; issue = nil; loadedKey = nil; loading = false
        guard reader.isConfigured, !isPrivate || reader.isAuthenticated else { return }
        loading = true
        defer { if generation == operation { loading = false } }
        do {
            let result = try await load()
            guard !Task.isCancelled, generation == operation, key == captured else { return }
            value = result; loadedKey = captured
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == operation, key == captured else { return }
            issue = OfficialScreenIssue(error); loadedKey = captured
        }
    }
}
struct OfficialReadOnlyNotice: View {
    let offline: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if offline { Label("official.offlineExample", systemImage: "testtube.2") }
            Text("official.readOnly")
        }.font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
struct OfficialEventCard: View {
    let event: OfficialEvent
    var body: some View {
        QuestifyImageEntityCard(imageSource: event.coverImage, title: event.title, subtitle: event.subtitle,
                                fallbackTitle: "official.untitled", fallbackSymbol: "sparkles") {
            Label(LocalizedStringKey(event.statusKey), systemImage: "calendar")
            if event.paused { Label("official.status.paused", systemImage: "pause.circle") }
            if event.recruitmentBlocked == true {
                VStack(alignment: .leading, spacing: 4) {
                    Label("official.informationIncomplete", systemImage: "exclamationmark.triangle")
                        .fontWeight(.semibold)
                    if let reason = event.recruitmentWarningReason { Text(verbatim: reason) }
                    else { Text("official.informationReasonUnknown") }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            if let city = event.city, !city.isEmpty {
                QuestifyImageEntityMetadata(label: "official.city", value: city, systemImage: "mappin")
            } else { Text("official.cityUnknown") }
            if QuestifyCardArtwork.safeURL(event.coverImage) == nil { Text("official.imageUnavailable").font(.caption) }
        }
    }
}
struct OfficialEventTimeValue: View {
    let value: OfficialEventTime?
    var body: some View {
        switch value {
        case .text(let text): Text(verbatim: text)
        case .milliseconds(let number): Text(Date(timeIntervalSince1970: number / 1000), format: .dateTime.year().month().day().hour().minute())
        case nil: Text("official.notAnnounced")
        }
    }
}
