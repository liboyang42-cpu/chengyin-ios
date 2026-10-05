import SwiftUI

@MainActor final class AccountCollectionScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = AccountCollectionReadModel<Value>()
    var isLoading: Bool { state.isLoading }
    var loadedScope: UUID? { state.loadedScope }
    func value(scope: UUID) -> Value? { state.visibleValue(scope: scope) }
    func issue(scope: UUID) -> AccountCollectionIssue? { state.visibleIssue(scope: scope) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func load(scope: UUID, currentScope: () -> UUID, operation: () async throws -> Value) async {
        revision &+= 1
        await state.load(scope: scope, currentScope: currentScope, operation: operation)
        revision &+= 1
    }
}
@MainActor final class AccountCollectionFavoritesScreenModel: ObservableObject {
    @Published private var revision: UInt64 = 0
    let state = AccountCollectionFavoritesModel()
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func refresh(reader: any AccountCollectionReading, pageSize: Int) async {
        let scope = reader.scope
        revision &+= 1
        await state.refresh(scope: scope, currentScope: { reader.scope }) {
            try await reader.favoriteTopics(pageNumber: 1, pageSize: pageSize)
        }
        revision &+= 1
    }
    func loadMore(reader: any AccountCollectionReading, pageSize: Int) async {
        let scope = reader.scope
        revision &+= 1
        await state.loadMore(scope: scope, currentScope: { reader.scope }) { page in
            try await reader.favoriteTopics(pageNumber: page, pageSize: pageSize)
        }
        revision &+= 1
    }
}
@MainActor final class AccountCollectionPostsScreenModel: ObservableObject {
    @Published private var revision: UInt64 = 0
    let state = AccountCollectionPostsModel()
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func refresh(reader: any AccountCollectionReading, pageSize: Int) async {
        let scope = reader.scope
        revision &+= 1
        await state.refresh(scope: scope, currentScope: { reader.scope }) {
            try await reader.favoritePosts(pageNumber: 1, pageSize: pageSize)
        }
        revision &+= 1
    }
    func loadMore(reader: any AccountCollectionReading, pageSize: Int) async {
        let scope = reader.scope
        revision &+= 1
        await state.loadMore(scope: scope, currentScope: { reader.scope }) { page in
            try await reader.favoritePosts(pageNumber: page, pageSize: pageSize)
        }
        revision &+= 1
    }
}
struct AccountCollectionLoadKey: Hashable {
    let scope: UUID
    let configured: Bool
    let authenticated: Bool
    let query: String
    let id: Int?
    @MainActor init(reader: any AccountCollectionReading, query: String = "", id: Int? = nil) {
        scope = reader.scope; configured = reader.isConfigured; authenticated = reader.isAuthenticated
        self.query = query; self.id = id
    }
}

struct AccountCollectionIssueView: View {
    let issue: AccountCollectionIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                if case .server(let message) = issue, !message.isEmpty { Text(verbatim: message) }
                else { Text(LocalizedStringKey(issue.localizationKey)) }
            } icon: { Image(systemName: issue == .login ? "lock" : "exclamationmark.circle") }
            .accessibilityIdentifier("accountCollection.issue")
            if let retry, issue != .login, issue != .notConfigured {
                Button("accountCollection.retry", action: retry)
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("accountCollection.retry")
            }
        }.padding(.vertical, 10)
    }
}
struct AccountCollectionTitle: View {
    let value: String?
    let fallback: LocalizedStringKey
    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: value) }
        else { Text(fallback) }
    }
}
struct AccountCollectionCouponBadge: View {
    let status: AccountCollectionCouponStatus
    private var symbol: String {
        switch status {
        case .unused: return "ticket"
        case .used: return "checkmark.circle"
        case .expired: return "calendar.badge.exclamationmark"
        case .invalid: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    var body: some View {
        QuestifyStatusBadge(title: LocalizedStringKey("accountCollection.coupon.status." + status.rawValue),
                            systemImage: symbol, emphasized: status == .unused, stateKey: status.rawValue)
    }
}
struct AccountCollectionCouponDate: View {
    let label: LocalizedStringKey
    let value: String?
    var body: some View {
        if let day = AccountCollectionCoupon.calendarDay(value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: day).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Refresh only the visible screen after foregrounding. Navigation away invalidates any
/// pending completion without destroying the list link that owns a pushed destination.
struct AccountCollectionReadLifecycle: ViewModifier {
    let key: AccountCollectionLoadKey
    let refresh: () async -> Void
    let cancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var needsRefresh = false
    func body(content: Content) -> some View {
        content
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
