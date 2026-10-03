import SwiftUI
import UIKit

/// Both source photo destinations use the same full-screen Apple viewer. Loading is anonymous,
/// bounded, origin-reviewed and disabled by default. No source URL is sent merely by opening it.
@MainActor struct NativeMediaGalleryEntry: View {
    let sources: [String]
    var scope: UUID = UUID()
    var titleKey = "media.destination.squareImages"
    var compact = false
    let reader: any RetainedPublicImageReading
    init(sources: [String], scope: UUID = UUID(), titleKey: String = "media.destination.squareImages", compact: Bool = false,
         reader: (any RetainedPublicImageReading)? = nil) {
        self.sources = sources; self.scope = scope; self.titleKey = titleKey; self.compact = compact
        self.reader = reader ?? RetainedPublicImageReader()
    }
    @State private var selection: Selection?
    @State private var returnFocusIndex: Int?
    @AccessibilityFocusState private var focusedImageIndex: Int?
    private struct Selection: Identifiable { let id = UUID(); let snapshot: MediaGallerySnapshot }
    var body: some View {
        Group {
            if !sources.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(sources.prefix(compact ? 1 : 100).enumerated()), id: \.offset) { index, source in
                            Button { returnFocusIndex = index; selection = Selection(snapshot: .init(sources: sources, selectedIndex: index)) } label: {
                                NativeMediaImage(raw: source, reader: reader, zoomable: false)
                                    .frame(width: compact ? 180 : 112, height: 112).clipped()
                            }.buttonStyle(.plain)
                                .accessibilityLabel(Text("media.destination.openImage"))
                                .accessibilityValue(Text("\(index + 1) / \(min(sources.count, 100))"))
                                .accessibilityIdentifier("media.gallery.open.\(index)")
                                .accessibilityFocused($focusedImageIndex, equals: index)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selection, onDismiss: {
            focusedImageIndex = returnFocusIndex; returnFocusIndex = nil
        }) { selected in
            NativeMediaGallery(snapshot: selected.snapshot, titleKey: titleKey, reader: reader)
        }
        .onChange(of: scope) { _, _ in invalidateSelection() }
        .onChange(of: sources) { _, _ in invalidateSelection() }
    }
    private func invalidateSelection() {
        returnFocusIndex = nil; focusedImageIndex = nil; selection = nil
    }
}

@MainActor struct NativeMediaGallery: View {
    let snapshot: MediaGallerySnapshot
    let titleKey: String
    let reader: any RetainedPublicImageReading
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var index: Int
    init(snapshot: MediaGallerySnapshot, titleKey: String, reader: any RetainedPublicImageReading) {
        self.snapshot = snapshot; self.titleKey = titleKey; self.reader = reader
        _index = State(initialValue: snapshot.initialIndex)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if snapshot.sources.isEmpty {
                    ContentUnavailableView("media.destination.empty", systemImage: "photo")
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(snapshot.sources.enumerated()), id: \.offset) { position, raw in
                            NativeMediaImage(raw: raw, reader: reader, zoomable: true)
                                .tag(position).id(position)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 8) {
                                position
                                previousButton
                                nextButton
                            }
                        } else {
                            HStack {
                                previousButton
                                Spacer()
                                position
                                Spacer()
                                nextButton
                            }
                        }
                    }.padding().font(.body)
                }
            }.background(Color(uiColor: .systemBackground))
                .appNavigationTitle(key: titleKey).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() }.accessibilityIdentifier("media.gallery.close") } }
        }
    }
    private var position: some View {
        Text("\(index + 1) / \(snapshot.sources.count)").monospacedDigit()
            .accessibilityIdentifier("media.gallery.position")
    }
    private var previousButton: some View {
        Button("media.destination.previous") { index = max(0, index - 1) }
            .frame(minHeight: 44).disabled(index == 0)
            .accessibilityIdentifier("media.gallery.previous")
    }
    private var nextButton: some View {
        Button("media.destination.next") { index = min(snapshot.sources.count - 1, index + 1) }
            .frame(minHeight: 44).disabled(index == snapshot.sources.count - 1)
            .accessibilityIdentifier("media.gallery.next")
    }
}

@MainActor private struct NativeMediaImage: View {
    let raw: String
    let reader: any RetainedPublicImageReading
    let zoomable: Bool
    @State private var image: UIImage?
    @State private var failed = false
    @State private var revision = 0
    var body: some View {
        Group {
            if let image {
                if zoomable { NativeZoomImage(image: image).accessibilityLabel(Text("media.destination.image")) }
                else { Image(uiImage: image).resizable().scaledToFit() }
            } else if !reader.enabled { Label("media.destination.unavailable", systemImage: "photo") }
            else if failed {
                VStack {
                    Label("media.destination.failed", systemImage: "photo.badge.exclamationmark")
                        .accessibilityIdentifier("media.gallery.failed")
                    Button("action.retry") { revision += 1 }.accessibilityIdentifier("media.gallery.retry")
                }
            } else { ProgressView("square.imageLoading") }
        }
        .task(id: "\(raw)|\(revision)") {
            image = nil; failed = false
            guard reader.enabled, let url = URL(string: raw) else { failed = true; return }
            do {
                let bytes = try await reader.image(url: url)
                try Task.checkCancellation()
                let clean = try RetainedImageSanitizer.sanitize(bytes)
                try Task.checkCancellation()
                guard let decoded = UIImage(data: clean.jpeg) else { throw RetainedImageFailure.invalid }
                image = decoded
            } catch { if !Task.isCancelled { failed = true } }
        }.onDisappear { image = nil }
    }
}
/// UIScrollView supplies bounded pinch/pan and double-tap zoom, rather than scaling past a
/// clipped SwiftUI frame. The paging controls remain available at any image zoom level.
@MainActor private struct NativeZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator; scroll.imageView.image = image
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        scroll.accessibilityLabel = appLocalized("media.destination.zoomHint", locale: .current)
        return scroll
    }
    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        if scroll.imageView.image !== image { scroll.setZoomScale(1, animated: false); scroll.imageView.image = image; scroll.setNeedsLayout() }
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
        override init(frame: CGRect) { super.init(frame: frame); imageView.contentMode = .scaleAspectFit; addSubview(imageView) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func layoutSubviews() {
            super.layoutSubviews()
            if zoomScale == 1 { imageView.frame = bounds; contentSize = bounds.size }
        }
    }
}
