import SwiftUI

/// Reuses the existing post image loading path. A tap previews decoded pixels;
/// it does not enable a new media reader, upload, save, share or another origin.
@MainActor struct ClubPostImageGallery: View {
    let post: ClubCommunityPost
    let clubID: Int?
    let identity: ClubReadIdentity
    @ObservedObject var model: ClubCommunityViewModel
    @State private var selection: ClubPostImageSelection?
    @State private var initialImage: Image?
    @State private var retries: [Int: Int] = [:]
    @State private var returnFocus: Int?
    @AccessibilityFocusState private var focusedImage: Int?
    private var current: Bool {
        (try? model.context.currentSession().identity) == identity &&
        model.snapshot?.posts.filter({ $0.id == post.id }).count == 1 && model.snapshot?.posts.contains(post) == true
    }
    var body: some View {
        let renderedReadScope = model.imageReadScope
        Group {
            if current {
                ForEach(Array(post.images.enumerated()), id: \.offset) { index, raw in
                    AsyncImage(url: URL(string: raw)) { phase in
                        switch phase {
                        case .success(let image):
                            Button {
                                guard current, renderedReadScope == model.imageReadScope, selection == nil else { return }
                                let target = ClubPostImageSelection(post: post, clubID: clubID, identity: identity,
                                                                   readScope: renderedReadScope, index: index)
                                guard let target else { return }
                                returnFocus = index; initialImage = image; selection = target
                            } label: { image.resizable().scaledToFit() }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("club.postImages.open \(index + 1) \(post.images.count)"))
                            .accessibilityIdentifier("club.postImages.open.\(post.id).\(index)")
                            .accessibilityFocused($focusedImage, equals: index)
                        case .failure:
                            VStack {
                                Label("media.destination.failed", systemImage: "photo.badge.exclamationmark")
                                Button("action.retry") { retries[index, default: 0] += 1 }
                                    .accessibilityIdentifier("club.postImages.retry.\(post.id).\(index)")
                            }
                        case .empty:
                            if URL(string: raw) == nil { Label("media.destination.failed", systemImage: "photo.badge.exclamationmark") }
                            else { ProgressView("square.imageLoading") }
                        @unknown default: Image(systemName: "photo")
                        }
                    }.id("\(renderedReadScope)|\(index)|\(retries[index, default: 0])")
                }
            }
        }
        .sheet(item: $selection, onDismiss: {
            initialImage = nil
            if current { focusedImage = returnFocus }
            returnFocus = nil
        }) { selected in
            if let initialImage {
                ClubPostImagePreview(selection: selected, initialImage: initialImage, post: post, model: model)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                    .presentationCompactAdaptation(.sheet)
            }
        }
        .onChange(of: model.imageReadScope) { _, _ in invalidate() }
        .onChange(of: identity) { _, _ in invalidate() }
        .onChange(of: post) { _, _ in invalidate() }
    }
    private func invalidate() {
        selection = nil; initialImage = nil; retries = [:]; returnFocus = nil; focusedImage = nil
    }
}

@MainActor private struct ClubPostImagePreview: View {
    let selection: ClubPostImageSelection
    let initialImage: Image
    let post: ClubCommunityPost
    @ObservedObject var model: ClubCommunityViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var index: Int
    @State private var retries: [Int: Int] = [:]
    init(selection: ClubPostImageSelection, initialImage: Image, post: ClubCommunityPost, model: ClubCommunityViewModel) {
        self.selection = selection; self.initialImage = initialImage; self.post = post; self.model = model
        _index = State(initialValue: selection.initialIndex)
    }
    private var current: Bool {
        guard let identity = try? model.context.currentSession().identity else { return false }
        return selection.isCurrent(post: post, clubID: selection.clubID, identity: identity, readScope: model.imageReadScope) &&
            model.snapshot?.posts.filter({ $0.id == post.id }).count == 1 && model.snapshot?.posts.contains(post) == true
    }
    var body: some View {
        NavigationStack {
            Group {
                if current {
                    VStack(spacing: 12) {
                        TabView(selection: $index) {
                            ForEach(Array(selection.sources.enumerated()), id: \.offset) { position, raw in
                                Group {
                                    if position == selection.initialIndex {
                                        ClubPostZoomableImage(image: initialImage)
                                    } else {
                                        AsyncImage(url: URL(string: raw)) { phase in
                                            switch phase {
                                            case .success(let image): ClubPostZoomableImage(image: image)
                                            case .failure:
                                                VStack {
                                                    Label("media.destination.failed", systemImage: "photo.badge.exclamationmark")
                                                    Button("action.retry") { retries[position, default: 0] += 1 }
                                                        .accessibilityIdentifier("club.postImages.previewRetry.\(position)")
                                                }
                                            case .empty:
                                                if URL(string: raw) == nil { Label("media.destination.failed", systemImage: "photo.badge.exclamationmark") }
                                                else { ProgressView("square.imageLoading") }
                                            @unknown default: Image(systemName: "photo")
                                            }
                                        }.id("\(selection.id)|\(position)|\(retries[position, default: 0])")
                                    }
                                }.tag(position)
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never))
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 8) { positionLabel; previous; next }
                                .padding()
                        } else {
                            HStack { previous; Spacer(); positionLabel; Spacer(); next }.padding()
                        }
                    }
                } else { Color.clear.onAppear { dismiss() } }
            }
            .navigationTitle("club.postImages.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }.accessibilityIdentifier("club.postImages.close")
                }
            }
        }
        .onChange(of: model.imageReadScope) { _, _ in dismiss() }
        .accessibilityAction(.escape) { dismiss() }
    }
    private var positionLabel: some View {
        Text("\(index + 1) / \(selection.sources.count)").monospacedDigit().accessibilityIdentifier("club.postImages.position")
    }
    private var previous: some View {
        Button("media.destination.previous") { index = selection.previous(index) }
            .frame(minHeight: 44).disabled(index == 0).accessibilityIdentifier("club.postImages.previous")
    }
    private var next: some View {
        Button("media.destination.next") { index = selection.next(index) }
            .frame(minHeight: 44).disabled(index == selection.sources.count - 1).accessibilityIdentifier("club.postImages.next")
    }
}

@MainActor private struct ClubPostZoomableImage: View {
    let image: Image
    @State private var zoom = ClubPostImageZoom()
    @State private var pinchStart: Double?
    @State private var dragStart: CGSize?
    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width), height = Double(geometry.size.height)
            image.resizable().scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(CGFloat(zoom.scale)).offset(x: CGFloat(zoom.x), y: CGFloat(zoom.y))
                .contentShape(Rectangle())
                .gesture(MagnifyGesture().onChanged { value in
                    if pinchStart == nil { pinchStart = zoom.scale }
                    zoom.setScale((pinchStart ?? 1) * Double(value.magnification), width: width, height: height)
                }.onEnded { _ in pinchStart = nil })
                .simultaneousGesture(DragGesture().onChanged { value in
                    if dragStart == nil { dragStart = CGSize(width: CGFloat(zoom.x), height: CGFloat(zoom.y)) }
                    zoom.pan(x: Double(dragStart?.width ?? 0) + Double(value.translation.width),
                             y: Double(dragStart?.height ?? 0) + Double(value.translation.height), width: width, height: height)
                }.onEnded { _ in dragStart = nil }, including: zoom.scale > 1 ? .all : .none)
                .onTapGesture(count: 2) { zoom.setScale(zoom.scale > 1 ? 1 : 2.5, width: width, height: height) }
                .accessibilityLabel("media.destination.image")
                .accessibilityHint("media.destination.zoomHint")
                .accessibilityAction(named: Text("club.postImages.zoomIn")) { zoom.setScale(zoom.scale * 1.5, width: width, height: height) }
                .accessibilityAction(named: Text("club.postImages.zoomOut")) { zoom.setScale(zoom.scale / 1.5, width: width, height: height) }
                .accessibilityAction(named: Text("club.postImages.reset")) { zoom.reset() }
                .overlay(alignment: .topTrailing) {
                    if zoom.scale > 1 {
                        Button("club.postImages.reset") { zoom.reset() }
                            .padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                            .accessibilityIdentifier("club.postImages.reset")
                    }
                }
        }.clipped().onDisappear { zoom.reset(); pinchStart = nil; dragStart = nil }
    }
}
