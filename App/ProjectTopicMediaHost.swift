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
    private func text(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
    var body: some View {
        let original = controller.opening
        Section(text("主题图片", "Topic images")) {
            Button(text("选择封面图片（3:4）", "Choose cover image (3:4)")) { controller.open(.cover) }
                .disabled(!controller.canOpen(.cover)).accessibilityIdentifier("projectTopicMedia.cover")
            Button(text("添加横图（16:9）", "Add gallery image (16:9)")) { controller.open(.gallery) }
                .disabled(!controller.canOpen(.gallery)).accessibilityIdentifier("projectTopicMedia.gallery")
            Text(text("横图最多9张，每次添加1张。选择、裁切和预览后，需分别确认上传与回填。", "Up to 9 gallery images, added one at a time. Choose, crop and preview, then confirm upload and apply separately."))
                .font(.caption)
            if !controller.canOpen(.cover) && !controller.canOpen(.gallery) && original == nil {
                Text(text("当前主题或账号尚未配置图片上传，或编辑状态已改变。", "Image upload is not configured for this topic/account, or the editor context has changed."))
                    .font(.caption).accessibilityIdentifier("projectTopicMedia.unavailable")
            }
            Text(text("主题视频尚未接通，暂不提供选择入口。", "Topic video is not connected yet."))
                .font(.caption).accessibilityIdentifier("projectTopicMedia.videoUnavailable")
        }
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
    @Environment(\.locale) private var locale
    private func text(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    Section {
                        Text(text("图片仅在本次编辑中暂存，关闭后清除。上传不代表主题已发布或已通过审核。", "Images are temporary for this editor visit. Closing clears them. Uploading does not publish or approve a topic."))
                        if [.idle, .failed].contains(controller.state) {
                            Button(text("选择图片", "Choose image")) { controller.choose(original) }
                                .accessibilityIdentifier("projectTopicMedia.choose")
                        }
                        if controller.state == .picking {
                            ProgressView(text("正在读取图片", "Reading image"))
                            Button(text("取消", "Cancel")) { controller.cancelSelection(original) }
                        }
                        if let crop = controller.crop {
                            ProjectTopicImageCropControls(crop: crop, field: original.field,
                                confirm: { controller.confirmCrop(crop, rect: $0, original: original) },
                                cancel: { controller.cancelSelection(original) }).id(crop.id)
                        }
                        if let thumbnail = controller.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 300)
                                .accessibilityLabel(text("裁切后的本地图片预览", "Cropped local image preview"))
                                .accessibilityIdentifier("projectTopicMedia.preview")
                        }
                        if controller.state == .preview {
                            Text(text("尚未上传", "Not uploaded"))
                            Button(text("确认上传图片", "Confirm image upload")) { controller.upload(original) }
                                .accessibilityIdentifier("projectTopicMedia.upload")
                            Button(text("移除本地选择", "Remove local selection")) { controller.cancelSelection(original) }
                        }
                        if controller.state == .uploading { ProgressView(text("正在上传，尚未回填", "Uploading; not applied")) }
                        if [.uploaded, .localSaveFailed].contains(controller.state) {
                            Text(text("上传成功。请确认回填到当前主题并保存本地草稿。", "Upload succeeded. Confirm to apply the reference and save the local draft."))
                            Button(text("回填并保存草稿", "Apply and save draft")) { controller.apply(original) }
                                .accessibilityIdentifier("projectTopicMedia.apply")
                        }
                        if controller.state == .localSaveFailed {
                            Text(text("尚未回填。可能是本地保存失败或横图链接总长度超过限制；不会重新上传。", "Not applied. Local saving may have failed, or gallery links exceed the total length limit. No re-upload will occur."))
                        }
                        if controller.state == .failed { Text(text("无法读取、裁切或验证此图片，请重新选择。", "This image could not be read, cropped or verified. Choose another image.")) }
                        if controller.state == .unknown {
                            Text(text("上传结果未能确认，可能已产生远端文件。未回填，也不会自动重试。请关闭后检查，避免重复上传。", "The upload result could not be confirmed; a remote file may exist. Nothing was applied and no automatic retry will run. Close and check before uploading again."))
                                .accessibilityIdentifier("projectTopicMedia.unknown")
                        }
                    }
                } else { Text(text("编辑状态已改变，本次选择已失效。", "The editor context changed. This selection expired.")) }
            }
            .navigationTitle(text(original.field == .cover ? "主题封面" : "主题横图", original.field == .cover ? "Topic cover" : "Topic gallery"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("关闭", "Close")) { controller.close(original) } } }
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
