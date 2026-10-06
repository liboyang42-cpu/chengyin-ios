import SwiftUI

/// Local draft-ID-bound crop controls, reused by bounded template and story-image hosts.
@MainActor struct TemplateImageCropView: View {
    let draft: TemplateImageCropDraft
    let confirm: (UUID, TemplateImageCropRect) -> Void
    let cancel: (UUID) -> Void
    var body: some View {
        TemplateImageCropControls(draft: draft, confirm: confirm, cancel: cancel)
            .id(draft.id) // Replacement resets every control and retires the old view.
    }
}

@MainActor private struct TemplateImageCropControls: View {
    let draft: TemplateImageCropDraft
    let confirm: (UUID, TemplateImageCropRect) -> Void
    let cancel: (UUID) -> Void
    @State private var horizontal = 0.5
    @State private var vertical = 0.5
    @State private var zoom = 1.0
    private var rect: TemplateImageCropRect? {
        try? .init(sourceWidth: draft.source.width, sourceHeight: draft.source.height,
                   horizontal: horizontal, vertical: vertical, zoom: zoom)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("template.imageCrop.title").font(.headline)
            Text("template.imageCrop.localOnly").font(.footnote)
            if let rect, let preview = try? TemplateImageCropRenderer.preview(draft.source, rect: rect) {
                Image(uiImage: preview).resizable()
                    .aspectRatio(CGFloat(draft.source.width) / CGFloat(draft.source.height), contentMode: .fit)
                    .frame(maxHeight: 240)
                    .accessibilityLabel("image.crop.preview")
                Text("image.crop.horizontal")
                Slider(value: $horizontal, in: 0...1).disabled(zoom == 1)
                    .accessibilityLabel("image.crop.horizontal")
                    .accessibilityIdentifier("template.imageCrop.horizontal")
                Text("image.crop.vertical")
                Slider(value: $vertical, in: 0...1).disabled(zoom == 1)
                    .accessibilityLabel("image.crop.vertical")
                    .accessibilityIdentifier("template.imageCrop.vertical")
                Text("image.crop.zoom")
                Slider(value: $zoom, in: 1...4).accessibilityLabel("image.crop.zoom")
                    .accessibilityIdentifier("template.imageCrop.zoom")
                Button("template.imageCrop.reset") { horizontal = 0.5; vertical = 0.5; zoom = 1 }
                    .accessibilityIdentifier("template.imageCrop.reset")
                Button("template.imageCrop.confirm") { confirm(draft.id, rect) }
                    .accessibilityIdentifier("template.imageCrop.confirm")
            } else { Text("image.retained.failed") }
            Button("image.retained.cancel", role: .cancel) { cancel(draft.id) }
                .accessibilityIdentifier("template.imageCrop.cancel")
        }
        .buttonStyle(.borderless)
        .onDisappear { cancel(draft.id) }
    }
}
