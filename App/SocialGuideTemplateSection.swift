import SwiftUI

/// Source guide is a six-row introduction, not a second template marketplace.
enum SocialGuideTemplateRows {
    static func select(_ home: DiscoveryTemplateHome) -> [DiscoveryPlayTemplate] {
        let source = !home.hot.isEmpty ? home.hot : !home.recommended.isEmpty ? home.recommended : home.mustPlay
        // Choose the nonempty source pool before filtering, as the mini-program does.
        return Array(source.filter { $0.id > 0 && !text($0.title).isEmpty }.prefix(6))
    }
    static func text(_ value: String?) -> String {
        // JavaScript String.trim whitespace, including BOM and excluding U+0085.
        let whitespace = CharacterSet(charactersIn:
            "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}"
            + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return (value ?? "").trimmingCharacters(in: whitespace)
    }
    static func useCount(_ item: DiscoveryPlayTemplate) -> Int? { item.useNum.flatMap { $0 > 0 ? $0 : nil } }
}

@MainActor final class SocialGuideTemplateModel: ObservableObject {
    struct ReaderKey: Equatable {
        let reader: ObjectIdentifier
        let scope: String
        let configured: Bool
        init(_ reader: any DiscoveryReading) {
            self.reader = ObjectIdentifier(reader); scope = reader.discoveryPresentationIdentity; configured = reader.isConfigured
        }
    }
    struct Snapshot {
        let id = UUID()
        let key: ReaderKey
        let rows: [DiscoveryPlayTemplate]
    }
    struct Destination: Identifiable {
        enum Target: Equatable { case detail(Int), catalog }
        let id = UUID()
        let key: ReaderKey
        let target: Target
    }
    enum Phase: Equatable { case idle, loading, ready, failed, unavailable }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var selection: Destination?
    struct ReloadPermit { let generation: Int; let key: ReaderKey }
    struct CatalogPermit { let generation: Int; let key: ReaderKey }
    private var generation = 0

    func visibleSnapshot(reader: any DiscoveryReading) -> Snapshot? {
        guard reader.isConfigured, snapshot?.key == ReaderKey(reader) else { return nil }
        return snapshot
    }
    func destination(reader: any DiscoveryReading) -> Destination? {
        guard reader.isConfigured, selection?.key == ReaderKey(reader) else { return nil }
        return selection
    }
    func openDetail(index: Int, snapshotID: UUID, reader: any DiscoveryReading) {
        guard selection == nil, let snapshot = visibleSnapshot(reader: reader), snapshot.id == snapshotID,
              snapshot.rows.indices.contains(index) else { return }
        selection = .init(key: snapshot.key, target: .detail(snapshot.rows[index].id))
    }
    func catalogPermit(reader: any DiscoveryReading) -> CatalogPermit { .init(generation: generation, key: ReaderKey(reader)) }
    func openCatalog(reader: any DiscoveryReading, permit: CatalogPermit) {
        guard reader.isConfigured, permit.generation == generation, permit.key == ReaderKey(reader), selection == nil else { return }
        selection = .init(key: permit.key, target: .catalog)
    }
    func closeDestination(id: UUID) { if selection?.id == id { selection = nil } }
    func reloadPermit(reader: any DiscoveryReading) -> ReloadPermit { .init(generation: generation, key: ReaderKey(reader)) }
    func reload(reader: any DiscoveryReading, permit: ReloadPermit) async {
        guard permit.generation == generation, permit.key == ReaderKey(reader), !Task.isCancelled else { return }
        await load(reader: reader)
    }
    func invalidate() { generation += 1; snapshot = nil; selection = nil; phase = .idle }
    /// A presented destination may cover its owner. Cancel only in-flight results;
    /// retain the exact scoped rows/selection until normal dismissal or scope retirement.
    func suspend() { generation += 1; if phase == .loading { phase = .idle } }
    func load(reader: any DiscoveryReading) async {
        guard !Task.isCancelled else { return }
        invalidate(); let request = generation, key = ReaderKey(reader)
        guard key.configured else { phase = .unavailable; return }
        phase = .loading
        do {
            let home = try await reader.discoveryTemplateHome()
            guard request == generation, key == ReaderKey(reader), !Task.isCancelled else { return }
            snapshot = .init(key: key, rows: SocialGuideTemplateRows.select(home)); phase = .ready
        } catch {
            guard request == generation, key == ReaderKey(reader), !Task.isCancelled else { return }
            phase = error is CancellationError ? .idle : .failed
        }
    }
}

@MainActor struct SocialGuideTemplateSection: View {
    let reader: (any DiscoveryReading)?
    var body: some View {
        if let reader { SocialGuideTemplateContent(reader: reader) }
        else {
            Section("social.guideTemplates.title") {
                Text("social.guideTemplates.unavailable").foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor private struct SocialGuideTemplateContent: View {
    let reader: any DiscoveryReading
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = SocialGuideTemplateModel()
    @State private var readerRevision: UInt64 = 0
    private struct LoadKey: Equatable {
        let reader: SocialGuideTemplateModel.ReaderKey
        let active: Bool
    }
    private var loadKey: LoadKey {
        _ = readerRevision
        return .init(reader: .init(reader), active: scenePhase == .active)
    }
    var body: some View {
        let presented = scenePhase == .active ? model.destination(reader: reader) : nil
        let catalogPermit = model.catalogPermit(reader: reader)
        let retryPermit = model.reloadPermit(reader: reader)
        Section("social.guideTemplates.title") {
            Text("social.guideTemplates.hint").font(.footnote).foregroundStyle(.secondary)
            if !reader.isConfigured { Text("social.guideTemplates.unavailable") }
            else if scenePhase == .active, let snapshot = model.visibleSnapshot(reader: reader) {
                if snapshot.rows.isEmpty {
                    Text("social.guideTemplates.empty").accessibilityIdentifier("social.guideTemplates.empty")
                }
                ForEach(Array(snapshot.rows.enumerated()), id: \.offset) { index, item in
                    Button {
                        guard scenePhase == .active else { return }
                        model.openDetail(index: index, snapshotID: snapshot.id, reader: reader)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: SocialGuideTemplateRows.text(item.title)).font(.headline)
                            let description = SocialGuideTemplateRows.text(item.description)
                            if !description.isEmpty { Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                            if let count = SocialGuideTemplateRows.useCount(item) {
                                LabeledContent("social.guideTemplates.used", value: String(count)).font(.caption)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 6)
                    }.buttonStyle(.plain).accessibilityIdentifier("social.guideTemplates.detail.\(item.id)")
                }
            } else if model.phase == .failed {
                Text("social.guideTemplates.failed").accessibilityIdentifier("social.guideTemplates.failed")
                Button("action.retry") {
                    guard scenePhase == .active else { return }
                    Task { await model.reload(reader: reader, permit: retryPermit) }
                }
                    .accessibilityIdentifier("social.guideTemplates.retry")
            } else { ProgressView("discovery.loading") }
            Button("social.guideTemplates.browse") {
                guard scenePhase == .active else { return }
                model.openCatalog(reader: reader, permit: catalogPermit)
            }
                .disabled(!reader.isConfigured || scenePhase != .active)
                .accessibilityIdentifier("social.guideTemplates.browse")
        }
        .task(id: loadKey) {
            guard scenePhase == .active else { model.invalidate(); return }
            await model.load(reader: reader)
        }
        .onReceive(reader.discoveryPresentationChanges) { readerRevision &+= 1 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.invalidate() } }
        .onDisappear {
            if model.selection == nil { model.invalidate() } else { model.suspend() }
        }
        .sheet(item: Binding(get: { scenePhase == .active ? model.destination(reader: reader) : nil },
                             set: { if $0 == nil, let id = presented?.id { model.closeDestination(id: id) } })) { destination in
            NavigationStack {
                Group {
                    if scenePhase == .active, model.destination(reader: reader)?.id == destination.id {
                        switch destination.target {
                        case .detail(let id): DiscoveryTemplateDetailView(id: id, reader: reader)
                        case .catalog: DiscoveryTemplateBrowserView(reader: reader)
                        }
                    } else { Text("social.guideTemplates.unavailable") }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { model.closeDestination(id: destination.id) } } }
            }
        }
    }
}
