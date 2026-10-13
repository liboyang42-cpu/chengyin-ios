import SwiftUI

@MainActor final class MerchantTemplateBrowserModel: ObservableObject {
    struct Permit: Equatable { let generation: UUID; let scope: UUID }
    struct Editor: Identifiable, Hashable {
        let id = UUID()
        let templateID: Int?
        let scope: UUID
    }
    let browser: MerchantTemplateBrowser
    @Published private(set) var revision = 0
    @Published private(set) var readID: UUID?
    @Published private(set) var editor: Editor?
    private var consumedReadID: UUID?
    private var visible = false
    private var active = false
    private var generation = UUID()
    private var boundScope: UUID
    init(reader: any MerchantOperationsReading) {
        browser = .init(reader: reader); boundScope = reader.scope
    }
    var permit: Permit { .init(generation: generation, scope: boundScope) }
    private func current(_ value: Permit) -> Bool {
        visible && active && value == permit && browser.reader.scope == boundScope
            && browser.reader.isAuthenticated && browser.reader.isConfigured
    }
    func appear(active: Bool) {
        guard !visible else { sceneChanged(active: active); return }
        visible = true; self.active = active; boundScope = browser.reader.scope
        generation = UUID(); readID = active ? UUID() : nil; revision += 1
    }
    func disappear() {
        visible = false; generation = UUID(); readID = nil; browser.deactivate(); revision += 1
    }
    func sceneChanged(active: Bool) {
        guard self.active != active else { return }
        self.active = active; generation = UUID(); browser.deactivate()
        readID = visible && active ? UUID() : nil; revision += 1
    }
    func scopeChanged() {
        generation = UUID(); browser.deactivate(); editor = nil
        boundScope = browser.reader.scope; readID = visible && active ? UUID() : nil; revision += 1
    }
    func loadAppearance(_ id: UUID?) async {
        guard let id, readID == id, consumedReadID != id, current(permit) else { return }
        consumedReadID = id
        await refresh(permit)
    }
    func refresh(_ value: Permit) async {
        guard current(value) else { return }
        revision += 1; await browser.refresh()
        guard current(value) else { return }; revision += 1
    }
    func more(_ value: Permit) async {
        guard current(value) else { return }
        revision += 1; await browser.loadMore()
        guard current(value) else { return }; revision += 1
    }
    func open(_ templateID: Int?, permit value: Permit) {
        guard current(value), browser.canOpen,
              templateID.map({ id in browser.rows.contains(where: { $0.id == id }) }) ?? true else { return }
        editor = .init(templateID: templateID, scope: boundScope)
    }
    func editorBinding(_ original: Editor?) -> Binding<Editor?> {
        Binding(get: { self.editor?.id == original?.id ? original : nil }, set: { value in
            guard let original, self.editor?.id == original.id, value == nil else { return }
            self.editor = nil
        })
    }
}

@MainActor struct MerchantTemplateBrowserView: View {
    let reader: any MerchantOperationsReading
    let imageHost: MerchantRetainedImageHost?
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    var body: some View {
        MerchantTemplateBrowserContent(reader: reader, imageHost: imageHost, templateAssistFactory: templateAssistFactory)
            .id(ObjectIdentifier(reader))
    }
}

@MainActor private struct MerchantTemplateBrowserContent: View {
    let reader: any MerchantOperationsReading
    let imageHost: MerchantRetainedImageHost?
    let templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)?
    @StateObject private var model: MerchantTemplateBrowserModel
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any MerchantOperationsReading, imageHost: MerchantRetainedImageHost?, templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)?) {
        self.reader = reader; self.imageHost = imageHost; self.templateAssistFactory = templateAssistFactory
        _model = StateObject(wrappedValue: .init(reader: reader))
    }
    private var browser: MerchantTemplateBrowser { model.browser }
    var body: some View {
        let permit = model.permit, editor = model.editor, readID = model.readID
        ScrollView {
            LazyVStack(spacing: 18) {
                MerchantOperationsBoundary(isExample: reader.isOfflineExample)
                if !reader.isConfigured { Text("auth.notConfigured") }
                else if !reader.isAuthenticated { Text("merchant.operations.signedOut") }
                else if browser.isCurrent {
                    if let issue = browser.issue {
                        MerchantOperationsIssueView(issue: issue)
                        if browser.loaded { Text("merchant.templateBrowser.retained").font(.footnote) }
                        Button("merchant.templateBrowser.retryRefresh") { Task { await model.refresh(permit) } }
                            .disabled(browser.isRefreshing).accessibilityIdentifier("merchant.templateBrowser.retryRefresh")
                    }
                    if browser.loaded {
                        Button("merchant.operations.newTemplate") { model.open(nil, permit: permit) }.disabled(!browser.canOpen).accessibilityIdentifier("merchant.operations.newTemplate")
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
                            Button { model.open(row.id, permit: permit) } label: {
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
                Button("merchant.operations.reloadSource", systemImage: "arrow.clockwise") { Task { await model.refresh(permit) } }
                    .disabled(browser.isRefreshing).accessibilityIdentifier("merchant.templateBrowser.reload")
            }
        }
        .refreshable { await model.refresh(permit) }
        .navigationDestination(item: model.editorBinding(editor)) { selected in
            if selected.scope == reader.scope, reader.isAuthenticated {
                MerchantOperationsDocumentView(reader: reader, destination: .template(selected.templateID), imageHost: imageHost, templateAssistFactory: templateAssistFactory)
                    .id(selected.id)
            } else { Text("merchant.operations.signedOut") }
        }
        .task(id: readID) { await model.loadAppearance(readID) }
        .onAppear { model.appear(active: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: reader.scope) { _, _ in model.scopeChanged() }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(active: phase == .active) }
    }
    @ViewBuilder private var footer: some View {
        let permit = model.permit
        if browser.isLoadingMore {
            ProgressView("merchant.templateBrowser.loadingMore").accessibilityIdentifier("merchant.templateBrowser.loadingMore")
        } else if let issue = browser.loadMoreIssue {
            MerchantOperationsIssueView(issue: issue)
            Text("merchant.templateBrowser.moreFailed").font(.footnote)
            Button("merchant.templateBrowser.retryMore") { Task { await model.more(permit) } }
                .disabled(!browser.canLoadMore).accessibilityIdentifier("merchant.templateBrowser.retryMore")
        } else if browser.hasMore {
            Button("merchant.templateBrowser.more") { Task { await model.more(permit) } }
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
