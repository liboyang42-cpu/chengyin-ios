import AVFoundation
import SwiftUI
import UIKit

/// Constructed only after RoamStampCameraView's existing purpose + deployment + OS gate.
/// The engine never requests authorization, imports images, saves Photos, or sends network data.
@MainActor final class RoamStampFramingCameraController: UIViewController {
    private let engine = RoamStampFramingEngine()
    private let preview = UIView()
    private let scale = UISlider()
    private let percent = UILabel()
    private let hint = UILabel()
    private let shutter = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private var layer: AVCaptureVideoPreviewLayer?
    private var framing = RoamStampFramingState()
    private var pinchStart = RoamStampFramingState.defaultRatio
    private var ready = false
    private var shotFailed = false
    private let finished: (Result<RetainedSelectedImage?, Error>) -> Void

    init(finished: @escaping (Result<RetainedSelectedImage?, Error>) -> Void) {
        self.finished = finished; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        preview.backgroundColor = .black; preview.layer.cornerRadius = 20; preview.clipsToBounds = true
        preview.accessibilityIdentifier = "roam.stampFraming.preview"
        preview.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        scale.minimumValue = Float(RoamStampFramingState.minimumRatio)
        scale.maximumValue = Float(RoamStampFramingState.maximumRatio)
        scale.accessibilityLabel = String(localized: "roam.stampFraming.range")
        scale.accessibilityIdentifier = "roam.stampFraming.range"
        scale.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        percent.textAlignment = .center; percent.font = .preferredFont(forTextStyle: .headline)
        percent.adjustsFontForContentSizeCategory = true
        hint.text = String(localized: "roam.stampFraming.hint"); hint.numberOfLines = 0
        hint.textAlignment = .center; hint.font = .preferredFont(forTextStyle: .caption1)
        hint.adjustsFontForContentSizeCategory = true
        shutter.setTitle(String(localized: "media.stamp.capture"), for: .normal)
        shutter.configuration = .filled(); shutter.accessibilityIdentifier = "roam.stampFraming.shutter"
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)
        close.setTitle(String(localized: "action.cancel"), for: .normal)
        close.accessibilityIdentifier = "roam.stampFraming.cancel"
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        [preview, scale, percent, hint, shutter, close].forEach(view.addSubview)
        let layer = AVCaptureVideoPreviewLayer(session: engine.session)
        layer.videoGravity = .resizeAspectFill; preview.layer.insertSublayer(layer, at: 0); self.layer = layer
        refreshControls()
        engine.start { [weak self] succeeded in
            guard let self, self.framing.isActive else { return }
            guard succeeded, let connection = self.layer?.connection,
                  connection.isVideoRotationAngleSupported(90) else { self.fail(); return }
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
            }
            self.ready = true; self.refreshControls()
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        close.frame = CGRect(x: safe.minX + 16, y: safe.minY, width: 100, height: 44)
        let percentHeight = max(28, ceil(percent.font.lineHeight))
        let hintHeight = max(44, ceil(hint.sizeThatFits(CGSize(width: max(1, safe.width - 32), height: .greatestFiniteMagnitude)).height))
        let reservedHeight = 48 + 8 + percentHeight + 4 + 44 + hintHeight + 8 + 48 + 8
        let width = max(0, min(safe.width - 32, (safe.height - reservedHeight) * 0.8))
        preview.frame = CGRect(x: safe.midX - width / 2, y: safe.minY + 48, width: width, height: width / 0.8)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.frame = preview.bounds
        CATransaction.commit()
        percent.frame = CGRect(x: safe.minX + 16, y: preview.frame.maxY + 8, width: safe.width - 32, height: percentHeight)
        scale.frame = CGRect(x: safe.minX + 24, y: percent.frame.maxY + 4, width: safe.width - 48, height: 44)
        hint.frame = CGRect(x: safe.minX + 16, y: scale.frame.maxY, width: safe.width - 32, height: hintHeight)
        shutter.frame = CGRect(x: safe.minX + 24, y: hint.frame.maxY + 8, width: safe.width - 48, height: 48)
        refreshControls()
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); invalidate() }
    func invalidate() { framing.cancel(); ready = false; engine.stop() }
    private func refreshControls() {
        scale.value = Float(framing.ratio)
        let value = framing.ratio.formatted(.percent.precision(.fractionLength(0)))
        percent.text = value; scale.accessibilityValue = value
        let idle = ready && framing.isActive && framing.pending == nil && view.bounds.height >= view.bounds.width && preview.bounds.width >= 16
        scale.isEnabled = idle; shutter.isEnabled = idle
        close.isEnabled = framing.isActive
        let message = String(localized: view.bounds.width > view.bounds.height ? "roam.stampFraming.portrait" : (framing.pending != nil ? "roam.stampFraming.capturing" : (shotFailed ? "roam.stampFraming.retry" : "roam.stampFraming.hint")))
        if hint.text != message { hint.text = message; view.setNeedsLayout() }
    }
    @objc private func sliderChanged() { framing.adjust(to: Double(scale.value)); refreshControls() }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard ready, framing.isActive, framing.pending == nil else { return }
        if gesture.state == .began { pinchStart = framing.ratio }
        if gesture.state == .began || gesture.state == .changed {
            framing.adjust(to: pinchStart * Double(gesture.scale)); refreshControls()
        }
    }
    @objc private func cancel() {
        guard framing.isActive else { return }
        invalidate(); finished(.success(nil))
    }
    @objc private func capture() {
        guard ready, shutter.isEnabled, UIApplication.shared.applicationState == .active else { return }
        do {
            guard let shot = try framing.begin(viewportWidth: Double(preview.bounds.width), viewportHeight: Double(preview.bounds.height)) else { return }
            shotFailed = false; refreshControls()
            engine.capture { [weak self] bytes in
                guard let self, self.framing.isActive, self.framing.pending?.id == shot.id else { return }
                guard UIApplication.shared.applicationState == .active else {
                    _ = self.framing.resolve(shot.id, succeeded: false)
                    self.shotFailed = true; self.refreshControls(); return
                }
                do {
                    guard let bytes, let image = UIImage(data: bytes) else { throw RetainedImageFailure.invalid }
                    let result = try RoamStampFramedPixels.render(image, frame: shot.frame)
                    guard self.framing.resolve(shot.id, succeeded: true) else { return }
                    self.engine.stop(); self.finished(.success(result))
                } catch {
                    guard self.framing.resolve(shot.id, succeeded: false) else { return }
                    self.shotFailed = true; self.refreshControls()
                }
            }
        } catch { shotFailed = true; refreshControls() }
    }
    private func fail() {
        guard framing.isActive else { return }
        invalidate(); finished(.failure(RetainedImageFailure.invalid))
    }
}

/// AVCaptureSession mutations and blocking start/stop run on a private serial queue. The only
/// cross-queue product is JPEG bytes; per-shot delegates and controller state reject late delivery.
private final class RoamStampFramingEngine: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "chengyin.roam.stamp-framing")
    private let output = AVCapturePhotoOutput()
    private let stopLock = NSLock()
    private var stopped = false
    private var isStopped: Bool { stopLock.lock(); defer { stopLock.unlock() }; return stopped }
    private var delegate: RoamStampFramingPhotoDelegate?
    func start(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard !isStopped, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                Task { @MainActor in completion(false) }; return
            }
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw RetainedImageFailure.invalid }
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                guard session.canSetSessionPreset(.photo), session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration(); throw RetainedImageFailure.invalid
                }
                session.sessionPreset = .photo; session.addInput(input); session.addOutput(output)
                session.commitConfiguration()
                guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) else { throw RetainedImageFailure.invalid }
                connection.videoRotationAngle = 90
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
                }
                if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
                guard !isStopped else { Task { @MainActor in completion(false) }; return }
                session.startRunning()
                let running = session.isRunning
                Task { @MainActor in completion(running) }
            } catch { Task { @MainActor in completion(false) } }
        }
    }
    func capture(_ completion: @escaping @MainActor @Sendable (Data?) -> Void) {
        queue.async { [self] in
            guard !isStopped, AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  session.isRunning, delegate == nil, output.availablePhotoCodecTypes.contains(.jpeg) else {
                Task { @MainActor in completion(nil) }; return
            }
            let shot = RoamStampFramingPhotoDelegate { [weak self] data in
                self?.queue.async { [weak self] in self?.delegate = nil }
                Task { @MainActor in completion(data) }
            }
            delegate = shot
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off; settings.photoQualityPrioritization = .speed
            output.capturePhoto(with: settings, delegate: shot)
        }
    }
    func stop() {
        stopLock.lock(); stopped = true; stopLock.unlock()
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }
}
private final class RoamStampFramingPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Data?) -> Void
    private let lock = NSLock()
    private var delivered = false
    private var processed: Data?
    init(completion: @escaping @Sendable (Data?) -> Void) { self.completion = completion }
    private func finish(_ bytes: Data?) {
        lock.lock(); let deliver = !delivered; delivered = true; lock.unlock()
        if deliver { completion(bytes) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let bytes = error == nil ? photo.fileDataRepresentation() : nil
        lock.lock(); processed = bytes; lock.unlock()
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock(); let bytes = processed; processed = nil; lock.unlock()
        finish(error == nil ? bytes : nil)
    }
}

@MainActor enum RoamStampFramedPixels {
    static func render(_ image: UIImage, frame: RoamStampFrame) throws -> RetainedSelectedImage {
        guard let raw = image.cgImage else { throw RetainedImageFailure.invalid }
        let sideways: Bool
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored: sideways = true
        default: sideways = false
        }
        let width = Double(sideways ? raw.height : raw.width), height = Double(sideways ? raw.width : raw.height)
        let crop = try frame.crop(imageWidth: width, imageHeight: height)
        let factor = Double(crop.outputWidth) / crop.width
        let output = CGSize(width: CGFloat(crop.outputWidth), height: CGFloat(crop.outputHeight))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: output))
            // UIImage.draw applies EXIF orientation while drawing into a fresh pixel-only container.
            image.draw(in: CGRect(x: -crop.x * factor, y: -crop.y * factor, width: width * factor, height: height * factor))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { throw RetainedImageFailure.invalid }
        return try RetainedImageSanitizer.sanitize(jpeg)
    }
}
