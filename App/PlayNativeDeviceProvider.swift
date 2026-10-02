import SwiftUI
import UIKit
import CoreLocation
import CoreMotion
import Vision
import CoreImage

/// OS access remains opt-in. Construction, sheet hosting and supported inspection
/// do not request permissions, start a sensor, or open a camera.
@MainActor @Observable final class PlayNativeDeviceProvider: NSObject, PlayDeviceProviding, CLLocationManagerDelegate {
    let supported: Set<PlayDeviceKind>
    var showingCamera = false
    private var cameraReply: CheckedContinuation<Data, Error>?
    private var locationReply: CheckedContinuation<PlayDeviceOutput, Error>?
    private var motionReply: CheckedContinuation<PlayDeviceOutput, Error>?
    private var locationManager: CLLocationManager?
    private var motionManager: CMMotionManager?
    init(grants: Set<PlayDeviceKind> = []) { supported = grants.intersection([.photo, .scan, .location, .motion]); super.init() }
    func capture(_ kind: PlayDeviceKind, context: PlayDeviceContext) async throws -> PlayDeviceOutput {
        guard supported.contains(kind) else { throw PlayExperienceError.disabled }
        switch kind {
        case .photo, .scan:
            guard cameraReply == nil, UIImagePickerController.isSourceTypeAvailable(.camera) else { throw PlayExperienceError.unsupported }
            let bytes: Data = try await withCheckedThrowingContinuation { cameraReply = $0; showingCamera = true }
            if kind == .photo { return .photo(bytes, mimeType: "image/jpeg") }
            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
            try VNImageRequestHandler(data: bytes).perform([request])
            guard let code = request.results?.first?.payloadStringValue, !code.isEmpty else { throw PlayExperienceError.invalidAction }
            return .scan(code)
        case .location:
            guard locationReply == nil else { throw PlayExperienceError.invalidAction }
            return try await withCheckedThrowingContinuation { reply in
                locationReply = reply; let manager = CLLocationManager(); locationManager = manager; manager.delegate = self
                if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
                else { requestLocationIfAuthorized(manager) }
            }
        case .motion:
            guard motionReply == nil else { throw PlayExperienceError.invalidAction }
            let manager = CMMotionManager()
            guard manager.isAccelerometerAvailable else { throw PlayExperienceError.unsupported }
            motionManager = manager
            return try await withCheckedThrowingContinuation { reply in
                motionReply = reply; manager.accelerometerUpdateInterval = 0.1
                manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.motionManager?.stopAccelerometerUpdates(); self.motionManager = nil
                        let pending = self.motionReply; self.motionReply = nil
                        if let data { pending?.resume(returning: .sample(.init(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z, timestamp: data.timestamp))) }
                        else { pending?.resume(throwing: PlayExperienceError.unsupported) }
                    }
                }
            }
        default: throw PlayExperienceError.unsupported
        }
    }
    func finishCamera(_ image: UIImage?) {
        let reply = cameraReply; cameraReply = nil; showingCamera = false
        if let bytes = image?.jpegData(compressionQuality: 0.9) { reply?.resume(returning: bytes) }
        else { reply?.resume(throwing: CancellationError()) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { requestLocationIfAuthorized(manager) }
    private func requestLocationIfAuthorized(_ manager: CLLocationManager) {
        guard locationReply != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: locationManager(manager, didFailWithError: PlayExperienceError.disabled)
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let reply = locationReply; locationReply = nil; locationManager = nil
        guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 30 else {
            reply?.resume(throwing: PlayExperienceError.invalidAction); return
        }
        // CoreLocation is WGS84. Never relabel it GCJ02 or award local arrival.
        reply?.resume(returning: .location(location.coordinate.longitude, location.coordinate.latitude, coordinateSystem: "WGS84"))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let reply = locationReply; locationReply = nil; locationManager = nil; reply?.resume(throwing: error)
    }
    func cancel() {
        finishCamera(nil); locationManager?.stopUpdatingLocation(); locationManager = nil
        let location = locationReply; locationReply = nil; location?.resume(throwing: CancellationError())
        motionManager?.stopAccelerometerUpdates(); motionManager = nil
        let motion = motionReply; motionReply = nil; motion?.resume(throwing: CancellationError())
    }
}

@MainActor struct PlayNativeCameraSheet: UIViewControllerRepresentable {
    let provider: PlayNativeDeviceProvider
    func makeCoordinator() -> Coordinator { Coordinator(provider) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.cameraDevice = .rear; picker.mediaTypes = ["public.image"]; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let provider: PlayNativeDeviceProvider
        init(_ provider: PlayNativeDeviceProvider) { self.provider = provider }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { provider.finishCamera(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            provider.finishCamera(info[.originalImage] as? UIImage)
        }
    }
}

/// Source filter_shot_camera.dart transforms actual pixels, not just the preview.
@MainActor enum PlayNativePhotoFilter {
    static func render(_ bytes: Data, style: PlayPhotoFilter) throws -> Data {
        guard let original = UIImage(data: bytes), original.size.width > 0, original.size.height > 0,
              original.size.width * original.size.height <= 24_000_000 else { throw PlayExperienceError.invalidAction }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let bounds = CGRect(origin: .zero, size: original.size)
        // Normalize UIImage orientation before source-strip cropping and filtering.
        let normalized = UIGraphicsImageRenderer(size: original.size, format: format).image { _ in original.draw(in: bounds) }
        guard let sourceCG = normalized.cgImage else { throw PlayExperienceError.invalidAction }
        var nightImage: UIImage?
        if style == .nightVision {
            guard let filter = CIFilter(name: "CIColorMatrix") else { throw PlayExperienceError.unsupported }
            filter.setValue(CIImage(cgImage: sourceCG), forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 0.05, y: 0.10, z: 0.02, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: 0.28, y: 0.68, z: 0.18, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: 0.04, y: 0.15, z: 0.04, w: 0), forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 18.0 / 255, z: 0, w: 0), forKey: "inputBiasVector")
            guard let result = filter.outputImage, let cg = CIContext().createCGImage(result, from: result.extent) else { throw PlayExperienceError.invalidAction }
            nightImage = UIImage(cgImage: cg)
        }
        let output = UIGraphicsImageRenderer(size: original.size, format: format).image { renderer in
            let context = renderer.cgContext
            switch style {
            case .nightVision:
                nightImage?.draw(in: bounds)
                let step = max(3, bounds.height / 180)
                context.setStrokeColor(UIColor(red: 124.0/255, green: 1, blue: 138.0/255, alpha: 0.20).cgColor)
                context.setLineWidth(max(1, step / 3))
                for y in stride(from: CGFloat.zero, to: bounds.height, by: step) { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: bounds.width, y: y)) }
                context.strokePath()
            case .petPOV:
                for strip in 0..<72 {
                    let t = Double(strip) / 71, crop = bounds.width * CGFloat(min(0.28, 0.05 + 0.20 * pow(abs(t - 0.18), 1.65)))
                    let source = CGRect(x: crop, y: CGFloat(strip) * bounds.height / 72, width: bounds.width - crop * 2, height: bounds.height / 72 + 1)
                    let destination = CGRect(x: 0, y: CGFloat(strip) * bounds.height / 72, width: bounds.width, height: bounds.height / 72 + 1)
                    if let cropped = sourceCG.cropping(to: source) { UIImage(cgImage: cropped).draw(in: destination) }
                }
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.54).cgColor] as CFArray, locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.height * 0.48), end: CGPoint(x: 0, y: bounds.height), options: [])
                }
                let inset = max(4, min(bounds.width, bounds.height) * 0.05)
                UIColor(red: 1, green: 182.0/255, blue: 210.0/255, alpha: 1).setStroke()
                let frame = UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerRadius: inset * 0.7)
                frame.lineWidth = max(2, min(bounds.width, bounds.height) * 0.018); frame.stroke()
            }
        }
        guard let png = output.pngData() else { throw PlayExperienceError.invalidAction }; return png
    }
}
