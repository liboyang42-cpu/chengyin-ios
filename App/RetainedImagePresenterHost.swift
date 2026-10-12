import SwiftUI
import UIKit

/// Mount once in the signed-in shell; ownership and OS consent grants are independent.
/// No user-visible OS surface is presented by construction or mounting.
@MainActor final class RetainedImagePickerHost {
    var nativeSelectionEnabled = false
    weak var controller: UIViewController?
#if DEBUG
    /// Default nil; installed only by synthetic diagnostic fixtures.
    var diagnosticEvent: ((String) -> Void)?
    fileprivate var diagnosticPresenterSequence = 0
    fileprivate func recordDiagnostic(_ event: String, controller: UIViewController, number: Int) {
        diagnosticEvent?("nativePresenter[\(number)].\(event) attached=\(controller.viewIfLoaded?.window != nil) child=\(controller.parent != nil) presented=\(controller.presentedViewController != nil) presenting=\(controller.presentingViewController != nil)")
    }
#endif
    func makePicker(selectionApproval: (() -> Bool)? = nil) -> RetainedNativeImagePicker {
        weak var presented: UIViewController?
        return .init(enabled: selectionApproval?() ?? nativeSelectionEnabled, present: { [weak self] picker in
            guard let self, selectionApproval?() ?? self.nativeSelectionEnabled, let controller = self.controller,
                  controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return false }
            presented = picker; controller.present(picker, animated: true); return true
        }, dismiss: {
            presented?.dismiss(animated: true); presented = nil
        })
    }
    func imPicker(scope: IMScope, currentScope: @escaping () -> IMScope?, selectionApproval: (() -> Bool)? = nil) -> any IMImageSelecting {
        IMNativeImagePicker(picker: makePicker(selectionApproval: selectionApproval), currentScope: currentScope)
    }
}
@MainActor struct RetainedImagePresenterHost: UIViewControllerRepresentable {
    let host: RetainedImagePickerHost
#if DEBUG
    @MainActor final class Coordinator {
        weak var host: RetainedImagePickerHost?
        let number: Int
        init(host: RetainedImagePickerHost) {
            self.host = host
            if host.diagnosticEvent != nil { host.diagnosticPresenterSequence += 1 }
            number = host.diagnosticPresenterSequence
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(host: host) }
#endif
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController(); host.controller = controller
#if DEBUG
        host.recordDiagnostic("make", controller: controller, number: context.coordinator.number)
#endif
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { host.controller = controller }
#if DEBUG
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.host?.recordDiagnostic("dismantle.before-dismiss", controller: controller, number: coordinator.number)
        controller.dismiss(animated: false)
        coordinator.host?.recordDiagnostic("dismantle.after-dismiss", controller: controller, number: coordinator.number)
    }
#else
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) { controller.dismiss(animated: false) }
#endif
}
