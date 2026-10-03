import SwiftUI

/// Shared by the normal Account creator section and synthetic entry-wiring recorder.
struct OwnerDraftAccountLink: View {
    let browser: OwnerDraftBrowser?
    var body: some View {
        NavigationLink { OwnerDraftDestination(browser: browser) } label: {
            Label("ownerDraft.title", systemImage: "doc.on.doc")
        }.accessibilityIdentifier("account.ownerDrafts")
    }
}

struct OwnerDraftDestination: View {
    let browser: OwnerDraftBrowser?
    var body: some View {
        Group {
            if let browser { OwnerDraftBrowserView(browser: browser).id(browser.identity) }
            else {
                ContentUnavailableView("ownerDraft.notConfigured.title", systemImage: "icloud.slash",
                    description: Text("ownerDraft.notConfigured.detail"))
                    .accessibilityIdentifier("ownerDraft.notConfigured")
            }
        }.appNavigationTitle("ownerDraft.title")
    }
}

/// The guest entry uses the app's existing login flow. Choosing a role grants no draft access.
struct OwnerDraftGuestView: View {
    @State private var showsLogin = false
    var body: some View {
        Form {
            Section {
                Text("ownerDraft.signIn.detail").fixedSize(horizontal: false, vertical: true)
                Button("ownerDraft.signIn") { showsLogin = true }.accessibilityIdentifier("ownerDraft.signIn")
            }
        }.appNavigationTitle("ownerDraft.title")
            .sheet(isPresented: $showsLogin) { LoginView(intent: .player) }
    }
}

struct OwnerDraftBrowserView: View {
    let browser: OwnerDraftBrowser
    private struct Route: Identifiable, Hashable { let id: Int64 }
    @State private var route: Route?
    var body: some View {
        List {
            Section {
                Text("ownerDraft.readOnly").font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch browser.phase {
            case .idle, .loading:
                ProgressView("ownerDraft.loading").accessibilityIdentifier("ownerDraft.loading")
            case .empty:
                Text("ownerDraft.empty").accessibilityIdentifier("ownerDraft.empty")
            case .failed, .invalidated:
                OwnerDraftFailureView(issue: browser.issue)
                if browser.phase != .invalidated {
                    Button("action.retry") { Task { await browser.load() } }.accessibilityIdentifier("ownerDraft.retry")
                }
            case .ready:
                ForEach(browser.rows) { row in
                    Button { route = Route(id: row.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(row.businessType == .activity ? "ownerDraft.activity" : "ownerDraft.topic")).font(.headline)
                            Text(verbatim: "#\(row.id)").font(.subheadline)
                            OwnerDraftMetadata(summary: row)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("ownerDraft.row.\(row.id)")
                }
            }
        }
        .appNavigationTitle("ownerDraft.title")
        .refreshable { await browser.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await browser.load() } } label: { Label("ownerDraft.refresh", systemImage: "arrow.clockwise") }
                    .disabled(browser.phase == .loading || browser.phase == .invalidated)
                    .accessibilityIdentifier("ownerDraft.refresh")
            }
        }
        .task { await browser.load() }
        .onDisappear { if route == nil { browser.closeList() } }
        .navigationDestination(item: $route) { route in
            OwnerDraftDetailView(browser: browser, id: route.id)
        }
    }
}

private struct OwnerDraftMetadata: View {
    let summary: OwnerDraftSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("ownerDraft.version", value: String(summary.version))
            VStack(alignment: .leading, spacing: 2) {
                Text("ownerDraft.savedTime").font(.caption).foregroundStyle(.secondary)
                if let value = summary.savedTime { Text(verbatim: value) }
                else { Text("ownerDraft.timeUnavailable") }
            }
        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
}

private struct OwnerDraftDetailView: View {
    let browser: OwnerDraftBrowser
    let id: Int64
    var body: some View {
        Form {
            if browser.detailLoading {
                ProgressView("ownerDraft.loading").accessibilityIdentifier("ownerDraft.detailLoading")
            } else if let detail = browser.detail, detail.id == id {
                Section("ownerDraft.metadata") {
                    LabeledContent("ownerDraft.id", value: String(detail.id))
                    LabeledContent("ownerDraft.type") { Text(LocalizedStringKey(detail.businessType == .activity ? "ownerDraft.activity" : "ownerDraft.topic")) }
                    OwnerDraftMetadata(summary: detail)
                }.accessibilityIdentifier("ownerDraft.metadata")
                Section {
                    Label("ownerDraft.unsupported.title", systemImage: "doc.text.magnifyingglass")
                    Text("ownerDraft.unsupported.detail").fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("ownerDraft.unsupported")
                if let receipts = detail.installedReceipts { OwnerDraftReceiptSummaryView(summary: receipts) }
            } else if let issue = browser.detailIssue {
                OwnerDraftFailureView(issue: issue)
                if issue != .staleSession {
                    Button("action.retry") { Task { await browser.restore(id: id) } }.accessibilityIdentifier("ownerDraft.detailRetry")
                }
            }
        }
        .appNavigationTitle("ownerDraft.detail")
        .task(id: id) { await browser.restore(id: id) }
        .onDisappear { browser.closeDetail() }
        .refreshable { await browser.restore(id: id) }
    }
}

private struct OwnerDraftFailureView: View {
    let issue: ContentDraftIssue?
    private var key: String {
        switch issue {
        case .staleSession, .unauthorized: return "ownerDraft.stale"
        case .disabled: return "ownerDraft.notConfigured.detail"
        case .forbidden: return "ownerDraft.forbidden"
        case .notFound: return "ownerDraft.notFound"
        case .malformed, .invalid: return "ownerDraft.malformed"
        default: return "ownerDraft.error"
        }
    }
    var body: some View {
        Text(LocalizedStringKey(key)).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ownerDraft.error")
    }
}

/// No actions: the historical binding describes a receipt, never permission to use its content.
struct OwnerDraftReceiptSummaryView: View {
    let summary: OwnerDraftInstalledReceipts
    var body: some View {
        Section("ownerDraft.receipts.title") {
            Text("ownerDraft.receipts.policy").font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey("ownerDraft.receipts.state." + summary.state.rawValue))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ownerDraft.receipts.state")
            if summary.state == .historical {
                if summary.hasMore {
                    Text("ownerDraft.receipts.hasMore").font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ownerDraft.receipts.hasMore")
                }
                if summary.rows.isEmpty {
                    Text("ownerDraft.receipts.empty").accessibilityIdentifier("ownerDraft.receipts.empty")
                } else {
                    LabeledContent("ownerDraft.receipts.count", value: String(summary.rows.count))
                    ForEach(summary.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("ownerDraft.receipts.id", value: String(row.id))
                            LabeledContent("ownerDraft.receipts.draftVersion", value: String(row.draftVersion))
                            Text(verbatim: row.installedTime)
                            Text(LocalizedStringKey(bindingKey(row.binding)))
                                .font(.footnote).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ownerDraft.receipts.row.\(row.id)")
                    }
                }
            }
        }
    }
    private func bindingKey(_ binding: InstalledDraftModules.Binding) -> String {
        switch binding {
        case .exact: return "ownerDraft.receipts.binding.exact"
        case .stale: return "ownerDraft.receipts.binding.stale"
        case .unverifiable: return "ownerDraft.receipts.binding.unverifiable"
        }
    }
}
