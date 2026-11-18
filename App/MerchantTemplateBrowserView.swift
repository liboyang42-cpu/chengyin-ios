import SwiftUI

@MainActor private final class MerchantTemplateBrowserModel: ObservableObject {
    let browser: MerchantTemplateBrowser
    @Published private(set) var revision = 0
    init(reader: any MerchantOperationsReading) { browser = .init(reader: reader) }
    func refresh() async { revision += 1; await browser.refresh(); revision += 1 }
    func more() async { revision += 1; await browser.loadMore(); revision += 1 }
    func deactivate() { browser.deactivate(); revision += 1 }
}

@MainActor struct MerchantTemplateBrowserView: View {
    let reader: any MerchantOperationsReading
    let imageHost: MerchantRetainedImageHost?
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    @StateObject private var model: MerchantTemplateBrowserModel
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any MerchantOperationsReading, imageHost: MerchantRetainedImageHost?, templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil) {
        self.reader = reader; self.imageHost = imageHost; self.templateAssistFactory = templateAssistFactory
        _model = StateObject(wrappedValue: .init(reader: reader))
    }
    private var browser: MerchantTemplateBrowser { model.browser }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                MerchantOperationsBoundary(isExample: reader.isOfflineExample)
                if !reader.isConfigured { Text("auth.notConfigured") }
                else if !reader.isAuthenticated { Text("merchant.operations.signedOut") }
                else if browser.isCurrent {
                    if let issue = browser.issue {
                        MerchantOperationsIssueView(issue: issue)
                        if browser.loaded { Text("merchant.templateBrowser.retained").font(.footnote) }
                        Button("merchant.templateBrowser.retryRefresh") { Task { await model.refresh() } }
                            .disabled(browser.isRefreshing).accessibilityIdentifier("merchant.templateBrowser.retryRefresh")
                    }
                    if browser.loaded {
                        NavigationLink("merchant.operations.newTemplate") {
                            MerchantOperationsDocumentView(reader: reader, destination: .template(nil), imageHost: imageHost, templateAssistFactory: templateAssistFactory)
                        }.disabled(!browser.canOpen).accessibilityIdentifier("merchant.operations.newTemplate")
                        if let total = browser.total {
                            Text("merchant.templateBrowser.count \(browser.rows.count) \(total)")
                                .font(.footnote).accessibilityIdentifier("merchant.templateBrowser.count")
                        } else {
                            Text("merchant.templateBrowser.loadedCount \(browser.rows.count)")
                                .font(.footnote).accessibilityIdentifier("merchant.templateBrowser.count")
                        }
                        if browser.rows.isEmpty {
                            ContentUnavailableView("merchant.operations.empty", systemImage: "square.grid.2x2", description: Text("merchant.templateBrowser.emptyHint"))
                                .accessibilityIdentifier("merchant.templateBrowser.empty")
                        }
                        ForEach(browser.rows) { row in
                            NavigationLink {
                                MerchantOperationsDocumentView(reader: reader, destination: .template(row.id), imageHost: imageHost, templateAssistFactory: templateAssistFactory)
                            } label: {
                                QuestifyImageEntityCard(imageSource: reader.isOfflineExample ? nil : row.imgUrl, title: row.title, subtitle: row.description,
                                    fallbackTitle: "merchant.operations.untitled", minimumHeight: 230, progressiveBlur: .cover,
                                    artworkIdentity: .init(owner: reader.scope.uuidString, content: "merchant-template:\(row.id)", version: String(model.revision))) {
                                    Text(LocalizedStringKey(status(row.status)))
                                    if let method = row.validationMethod.flatMap(MerchantTemplateMethod.init(rawValue:)) { Text(LocalizedStringKey(method.titleKey)) }
                                }
                            }.buttonStyle(.plain).disabled(!browser.canOpen)
                                .accessibilityIdentifier("merchant.operations.template.\(row.id)")
                        }
                        footer
                    }
                }
                if reader.isConfigured && reader.isAuthenticated && (browser.isRefreshing || !browser.isCurrent) {
                    ProgressView("merchant.templateBrowser.refreshing").accessibilityIdentifier("merchant.templateBrowser.loading")
                }
            }.padding()
        }
        .appNavigationTitle("merchant.operations.templates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("merchant.operations.reloadSource", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(browser.isRefreshing).accessibilityIdentifier("merchant.templateBrowser.reload")
            }
        }
        .refreshable { await model.refresh() }
        // A returning editor starts a new first-page read, never an optimistic list patch.
        .task(id: reader.scope) { await model.refresh() }
        .onDisappear { model.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.deactivate() }
            else { Task { await model.refresh() } }
        }
    }
    @ViewBuilder private var footer: some View {
        if browser.isLoadingMore {
            ProgressView("merchant.templateBrowser.loadingMore").accessibilityIdentifier("merchant.templateBrowser.loadingMore")
        } else if let issue = browser.loadMoreIssue {
            MerchantOperationsIssueView(issue: issue)
            Text("merchant.templateBrowser.moreFailed").font(.footnote)
            Button("merchant.templateBrowser.retryMore") { Task { await model.more() } }
                .disabled(!browser.canLoadMore).accessibilityIdentifier("merchant.templateBrowser.retryMore")
        } else if browser.hasMore {
            Button("merchant.templateBrowser.more") { Task { await model.more() } }
                .disabled(!browser.canLoadMore).accessibilityIdentifier("merchant.templateBrowser.more")
        } else if !browser.rows.isEmpty {
            Text("merchant.templateBrowser.end").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.templateBrowser.end")
        }
    }
    private func status(_ value: Int?) -> String {
        switch value { case 0: return "merchant.operations.template.unpublished"; case 1: return "merchant.operations.template.published"
        case 2: return "merchant.operations.review.pending"; default: return "merchant.operations.review.unknown" }
    }
}
