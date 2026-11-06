import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class OwnMediaImagePreviewModel {
    enum Phase: Equatable { case idle, loading, ready, failed, expired }
    let asset: OwnMediaAsset
    private let access: OwnMediaImagePreviewAccess?
    private let currentAsset: () -> OwnMediaAsset?
    private let source: UUID?
    private var mounted = false, foreground = false
    private var operation = UUID()
    private var reader: OwnMediaImagePreviewReader?
    private var task: Task<Void, Never>?, expirationTask: Task<Void, Never>?
    private var storedImage: UIImage?
    private var displayDeadline: ContinuousClock.Instant?
    private(set) var presentation: UUID?
    private(set) var phase: Phase = .idle
    init(asset: OwnMediaAsset, access: OwnMediaImagePreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?) {
        self.asset = asset; self.access = access; self.currentAsset = currentAsset
        source = access?.sourceRevision(asset)
    }
    deinit { task?.cancel(); expirationTask?.cancel() }
    var available: Bool {
        guard mounted, foreground, asset.mediaType == .image, let source,
              access?.sourceRevision(asset) == source, let current = currentAsset() else { return false }
        return OwnMediaImagePreviewReader.sameAsset(asset, current)
    }
    var image: UIImage? {
        guard available, phase == .ready, reader?.isConfigured == true,
              let displayDeadline, ContinuousClock().now < displayDeadline else { return nil }
        return storedImage
    }
    func appear(foreground: Bool) { mounted = true; self.foreground = foreground }
    func setForeground(_ value: Bool) { foreground = value; if !value, let id = presentation { close(id) } }
    func disappear() { mounted = false; if let id = presentation { close(id) } }
    @discardableResult func open() -> Task<Void, Never>? {
        guard available, presentation == nil else { return nil }
        let id = UUID(); presentation = id; return start(id)
    }
    @discardableResult func retry(_ id: UUID) -> Task<Void, Never>? {
        guard available, presentation == id, phase == .failed || phase == .expired else { return nil }
        return start(id)
    }
    func close(_ id: UUID) {
        guard presentation == id else { return }
        operation = UUID(); task?.cancel(); task = nil; expirationTask?.cancel(); expirationTask = nil
        reader?.retire(); reader = nil; storedImage = nil; displayDeadline = nil; phase = .idle; presentation = nil
    }
    func accepts(_ id: UUID, operation: UUID) -> Bool { available && presentation == id && self.operation == operation }
    private func start(_ id: UUID) -> Task<Void, Never>? {
        guard available, presentation == id else { return nil }
        operation = UUID(); let run = operation
        task?.cancel(); expirationTask?.cancel(); expirationTask = nil; reader?.retire(); reader = nil; storedImage = nil; displayDeadline = nil
        guard let next = access?.makeReader(asset), next.sourceRevision == source else { phase = .failed; return nil }
        reader = next; phase = .loading
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.operation == run { self.task = nil } }
            do {
                guard !Task.isCancelled, self.accepts(id, operation: run) else { return }
                let result = try await next.load(asset: self.asset, currentAsset: self.currentAsset,
                    presentationIsCurrent: { [weak self] in self?.accepts(id, operation: run) == true })
                guard !Task.isCancelled, self.accepts(id, operation: run), next.isConfigured else { return }
                guard ContinuousClock().now < result.displayDeadline else {
                    self.storedImage = nil; self.displayDeadline = nil; self.phase = .expired; next.retire(); return
                }
                let clean = try RetainedImageSanitizer.sanitize(result.bytes)
                guard let image = UIImage(data: clean.jpeg) else { throw OwnMediaImagePreviewFailure.invalidResponse }
                guard !Task.isCancelled, self.accepts(id, operation: run), next.isConfigured else { return }
                guard ContinuousClock().now < result.displayDeadline else {
                    self.storedImage = nil; self.displayDeadline = nil; self.phase = .expired; next.retire(); return
                }
                self.storedImage = image; self.displayDeadline = result.displayDeadline; self.phase = .ready
                let deadline = result.displayDeadline
                self.expirationTask = Task { @MainActor [weak self] in
                    do { try await ContinuousClock().sleep(until: deadline) } catch { return }
                    guard !Task.isCancelled, let self, self.accepts(id, operation: run) else { return }
                    self.storedImage = nil; self.displayDeadline = nil; self.phase = .expired; next.retire()
                }
            } catch {
                guard !Task.isCancelled, self.accepts(id, operation: run) else { return }
                self.storedImage = nil; self.displayDeadline = nil; self.phase = .failed
            }
        }
        task = work; return work
    }
    func binding(_ offered: UUID) -> Binding<UUID?> {
        .init(get: { self.available && self.presentation == offered ? offered : nil }, set: { value in
            if value == nil { self.close(offered) }
        })
    }
}

private struct OwnMediaImagePreviewViewIdentity: Hashable {
    let id: Int64, state: String, reason: [UInt8], source: UUID?
    @MainActor init(asset: OwnMediaAsset, access: OwnMediaImagePreviewAccess?) {
        id = asset.id; state = asset.reviewState.rawValue; reason = Array(asset.reviewReason.utf8); source = access?.sourceRevision(asset)
    }
}
/// Rebuild only this read-only presentation owner when the exact row or source changes.
@MainActor struct OwnMediaImagePreviewButton: View {
    let asset: OwnMediaAsset
    let access: OwnMediaImagePreviewAccess?
    let currentAsset: () -> OwnMediaAsset?
    var body: some View {
        if asset.mediaType == .image {
            OwnMediaImagePreviewOwner(asset: asset, access: access, currentAsset: currentAsset)
                .id(OwnMediaImagePreviewViewIdentity(asset: asset, access: access))
        }
    }
}
@MainActor private struct OwnMediaImagePreviewOwner: View {
    @State private var model: OwnMediaImagePreviewModel
    @Environment(\.scenePhase) private var scenePhase
    init(asset: OwnMediaAsset, access: OwnMediaImagePreviewAccess?, currentAsset: @escaping () -> OwnMediaAsset?) {
        _model = State(initialValue: OwnMediaImagePreviewModel(asset: asset, access: access, currentAsset: currentAsset))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.open() } label: { Text("open", tableName: "OwnMediaImagePreview") }
                .disabled(!model.available || model.presentation != nil)
                .frame(minHeight: 44).accessibilityIdentifier("member.media.imagePreview.\(model.asset.id)")
            if !model.available { Text("unavailable", tableName: "OwnMediaImagePreview").font(.footnote).foregroundStyle(.secondary) }
        }
        .onAppear { model.appear(foreground: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, value in model.setForeground(value == .active) }
        .onChange(of: model.available) { _, available in if !available, let id = model.presentation { model.close(id) } }
        .background {
            if let offered = model.presentation {
                OwnMediaImagePreviewPresenter(model: model, offered: offered).id(offered)
            }
        }
    }
}
@MainActor private struct OwnMediaImagePreviewPresenter: View {
    let model: OwnMediaImagePreviewModel
    let offered: UUID
    private struct Item: Identifiable { let id: UUID }
    private var binding: Binding<Item?> {
        .init(get: { model.binding(offered).wrappedValue.map { Item(id: $0) } }, set: { value in
            if value == nil { model.close(offered) }
        })
    }
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: binding, onDismiss: { model.close(offered) }) { item in
                OwnMediaImagePreviewSheet(model: model, offered: item.id)
            }
    }
}
@MainActor private struct OwnMediaImagePreviewSheet: View {
    let model: OwnMediaImagePreviewModel
    let offered: UUID
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("privateOnly", tableName: "OwnMediaImagePreview").font(.footnote).foregroundStyle(.secondary)
                    if model.available, model.presentation == offered {
                        if let image = model.image {
                            OwnMediaImagePreviewZoom(image: image).frame(minHeight: 320)
                                .accessibilityIdentifier("member.media.imagePreview.image")
                        } else {
                            switch model.phase {
                            case .loading: ProgressView { Text("loading", tableName: "OwnMediaImagePreview") }
                            case .failed, .expired:
                                Text(LocalizedStringKey(model.phase == .expired ? "expired" : "failed"), tableName: "OwnMediaImagePreview")
                                Button { model.retry(offered) } label: { Text("retry", tableName: "OwnMediaImagePreview") }
                                    .frame(minHeight: 44).accessibilityIdentifier("member.media.imagePreview.retry")
                            case .idle, .ready: Text("unavailable", tableName: "OwnMediaImagePreview")
                            }
                        }
                    } else { Text("changed", tableName: "OwnMediaImagePreview") }
                    Text("limitations", tableName: "OwnMediaImagePreview").font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text("title", tableName: "OwnMediaImagePreview"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { model.close(offered) } label: { Text("close", tableName: "OwnMediaImagePreview") }
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("member.media.imagePreview.close")
            } }
        }
        .privacySensitive()
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.close(offered) } }
        .onDisappear { model.close(offered) }
    }
}
@MainActor private struct OwnMediaImagePreviewZoom: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Scroll {
        let scroll = Scroll(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator; scroll.imageView.image = image
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        tap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(tap)
        scroll.accessibilityLabel = appLocalized("media.destination.zoomHint", locale: .current); return scroll
    }
    func updateUIView(_ scroll: Scroll, context: Context) {
        if scroll.imageView.image !== image { scroll.setZoomScale(1, animated: false); scroll.imageView.image = image; scroll.setNeedsLayout() }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? Scroll)?.imageView }
        @objc func zoom(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? Scroll else { return }
            scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
    final class Scroll: UIScrollView {
        let imageView = UIImageView()
        init() { super.init(frame: .zero); imageView.contentMode = .scaleAspectFit; addSubview(imageView) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func layoutSubviews() { super.layoutSubviews(); if zoomScale == 1 { imageView.frame = bounds; contentSize = bounds.size } }
    }
}
