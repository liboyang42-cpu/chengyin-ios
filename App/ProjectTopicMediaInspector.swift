import Foundation
import CryptoKit
import Darwin
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// A single, sanitized JPEG in a private app-owned temporary directory. No provider
/// URL, asset ID or filename is persisted; an opaque reference resolves only here.
final class ProjectTopicMediaInspector: ProjectTopicMediaInspecting {
    let reference: ProjectTopicMediaLocalReference
    private let context: ProjectTopicMediaContext
    private let directory: URL
    private let file: URL
    private let image: RetainedSelectedImage
    init(image: RetainedSelectedImage, context: ProjectTopicMediaContext) throws {
        self.image = image; self.context = context
        reference = .init(id: UUID(), revision: UUID())
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TopicImage-" + UUID().uuidString, isDirectory: true)
        file = directory.appendingPathComponent("selected.jpg")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try image.jpeg.write(to: file, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    deinit { remove() }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func inspect(_ request: ProjectTopicMediaInspectionRequest,
                 consume: (Data) throws -> Void) throws -> ProjectTopicMediaInspectionReport {
        guard request.context == context, request.reference == reference,
              let limit = request.policy.kinds.first(where: { $0.kind == .image }),
              limit.mimeTypes.contains("image/jpeg") else { throw ProjectTopicMediaFailure.changedContext }
        let ceiling = min(min(request.policy.maximumTotalBytes, limit.maximumBytes), UInt64(RetainedSelectedImage.maximumBytes))
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw ProjectTopicMediaFailure.inspectionUnavailable }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_nlink == 1, before.st_size > 0, UInt64(before.st_size) <= ceiling else { throw ProjectTopicMediaFailure.byteLimit }
        var bytes = Data()
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard UInt64(bytes.count) <= ceiling, UInt64(chunk.count) <= ceiling - UInt64(bytes.count) else { throw ProjectTopicMediaFailure.byteLimit }
            try consume(chunk); bytes.append(chunk)
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              bytes.count == Int(before.st_size), bytes == image.jpeg else { throw ProjectTopicMediaFailure.changedSource }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source), UTType(type as String) == .jpeg,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == image.width, height == image.height, width > 0, height > 0,
              UInt64(width) <= limit.maximumWidth, UInt64(height) <= limit.maximumHeight,
              UInt64(width) <= limit.maximumPixels / UInt64(height) else { throw ProjectTopicMediaFailure.dimensionLimit }
        // Decode the complete bounded sanitized image, not an untrusted metadata thumbnail.
        guard let pixels = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              pixels.width == width, pixels.height == height, CGImageSourceGetStatus(source) == .statusComplete else { throw ProjectTopicMediaFailure.invalidInspection }
        return .init(requestID: request.id, reference: reference, kind: .image, mimeType: "image/jpeg",
                     byteCount: UInt64(bytes.count), width: UInt64(width), height: UInt64(height), durationMilliseconds: nil,
                     decodedContentSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                     checks: [.regularAppManagedFile, .containerRecognized, .metadataDecoded, .imageDecoded])
    }
}

/// Integer geometry exactly matches the Mini's fixed topic ratios without upscaling.
struct ProjectTopicImageCropRect: Equatable {
    let field: ProjectTopicImageField
    let sourceWidth, sourceHeight, x, y, width, height: Int
    init(image: RetainedSelectedImage, field: ProjectTopicImageField, horizontal: Double = 0.5,
         vertical: Double = 0.5, zoom: Double = 1) throws {
        guard horizontal.isFinite, vertical.isFinite, zoom.isFinite,
              (0...1).contains(horizontal), (0...1).contains(vertical), (1...4).contains(zoom) else { throw RetainedImageFailure.invalid }
        let available = min(image.width / field.widthUnits, image.height / field.heightUnits)
        guard available > 0 else { throw RetainedImageFailure.invalid }
        let units = max(1, Int((Double(available) / zoom).rounded(.down)))
        self.field = field; sourceWidth = image.width; sourceHeight = image.height
        width = units * field.widthUnits; height = units * field.heightUnits
        x = Int((Double(image.width - width) * horizontal).rounded())
        y = Int((Double(image.height - height) * vertical).rounded())
    }
}
@MainActor enum ProjectTopicImageCropRenderer {
    static func preview(_ image: RetainedSelectedImage, rect: ProjectTopicImageCropRect, field: ProjectTopicImageField) throws -> UIImage {
        guard rect.field == field, rect.sourceWidth == image.width, rect.sourceHeight == image.height,
              rect.width * field.heightUnits == rect.height * field.widthUnits,
              let decoded = UIImage(data: image.jpeg), decoded.imageOrientation == .up, let pixels = decoded.cgImage,
              pixels.width == image.width, pixels.height == image.height,
              let cropped = pixels.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)) else { throw RetainedImageFailure.invalid }
        return UIImage(cgImage: cropped)
    }
    static func render(_ image: RetainedSelectedImage, rect: ProjectTopicImageCropRect, field: ProjectTopicImageField) throws -> RetainedSelectedImage {
        let cropped = try preview(image, rect: rect, field: field)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: rect.width, height: rect.height)
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            cropped.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.9, 0.75, 0.55] {
            if let bytes = result.jpegData(compressionQuality: quality), bytes.count <= RetainedSelectedImage.maximumBytes {
                return try .init(jpeg: bytes, width: rect.width, height: rect.height)
            }
        }
        throw RetainedImageFailure.invalid
    }
}
