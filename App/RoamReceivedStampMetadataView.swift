import SwiftUI

private struct RoamReceivedStampReaderKey: EnvironmentKey {
    static let defaultValue: RoamReceivedStampReader? = nil
}
extension EnvironmentValues {
    var roamReceivedStampReader: RoamReceivedStampReader? {
        get { self[RoamReceivedStampReaderKey.self] }
        set { self[RoamReceivedStampReaderKey.self] = newValue }
    }
}
private func receivedStampText(_ key: String) -> Text { Text(LocalizedStringKey("roam.receivedMetadata." + key), tableName: "RoamReceivedStamp") }

/// Mounted only outside the original album's lazy content; nil hosts remain unchanged.
@MainActor struct RoamReceivedStampNavigation: ViewModifier {
    let isEntry: Bool
    @Environment(\.roamReceivedStampReader) private var reader
    @State private var target: Target?
    private struct Target: Hashable { let id = UUID(); let owner: RoamAlbumReadOwner }
    func body(content: Content) -> some View {
        if isEntry, let reader {
            let offered = RoamAlbumReadOwner(reader: reader, scope: nil)
            content.safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        guard offered == RoamAlbumReadOwner(reader: reader, scope: nil), reader.identity != nil,
                              reader.isConfigured, target == nil else { return }
                        target = .init(owner: offered)
                    } label: { Label { receivedStampText("open") } icon: { Image(systemName: "tray.and.arrow.down") } }
                        .disabled(reader.identity == nil || !reader.isConfigured)
                        .accessibilityIdentifier("roam.receivedMetadata.open")
                    if !reader.isConfigured { Text(LocalizedStringKey(reader.identity == nil ? "roam.signInRequired" : "roam.notConfigured")).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial)
            }
            .onChange(of: offered) { _, _ in target = nil }
            .navigationDestination(item: $target) { target in
                if target.owner == RoamAlbumReadOwner(reader: reader, scope: nil) {
                    RoamReceivedStampMetadataDestination(reader: reader, owner: target.owner)
                } else { receivedStampText("changed") }
            }
        } else { content }
    }
}

/// Received metadata only. The original read-only scope never gains image, capture or exchange authority.
@MainActor struct RoamReceivedStampMetadataDestination: View {
    let reader: RoamReceivedStampReader
    let owner: RoamAlbumReadOwner
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pageOwner = RoamAlbumPageOwner()
    @State private var scope: RoamStampAlbumReadOnlyScope?
    @State private var mounted = false
    @State private var didAttach = false
    init(reader: RoamReceivedStampReader, owner: RoamAlbumReadOwner? = nil) {
        self.reader = reader; self.owner = owner ?? .init(reader: reader, scope: nil)
    }
    private var isCurrent: Bool { owner == RoamAlbumReadOwner(reader: reader, scope: nil) }
    var body: some View {
        Group {
            if !isCurrent { receivedStampText("changed") }
            else if reader.identity == nil { Text("roam.signInRequired") }
            else if !reader.isConfigured { Text("roam.notConfigured") }
            else if scenePhase == .active {
                if let scope, scope.isCurrent {
                    RoamReceivedStampMetadataContent(reader: reader, scope: scope)
                        .id(scope.id).background { RoamAlbumMetadataLifetime(scope: scope).id(scope.id) }
                } else if didAttach {
                    VStack(spacing: 12) {
                        receivedStampText("retired")
                        Button { attach() } label: { receivedStampText("reopen") }
                            .accessibilityIdentifier("roam.receivedMetadata.reopen")
                    }.padding()
                } else { ProgressView("roam.loading") }
            } else { Color.clear }
        }
        .navigationTitle(receivedStampText("title"))
        .onAppear { mounted = true; if !didAttach { attach() } }
        .onDisappear { mounted = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scope?.retire() }
            else if !didAttach { attach() }
        }
        .onChange(of: RoamAlbumReadOwner(reader: reader, scope: nil)) { _, _ in scope?.retire() }
        .privacySensitive().accessibilityIdentifier("roam.receivedMetadata.page")
    }
    private func attach() {
        guard mounted, scenePhase == .active, isCurrent, reader.isConfigured, let identity = reader.identity else { return }
        scope?.retire()
        let fresh = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { true })
        fresh.bind(to: pageOwner); scope = fresh; didAttach = true
    }
}

@MainActor private struct RoamReceivedStampMetadataContent: View {
    let reader: RoamReceivedStampReader
    let scope: RoamStampAlbumReadOnlyScope
    @StateObject private var presentation: RoamAlbumReadPresentation
    @Environment(\.scenePhase) private var scenePhase
    init(reader: RoamReceivedStampReader, scope: RoamStampAlbumReadOnlyScope) {
        self.reader = reader; self.scope = scope
        _presentation = StateObject(wrappedValue: .init(reader: reader, scope: scope))
    }
    private var pager: RoamAlbumPager { presentation.pager }
    var body: some View {
        let more = presentation.readAction(), refresh = presentation.refreshAction()
        List {
            if scope.matches(reader) {
                Section { receivedStampText("boundary").font(.footnote).foregroundStyle(.secondary) }
                if let total = pager.total {
                    LabeledContent { Text(total, format: .number) } label: { receivedStampText("total") }
                }
                if let error = pager.error {
                    if CollectionReadAccess(error) == .denied { Label("roam.w208.entry.denied", systemImage: "lock") }
                    else { RoamExperienceIssue(error: error, retry: more) }
                }
                if pager.loaded && pager.stamps.isEmpty && pager.error == nil {
                    receivedStampText("empty").accessibilityIdentifier("roam.receivedMetadata.empty")
                }
                ForEach(pager.stamps) { stamp in
                    NavigationLink {
                        RoamReceivedStampMetadataDetail(stamp: stamp, scope: scope, isCurrent: { scope.isCurrent && pager.stamps.contains(stamp) })
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RoamStampCard(stamp: stamp, offline: false, allowsRemoteImages: false)
                            if let key = RoamReceivedStampKind.key(stamp.kind) { receivedStampText(key).font(.caption) }
                        }
                    }.accessibilityIdentifier("roam.receivedMetadata.record")
                }
                if presentation.loading { ProgressView("roam.loading") }
                if pager.loaded && pager.hasMore && !presentation.loading {
                    Button("roam.experience.loadMore", action: more).accessibilityIdentifier("roam.receivedMetadata.more")
                }
                if pager.loaded && !pager.hasMore && !pager.stamps.isEmpty && pager.error == nil {
                    receivedStampText("end").foregroundStyle(.secondary).accessibilityIdentifier("roam.receivedMetadata.end")
                }
                if !presentation.loading {
                    Button("action.retry") { Task { await refresh() } }.accessibilityIdentifier("roam.receivedMetadata.refresh")
                }
            } else { receivedStampText("changed") }
        }
        .onAppear { presentation.appear(foreground: scenePhase == .active) }
        .onDisappear { presentation.disappear() }
        .onChange(of: scenePhase) { _, phase in presentation.setForeground(phase == .active) }
        .refreshable { await refresh() }
    }
}

@MainActor struct RoamReceivedStampMetadataDetail: View {
    let stamp: RoamAlbumStamp
    let scope: RoamStampAlbumReadOnlyScope
    let isCurrent: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            if scenePhase == .active && scope.isCurrent && isCurrent() && stamp.isVisible {
                RoamStampCard(stamp: stamp, offline: false, allowsRemoteImages: false)
                receivedStampText("anonymous").accessibilityIdentifier("roam.receivedMetadata.anonymous")
                if let key = RoamReceivedStampKind.key(stamp.kind) {
                    LabeledContent { receivedStampText(key) } label: { receivedStampText("kind") }
                }
                receivedStampText("boundary").font(.footnote).foregroundStyle(.secondary)
            } else { receivedStampText("changed") }
        }.navigationTitle(receivedStampText("detail"))
            .privacySensitive().accessibilityIdentifier("roam.receivedMetadata.detail")
    }
}
/// Only the original two kind values have labels; no author/location inference from metadata.
enum RoamReceivedStampKind {
    static func key(_ value: Int?) -> String? {
        switch value { case 0: return "freePhoto"; case 1: return "cancelledStamp"; default: return nil }
    }
}
