import SwiftUI
import Observation
import UIKit

@MainActor struct RoamStampAlbumView: View {
    let reader: any RoamExperienceReading
    var stampDestination: (() -> AnyView)? = nil
    let readOnlyScope: RoamStampAlbumReadOnlyScope?
    @State private var pager: RoamAlbumPager
    @State private var revision = 0
    @State private var loading = false
    init(reader: any RoamExperienceReading, stampDestination: (() -> AnyView)? = nil, readOnlyScope: RoamStampAlbumReadOnlyScope? = nil) {
        self.stampDestination = stampDestination; self.readOnlyScope = readOnlyScope
        self.reader = reader
        let albumReader: any RoamExperienceReading
        if let readOnlyScope { albumReader = readOnlyScope } else { albumReader = reader }
        _pager = State(initialValue: RoamAlbumPager(reader: albumReader))
    }
    var canShowAlbum: Bool { readOnlyScope?.matches(reader) ?? true }
    var allowsCapture: Bool { readOnlyScope == nil && !(reader is RoamAlbumMetadataReader) }
    var allowsRemoteImages: Bool { readOnlyScope?.allowsRemoteImages ?? !(reader is RoamAlbumMetadataReader) }
    @ViewBuilder var captureDestination: some View {
        if allowsCapture {
            if let stampDestination { stampDestination() } else { AnyView(RoamStampCameraView()) }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if canShowAlbum {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let total = pager.total { StampAlbumTotalHeader(total: total) }
                if let error = pager.error {
                    if CollectionReadAccess(error) == .denied { StampAlbumDeniedNotice() }
                    else { RoamExperienceIssue(error: error) { Task { await load() } } }
                }
                if pager.loaded && pager.stamps.isEmpty {
                    ContentUnavailableView("roam.experience.albumEmpty", systemImage: "rectangle.stack", description: Text("roam.experience.albumEmptyHint"))
                        .accessibilityIdentifier("roam.experience.album.empty")
                    if allowsCapture {
                        NavigationLink { captureDestination } label: { Label("stampAlbum.openCamera", systemImage: "camera") }
                            .buttonStyle(.borderedProminent).frame(minHeight: 44)
                            .accessibilityIdentifier("roam.experience.album.openCamera")
                    }
                }
                ForEach(pager.stamps) { stamp in
                    NavigationLink { RoamStampDetailView(stamp: stamp, offline: reader.isOfflineExample, readOnlyScope: readOnlyScope, allowsRemoteImages: allowsRemoteImages) } label: {
                        RoamStampCard(stamp: stamp, offline: reader.isOfflineExample, allowsRemoteImages: allowsRemoteImages)
                    }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("roam.experience.album.stamp")
                }
                if loading { ProgressView("roam.loading") }
                if pager.hasMore && !loading && pager.loaded {
                    Button("roam.experience.loadMore") { Task { await load() } }
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
            .task(id: reader.identity) { await refresh() }
            .refreshable { await refresh() }
            .onDisappear { pager.cancelPending(); revision += 1; loading = false }
            .accessibilityIdentifier("roam.experience.album")
    }
    private func refresh() async {
        guard canShowAlbum else { pager.reset(); revision += 1; loading = false; return }
        revision += 1; loading = false; pager.reset(); await load()
    }
    private func load() async {
        guard canShowAlbum, !loading else { return }
        revision += 1; let ticket = revision
        loading = true
        await pager.loadNext()
        guard canShowAlbum else { pager.reset(); revision += 1; loading = false; return }
        if revision == ticket { loading = false; revision += 1 }
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
                        Image(systemName: "building.2.crop.circle").font(.system(size: 52)).foregroundStyle(.tint)
                    }.frame(height: 140).accessibilityLabel(Text("roam.experience.sampleArt"))
                } else if allowsRemoteImages { RoamStampImage(source: stamp.picUrl) }
                else { Label("roam.experience.imageUnavailable", systemImage: "photo") }
                if let caption = stamp.caption, !caption.isEmpty { Text(verbatim: caption).font(.title3).multilineTextAlignment(.leading) }
                if let date = stamp.createTime { Text(verbatim: date.replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(.secondary) }
                if stamp.checkState == 0 { Text("roam.experience.reviewNotSubmitted").font(.caption).foregroundStyle(.secondary) }
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
                    Text("roam.experience.albumPrivacy").font(.caption).foregroundStyle(.secondary)
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
                        Image(systemName: "camera.metering.none").font(.system(size: 52)).foregroundStyle(.tint).frame(maxWidth: .infinity).padding()
                            .accessibilityHidden(true)
                        TextField("roam.experience.caption", text: $draft.caption, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("roam.experience.stamp.caption")
                        LabeledContent("roam.experience.remaining", value: String(draft.remaining)).font(.caption).monospacedDigit()
                        if !draft.canReview { Label("roam.experience.captionLimit", systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                        Button("roam.experience.previewDraft") { withAnimation(reduceMotion ? nil : QuestifyMotion.content) { review = true } }
                            .buttonStyle(.borderedProminent).disabled(!draft.canReview)
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


/// A frozen view-only album scope. It delegates the existing album read and no other capability.
@MainActor @Observable final class RoamStampAlbumReadOnlyScope: RoamExperienceReading {
    private let base: any RoamExperienceReading
    private let readerID: ObjectIdentifier
    private let expected: RoamExperienceIdentity
    private let presentationIsCurrent: () -> Bool
    private let metadataScope: UUID?
    private var retired = false
    let id = UUID()
    init(reader: any RoamExperienceReading, identity: RoamExperienceIdentity,
         isCurrent: @escaping () -> Bool) {
        base = reader; readerID = ObjectIdentifier(reader); expected = identity; presentationIsCurrent = isCurrent
        metadataScope = (reader as? RoamAlbumMetadataReader)?.scope
    }
    var isCurrent: Bool {
        !retired && presentationIsCurrent() && base.identity == expected &&
        (base as? RoamAlbumMetadataReader)?.scope == metadataScope
    }
    var allowsRemoteImages: Bool { !(base is RoamAlbumMetadataReader) }
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
        guard mounted, scope == nil, scenePhase == .active, let identity = reader.identity else { return }
        scope = RoamStampAlbumReadOnlyScope(reader: reader, identity: identity, isCurrent: { true })
    }
}

/// A child detail can cover this page. Removing the page's attachment retires only its own scope.
@MainActor struct RoamAlbumMetadataLifetime: UIViewControllerRepresentable {
    let scope: RoamStampAlbumReadOnlyScope
    func makeUIViewController(context: Context) -> Controller { Controller(scope: scope) }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.scope.retire() }
    @MainActor final class Controller: UIViewController {
        let scope: RoamStampAlbumReadOnlyScope
        init(scope: RoamStampAlbumReadOnlyScope) { self.scope = scope; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { return nil }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            var current: UIViewController? = self
            while let value = current {
                if value.isBeingDismissed || value.isMovingFromParent { scope.retire(); return }
                current = value.parent
            }
        }
    }
}
