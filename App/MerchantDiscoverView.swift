import SwiftUI

@MainActor struct MerchantDiscoverView: View {
    let reader: any SearchMapReading
    var publicMerchant = PublicMerchantHomeContext()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var presentation = MerchantDiscoveryPresentation()
    @State private var tag = MerchantDiscoveryTag.all
    @State private var rows: [MerchantDiscoveryRow] = []
    @State private var loading = false
    @State private var loadedKey: Key?
    @State private var issue: String?
    @State private var unavailable = false
    @State private var gate = SearchMapQueryGate()
    private struct Key: Equatable { let tag: MerchantDiscoveryTag; let scope: UUID; let readerID: ObjectIdentifier; let configured: Bool; let authenticated: Bool; let visible: Bool }
    private var key: Key { .init(tag: tag, scope: reader.scope, readerID: ObjectIdentifier(reader), configured: reader.isConfigured, authenticated: reader.isAuthenticated, visible: isVisible) }
    var body: some View {
        let offeredSelectionID = presentation.occupiedID
        return List {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(MerchantDiscoveryTag.allCases) { value in
                            Button { select(value) } label: { Text(LocalizedStringKey(value.titleKey)).frame(minHeight: 44) }
                                .buttonStyle(.bordered)
                                .tint(value == tag ? .accentColor : .secondary)
                                .accessibilityAddTraits(value == tag ? [.isSelected] : [])
                                .accessibilityIdentifier("merchant.discover.tag.\(value.titleKey.split(separator: ".").last!)")
                        }
                    }
                }
            }
            if reader.isOfflineExample { Text("searchMap.offline").font(.footnote) }
            if !reader.isConfigured { SearchMapIssue(key: "searchMap.notConfigured") }
            else if loading || loadedKey != key { ProgressView("searchMap.loading").accessibilityIdentifier("merchant.discover.loading") }
            else if let issue { SearchMapIssue(key: issue) { Task { await load() } } }
            else if rows.isEmpty {
                ContentUnavailableView("merchant.discover.empty", systemImage: "storefront",
                    description: Text(LocalizedStringKey(tag == .all ? "merchant.discover.approvedOnly" : "merchant.discover.tryTag")))
            } else {
                // Source tolerates missing/duplicate row IDs. Rendering identity must not hide a row.
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.target != nil {
                        let offeredKey = key
                        let revision = presentation.revision
                        Button {
                            guard isVisible, scenePhase == .active, key == offeredKey, loadedKey == offeredKey, !loading, issue == nil else { return }
                            _ = presentation.open(row, among: rows, scope: offeredKey.scope, expectedRevision: revision)
                        } label: { card(row) }
                            .accessibilityIdentifier("merchant.discover.row.\(row.id)")
                    } else {
                        Button { unavailable = true } label: { card(row) }
                            .accessibilityHint(Text("merchant.discover.unavailable"))
                            .accessibilityIdentifier("merchant.discover.row.\(row.id)")
                    }
                }
            }
        }
        .appNavigationTitle("merchant.discover.title")
        .task(id: key) { await load() }
        .refreshable { await load() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; retire(); presentation.endHost() }
        .onChange(of: key) { _, _ in presentation.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { retire() }
            else if isVisible { Task { await load() } }
        }
        .sheet(item: Binding(get: { presentation.selection }, set: { next in
            if next == nil, let id = offeredSelectionID { presentation.close(expectedID: id) }
        }), onDismiss: {
            if let id = offeredSelectionID { presentation.finishDismiss(expectedID: id) }
        }) { selected in
            NavigationStack {
                if selected.scope == reader.scope, reader.isConfigured, presentation.occupiedID == selected.id {
                    PublicMerchantHomeView(target: selected.target, context: publicMerchant)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("action.close") { presentation.close(expectedID: selected.id) }
                                    .accessibilityIdentifier("merchant.discover.detail.close")
                            }
                        }
                }
            }
            .onAppear { presentation.didAppear(expectedID: selected.id) }
        }
        .alert("merchant.discover.unavailable", isPresented: $unavailable) { Button("action.close", role: .cancel) {} }
    }
    private func card(_ row: MerchantDiscoveryRow) -> some View {
        HStack(alignment: .top) {
            Group {
                if let url = row.image, let render = publicMerchant.image { render(url) }
                else { Image(systemName: "storefront").resizable().scaledToFit().padding(10).foregroundStyle(.secondary) }
            }.frame(width: 56, height: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if let name = row.displayName { Text(verbatim: name).font(.headline) }
                else { Text("merchant.discover.unnamed").font(.headline) }
                if let summary = row.summary { Text(verbatim: summary).font(.subheadline) }
                if !row.chips.isEmpty { Text(verbatim: row.chips.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine)
    }
    private func select(_ value: MerchantDiscoveryTag) {
        guard value != tag else { return }
        gate.invalidate(); presentation.invalidate(); loadedKey = nil; rows = []; issue = nil; loading = true; tag = value
    }
    private func retire() {
        gate.invalidate(); presentation.invalidate(); loadedKey = nil; rows = []; issue = nil; loading = false
    }
    private func load() async {
        guard isVisible, scenePhase == .active, !Task.isCancelled else { return }
        presentation.invalidate()
        let captured = key, ticket = gate.begin(scope: reader.scope)
        loadedKey = nil; rows = []; issue = nil; loading = true
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        guard reader.isConfigured else { return }
        do {
            let value = try await reader.merchantDiscovery(tag: captured.tag)
            guard !Task.isCancelled, scenePhase == .active, key == captured, gate.accepts(ticket, scope: reader.scope) else { return }
            loadedKey = captured; rows = value
        } catch {
            guard !Task.isCancelled, scenePhase == .active, key == captured, gate.accepts(ticket, scope: reader.scope) else { return }
            loadedKey = captured; issue = SearchMapIssue.key(error)
        }
    }
}
