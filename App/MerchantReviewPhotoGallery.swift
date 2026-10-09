import SwiftUI
import CryptoKit

/// A local lease over an already validated management row. It grants no reads or writes.
@MainActor struct MerchantReviewPhotoContext {
    private weak var owner: MerchantBusinessViewModel?
    private let scope: MerchantBusinessScope
    private let authorization: UUID?
    private let revision: Int
    private let access: MerchantBusinessAccess
    private let rowID: String
    private let rowFingerprint: Data

    init?(owner: MerchantBusinessViewModel, row: MerchantBusinessRecord) {
        guard let scope = owner.coordinator.reader.scope,
              let snapshot = Self.snapshot(owner), let fingerprint = Self.fingerprint(row),
              Self.rows(owner, snapshot: snapshot).contains(where: { Self.fingerprint($0) == fingerprint }) else { return nil }
        self.owner = owner; self.scope = scope; authorization = owner.coordinator.reader.authorizationGeneration
        revision = owner.revision; access = snapshot.access; rowID = row.id; rowFingerprint = fingerprint
    }
    var isCurrent: Bool {
        guard let owner, owner.revision == revision, let currentScope = owner.coordinator.reader.scope,
              scope.accountID == currentScope.accountID, scope.epoch == currentScope.epoch,
              scope.realm.utf8.elementsEqual(currentScope.realm.utf8),
              owner.coordinator.reader.authorizationGeneration == authorization,
              let snapshot = Self.snapshot(owner), Self.sameAccess(access, snapshot.access) else { return false }
        return Self.rows(owner, snapshot: snapshot).contains {
            $0.id.utf8.elementsEqual(rowID.utf8) && Self.fingerprint($0) == rowFingerprint
        }
    }
    func matches(_ row: MerchantBusinessRecord) -> Bool { isCurrent && Self.fingerprint(row) == rowFingerprint }
    static func photos(_ row: MerchantBusinessRecord) -> [String]? {
        guard row.kind == .review, let values = row.fields["imageUrls"]?.array, (1...9).contains(values.count) else { return nil }
        let urls = values.compactMap(\.string)
        guard urls.count == values.count, urls.allSatisfy(MerchantBusinessRecord.safeHTTPS) else { return nil }
        return urls // Preserve source order and duplicate URLs as separate ordinal photos.
    }
    static func fingerprint(_ row: MerchantBusinessRecord) -> Data? {
        guard row.kind == .review else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(MerchantBusinessValue.object(row.fields)) else { return nil }
        return Data(SHA256.hash(data: data))
    }
    private static func snapshot(_ owner: MerchantBusinessViewModel) -> MerchantBusinessSnapshot? {
        let c = owner.coordinator
        guard c.reader.isConfigured, c.isCurrent, !c.isBusy, c.failureKey == nil,
              let snapshot = c.snapshot, case .reviews = snapshot.document.query else { return nil }
        return snapshot
    }
    private static func rows(_ owner: MerchantBusinessViewModel, snapshot: MerchantBusinessSnapshot) -> [MerchantBusinessRecord] {
        if let pages = owner.reviewLoadedPages {
            guard pages.matches(scope: owner.coordinator.reader.scope,
                                authorizationGeneration: owner.coordinator.reader.authorizationGeneration,
                                access: snapshot.access) else { return [] }
            return pages.rows.filter(owner.listFilters.review.matches)
        }
        return snapshot.document.rows.filter(owner.listFilters.review.matches)
    }
    private static func sameAccess(_ a: MerchantBusinessAccess, _ b: MerchantBusinessAccess) -> Bool {
        a == b && a.role.utf8.elementsEqual(b.role.utf8)
            && a.name.map { Data($0.utf8) } == b.name.map { Data($0.utf8) }
            && Set(a.permissions.map { Data($0.utf8) }) == Set(b.permissions.map { Data($0.utf8) })
    }
}

@MainActor final class MerchantReviewPhotoSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var index: Int
    @Published private(set) var zoom = 1.0
    @Published private(set) var imageGeneration = UUID()
    @Published private(set) var active = true
    private var context: MerchantReviewPhotoContext?
    private var sources: [String]
    private let validity: () -> Bool
    init?(context: MerchantReviewPhotoContext, sources: [String], index: Int, validity: @escaping () -> Bool) {
        guard context.isCurrent, (1...9).contains(sources.count), sources.indices.contains(index),
              sources.allSatisfy(MerchantBusinessRecord.safeHTTPS), validity() else { return nil }
        self.context = context; self.sources = sources; self.index = index; self.validity = validity
    }
    var isCurrent: Bool { active && validity() && context?.isCurrent == true }
    var count: Int { isCurrent ? sources.count : 0 }
    var currentURL: URL? { guard isCurrent, sources.indices.contains(index) else { return nil }; return URL(string: sources[index]) }
    func isImageCurrent(_ generation: UUID, at position: Int) -> Bool {
        isCurrent && imageGeneration == generation && index == position
    }
    @discardableResult func select(_ position: Int) -> Bool {
        guard isCurrent else { retire(); return false }
        guard sources.indices.contains(position) else { return false }
        guard index != position else { return true }
        index = position; zoom = 1; imageGeneration = UUID(); return true
    }
    @discardableResult func setZoom(_ value: Double) -> Bool {
        guard isCurrent else { retire(); return false }
        guard value.isFinite else { return false }
        zoom = min(5, max(1, value)); return true
    }
    @discardableResult func setImageZoom(_ value: Double, generation: UUID, at position: Int) -> Bool {
        guard isImageCurrent(generation, at: position) else { return false }
        return setZoom(value)
    }
    func retryImage(_ generation: UUID, at position: Int) {
        guard isImageCurrent(generation, at: position) else { return }
        imageGeneration = UUID(); zoom = 1
    }
    func retire() {
        guard active else { return }
        active = false; sources = []; context = nil; zoom = 1; imageGeneration = UUID()
    }
}

@MainActor final class MerchantReviewPhotoGalleryModel: ObservableObject {
    @Published private(set) var session: MerchantReviewPhotoSession?
    private(set) var active = false
    @Published private(set) var generation = UUID()
    func activate() { guard !active else { return }; active = true; generation = UUID() }
    func retire() { active = false; generation = UUID(); session?.retire(); session = nil }
    func revalidate() { if let session, !session.isCurrent { cancel(id: session.id) } }
    func open(permit: UUID, context: MerchantReviewPhotoContext?, row: MerchantBusinessRecord, index: Int) {
        guard active, permit == generation, session == nil, let context, context.matches(row),
              let sources = MerchantReviewPhotoContext.photos(row) else { return }
        session = MerchantReviewPhotoSession(context: context, sources: sources, index: index) { [weak self] in
            self?.active == true && self?.generation == permit
        }
    }
    func cancel(id: UUID) {
        guard session?.id == id else { return }
        generation = UUID(); session?.retire(); session = nil
    }
    func presentationBinding() -> Binding<MerchantReviewPhotoSession?> {
        let presentedID = session?.id
        return Binding(get: { [weak self] in
            guard let self, self.session?.id == presentedID, self.session?.isCurrent == true else { return nil }
            return self.session
        }, set: { [weak self] value in
            guard value == nil, let presentedID else { return }
            self?.cancel(id: presentedID)
        })
    }
}

/// No image request occurs in the entry. Only the selected photo is mounted after an explicit tap.
@MainActor struct MerchantReviewPhotoGalleryEntry: View {
    @ObservedObject var owner: MerchantBusinessViewModel
    let row: MerchantBusinessRecord
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = MerchantReviewPhotoGalleryModel()
    var body: some View {
        let permit = model.generation
        let context = MerchantReviewPhotoContext(owner: owner, row: row)
        if let photos = MerchantReviewPhotoContext.photos(row) {
            VStack(alignment: .leading, spacing: 8) {
                Label("merchant.business.imagesAvailable", systemImage: "photo.on.rectangle")
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(photos.indices, id: \.self) { position in
                            Button {
                                guard scenePhase == .active else { return }
                                model.open(permit: permit, context: context, row: row, index: position)
                            } label: {
                                VStack {
                                    Image(systemName: "photo")
                                    Text(verbatim: "\(position + 1) / \(photos.count)")
                                }.frame(minWidth: 64, minHeight: 44)
                            }.buttonStyle(.bordered)
                                .disabled(context == nil)
                                .accessibilityLabel(Text("merchant.reviewPhotos.open"))
                                .accessibilityValue(Text(verbatim: "\(position + 1) / \(photos.count)"))
                                .accessibilityIdentifier("merchant.reviewPhotos.open.\(position)")
                        }
                    }
                }
            }
            .sheet(item: model.presentationBinding()) { selected in
                MerchantReviewPhotoGallery(session: selected, owner: owner) { model.cancel(id: selected.id) }
            }
            .onAppear { if scenePhase == .active { model.activate() } }
            .onDisappear { model.retire() }
            .onChange(of: scenePhase) { _, value in if value == .active { model.activate() } else { model.retire() } }
            .onChange(of: owner.revision) { _, _ in model.revalidate() }
            .onChange(of: owner.listFilters) { _, _ in model.revalidate() }
            .onChange(of: owner.coordinator.reader.isConfigured) { _, configured in if configured && scenePhase == .active { model.activate() } else { model.retire() } }
            .onChange(of: owner.coordinator.reader.scope) { _, _ in model.retire(); if scenePhase == .active { model.activate() } }
            .onChange(of: owner.coordinator.reader.authorizationGeneration) { _, _ in model.retire(); if scenePhase == .active { model.activate() } }
            .onChange(of: MerchantReviewPhotoContext.fingerprint(row)) { _, _ in model.retire(); if scenePhase == .active { model.activate() } }
        }
    }
}

@MainActor private struct MerchantReviewPhotoGallery: View {
    @ObservedObject var session: MerchantReviewPhotoSession
    @ObservedObject var owner: MerchantBusinessViewModel
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if scenePhase == .active, session.isCurrent {
                    TabView(selection: Binding(get: { session.index }, set: { _ = session.select($0) })) {
                        ForEach(0..<session.count, id: \.self) { position in
                            Group {
                                if position == session.index, let url = session.currentURL {
                                    MerchantReviewPhotoImage(session: session, url: url, position: position, generation: session.imageGeneration)
                                        .id(session.imageGeneration)
                                } else { Color.clear }
                            }.tag(position)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                    if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 8) { navigationControls } }
                    else { HStack { navigationControls } }
                    Group {
                        if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 8) { zoomControls } }
                        else { HStack { zoomControls } }
                    }.buttonStyle(.bordered)
                    Text("merchant.reviewPhotos.zoomHint").font(.footnote).foregroundStyle(.secondary)
                } else { ContentUnavailableView("merchant.reviewPhotos.unavailable", systemImage: "photo") }
            }.padding().navigationTitle("merchant.business.imagesAvailable").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { session.retire(); close() } } }
        }.privacySensitive()
            .onDisappear { session.retire() }
            .onChange(of: scenePhase) { _, value in if value != .active { session.retire(); close() } }
            .onChange(of: owner.revision) { _, _ in if !session.isCurrent { session.retire(); close() } }
    }
    @ViewBuilder private var zoomControls: some View {
        Button("merchant.reviewPhotos.zoomOut") { _ = session.setZoom(session.zoom - 0.5) }
            .disabled(session.zoom <= 1).frame(minHeight: 44).accessibilityIdentifier("merchant.reviewPhotos.zoomOut")
        Button("merchant.reviewPhotos.resetZoom") { _ = session.setZoom(1) }
            .disabled(session.zoom == 1).frame(minHeight: 44).accessibilityIdentifier("merchant.reviewPhotos.resetZoom")
        Button("merchant.reviewPhotos.zoomIn") { _ = session.setZoom(session.zoom + 0.5) }
            .disabled(session.zoom >= 5).frame(minHeight: 44).accessibilityIdentifier("merchant.reviewPhotos.zoomIn")
    }
    @ViewBuilder private var navigationControls: some View {
        Button("merchant.reviewPhotos.previous") { _ = session.select(session.index - 1) }
            .disabled(session.index == 0).frame(minHeight: 44).accessibilityIdentifier("merchant.reviewPhotos.previous")
        Text(verbatim: "\(session.index + 1) / \(session.count)").monospacedDigit()
            .accessibilityLabel(Text("merchant.reviewPhotos.position"))
            .accessibilityValue(Text(verbatim: "\(session.index + 1) / \(session.count)"))
            .accessibilityIdentifier("merchant.reviewPhotos.position")
        Button("merchant.reviewPhotos.next") { _ = session.select(session.index + 1) }
            .disabled(session.index + 1 >= session.count).frame(minHeight: 44).accessibilityIdentifier("merchant.reviewPhotos.next")
    }
}

@MainActor private struct MerchantReviewPhotoImage: View {
    @ObservedObject var session: MerchantReviewPhotoSession
    let url: URL
    let position: Int
    let generation: UUID
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var magnification: CGFloat = 1
    var body: some View {
        if scenePhase == .active, session.isImageCurrent(generation, at: position) {
            // Preserve the existing safeHTTPS + AsyncImage rendering policy. No neighboring image is mounted.
            AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                if scenePhase == .active, session.isImageCurrent(generation, at: position) {
                    switch phase {
                    case .success(let image):
                        GeometryReader { geometry in
                            let scale = CGFloat(min(5, max(1, session.zoom * Double(magnification))))
                            ScrollView([.horizontal, .vertical]) {
                                image.resizable().scaledToFit()
                                    .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                                    .accessibilityLabel(Text("merchant.business.reviewImage"))
                            }.clipped()
                                .simultaneousGesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
                                    .onEnded { value in _ = session.setImageZoom(session.zoom * Double(value), generation: generation, at: position) })
                        }
                    case .failure:
                        VStack {
                            Label("merchant.business.imageUnavailable", systemImage: "photo.badge.exclamationmark")
                            Button("action.retry") { session.retryImage(generation, at: position) }
                                .accessibilityIdentifier("merchant.reviewPhotos.retry")
                        }
                    default: ProgressView("square.imageLoading")
                    }
                }
            }
        }
    }
}
