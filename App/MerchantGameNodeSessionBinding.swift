import SwiftUI

extension AppSession {
    /// Read-only production binding: projection, entries and live check-in codes reuse the existing
    /// merchant-content service; station commands and receipt reads stay disabled (MerchantCityNPCParityGates).
    var merchantGameNodeService: any MerchantGameNodeServing { MerchantGameNodeContentReader(service: merchantContentService) }
}

/// Session-scoped host; a sign-out or account change replaces the page and its coordinator.
@MainActor struct SessionMerchantGameNodeView: View {
    @ObservedObject var session: AppSession
    let activityID: Int
    var nodeID: Int? = nil
    var focusPause = false
    var body: some View {
        MerchantGameNodeView(service: session.merchantGameNodeService, activityID: activityID, nodeID: nodeID, focusPause: focusPause)
            .id("\(session.sessionRevision)-\(session.merchantContentService.scope)")
    }
}
