import SwiftUI
import PhotosUI
import UIKit
import ImageIO

/// ImageIO inspects bounded dimensions before decode; thumbnail generation prevents full-size
/// decompression. UIKit redraw produces a fresh JPEG with no source EXIF/GPS/container metadata.
@MainActor enum RetainedImageSanitizer {
    static func sanitize(_ bytes: Data) throws -> RetainedSelectedImage {
        guard !bytes.isEmpty, bytes.count <= RetainedSelectedImage.maximumInputBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30000, height <= 30000,
              width <= 100_000_000 / height else { throw RetainedImageFailure.invalid }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: RetainedSelectedImage.maximumDimension,
            kCGImageSourceShouldCacheImmediately: true]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw RetainedImageFailure.invalid }
        let size = CGSize(width: decoded.width, height: decoded.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: decoded).draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.9, 0.75, 0.55] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= RetainedSelectedImage.maximumBytes {
                return try .init(jpeg: jpeg, width: decoded.width, height: decoded.height)
            }
        }
        throw RetainedImageFailure.invalid
    }
}
/// Reusable selected-item-only PhotosUI bridge. Default OS gate is off. No library-wide request.
@MainActor final class RetainedNativeImagePicker: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    let enabled: Bool
    private let present: (UIViewController) -> Bool
    private let dismiss: () -> Void
    private var pending: CheckedContinuation<RetainedSelectedImage?, Error>?
    private var generation = 0
    private var progress: Progress?
    init(enabled: Bool = false, present: @escaping (UIViewController) -> Bool, dismiss: @escaping () -> Void) {
        self.enabled = enabled; self.present = present; self.dismiss = dismiss
    }
    func select() async throws -> RetainedSelectedImage? {
        guard enabled else { throw RetainedImageFailure.disabled }
        guard pending == nil else { throw RetainedImageFailure.invalid }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
                let picker = PHPickerViewController(configuration: config); picker.delegate = self
                if !present(picker) { finish(.failure(RetainedImageFailure.disabled)) }
                else { picker.presentationController?.delegate = self }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { cancel() }
    func cancel() { generation += 1; progress?.cancel(); progress = nil; dismiss(); finish(.success(nil)) }
    private func finish(_ value: Result<RetainedSelectedImage?, Error>) {
        let continuation = pending; pending = nil; progress = nil; continuation?.resume(with: value)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss()
        guard let result = results.first else { finish(.success(nil)); return }
        let stamp = generation
        // File representation allows a byte-size check before loading selected bytes into memory.
        progress = result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.image") { [weak self] url, error in
            let outcome: Result<Data, Error>
            do {
                guard let url, error == nil else { throw RetainedImageFailure.invalid }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size > 0, size <= RetainedSelectedImage.maximumInputBytes else { throw RetainedImageFailure.invalid }
                outcome = .success(try Data(contentsOf: url, options: .mappedIfSafe))
            } catch { outcome = .failure(error) }
            Task { @MainActor in
                guard let self, self.generation == stamp, self.pending != nil else { return }
                do { self.finish(.success(try RetainedImageSanitizer.sanitize(outcome.get()))) }
                catch { self.finish(.failure(error)) }
            }
        }
    }
}
@MainActor final class IMNativeImagePicker: IMImageSelecting {
    private let picker: RetainedNativeImagePicker
    private let currentScope: () -> IMScope?
    var isConfigured: Bool { picker.enabled }
    init(picker: RetainedNativeImagePicker, currentScope: @escaping () -> IMScope?) { self.picker = picker; self.currentScope = currentScope }
    func select(scope: IMScope, consent: IMMediaConsent) async throws -> IMMediaSelection? {
        guard consent.scope == scope, consent.purpose == .selection, currentScope() == scope else { throw IMCapabilityGap.staleScope }
        guard let image = try await picker.select() else { return nil }
        guard currentScope() == scope, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        return try .init(scope: scope, bytes: image.jpeg, mimeType: "image/jpeg", fileExtension: "jpg", id: consent.selectionID)
    }
    func cancel() { picker.cancel() }
}
