import SwiftUI
import UIKit

@MainActor private struct ProfileCurrentMediaContext {
    let snapshot: ProfileEditSnapshot
    let sources: [String]
    let keys: [ProfileCurrentMediaReadKey?]
    let reader: ProfileCurrentMediaReader
    static func current(model: ProfileEditModel, edit: ProfileTextFieldEdit,
                        kind: ProfileCurrentMediaKind, reader: ProfileCurrentMediaReader?,
                        active: Bool) -> Self? {
        guard active, let reader, let snapshot = model.currentMediaReadSnapshot(for: edit),
              (edit.field == .casePictures && kind == .caseImage) || (edit.field == .contactQR && kind == .contactQR) else { return nil }
        let sources = ProfileCurrentMediaReader.sources(snapshot: snapshot, kind: kind)
        let keys = sources.indices.map { reader.key(snapshot: snapshot, kind: kind, originalIndex: $0,
            identity: edit.identity, viewerRevision: edit.viewerRevision) }
        guard keys.contains(where: { $0 != nil }) else { return nil }
        return .init(snapshot: snapshot, sources: sources, keys: keys, reader: reader)
    }
}

/// Saved images remain separate from staged removals/uploads. Native paging,
/// zoom and accessibility remain gated by purpose; the private subtree is retired
/// when the exact self snapshot, editor, purpose or independent read approval changes.
@MainActor struct ProfileCurrentMediaPreview: View {
    @ObservedObject var model: ProfileEditModel
    let edit: ProfileTextFieldEdit
    let kind: ProfileCurrentMediaKind
    let reader: ProfileCurrentMediaReader?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var visibility = ProfileSavedMediaVisibility()
    @State private var selection: Selection?
    @AccessibilityFocusState private var focusedIndex: Int?
    private struct Selection: Identifiable { let id = UUID(); let index: Int; let keys: [ProfileCurrentMediaReadKey?] }
    private var context: ProfileCurrentMediaContext? {
        return .current(model: model, edit: edit, kind: kind, reader: reader, active: visibility.active && scenePhase == .active)
    }
    private var titleKey: String { kind == .caseImage ? "profile.case.images" : "profile.contactQR.title" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(kind == .caseImage ? "profile.currentMedia.savedWork" : "profile.currentMedia.savedQR"), tableName: "ProfileCurrentMediaUI")
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let context {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(context.sources.indices, id: \.self) { index in
                            if ProfileCurrentMediaPreviewLayout.expandsThumbnails(for: dynamicTypeSize) {
                                thumbnail(index, context: context, stacked: true)
                                    .containerRelativeFrame(.horizontal)
                            } else {
                                thumbnail(index, context: context, stacked: false)
                            }
                        }
                    }
                }
                .id(context.keys)
                if kind == .caseImage, ProfileCasePortfolio(casePics: context.snapshot.casePics).omittedImageCount > 0 {
                    LabeledContent("profile.case.imagesOmitted", value: String(ProfileCasePortfolio(casePics: context.snapshot.casePics).omittedImageCount))
                }
            } else {
                Label { Text("profile.currentMedia.unavailable", tableName: "ProfileCurrentMediaUI") }
                    icon: { Image(systemName: kind == .caseImage ? "photo.on.rectangle" : "qrcode") }
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.currentMedia.unavailable.\(kind.rawValue)")
            }
            Text("profile.currentMedia.savedOnly", tableName: "ProfileCurrentMediaUI")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .privacySensitive()
        .onChange(of: context?.keys) { _, keys in
            if let selection, keys != selection.keys { close(selection, restoreFocus: false) }
        }
        .background {
            if let presented = selection {
                Color.clear.frame(width: 0, height: 0)
                    .sheet(item: presentation(presented), onDismiss: { close(presented, restoreFocus: true) }) { value in
                        ProfileCurrentMediaGallerySheet(model: model, edit: edit, kind: kind,
                            reader: reader, index: value.index, selectedKeys: value.keys, titleKey: titleKey,
                            close: { close(value, restoreFocus: true) })
                    }.id(presented.id)
            }
        }
        .onAppear { visibility.appear(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            visibility.scene(active: phase == .active)
            if phase != .active { selection = nil; focusedIndex = nil }
        }
        .onDisappear { visibility.disappear(); selection = nil; focusedIndex = nil }
    }
    private func thumbnail(_ index: Int, context: ProfileCurrentMediaContext, stacked: Bool) -> some View {
        Button {
            guard let fresh = self.context, fresh.keys == context.keys, fresh.keys[index] != nil else { return }
            selection = .init(index: index, keys: fresh.keys)
        } label: {
            VStack(alignment: stacked ? .leading : .center, spacing: 6) {
                ProfileCurrentMediaImage(model: model, edit: edit, kind: kind,
                    index: index, reader: context.reader, zoomable: false)
                    .id(context.keys[index])
                // Keep the action and actual loading/failure/unavailable text in
                // the combined button label rather than hiding it behind a generic image label.
                Text("media.destination.openImage").font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(index + 1) / \(context.sources.count)").monospacedDigit().font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: stacked ? nil : ProfileCurrentMediaPreviewLayout.thumbnailSide)
            .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(context.keys[index] == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.currentMedia.open.\(kind.rawValue).\(index)")
        .accessibilityFocused($focusedIndex, equals: index)
    }
    private func presentation(_ presented: Selection) -> Binding<Selection?> {
        .init(get: { selection?.id == presented.id ? selection : nil }, set: { value in
            if value == nil { close(presented, restoreFocus: true) }
        })
    }
    private func close(_ presented: Selection, restoreFocus: Bool) {
        guard selection?.id == presented.id else { return }
        selection = nil
        focusedIndex = restoreFocus && context?.keys == presented.keys ? presented.index : nil
    }
}

@MainActor private struct ProfileCurrentMediaGallerySheet: View {
    @ObservedObject var model: ProfileEditModel
    let edit: ProfileTextFieldEdit
    let kind: ProfileCurrentMediaKind
    let reader: ProfileCurrentMediaReader?
    let index: Int
    let selectedKeys: [ProfileCurrentMediaReadKey?]
    let titleKey: String
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var visibility = ProfileSavedMediaVisibility()
    private var context: ProfileCurrentMediaContext? {
        guard let value = ProfileCurrentMediaContext.current(model: model, edit: edit,
            kind: kind, reader: reader, active: visibility.active && scenePhase == .active), value.keys == selectedKeys else { return nil }
        return value
    }
    var body: some View {
        Group {
            if let context {
                ProfileCurrentMediaGallery(model: model, edit: edit, kind: kind, reader: context.reader,
                    sources: context.sources, initialIndex: index, titleKey: titleKey, close: close)
                    .id(selectedKeys)
            } else {
                NavigationStack {
                    ScrollView {
                        ContentUnavailableView {
                            Label { Text("profile.currentMedia.changed", tableName: "ProfileCurrentMediaUI") }
                                icon: { Image(systemName: "photo.badge.exclamationmark") }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("action.close", action: close)
                            .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
                            .accessibilityIdentifier("profile.currentMedia.close")
                    } }
                }
            }
        }
        .privacySensitive()
        .onChange(of: context?.keys) { _, keys in if keys == nil { close() } }
        .onAppear {
            visibility.appear(active: scenePhase == .active)
            if scenePhase != .active { close() }
        }
        .onChange(of: scenePhase) { _, phase in
            visibility.scene(active: phase == .active)
            if phase != .active { close() }
        }
        .onDisappear { visibility.disappear() }
    }
}

/// Publish only if the exact key still owns this visible tile after decode. A
/// public gallery's cached image is deliberately not reused for private media.
@MainActor private struct ProfileCurrentMediaImage: View {
    @ObservedObject var model: ProfileEditModel
    let edit: ProfileTextFieldEdit
    let kind: ProfileCurrentMediaKind
    let index: Int
    let reader: ProfileCurrentMediaReader
    let zoomable: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var visibility = ProfileSavedMediaVisibility()
    @State private var image: UIImage?
    @State private var loadedKey: ProfileCurrentMediaReadKey?
    @State private var failedKey: ProfileCurrentMediaReadKey?
    @State private var retry = 0
    private var key: ProfileCurrentMediaReadKey? {
        guard visibility.active, scenePhase == .active, let snapshot = model.currentMediaReadSnapshot(for: edit) else { return nil }
        return reader.key(snapshot: snapshot, kind: kind, originalIndex: index,
            identity: edit.identity, viewerRevision: edit.viewerRevision)
    }
    private struct Load: Hashable { let key: ProfileCurrentMediaReadKey?; let retry: Int; let lifetime: UUID }
    var body: some View {
        let load = Load(key: key, retry: retry, lifetime: visibility.lifetime)
        Group {
            if let key, loadedKey == key, let image {
                if zoomable { ProfileCurrentMediaZoom(image: image) }
                else {
                    // Only successfully decoded artwork is constrained/clipped.
                    // Status text below is always allowed its full intrinsic height.
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: ProfileCurrentMediaPreviewLayout.thumbnailSide, height: ProfileCurrentMediaPreviewLayout.thumbnailSide)
                        .clipped()
                        .accessibilityLabel(Text("media.destination.image"))
                }
            } else {
                if zoomable {
                    ScrollView {
                        status.padding().frame(maxWidth: .infinity)
                    }
                } else { status }
            }
        }
        .privacySensitive()
        .task(id: load) {
            guard !Task.isCancelled, visibility.matches(load.lifetime), self.key == load.key else { return }
            image = nil; loadedKey = nil; failedKey = nil
            let lifetime = load.lifetime
            guard visibility.matches(lifetime), let key, let snapshot = model.currentMediaReadSnapshot(for: edit) else { return }
            do {
                let bytes = try await reader.image(snapshot: snapshot, key: key,
                    currentSnapshot: { visibility.matches(lifetime) && self.key == key ? model.currentMediaReadSnapshot(for: edit) : nil })
                try Task.checkCancellation()
                guard visibility.matches(lifetime), self.key == key else { return }
                let clean = try RetainedImageSanitizer.sanitize(bytes)
                guard let decoded = UIImage(data: clean.jpeg) else { throw RetainedImageFailure.invalid }
                try Task.checkCancellation()
                guard visibility.matches(lifetime), self.key == key else { return }
                image = decoded; loadedKey = key
            } catch {
                guard !Task.isCancelled, visibility.matches(lifetime), self.key == key else { return }
                failedKey = key
            }
        }
        .onAppear { visibility.appear(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            visibility.scene(active: phase == .active); image = nil; loadedKey = nil; failedKey = nil
        }
        .onChange(of: key) { _, _ in image = nil; loadedKey = nil; failedKey = nil }
        .onDisappear { visibility.disappear(); image = nil; loadedKey = nil; failedKey = nil }
    }
    private var status: some View {
        let state: ProfileCurrentMediaStatusContent.State = key == nil ? .unavailable : (failedKey == key ? .failed : .loading)
        return ProfileCurrentMediaStatusContent(state: state,
            retry: zoomable ? { retry += 1 } : nil,
            retryIdentifier: "profile.currentMedia.retry.\(kind.rawValue).\(index)")
            .accessibilityIdentifier(state == .loading ? "profile.currentMedia.loading.\(kind.rawValue).\(index)" : "profile.currentMedia.status.\(kind.rawValue).\(index)")
    }

}

@MainActor private struct ProfileCurrentMediaGallery: View {
    @ObservedObject var model: ProfileEditModel
    let edit: ProfileTextFieldEdit
    let kind: ProfileCurrentMediaKind
    let reader: ProfileCurrentMediaReader
    let sources: [String]
    let titleKey: String
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var index: Int
    init(model: ProfileEditModel, edit: ProfileTextFieldEdit, kind: ProfileCurrentMediaKind,
         reader: ProfileCurrentMediaReader, sources: [String], initialIndex: Int, titleKey: String,
         close: @escaping () -> Void) {
        self.model = model; self.edit = edit; self.kind = kind; self.reader = reader
        self.sources = sources; self.titleKey = titleKey; self.close = close
        _index = State(initialValue: sources.indices.contains(initialIndex) ? initialIndex : 0)
    }
    var body: some View {
        NavigationStack {
            Group {
                if ProfileCurrentMediaPreviewLayout.scrollsGallery(for: dynamicTypeSize, verticalSizeClass: verticalSizeClass) {
                    // In compact height / large text the controls may exceed the
                    // viewport. Let the whole page scroll rather than compressing them.
                    ScrollView {
                        VStack(spacing: 12) {
                            pages.frame(height: ProfileCurrentMediaPreviewLayout.compactPageHeight)
                            controls
                        }
                    }
                } else {
                    VStack(spacing: 12) { pages; controls }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .appNavigationTitle(key: titleKey).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close", action: close)
                    .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
                    .accessibilityIdentifier("profile.currentMedia.close")
            } }
        }
    }
    private var pages: some View {
        TabView(selection: $index) {
            ForEach(sources.indices, id: \.self) { position in
                Group {
                    if abs(position - index) <= 1 {
                        ProfileCurrentMediaImage(model: model, edit: edit, kind: kind,
                            index: position, reader: reader, zoomable: true)
                    } else { Color.clear }
                }.tag(position).id(position)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never))
    }
    @ViewBuilder private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { position; previous; next }.padding()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack { previous; Spacer(); position; Spacer(); next }
                VStack(spacing: 8) { position; previous; next }
            }.padding()
        }
    }
    private var position: some View {
        Text("\(index + 1) / \(sources.count)").monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("profile.currentMedia.position")
    }
    private var previous: some View {
        Button("media.destination.previous") { index = max(0, index - 1) }
            .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
            .fixedSize(horizontal: false, vertical: true).disabled(index == 0).accessibilityIdentifier("profile.currentMedia.previous")
    }
    private var next: some View {
        Button("media.destination.next") { index = min(sources.count - 1, index + 1) }
            .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
            .fixedSize(horizontal: false, vertical: true).disabled(index >= sources.count - 1).accessibilityIdentifier("profile.currentMedia.next")
    }
}

/// Layout decisions only; no authorization, source projection or request capability.
enum ProfileCurrentMediaPreviewLayout {
    static let thumbnailSide: CGFloat = 112
    static let minimumAction: CGFloat = 44
    static let compactPageHeight: CGFloat = 240
    static func expandsThumbnails(for size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
    static func scrollsGallery(for size: DynamicTypeSize, verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        size.isAccessibilitySize || verticalSizeClass == .compact
    }
}

struct ProfileCurrentMediaStatusContent: View {
    enum State: Equatable { case loading, failed, unavailable }
    let state: State
    var retry: (() -> Void)? = nil
    var retryIdentifier: String = "profile.currentMedia.retry"
    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch state {
                case .loading:
                    VStack(spacing: 8) {
                        ProgressView().accessibilityHidden(true)
                        Text("square.imageLoading")
                    }.accessibilityElement(children: .combine)
                case .failed:
                    Label("media.destination.failed", systemImage: "photo.badge.exclamationmark")
                case .unavailable:
                    Label("media.destination.unavailable", systemImage: "photo")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Thumbnail is already an Open button: no nested retry action.
            if state == .failed, let retry {
                Button("action.retry", action: retry)
                    .frame(minWidth: ProfileCurrentMediaPreviewLayout.minimumAction, minHeight: ProfileCurrentMediaPreviewLayout.minimumAction)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(retryIdentifier)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// Local-only UIScrollView zoom; no sharing, URL inspection or extra image load.
@MainActor private struct ProfileCurrentMediaZoom: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView(frame: .zero); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator; scroll.imageView.image = image
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        scroll.accessibilityLabel = appLocalized("media.destination.zoomHint", locale: .current)
        return scroll
    }
    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        if scroll.imageView.image !== image {
            scroll.setZoomScale(1, animated: false); scroll.imageView.image = image; scroll.setNeedsLayout()
        }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomScrollView)?.imageView }
        @objc func zoom(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? ZoomScrollView else { return }
            scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
    final class ZoomScrollView: UIScrollView {
        let imageView = UIImageView()
        override init(frame: CGRect) {
            super.init(frame: frame); imageView.contentMode = .scaleAspectFit; addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func layoutSubviews() {
            super.layoutSubviews()
            if zoomScale == 1 { imageView.frame = bounds; contentSize = bounds.size }
        }
    }
}
