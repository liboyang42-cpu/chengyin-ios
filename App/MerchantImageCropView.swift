import SwiftUI
import UIKit

/// Only accepts the sanitizer's bounded, upright, metadata-free selection.
@MainActor enum MerchantImageCropRenderer {
    static func preview(_ source: RetainedSelectedImage, rect: MerchantImageCropRect) throws -> UIImage {
        guard let image = UIImage(data: source.jpeg), image.imageOrientation == .up,
              let pixels = image.cgImage, pixels.width == source.width, pixels.height == source.height,
              rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
              rect.x + rect.width <= source.width, rect.y + rect.height <= source.height,
              let cropped = pixels.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)) else {
            throw RetainedImageFailure.invalid
        }
        return UIImage(cgImage: cropped)
    }
    static func render(_ source: RetainedSelectedImage, rect: MerchantImageCropRect) throws -> RetainedSelectedImage {
        let image = try preview(source, rect: rect)
        // Redraw and encode a fresh image; never copy source container metadata.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: rect.width, height: rect.height)
        let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.9, 0.75, 0.55] {
            if let bytes = output.jpegData(compressionQuality: quality), bytes.count <= RetainedSelectedImage.maximumBytes {
                return try .init(jpeg: bytes, width: rect.width, height: rect.height)
            }
        }
        throw RetainedImageFailure.invalid
    }
}

struct MerchantImageCropDraft: Identifiable {
    let id = UUID()
    let source: RetainedSelectedImage
    let aspect: MerchantImageCropAspect
}

@MainActor struct MerchantImageCropView: View {
    let draft: MerchantImageCropDraft
    let confirm: (UUID, MerchantImageCropRect) -> Void
    let cancel: () -> Void
    @State private var horizontal = 0.5
    @State private var vertical = 0.5
    @State private var zoom = 1.0
    private var rect: MerchantImageCropRect? {
        try? .init(sourceWidth: draft.source.width, sourceHeight: draft.source.height, aspect: draft.aspect,
                   horizontal: horizontal, vertical: vertical, zoom: zoom)
    }
    private var titleKey: String {
        switch draft.aspect {
        case .logo: return "image.crop.logo"
        case .cover: return "image.crop.cover"
        case .gallery: return "image.crop.gallery"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(titleKey)).font(.headline)
            Text("image.crop.localOnly").font(.footnote)
            if let rect, let preview = try? MerchantImageCropRenderer.preview(draft.source, rect: rect) {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240)
                    .accessibilityLabel("image.crop.preview")
                Text("image.crop.horizontal")
                Slider(value: $horizontal, in: 0...1).accessibilityLabel("image.crop.horizontal")
                    .accessibilityIdentifier("image.crop.horizontal")
                Text("image.crop.vertical")
                Slider(value: $vertical, in: 0...1).accessibilityLabel("image.crop.vertical")
                    .accessibilityIdentifier("image.crop.vertical")
                Text("image.crop.zoom")
                Slider(value: $zoom, in: 1...4).accessibilityLabel("image.crop.zoom")
                    .accessibilityIdentifier("image.crop.zoom")
                Button("image.crop.confirm") { confirm(draft.id, rect) }
                    .accessibilityIdentifier("image.crop.confirm")
            } else { Text("image.retained.failed") }
            Button("image.retained.cancel", role: .cancel, action: cancel)
                .accessibilityIdentifier("image.crop.cancel")
        }
    }
}
