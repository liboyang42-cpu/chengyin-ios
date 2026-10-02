import SwiftUI
import UIKit

/// Mount once in the signed-in shell; ownership and OS consent grants are independent.
/// No user-visible OS surface is presented by construction or mounting.
@MainActor final class RetainedImagePickerHost {
    var nativeSelectionEnabled = false
    weak var controller: UIViewController?
    func makePicker() -> RetainedNativeImagePicker {
        weak var presented: UIViewController?
        return .init(enabled: nativeSelectionEnabled, present: { [weak self] picker in
            guard let self, self.nativeSelectionEnabled, let controller = self.controller,
                  controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return false }
            presented = picker; controller.present(picker, animated: true); return true
        }, dismiss: {
            presented?.dismiss(animated: true); presented = nil
        })
    }
    func imPicker(scope: IMScope, currentScope: @escaping () -> IMScope?) -> any IMImageSelecting {
        IMNativeImagePicker(picker: makePicker(), currentScope: currentScope)
    }
}
@MainActor struct RetainedImagePresenterHost: UIViewControllerRepresentable {
    let host: RetainedImagePickerHost
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController(); host.controller = controller; return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { host.controller = controller }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) { controller.dismiss(animated: false) }
}
