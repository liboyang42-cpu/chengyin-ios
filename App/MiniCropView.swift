import SwiftUI
import UIKit

/// Native counterpart of mini-program pages/crop: a centered frame of the requested ratio, pinch/pan
/// under it (clamped by `MiniCropGeometry`), and cancel / use-original / confirm for each image in turn.
/// Purely local: it returns source rectangles and never uploads or writes anything.
@MainActor struct MiniCropView: View {
    enum Result: Equatable { case original, crop(MiniCropGeometry.SourceRect) }

    let images: [UIImage]
    let ratio: String
    let onFinish: ([Result]) -> Void
    let onCancel: () -> Void
    @State private var index = 0
    @State private var results: [Result] = []
    @State private var scale = 1.0
    @State private var offset = CGSize.zero
    @State private var gestureScale = 1.0
    @State private var gestureOffset = CGSize.zero
    @State private var displayedFrame = CGSize.zero

    var body: some View {
        VStack(spacing: 16) {
            if images.count > 1 {
                Text("publishParity.crop.progress \(index + 1) \(images.count)").font(.caption)
                    .accessibilityIdentifier("miniCrop.progress")
            }
            if images.indices.contains(index) { canvas(images[index]) }
            else { Text("publishParity.crop.failed").accessibilityIdentifier("miniCrop.failed") }
            HStack {
                Button("publishParity.crop.cancel", role: .cancel, action: onCancel).accessibilityIdentifier("miniCrop.cancel")
                Spacer()
                Button("publishParity.crop.useOriginal") { advance(.original) }.accessibilityIdentifier("miniCrop.useOriginal")
                Button("publishParity.crop.confirm") { confirm() }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("miniCrop.confirm")
            }
        }
        .padding()
        .navigationTitle(Text("publishParity.crop.title"))
    }

    private func canvas(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let size = image.size
            if let frame = MiniCropGeometry.frame(ratio: ratio, imageWidth: size.width, imageHeight: size.height,
                                                  availableWidth: proxy.size.width, availableHeight: proxy.size.height) {
                let live = clamped(scale: scale * gestureScale, x: offset.width + gestureOffset.width,
                                   y: offset.height + gestureOffset.height, image: size, frame: frame)
                let base = max(frame.width / size.width, frame.height / size.height)
                Image(uiImage: image).resizable()
                    .frame(width: size.width * base * live.scale, height: size.height * base * live.scale)
                    .offset(x: live.x, y: live.y)
                    .frame(width: frame.width, height: frame.height).clipped()
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .gesture(SimultaneousGesture(
                        MagnifyGesture().onChanged { gestureScale = $0.magnification }.onEnded { _ in commit(image: size, frame: frame) },
                        DragGesture().onChanged { gestureOffset = $0.translation }.onEnded { _ in commit(image: size, frame: frame) }))
                    .accessibilityLabel(Text("image.crop.preview"))
                    .accessibilityIdentifier("miniCrop.canvas")
                    .task(id: frame.width * 10_000 + frame.height) { displayedFrame = CGSize(width: frame.width, height: frame.height) }
            }
        }.frame(minHeight: 240)
    }

    private func clamped(scale: Double, x: Double, y: Double, image: CGSize, frame: (width: Double, height: Double)) -> MiniCropGeometry.Transform {
        MiniCropGeometry.clamp(scale: scale, x: x, y: y, imageWidth: image.width, imageHeight: image.height,
                               frameWidth: frame.width, frameHeight: frame.height)
    }

    private func commit(image: CGSize, frame: (width: Double, height: Double)) {
        let t = clamped(scale: scale * gestureScale, x: offset.width + gestureOffset.width, y: offset.height + gestureOffset.height,
                        image: image, frame: frame)
        scale = t.scale; offset = CGSize(width: t.x, height: t.y); gestureScale = 1; gestureOffset = .zero
    }

    private func confirm() {
        guard images.indices.contains(index) else { return }
        // Untouched free-ratio crop keeps the original, exactly like the mini's confirm shortcut.
        if MiniCropGeometry.keepsOriginal(ratio: ratio, scale: scale, x: offset.width, y: offset.height) { advance(.original); return }
        let size = images[index].size
        // Same inputs as the mini's computeCropRect: natural image size plus the on-screen frame and transform.
        guard displayedFrame.width > 0,
              let rect = MiniCropGeometry.cropRect(scale: scale, x: offset.width, y: offset.height,
                                                   imageWidth: size.width, imageHeight: size.height,
                                                   frameWidth: displayedFrame.width, frameHeight: displayedFrame.height) else { return }
        advance(.crop(rect))
    }

    private func advance(_ result: Result) {
        results.append(result)
        scale = 1; offset = .zero; gestureScale = 1; gestureOffset = .zero
        if index + 1 < images.count { index += 1 } else { onFinish(results) }
    }
}
