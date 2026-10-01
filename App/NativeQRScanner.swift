import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// Present as a sheet. Delivers one raw QR string on the main actor, then dismisses.
/// The receiving feature must validate the payload before performing any action.
@MainActor
struct NativeQRScanner: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var session = QRScannerSession()

    var body: some View {
        NavigationStack {
            content
                .appNavigationTitle("scanner.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.cancel") {
                            session.end()
                            dismiss()
                        }
                    }
                }
        }
        .onAppear { session.begin(isActive: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            session.setActive(phase == .active)
        }
        .onDisappear { session.end() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.status {
        case .checking:
            ProgressView("scanner.checking")
        case .requestingPermission:
            ProgressView("scanner.requestingPermission")
        case .permissionRequired:
            ContentUnavailableView {
                Label("scanner.permission.title", systemImage: "camera")
            } description: {
                Text("scanner.permission.hint")
            } actions: {
                Button("scanner.allowCamera") { session.requestPermission() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isActive)
            }
        case .denied:
            ContentUnavailableView {
                Label("scanner.denied.title", systemImage: "camera.fill")
            } description: {
                Text("scanner.denied.hint")
            } actions: {
                Button("scanner.openSettings") {
                    // This fixed system URL is unrelated to any scanned content.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .restricted:
            ContentUnavailableView("scanner.restricted.title", systemImage: "lock.shield",
                                   description: Text("scanner.restricted.hint"))
        case .unsupported:
            ContentUnavailableView("scanner.unsupported.title", systemImage: "qrcode.viewfinder",
                                   description: Text("scanner.unsupported.hint"))
        case .misconfigured:
            ContentUnavailableView("scanner.configuration.title", systemImage: "camera",
                                   description: Text("scanner.configuration.hint"))
        case .unavailable:
            ContentUnavailableView {
                Label("scanner.unavailable.title", systemImage: "camera")
            } description: {
                Text("scanner.unavailable.hint")
            } actions: {
                Button("action.retry") { session.retry() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isActive)
            }
        case .ready:
            if session.isActive {
                camera
            } else {
                ContentUnavailableView("scanner.paused.title", systemImage: "pause.circle",
                                       description: Text("scanner.paused.hint"))
            }
        case .finished:
            ProgressView("scanner.finishing")
        }
    }

    private var camera: some View {
        // Capture this attempt's identity rather than reading a newer attempt in a
        // delayed delegate callback from a controller that is being dismantled.
        let attempt = session.attempt
        return QRScannerCamera(
            onPayload: { payload in
                guard let accepted = session.accept(payload, attempt: attempt) else { return }
                dismiss()
                onScan(accepted)
            },
            onUnavailable: { session.scannerBecameUnavailable(attempt: attempt) }
        )
        .id(attempt)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("scanner.instructions")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
        }
    }
}

@MainActor
private final class QRScannerSession: ObservableObject {
    enum Status {
        case checking, permissionRequired, requestingPermission, denied, restricted
        case unsupported, misconfigured, unavailable, ready, finished
    }

    @Published private(set) var status: Status = .checking
    @Published private(set) var isActive = false
    @Published private(set) var attempt = UUID()

    private var isPresented = false
    private var isRequestingPermission = false
    private var payloadGate = ScanPayloadGate()

    func begin(isActive: Bool) {
        guard !isPresented else {
            setActive(isActive)
            return
        }
        isPresented = true
        self.isActive = isActive
        payloadGate = ScanPayloadGate()
        refresh()
    }

    func setActive(_ active: Bool) {
        guard isPresented, !payloadGate.isFinished else { return }
        isActive = active
        if active { refresh() }
    }

    func end() {
        // Invalidate before dismissal so late delegate or permission callbacks
        // cannot deliver a result or restart this presentation.
        isPresented = false
        payloadGate.cancel()
        isActive = false
        attempt = UUID()
        status = .finished
    }

    func requestPermission() {
        guard isPresented, isActive, !payloadGate.isFinished,
              !isRequestingPermission,
              QRScannerAvailability.isSupported,
              QRScannerAvailability.hasCameraUsageDescription,
              AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            refresh()
            return
        }
        isRequestingPermission = true
        status = .requestingPermission
        let requestedAttempt = attempt
        Task { @MainActor [weak self] in
            // A fast Cancel can happen before this task starts. Do not launch a
            // system prompt from an inactive or already-ended presentation.
            guard self?.isPresented == true, self?.isActive == true,
                  self?.attempt == requestedAttempt else {
                self?.isRequestingPermission = false
                self?.refresh()
                return
            }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            guard let self else { return }
            self.isRequestingPermission = false
            // An OS permission prompt cannot be canceled. Its completion may
            // refresh a visible presentation, but never reopens a dismissed one.
            self.refresh()
        }
    }

    func retry() {
        guard isActive else { return }
        refresh()
    }

    func scannerBecameUnavailable(attempt: UUID) {
        guard isPresented, self.attempt == attempt, !payloadGate.isFinished else { return }
        // Re-check permission to distinguish revocation/restriction from a
        // temporary scanner failure. Retry creates a fresh controller.
        refresh(allowReady: false)
    }

    func accept(_ payload: String, attempt: UUID) -> String? {
        guard isPresented, isActive, self.attempt == attempt else { return nil }
        guard let accepted = payloadGate.take(payload) else { return nil }
        isActive = false
        status = .finished
        return accepted
    }

    private func refresh(allowReady: Bool = true) {
        guard isPresented, !payloadGate.isFinished else { return }
        guard QRScannerAvailability.isSupported else {
            status = .unsupported
            return
        }
        guard QRScannerAvailability.hasCameraUsageDescription else {
            // Prevent AVFoundation's exception for a missing usage string.
            status = .misconfigured
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            status = isRequestingPermission ? .requestingPermission : .permissionRequired
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        case .authorized:
            if allowReady && DataScannerViewController.isAvailable {
                attempt = UUID()
                status = .ready
            } else {
                status = .unavailable
            }
        @unknown default:
            status = .unavailable
        }
    }
}

@MainActor
private enum QRScannerAvailability {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return DataScannerViewController.isSupported
        #endif
    }

    static var hasCameraUsageDescription: Bool {
        guard let reason = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
private struct QRScannerCamera: UIViewControllerRepresentable {
    var onPayload: (String) -> Void
    var onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> QRScannerContainerViewController {
        let controller = QRScannerContainerViewController()
        controller.onPayload = onPayload
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: QRScannerContainerViewController, context: Context) {
        controller.onPayload = onPayload
        controller.onUnavailable = onUnavailable
    }

    static func dismantleUIViewController(_ controller: QRScannerContainerViewController, coordinator: ()) {
        controller.invalidate()
    }
}

/// UIKit owns capture lifecycle; SwiftUI owns presentation, permission UI and result handling.
@MainActor
private final class QRScannerContainerViewController: UIViewController, DataScannerViewControllerDelegate {
    var onPayload: ((String) -> Void)?
    var onUnavailable: (() -> Void)?

    private var scanner: DataScannerViewController?
    private var isVisible = false
    private var isInvalidated = false
    private var didDeliver = false
    private var didReportFailure = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // These observers stop capture immediately even before SwiftUI processes
        // a scene change. All notification selectors execute on the main thread.
        NotificationCenter.default.addObserver(self, selector: #selector(suspendCapture),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeCapture),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        startIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        isVisible = false
        scanner?.stopScanning()
        super.viewWillDisappear(animated)
    }

    func invalidate() {
        isInvalidated = true
        isVisible = false
        scanner?.stopScanning()
        scanner?.delegate = nil
        onPayload = nil
        onUnavailable = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func suspendCapture() {
        scanner?.stopScanning()
    }

    @objc private func resumeCapture() {
        startIfPossible()
    }

    private func startIfPossible() {
        guard isVisible, !isInvalidated, !didDeliver, !didReportFailure,
              UIApplication.shared.applicationState == .active else { return }
        guard QRScannerAvailability.isSupported,
              QRScannerAvailability.hasCameraUsageDescription,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              DataScannerViewController.isAvailable else {
            reportUnavailable()
            return
        }
        let scanner: DataScannerViewController
        if let existing = self.scanner {
            scanner = existing
        } else {
            scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
            scanner.delegate = self
            self.scanner = scanner
            addChild(scanner)
            scanner.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scanner.view)
            NSLayoutConstraint.activate([
                scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
                scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            scanner.didMove(toParent: self)
        }
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            reportUnavailable()
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        consume(addedItems, from: dataScanner)
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        consume(updatedItems, from: dataScanner)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        consume([item], from: dataScanner)
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        guard dataScanner === scanner else { return }
        reportUnavailable()
    }

    private func consume(_ items: [RecognizedItem], from dataScanner: DataScannerViewController) {
        guard dataScanner === scanner, isVisible, !isInvalidated, !didDeliver, !didReportFailure,
              UIApplication.shared.applicationState == .active else { return }
        for item in items {
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
            // Stop before publishing; VisionKit may report the same item through
            // add, update and tap callbacks before SwiftUI removes this controller.
            didDeliver = true
            dataScanner.stopScanning()
            Task { @MainActor [weak self] in
                guard let self, !self.isInvalidated else { return }
                guard self.isVisible, UIApplication.shared.applicationState == .active else {
                    // A disappearing/backgrounded controller must not deliver.
                    // If an interactive dismissal is canceled, allow scanning
                    // to resume when viewDidAppear runs again.
                    self.didDeliver = false
                    return
                }
                self.onPayload?(payload)
            }
            return
        }
    }

    private func reportUnavailable() {
        guard !isInvalidated, !didDeliver, !didReportFailure else { return }
        didReportFailure = true
        scanner?.stopScanning()
        Task { @MainActor [weak self] in
            guard let self, !self.isInvalidated else { return }
            self.onUnavailable?()
        }
    }
}
