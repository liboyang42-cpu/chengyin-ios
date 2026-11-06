import SwiftUI

/// Explicit opt-in evidence for the real editor/sheet chain. Never logs payloads or IDs.
@MainActor enum MerchantBusinessLifecycleDiagnostics {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-business-lifecycle")
        #else
        false
        #endif
    }
    static func record(_ event: String, scene: ScenePhase, editor: Bool = false,
                       pending: Bool = false, confirmation: Bool = false, sameIdentity: Bool = false) {
        guard enabled else { return }
        let phase = scene == .active ? "active" : scene == .background ? "background" : "inactive"
        print("MERCHANT_BUSINESS_LIFECYCLE \(event):scene=\(phase);editor=\(editor);pending=\(pending);confirmation=\(confirmation);sameIdentity=\(sameIdentity)")
    }
}
