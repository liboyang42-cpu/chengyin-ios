import SwiftUI
import UIKit
import ImageIO
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit

/// The host supplies its existing media authority and content snapshot identity.
/// No credentials, new origins, business requests or backdrop capture are introduced.
struct QuestifyProgressiveBlurIdentity: Hashable, Sendable {
    let owner: String
    let content: String
    let version: String
}

struct ProgressiveArtworkRequest: Hashable, Sendable {
    let url: URL
    let identity: QuestifyProgressiveBlurIdentity
    let output: ProgressiveBlurOutput
    let parameters: ProgressiveBlurParameters
    let appearance: String
    let increasedContrast: Bool
    let usesBlur: Bool
    // Current cards use scaledToFill's centered crop; keep it explicit in the cache key.
    let cropX = 0.5
    let cropY = 0.5
}

struct ProgressivePixels: @unchecked Sendable { let image: CGImage }

/// Retirement is synchronous even when the image actor is busy in an opaque CI call.
/// The tiny mutable flag is protected by the lock; no image pixels are shared here.
final class ProgressiveArtworkLease: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isCurrent: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func invalidate() { lock.lock(); active = false; lock.unlock() }
    func check() throws { if !isCurrent { throw CancellationError() } }
}

/// Owns only immutable decoded/derived image data. All ImageIO and CI work runs
/// on this actor, never synchronously in body or on the MainActor.
actor ProgressiveArtworkRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private struct Key: Hashable { let request: ProgressiveArtworkRequest; let contentDigest: String }
    private var entries: [(Key, ProgressivePixels)] = []
    private var bytes = 0
    func clear() { entries.removeAll(); bytes = 0; context.clearCaches() }
    func render(_ data: Data, request: ProgressiveArtworkRequest, lease: ProgressiveArtworkLease = .init()) throws -> ProgressivePixels {
        try Task.checkCancellation(); try lease.check()
        let key = Key(request: request, contentDigest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        if let index = entries.firstIndex(where: { $0.0 == key }) {
            let hit = entries.remove(at: index); entries.append(hit); return hit.1
        }
        guard data.count <= ObjectCardMediaPolicy.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 32_000_000 else { throw ObjectCardMediaFailure.unsupportedImage }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let orientedWidth = rotated ? height.doubleValue : width.doubleValue
        let orientedHeight = rotated ? width.doubleValue : height.doubleValue
        let decodeFit = max(Double(request.output.width) / orientedWidth, Double(request.output.height) / orientedHeight)
        let decodeSide = max(1, Int(ceil(min(2048, max(orientedWidth, orientedHeight) * decodeFit))))
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeSide,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw ObjectCardMediaFailure.unsupportedImage }
        try Task.checkCancellation()
        let extent = CGRect(x: 0, y: 0, width: CGFloat(request.output.width), height: CGFloat(request.output.height))
        let fit = max(extent.width / CGFloat(decoded.width), extent.height / CGFloat(decoded.height))
        let scaled = CIImage(cgImage: decoded).transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        let crop = CGRect(x: (scaled.extent.width - extent.width) * CGFloat(request.cropX),
                          y: (scaled.extent.height - extent.height) * CGFloat(request.cropY),
                          width: extent.width, height: extent.height)
        let image = scaled.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        var result = image
        if request.usesBlur && request.parameters.maxRadius > 0 {
            let ramp = CIFilter.linearGradient()
            // Core Image coordinates increase upward. The contract increases from top to bottom.
            ramp.point0 = CGPoint(x: 0, y: extent.height * CGFloat(1 - request.parameters.start))
            ramp.point1 = CGPoint(x: 0, y: extent.height * CGFloat(1 - request.parameters.end))
            ramp.color0 = .black; ramp.color1 = .white
            guard var mask = ramp.outputImage else { throw ObjectCardMediaFailure.unsupportedImage }
            if request.parameters.curve == .smoothstep {
                let curve = CIFilter.colorPolynomial(); curve.inputImage = mask
                let coefficients = CIVector(x: 0, y: 0, z: 3, w: -2)
                curve.redCoefficients = coefficients; curve.greenCoefficients = coefficients; curve.blueCoefficients = coefficients
                curve.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
                guard let curved = curve.outputImage else { throw ObjectCardMediaFailure.unsupportedImage }
                mask = curved
            }
            let filter = CIFilter.maskedVariableBlur()
            filter.inputImage = image.clampedToExtent()
            filter.mask = mask.cropped(to: extent).clampedToExtent()
            filter.radius = Float(request.parameters.maxRadius * request.output.effectiveScale)
            guard let blurred = filter.outputImage else { throw ObjectCardMediaFailure.unsupportedImage }
            result = blurred.cropped(to: extent)
        }
        try Task.checkCancellation()
        guard let cg = context.createCGImage(result, from: extent, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw ObjectCardMediaFailure.unsupportedImage
        }
        try Task.checkCancellation(); try lease.check()
        let pixels = ProgressivePixels(image: cg), cost = cg.bytesPerRow * cg.height
        while !entries.isEmpty && (entries.count >= 2 || bytes + cost > 16 * 1024 * 1024) {
            let removed = entries.removeFirst().1.image; bytes -= removed.bytesPerRow * removed.height
        }
        if cost <= 16 * 1024 * 1024 { entries.append((key, pixels)); bytes += cost }
        return pixels
    }
}

@MainActor final class ProgressiveArtworkModel: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var loaded: ProgressiveArtworkRequest?
    private let renderer = ProgressiveArtworkRenderer()
    private var generation = UUID()
    private struct SourceKey: Equatable { let url: URL; let identity: QuestifyProgressiveBlurIdentity }
    private var source: SourceKey?
    private var data: Data?
    private var memoryPressure = false
    private var work: Task<Void, Never>?
    private var lease: ProgressiveArtworkLease?
    func retire(memoryPressure: Bool = false) {
        lease?.invalidate(); lease = nil
        work?.cancel(); work = nil
        generation = UUID(); image = nil; loaded = nil; data = nil; source = nil
        self.memoryPressure = memoryPressure
        Task { await renderer.clear() }
    }
    func load(_ request: ProgressiveArtworkRequest, reader: any ObjectCardImageLoading) async {
        guard !Task.isCancelled else { return }
        lease?.invalidate(); work?.cancel()
        let lease = ProgressiveArtworkLease(); self.lease = lease
        let task = Task { await performLoad(request, reader: reader, lease: lease) }
        work = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { lease.invalidate(); task.cancel() })
    }
    private func performLoad(_ request: ProgressiveArtworkRequest, reader: any ObjectCardImageLoading, lease: ProgressiveArtworkLease) async {
        // An already retired queued worker cannot replace a newer worker's generation.
        guard !Task.isCancelled, lease.isCurrent else { return }
        generation = UUID(); let ticket = generation
        image = nil; loaded = nil
        guard !memoryPressure else { return }
        let captured = SourceKey(url: request.url, identity: request.identity)
        if source != captured { data = nil; source = nil; await renderer.clear() }
        do {
            try Task.checkCancellation()
            guard ticket == generation, lease.isCurrent else { return }
            let bytes: Data
            if source == captured, let data { bytes = data }
            else { bytes = try await reader.image(url: request.url.absoluteString) }
            try Task.checkCancellation()
            guard ticket == generation, lease.isCurrent else { return }
            guard bytes.count <= ObjectCardMediaPolicy.maximumBytes else { throw ObjectCardMediaFailure.tooLarge }
            source = captured; data = bytes
            let pixels = try await renderer.render(bytes, request: request, lease: lease)
            try Task.checkCancellation()
            guard ticket == generation, source == captured, lease.isCurrent else { return }
            image = pixels.image; loaded = request
        } catch { /* Stable existing placeholder and information panel stay available. */ }
    }
}

/// A decorative image-only layer. Titles, logos, badges and controls remain in
/// QuestifyImageEntityCard's separate opaque foreground information panel.
@MainActor struct QuestifyProgressiveBlurArtwork<Placeholder: View>: View {
    let url: URL
    let identity: QuestifyProgressiveBlurIdentity
    let reader: any ObjectCardImageLoading
    let parameters: ProgressiveBlurParameters
    let placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @QuestifyReduceMotion private var reduceMotion
    @StateObject private var model = ProgressiveArtworkModel()
    @State private var constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    var body: some View {
        GeometryReader { geometry in
            if let output = ProgressiveBlurOutput(pointWidth: Double(geometry.size.width), pointHeight: Double(geometry.size.height), scale: Double(scale)) {
                let request = ProgressiveArtworkRequest(url: url, identity: identity, output: output, parameters: parameters,
                    appearance: scheme == .dark ? "dark" : "light", increasedContrast: contrast == .increased,
                    usesBlur: !reduceTransparency && !constrained)
                Group {
                    if model.loaded == request, let image = model.image {
                        Image(decorative: image, scale: CGFloat(output.effectiveScale), orientation: .up).resizable().scaledToFill()
                            .overlay(Color.black.opacity(reduceTransparency ? 0 : parameters.tintOpacity))
                    } else { placeholder() }
                }
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .task(id: request) { await model.load(request, reader: reader) }
                .transaction { transaction in if reduceMotion { transaction.animation = nil } }
            } else { placeholder() }
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(parameters.cornerRadius), style: .continuous))
        .allowsHitTesting(false).accessibilityHidden(true)
        .onDisappear { model.retire() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in model.retire(memoryPressure: true) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in updateConstraints() }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in updateConstraints() }
    }
    private func updateConstraints() {
        constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
}
