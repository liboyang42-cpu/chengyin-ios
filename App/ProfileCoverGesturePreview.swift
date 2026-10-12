import SwiftUI
import UIKit

/// Only receives the already selected, sanitized local image. No picker, file or network I/O.
@MainActor struct ProfileCoverGesturePreview: UIViewRepresentable {
    let draftID: UUID
    let source: RetainedSelectedImage
    @Binding var position: ProfileCoverCropPosition
    let isCurrent: () -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ProfileCoverCropCanvas {
        let view = ProfileCoverCropCanvas()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch)
        view.accessibilityIdentifier = "profile.localCover.gesturePreview"
        view.isAccessibilityElement = true
        view.accessibilityLabel = appLocalized("profile.localCover.gesturePreview", locale: .current)
        return view
    }
    func updateUIView(_ view: ProfileCoverCropCanvas, context: Context) {
        context.coordinator.bind(view, draftID: draftID, source: source, position: $position, isCurrent: isCurrent)
    }
    static func dismantleUIView(_ view: ProfileCoverCropCanvas, coordinator: Coordinator) { coordinator.retire(view) }
    @MainActor final class Coordinator: NSObject {
        private var retired = false
        private var draftID: UUID?
        private var position: Binding<ProfileCoverCropPosition>?
        private var isCurrent: (() -> Bool)?
        func bind(_ view: ProfileCoverCropCanvas, draftID: UUID, source: RetainedSelectedImage,
                  position: Binding<ProfileCoverCropPosition>, isCurrent: @escaping () -> Bool) {
            guard !retired else { return }
            if let bound = self.draftID, bound != draftID || view.source != source { retire(view); return }
            guard isCurrent() else { retire(view); return }
            self.draftID = draftID; self.position = position; self.isCurrent = isCurrent
            view.configure(draftID: draftID, source: source, position: position.wrappedValue)
            view.isUserInteractionEnabled = isCurrent()
        }
        private func owns(_ view: ProfileCoverCropCanvas) -> Bool {
            guard !retired, draftID != nil, draftID == view.draftID, isCurrent?() == true, view.hasValidImage else {
                retire(view); return false
            }
            return true
        }
        func applyPan(deltaX: Double, deltaY: Double, to view: ProfileCoverCropCanvas) {
            guard owns(view), let position, let source = view.source,
                  let next = try? position.wrappedValue.panned(deltaX: deltaX, deltaY: deltaY,
                    viewportWidth: Double(view.cropBounds.width), viewportHeight: Double(view.cropBounds.height),
                    sourceWidth: source.width, sourceHeight: source.height), owns(view) else { return }
            view.position = next; view.setNeedsLayout(); position.wrappedValue = next
        }
        func applyPinch(factor: Double, to view: ProfileCoverCropCanvas) {
            guard owns(view), let position, let source = view.source,
                  let next = try? position.wrappedValue.pinched(by: factor, sourceWidth: source.width, sourceHeight: source.height),
                  owns(view) else { return }
            view.position = next; view.setNeedsLayout(); position.wrappedValue = next
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? ProfileCoverCropCanvas else { return }
            let delta = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            guard [.began, .changed, .ended].contains(gesture.state) else { return }
            applyPan(deltaX: Double(delta.x), deltaY: Double(delta.y), to: view)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? ProfileCoverCropCanvas else { return }
            let factor = Double(gesture.scale); gesture.scale = 1
            guard [.began, .changed, .ended].contains(gesture.state) else { return }
            applyPinch(factor: factor, to: view)
        }
        func retire(_ view: ProfileCoverCropCanvas) {
            retired = true; draftID = nil; position = nil; isCurrent = nil
            view.isUserInteractionEnabled = false
            for gesture in view.gestureRecognizers ?? [] { gesture.isEnabled = false }
            view.clear()
        }
    }
}

@MainActor final class ProfileCoverCropCanvas: UIView {
    private let clipping = UIView()
    private let imageView = UIImageView()
    private(set) var draftID: UUID?
    private(set) var source: RetainedSelectedImage?
    private(set) var hasValidImage = false
    var position = ProfileCoverCropPosition()
    var cropBounds: CGRect { clipping.bounds }
    var renderedImageBounds: CGRect { imageView.frame }
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipping.clipsToBounds = true; clipping.isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        addSubview(clipping); clipping.addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func configure(draftID: UUID, source: RetainedSelectedImage, position: ProfileCoverCropPosition) {
        if self.draftID != draftID || self.source != source {
            self.draftID = draftID; self.source = source
            if let image = UIImage(data: source.jpeg), image.imageOrientation == .up, let pixels = image.cgImage,
               pixels.width == source.width, pixels.height == source.height,
               (try? position.rect(sourceWidth: source.width, sourceHeight: source.height)) != nil {
                imageView.image = image; hasValidImage = true
            } else { imageView.image = nil; hasValidImage = false }
        }
        self.position = position; setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              hasValidImage, let source, let crop = try? position.rect(sourceWidth: source.width, sourceHeight: source.height) else {
            clipping.frame = .zero; imageView.frame = .zero; return
        }
        let width = min(bounds.width, bounds.height * 16 / 9), height = width * 9 / 16
        clipping.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
        let scale = width / CGFloat(crop.width)
        imageView.frame = CGRect(x: -CGFloat(crop.x) * scale, y: -CGFloat(crop.y) * scale,
                                 width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
    }
    func clear() {
        draftID = nil; source = nil; hasValidImage = false; imageView.image = nil
        imageView.frame = .zero; clipping.frame = .zero
    }
}
