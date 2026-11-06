import SwiftUI

/// Captured audience host; child clears private presentation when leaving or backgrounded.
@MainActor struct CityArrivalEvidenceRuntimeHostView: View {
    @EnvironmentObject private var session: AppSession
    @Bindable var owner: CityArrivalEvidenceRuntimeOwner
    let revision: UInt64
    var body: some View {
        Group {
            if owner.isCurrent, let controller = owner.controller {
                CityArrivalEvidenceView(controller: controller)
            } else {
                Text("cityArrival.status.disabled", tableName: "CityArrivalEvidence")
            }
        }
        .onAppear { owner.synchronize() }
        .onChange(of: session.currentRuntimeDependencyContext) { _, _ in owner.synchronize() }
        .onChange(of: revision) { _, _ in owner.synchronize() }
        // Child owns foreground/disappearance; durable journal survives presentation invalidation.
    }
}

/// Actual merchant ID comes from the original VERIFY-gated business-home route.
@MainActor struct SessionCityArrivalMerchantView: View {
    @EnvironmentObject private var session: AppSession
    let merchantID: Int64
    var body: some View {
        Group {
            if let owner = session.makeCityArrivalEvidenceRuntimeOwner(audience: .merchant(merchantID: merchantID), board: nil), owner.isCurrent {
                CityArrivalEvidenceRuntimeHostView(owner: owner, revision: session.cityArrivalEvidenceRuntimeRevision)
            } else { Text("cityArrival.status.disabled", tableName: "CityArrivalEvidence") }
        }
    }
}
