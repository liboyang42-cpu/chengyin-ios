import SwiftUI
import Observation
import UIKit

@MainActor private func roamStampMetadataScope(_ reader: any RoamExperienceReading) -> UUID? {
    if let reader = reader as? RoamAlbumMetadataReader { return reader.scope }
    return (reader as? RoamReceivedStampReader)?.scope
}
@MainActor private func roamStampIsMetadataOnly(_ reader: any RoamExperienceReading) -> Bool {
    reader is RoamAlbumMetadataReader || reader is RoamReceivedStampReader
}

@MainActor struct RoamStampAlbumView: View {
    let reader: any RoamExperienceReading
    var stampDestination: (() -> AnyView)? = nil
    let readOnlyScope: RoamStampAlbumReadOnlyScope?
    init(reader: any RoamExperienceReading, stampDestination: (() -> AnyView)? = nil, readOnlyScope: RoamStampAlbumReadOnlyScope? = nil) {
        self.stampDestination = stampDestination; self.readOnlyScope = readOnlyScope
        self.reader = reader
    }
    var canShowAlbum: Bool { readOnlyScope?.matches(reader) ?? true }
    var allowsCapture: Bool { readOnlyScope == nil && !roamStampIsMetadataOnly(reader) }
    var allowsRemoteImages: Bool { readOnlyScope?.allowsRemoteImages ?? !roamStampIsMetadataOnly(reader) }
    @ViewBuilder var captureDestination: some View {
        if allowsCapture {
            if let stampDestination { stampDestination() } else { AnyView(RoamStampCameraView()) }
        }
    }
    var body: some View {
        RoamStampAlbumContent(album: self).id(RoamAlbumReadOwner(reader: reader, scope: readOnlyScope))
            .modifier(RoamReceivedStampNavigation(isEntry: !(reader is RoamReceivedStampReader)))
    }
}

/// Exact original reader and optional frozen metadata scope, not new image/capture permission.
struct RoamAlbumReadOwner: Hashable {
    let readerID: ObjectIdentifier
    let identity: RoamExperienceIdentity?
    let metadataScope: UUID?
    let presentationScope: UUID?
    let configured: Bool
    let current: Bool
    @MainActor init(reader: any RoamExperienceReading, scope: RoamStampAlbumReadOnlyScope?) {
        readerID = ObjectIdentifier(reader); identity = reader.identity
        metadataScope = roamStampMetadataScope(reader)
        presentationScope = scope?.id; configured = reader.isConfigured
        current = scope?.matches(reader) ?? true
    }
}

/// Only read intents retire on cover. Source rows and the existing metadata lease survive a push.
@MainActor final class RoamAlbumReadPresentation: ObservableObject {
    let pager: RoamAlbumPager
    let reader: any RoamExperienceReading
    let scope: RoamStampAlbumReadOnlyScope?
    private let owner: RoamAlbumReadOwner
    @Published private var revision = 0
    @Published private(set) var loading = false
    private var mounted = false
    private var foreground = false
    private var needsAppearanceRead = false
    private var operation = UUID()
    private var work: Task<Void, Never>?
    init(reader: any RoamExperienceReading, scope: RoamStampAlbumReadOnlyScope?) {
        self.reader = reader; self.scope = scope; owner = .init(reader: reader, scope: scope)
        let albumReader: any RoamExperienceReading
        if let scope { albumReader = scope } else { albumReader = reader }
        pager = .init(reader: albumReader)
    }
    var isCurrent: Bool {
        owner == RoamAlbumReadOwner(reader: reader, scope: scope) && (scope?.matches(reader) ?? true)
    }
    func appear(foreground: Bool) {
        mounted = true; self.foreground = foreground; needsAppearanceRead = true; retire()
        readOnAppearance()
    }
    func disappear() { mounted = false; needsAppearanceRead = false; retire() }
    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value; retire(); readOnAppearance()
    }
    private func readOnAppearance() {
        // Defer an initial inactive mount, but never refresh a hidden parent or revive a retired lease.
        guard mounted, foreground, needsAppearanceRead, isCurrent else { return }
        readAction(refresh: true)()
    }
    private func retire() {
        operation = UUID(); work?.cancel(); work = nil
        pager.cancelPending(); loading = false; revision &+= 1
    }
    private func accepts(_ offered: UUID) -> Bool {
        mounted && foreground && isCurrent && operation == offered && !Task.isCancelled
    }
    private func begin(_ offered: UUID, refresh: Bool) -> UUID? {
        guard accepts(offered), refresh || (!loading && pager.hasMore) else { return nil }
        operation = UUID(); work?.cancel(); work = nil
        if refresh { pager.reset() }
        loading = true; return operation
    }
    func readAction(refresh: Bool = false) -> () -> Void {
        let offered = operation
        return { [weak self] in
            guard let self, let issued = self.begin(offered, refresh: refresh) else { return }
            self.work = Task { [weak self] in
                guard let self else { return }
                await self.read(issued: issued)
            }
        }
    }
    func refreshAction() -> () async -> Void {
        let offered = operation
        return { [weak self] in
            guard let self, let issued = self.begin(offered, refresh: true) else { return }
            await self.read(issued: issued)
        }
    }
    private func read(issued: UUID) async {
        guard operation == issued else { return }
        guard accepts(issued) else { retire(); return }
        needsAppearanceRead = false
        await pager.loadNext()
        guard operation == issued else { return }
        guard accepts(issued) else {
            if !isCurrent { pager.reset() }
            retire(); return
        }
        loading = false; work = nil; operation = UUID(); revision &+= 1
    }
}

@MainActor private struct RoamStampAlbumContent: View {
    let album: RoamStampAlbumView
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation: RoamAlbumReadPresentation
    init(album: RoamStampAlbumView) {
        self.album = album
        _presentation = StateObject(wrappedValue: .init(reader: album.reader, scope: album.readOnlyScope))
    }
    private var reader: any RoamExperienceReading { album.reader }
    private var readOnlyScope: RoamStampAlbumReadOnlyScope? { album.readOnlyScope }
    private var canShowAlbum: Bool { album.canShowAlbum }
    private var allowsCapture: Bool { album.allowsCapture }
    private var allowsRemoteImages: Bool { album.allowsRemoteImages }
    private var captureDestination: some View { album.captureDestination }
    private var pager: RoamAlbumPager { presentation.pager }
    var body: some View {
        let read = presentation.readAction(), refresh = presentation.refreshAction()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if canShowAlbum {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let total = pager.total { StampAlbumTotalHeader(total: total) }
                if let error = pager.error {
                    if CollectionReadAccess(error) == .denied { StampAlbumDeniedNotice() }
                    else { RoamExperienceIssue(error: error, retry: read) }
                }
                if pager.loaded && pager.stamps.isEmpty {
                    ContentUnavailableView("roam.experience.albumEmpty", systemImage: "rectangle.stack", description: Text("roam.experience.albumEmptyHint"))
                        .accessibilityIdentifier("roam.experience.album.empty")
                    if allowsCapture {
                        NavigationLink { captureDestination } label: { Label("stampAlbum.openCamera", systemImage: "camera") }
                            .buttonStyle(.questifyPrimary).frame(minHeight: 44)
                            .accessibilityIdentifier("roam.experience.album.openCamera")
                    }
                }
                ForEach(pager.stamps) { stamp in
                    NavigationLink { RoamStampDetailView(stamp: stamp, offline: reader.isOfflineExample, readOnlyScope: readOnlyScope, allowsRemoteImages: allowsRemoteImages) } label: {
                        RoamStampCard(stamp: stamp, offline: reader.isOfflineExample, allowsRemoteImages: allowsRemoteImages)
                    }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("roam.experience.album.stamp")
                }
                if presentation.loading { ProgressView("roam.loading") }
                if pager.hasMore && !presentation.loading && pager.loaded {
                    Button("roam.experience.loadMore", action: read)
                        .buttonStyle(.bordered).accessibilityIdentifier("roam.experience.album.more")
                }
                } else { RoamStampReadOnlyUnavailable() }
            }.padding()
        }.navigationTitle("roam.experience.album")
            .toolbar {
                if allowsCapture {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { captureDestination } label: { Label("media.stamp.title", systemImage: "camera") }
                    }
                }
            }
            .onAppear { presentation.appear(foreground: scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in presentation.setForeground(phase == .active) }
            .refreshable { await refresh() }
            .onDisappear { presentation.disappear() }
            .accessibilityIdentifier("roam.experience.album")
    }
}
struct RoamStampCard: View {
    let stamp: RoamAlbumStamp
    let offline: Bool
    var allowsRemoteImages = true
    var body: some View {
        RoamExperienceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "envelope.badge").accessibilityHidden(true)
                    Text("roam.experience.cityStamp").font(.caption).bold()
                    Spacer()
                    Text(verbatim: String(format: "NO. %04d", stamp.id % 10000)).font(.caption.monospaced())
                }
                if offline {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.13))
                        Image(systemName: "building.2.crop.circle").font(.largeTitle).imageScale(.large).foregroundStyle(.tint)
                    }.frame(height: 140).accessibilityLabel(Text("roam.experience.sampleArt"))
                } else if allowsRemoteImages { RoamStampImage(source: stamp.picUrl) }
                else { Label("roam.experience.imageUnavailable", systemImage: "photo") }
                if let caption = stamp.caption, !caption.isEmpty { Text(verbatim: caption).font(.title3).multilineTextAlignment(.leading) }
                if let date = stamp.createTime { Text(verbatim: date.replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
private struct RoamStampImage: View {
    let source: String
    var body: some View {
        if let url = URL(string: source), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else if phase.error != nil { Label("roam.experience.imageUnavailable", systemImage: "photo.badge.exclamationmark") }
                else { ProgressView("roam.loading") }
            }.frame(maxWidth: .infinity, minHeight: 100, maxHeight: 240).accessibilityLabel(Text("roam.experience.stampImage"))
        } else { Label("roam.experience.imageUnavailable", systemImage: "photo") }
    }
}
@MainActor struct RoamStampDetailView: View {
    let stamp: RoamAlbumStamp
    let offline: Bool
    var readOnlyScope: RoamStampAlbumReadOnlyScope? = nil
    var allowsRemoteImages = true
    var canShowStamp: Bool { readOnlyScope?.isCurrent ?? true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if canShowStamp {
                    RoamExperienceNotice(offline: offline)
                    RoamStampCard(stamp: stamp, offline: offline, allowsRemoteImages: allowsRemoteImages && (readOnlyScope?.allowsRemoteImages ?? true))
                } else { RoamStampReadOnlyUnavailable() }
            }.padding()
        }.navigationTitle("roam.experience.cityStamp")
    }
}
struct RoamCityStampDraftView: View {
    let offline: Bool
    @State private var draft = RoamCityStampDraft()
    @State private var review = false
    @QuestifyReduceMotion private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoamExperienceNotice(offline: offline)
                RoamExperienceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("roam.experience.draftOnly", systemImage: "pencil.and.outline").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "camera.metering.none").font(.largeTitle).imageScale(.large).foregroundStyle(.tint).frame(maxWidth: .infinity).padding()
                            .accessibilityHidden(true)
                        TextField("roam.experience.caption", text: $draft.caption, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("roam.experience.stamp.caption")
                        LabeledContent("roam.experience.remaining", value: String(draft.remaining)).font(.caption).monospacedDigit()
                        if !draft.canReview { Label("roam.experience.captionLimit", systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                        Button("roam.experience.previewDraft") { withAnimation(reduceMotion ? nil : QuestifyMotion.content) { review = true } }
                            .buttonStyle(.questifyPrimary).disabled(!draft.canReview)
                            .accessibilityIdentifier("roam.experience.stamp.preview")
                        if review {
                            Divider()
                            Text("roam.experience.localPreview").font(.caption).bold()
                            if draft.caption.isEmpty { Text("roam.experience.captionEmpty").foregroundStyle(.secondary) }
                            else { Text(verbatim: draft.caption).font(.title3) }
                        }
                    }
                }
                Label("roam.experience.mediaUnavailable", systemImage: "camera.fill")
                Text("roam.experience.stampHint").font(.subheadline).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("roam.experience.cityStamp")
            .onChange(of: draft.caption) { _, _ in review = false }
            .accessibilityIdentifier("roam.experience.stamp.draft")
    }
}


/// SwiftUI retains this owner for the logical page while a child destination covers it.
final class RoamAlbumPageOwner: ObservableObject {}

/// A frozen view-only album scope. It delegates the existing album read and no other capability.
@MainActor @Observable final class RoamStampAlbumReadOnlyScope: RoamExperienceReading {
    private let base: any RoamExperienceReading
    private let readerID: ObjectIdentifier
    private let expected: RoamExperienceIdentity
    private let presentationIsCurrent: () -> Bool
    private let metadataScope: UUID?
    @ObservationIgnored private weak var pageOwner: RoamAlbumPageOwner?
    private var pageOwnerWasBound = false
    private var retired = false
    let id = UUID()
    init(reader: any RoamExperienceReading, identity: RoamExperienceIdentity,
         isCurrent: @escaping () -> Bool) {
        base = reader; readerID = ObjectIdentifier(reader); expected = identity; presentationIsCurrent = isCurrent
        metadataScope = roamStampMetadataScope(reader)
    }
    var isCurrent: Bool {
        !retired && (!pageOwnerWasBound || pageOwner != nil) && presentationIsCurrent() && base.identity == expected &&
        roamStampMetadataScope(base) == metadataScope
    }
    var allowsRemoteImages: Bool { !roamStampIsMetadataOnly(base) }
    var hasPageOwner: Bool { pageOwnerWasBound && pageOwner != nil }
    func bind(to owner: RoamAlbumPageOwner) {
        if pageOwnerWasBound {
            if pageOwner !== owner { retire() }
            return
        }
        pageOwner = owner; pageOwnerWasBound = true
    }
    func retire() { retired = true }
    func matches(_ reader: any RoamExperienceReading) -> Bool { ObjectIdentifier(reader) == readerID && isCurrent }
    var identity: RoamExperienceIdentity? { isCurrent ? expected : nil }
    var isConfigured: Bool { isCurrent && base.isConfigured }
    var isOfflineExample: Bool { base.isOfflineExample }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        guard isCurrent, !Task.isCancelled else { throw CancellationError() }
        guard base.isConfigured else { throw APIError.notConfigured }
        let result = try await base.album(page: page, pageSize: pageSize)
        guard isCurrent, !Task.isCancelled else { throw CancellationError() }
        return result
    }
    func history() throws -> [RoamHistoryRecord] { throw APIError.notConfigured }
    func localWalkStatus() throws -> RoamLocalWalkStatus { throw APIError.notConfigured }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
private struct RoamStampReadOnlyUnavailable: View {
    @Environment(\.locale) private var locale
    var body: some View {
        Text(verbatim: locale.language.languageCode?.identifier == "zh"
             ? "此集邮册已不属于当前查看会话。请返回后重新打开。"
             : "This album is no longer part of the current viewing session. Go back and open it again.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("roam.experience.album.scopeExpired")
    }
}


/// Stable whole-page read scope. Only metadata is loaded; remote pictures and capture stay absent.
@MainActor struct RoamAlbumMetadataDestination: View {
    let reader: RoamAlbumMetadataReader
    @Environment(\.scenePhase) private var scenePhase
    @State private var scope: RoamStampAlbumReadOnlyScope?
    @StateObject private var pageOwner = RoamAlbumPageOwner()
    @State private var mounted = false
    init(reader: RoamAlbumMetadataReader, scope: RoamStampAlbumReadOnlyScope? = nil) {
        self.reader = reader; _scope = State(initialValue: scope)
    }
    var body: some View {
        Group {
            if let scope {
                RoamStampAlbumView(reader: reader, readOnlyScope: scope)
                    .background { RoamAlbumMetadataLifetime(scope: scope).id(scope.id) }
            } else if reader.identity == nil {
                RoamExperienceIssue(error: APIError.unauthorized)
            } else { ProgressView("roam.loading") }
        }
        .onAppear { mounted = true; attachIfVisible() }
        .onDisappear { mounted = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scope?.retire() } else { attachIfVisible() }
        }
    }
    private func attachIfVisible() {
        guard mounted, scenePhase == .active else { return }
        if let scope { scope.bind(to: pageOwner); return }
        guard let identity = reader.identity else { return }
        let fresh = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { true })
        fresh.bind(to: pageOwner); scope = fresh
    }
}

/// A child detail can cover this page. Removing the page's attachment retires only its own scope.
@MainActor struct RoamAlbumMetadataLifetime: UIViewControllerRepresentable {
    let scope: RoamStampAlbumReadOnlyScope
    func makeUIViewController(context: Context) -> Controller { Controller(scope: scope) }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        // A covered page can lose this rendering attachment while its StateObject lives.
        // Once the logical page leaves, its weak owner expires and the scope rejects reads.
        if !controller.scope.hasPageOwner { controller.scope.retire() }
    }
    @MainActor final class Controller: UIViewController {
        let scope: RoamStampAlbumReadOnlyScope
        init(scope: RoamStampAlbumReadOnlyScope) { self.scope = scope; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { return nil }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard !scope.hasPageOwner else { return }
            var current: UIViewController? = self
            while let value = current {
                if value.isBeingDismissed || value.isMovingFromParent { scope.retire(); return }
                current = value.parent
            }
        }
    }
}
