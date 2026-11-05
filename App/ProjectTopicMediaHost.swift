import SwiftUI

/// Mounted beside the existing Mini-shaped basic fields, with native form/sheet controls.
@MainActor struct ProjectTopicMediaHost: View {
    @ObservedObject var editor: ProjectEditModel
    @StateObject private var controller: ProjectTopicMediaPresentation
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    init(editor: ProjectEditModel) {
        self.editor = editor; _controller = StateObject(wrappedValue: .init(editor: editor))
    }
    var body: some View {
        let original = controller.opening
        // Mini-program topic details: cover (3:4) and up to nine banner images (16:9).
        // Hidden entirely when this topic or account can't upload images; no "not connected" captions.
        let visible = controller.canOpen(.cover) || controller.canOpen(.gallery) || original != nil
        Section {
            if controller.canOpen(.cover) || original != nil {
                Button { controller.open(.cover) } label: { Label("projectTopicMedia.chooseCover", systemImage: "photo") }
                    .disabled(!controller.canOpen(.cover)).accessibilityIdentifier("projectTopicMedia.cover")
            }
            if controller.canOpen(.gallery) || original != nil {
                Button { controller.open(.gallery) } label: { Label("projectTopicMedia.addGallery", systemImage: "photo.on.rectangle") }
                    .disabled(!controller.canOpen(.gallery)).accessibilityIdentifier("projectTopicMedia.gallery")
            }
        } header: { if visible { Text("projectTopicMedia.title") } }
        .sheet(item: controller.binding(original)) { captured in
            ProjectTopicMediaSheet(controller: controller, original: captured)
        }
        .onChange(of: editor.topicMediaContext) { _, _ in controller.synchronize() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.retire() } }
        .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectTopicMediaSheet: View {
    @ObservedObject var controller: ProjectTopicMediaPresentation
    let original: ProjectTopicMediaPresentation.Opening
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    Section {
                                                if [.idle, .failed].contains(controller.state) {
                            Button("projectTopicMedia.choose") { controller.choose(original) }
                                .accessibilityIdentifier("projectTopicMedia.choose")
                        }
                        if controller.state == .picking {
                            ProgressView("projectTopicMedia.reading")
                            Button("action.cancel") { controller.cancelSelection(original) }
                        }
                        if let crop = controller.crop {
                            ProjectTopicImageCropControls(crop: crop, field: original.field,
                                confirm: { controller.confirmCrop(crop, rect: $0, original: original) },
                                cancel: { controller.cancelSelection(original) }).id(crop.id)
                        }
                        if let thumbnail = controller.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 300)
                                .accessibilityLabel(Text("projectTopicMedia.previewLabel"))
                                .accessibilityIdentifier("projectTopicMedia.preview")
                        }
                        if controller.state == .preview {
                            Text("projectTopicMedia.notUploaded").foregroundStyle(.secondary)
                            Button("projectTopicMedia.upload") { controller.upload(original) }
                                .accessibilityIdentifier("projectTopicMedia.upload")
                            Button("projectTopicMedia.reselect", role: .destructive) { controller.cancelSelection(original) }
                        }
                        if controller.state == .uploading { ProgressView("projectTopicMedia.uploading") }
                        if [.uploaded, .localSaveFailed].contains(controller.state) {
                            Text("projectTopicMedia.uploaded")
                            Button("projectTopicMedia.apply") { controller.apply(original) }
                                .accessibilityIdentifier("projectTopicMedia.apply")
                        }
                        if controller.state == .localSaveFailed {
                            Text("projectTopicMedia.applyFailed").foregroundStyle(.red)
                        }
                        if controller.state == .failed { Text("projectTopicMedia.failed").foregroundStyle(.red) }
                        if controller.state == .unknown {
                            Text("projectTopicMedia.unknown").foregroundStyle(.red)
                                .accessibilityIdentifier("projectTopicMedia.unknown")
                        }
                    }
                } else { Text("projectTopicMedia.expired") }
            }
            .navigationTitle(Text(LocalizedStringKey(original.field == .cover ? "projectTopicMedia.coverTitle" : "projectTopicMedia.galleryTitle"))).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { controller.close(original) } } }
            .background(RetainedImagePresenterHost(host: controller.pickerHost).frame(width: 0, height: 0))
        }
    }
}

@MainActor private struct ProjectTopicImageCropControls: View {
    let crop: ProjectTopicMediaPresentation.Crop
    let field: ProjectTopicImageField
    let confirm: (ProjectTopicImageCropRect) -> Void
    let cancel: () -> Void
    @State private var horizontal = 0.5
    @State private var vertical = 0.5
    @State private var zoom = 1.0
    private var rect: ProjectTopicImageCropRect? {
        try? .init(image: crop.image, field: field, horizontal: horizontal, vertical: vertical, zoom: zoom)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rect, let preview = try? ProjectTopicImageCropRenderer.preview(crop.image, rect: rect, field: field) {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("image.crop.preview")
                Text("image.crop.horizontal")
                Slider(value: $horizontal, in: 0...1).accessibilityLabel("image.crop.horizontal")
                Text("image.crop.vertical")
                Slider(value: $vertical, in: 0...1).accessibilityLabel("image.crop.vertical")
                Text("image.crop.zoom")
                Slider(value: $zoom, in: 1...4).accessibilityLabel("image.crop.zoom")
                Button("image.crop.confirm") { confirm(rect) }.accessibilityIdentifier("projectTopicMedia.confirmCrop")
            } else { Text("image.retained.failed") }
            Button("image.retained.cancel", role: .cancel, action: cancel)
        }
        .buttonStyle(.borderless)
    }
}

/// Exact topic-specific multipart route. A matching story grant can never admit it.
enum ProjectTopicImageCompositionRoute {
    static func field(_ request: URLRequest, baseURL: URL) -> ProjectTopicImageField? {
        guard request.url == baseURL.appendingPathComponent(ProjectTopicImageUploadClient.path),
              request.httpMethod == "POST", request.httpBodyStream == nil, let body = request.httpBody,
              let type = request.value(forHTTPHeaderField: "Content-Type") else { return nil }
        let prefix = "multipart/form-data; boundary=ProjectTopicImage-"
        guard type.hasPrefix(prefix), let id = UUID(uuidString: String(type.dropFirst(prefix.count))),
              id.uuidString == String(type.dropFirst(prefix.count)) else { return nil }
        let boundary = "ProjectTopicImage-" + id.uuidString
        for field in [ProjectTopicImageField.cover, .gallery] {
            let first = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\n\(field.businessType)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"topic.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
            let last = Data("\r\n--\(boundary)--\r\n".utf8)
            if body.starts(with: first), body.suffix(last.count) == last,
               body.count > first.count + last.count, body.count - first.count - last.count <= RetainedSelectedImage.maximumBytes,
               body.dropFirst(first.count).starts(with: [255, 216, 255]) { return field }
        }
        return nil
    }
}
